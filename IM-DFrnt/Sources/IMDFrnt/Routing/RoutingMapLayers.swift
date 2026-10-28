import SwiftUI

/// 노드 화면에서만 쓰는 보기 설정. 프로젝트·Undo·IMDF에는 저장하지 않는다.
enum RoutingMapLayer: String, CaseIterable, Identifiable {
    case background, unit, fixture
    var id: Self { self }
    var title: String {
        switch self {
        case .background: "배경 레이어"
        case .unit: "Unit"
        case .fixture: "Fixture"
        }
    }
}

struct RoutingMapLayerSettings: Equatable {
    var background = 1.0
    var unit = 0.35
    var fixture = 0.8

    subscript(layer: RoutingMapLayer) -> Double {
        get {
            switch layer {
            case .background: background
            case .unit: unit
            case .fixture: fixture
            }
        }
        set {
            guard newValue.isFinite else { return }
            let value = min(1, max(0, newValue))
            switch layer {
            case .background: background = value
            case .unit: unit = value
            case .fixture: fixture = value
            }
        }
    }
}

struct RoutingMapShape {
    var path: Path
    var style: VectorStyle
    var reference: RoutingFeatureReference?
    let bounds: CGRect

    init(path: Path, style: VectorStyle, reference: RoutingFeatureReference? = nil) {
        self.path = path; self.style = style; self.reference = reference; bounds = path.boundingRect
    }
}

/// 원본 IMDF의 합성 SVG를 고치지 않고 표시용 도형만 세 레이어로 분리한다.
struct RoutingMapDrawing {
    var background: DrawingDocument
    var shapes: [RoutingMapLayer: [RoutingMapShape]]
    var warnings: [String] = []

    /// 숨긴 레이어와 구멍 안은 제외한다. 겹친 면은 모두 반환해 사용자가 고른다.
    func features(at point: LocalPoint, settings: RoutingMapLayerSettings) -> [RoutingFeatureReference] {
        var seen = Set<RoutingFeatureReference>()
        return RoutingMapLayer.allCases.reversed().filter { settings[$0] > 0 }.flatMap { layer in
            (shapes[layer] ?? []).reversed().compactMap { shape in
                guard let ref = shape.reference, shape.path.contains(point.cg, eoFill: true), seen.insert(ref).inserted else { return nil }
                return ref
            }
        }
    }

    func draw(in context: GraphicsContext, settings: RoutingMapLayerSettings,
              backgroundColors: CanvasBackground, scale: CGFloat, visible: CGRect,
              reference: (GraphicsContext) -> Void = { _ in }) {
        // enum 순서가 합성 순서다. 불투명도는 면/선 각각이 아니라 레이어 전체에 적용한다.
        for layer in RoutingMapLayer.allCases where settings[layer] > 0 {
            var composite = context
            composite.opacity *= settings[layer]
            composite.drawLayer { ctx in
                if layer == .background {
                    reference(ctx)
                    background.drawImages(in: ctx)
                }
                for shape in shapes[layer] ?? [] {
                    let width = CanvasZoom.strokeWidth(shape.style.strokeWidth, at: scale)
                    guard shape.bounds.insetBy(dx: -width - 2, dy: -width - 2).intersects(visible) else { continue }
                    if let fill = shape.style.fill {
                        ctx.fill(shape.path, with: .color(backgroundColors.resolveFill(fill)), style: FillStyle(eoFill: true))
                    }
                    if let stroke = shape.style.stroke {
                        ctx.stroke(shape.path, with: .color(backgroundColors.resolve(stroke)),
                                   style: StrokeStyle(lineWidth: width, dash: shape.style.dashPattern.map { CGFloat($0) }))
                    }
                }
            }
        }
    }
}

/// 슬라이더·노드 이동 때 SVG 파싱/링 추출을 반복하지 않는 현재 층 전용 캐시.
@MainActor
final class RoutingMapDrawingCache {
    private struct Key: Equatable {
        var projectID: UUID
        var levelID: UUID
        var fingerprint: String
        var canvasSize: CGSize
        var revision: Int
        var coordinates: IMDFCoordinateSpace?
        var local: [String: [ProjectJSON]]
        var global: [String: [ProjectJSON]]
        var borrow: BorrowRegistry
        var ids: IDAssigner
    }
    private var key: Key?
    private var drawing: RoutingMapDrawing?
    private(set) var buildCount = 0

    func reset() { key = nil; drawing = nil }

    func value(env: AppEnvironment, document: DrawingDocument) -> RoutingMapDrawing? {
        guard let level = env.activeLevel, level.id == env.routingFloorID else { return nil }
        let next = Key(projectID: env.projectID, levelID: level.id, fingerprint: document.fingerprint,
                       canvasSize: document.canvasSize, revision: env.geometryRevision,
                       coordinates: level.info.imdfCoordinates, local: level.geoJSON,
                       global: env.buildingProject.globalGeoJSON, borrow: env.borrow, ids: env.ids)
        if key == next, let drawing { return drawing }
        var result = RoutingMapDrawing(background: document, shapes: [:])
        var authoredIDs = Set<UUID>()
        for type in [IMDFFeatureType.unit, .fixture] {
            let layer: RoutingMapLayer = type == .unit ? .unit : .fixture
            for feature in env.features.features(ofType: type, includingTrashed: true) {
                // 휴지통의 가져온 도형도 원본 GeoJSON에서 되살리지 않는다.
                authoredIDs.insert(env.ids.peek(feature.id) ?? feature.id)
                guard !feature.isInTrash else { continue }
                let rings = feature.polygonRings.isEmpty
                    ? [VertexExtractor.vertices(for: feature, document: document, segmentation: env.segmentation,
                                                kind: type.requiredGeometry, borrowed: env.borrow.objects(borrowedBy: feature.id))]
                    : feature.polygonRings
                var path = Path()
                for ring in rings where ring.count >= 3 {
                    path.addLines(ring.map(\.cg)); path.closeSubpath()
                }
                guard !path.isEmpty else { continue }
                let fill = type == .unit ? RGBAColor(r: 0.35, g: 0.65, b: 0.9, a: 1)
                                        : RGBAColor(r: 0.9, g: 0.6, b: 0.25, a: 1)
                var style = VectorStyle.default; style.fill = fill
                let ref = RoutingFeatureReference(kind: type == .unit ? .unit : .fixture, featureID: feature.id, source: .authored)
                result.shapes[layer, default: []].append(RoutingMapShape(path: path, style: style, reference: ref))
            }
        }
        if let coordinates = level.info.imdfCoordinates, !level.geoJSON.isEmpty {
            // 기존 IMDF 표시와 같은 좌표계/층 참조 규칙. 합성 SVG를 배경으로 재사용하면
            // Unit/Fixture를 0%로 해도 배경에 잔상이 남으므로 타입별로 다시 파싱한다.
            var unitLevels: [String: UUID] = [:]
            for floor in env.buildingProject.levels {
                for unit in floor.geoJSON["unit.geojson"] ?? [] {
                    if let id = unit["id"]?.string { unitLevels[id.lowercased()] = floor.id }
                }
            }
            var elements: [RoutingMapLayer: [String]] = [:]
            var references: [RoutingMapLayer: [RoutingFeatureReference?]] = [:]
            for type in ["level", "unit", "section", "fixture", "kiosk", "detail", "opening", "amenity", "anchor"] {
                let layer: RoutingMapLayer = type == "unit" ? .unit : (type == "fixture" ? .fixture : .background)
                let name = type + ".geojson"
                let shared = (env.buildingProject.globalGeoJSON[name] ?? []).filter {
                    BuildingProject.levelReferences($0, unitLevels: unitLevels).contains(level.id)
                }
                for feature in (level.geoJSON[name] ?? []) + shared {
                    if layer != .background, let id = feature["id"]?.uuid, authoredIDs.contains(id) { continue }
                    guard let geometry = feature["geometry"], geometry != .null else { continue }
                    do {
                        guard let object = try JSONSerialization.jsonObject(with: geometry.data()) as? [String: Any] else { continue }
                        elements[layer, default: []].append(try IMDFImporter.svgElement(object, type: type,
                            category: feature["properties"]?["category"]?.string ?? "", coordinates: coordinates))
                        let ref: RoutingFeatureReference?
                        if let id = feature["id"]?.uuid, let kind = RoutingFeatureKind(rawValue: type) {
                            ref = RoutingFeatureReference(kind: kind, featureID: id, source: .imported)
                        } else { ref = nil }
                        references[layer, default: []].append(ref)
                    } catch { result.warnings.append("\(type): \(error.localizedDescription)") }
                }
            }
            result.background = DrawingDocument(objects: [], canvasSize: document.canvasSize, sourceName: document.sourceName)
            for layer in RoutingMapLayer.allCases {
                guard let contents = elements[layer], !contents.isEmpty else { continue }
                let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(document.canvasSize.width)\" height=\"\(document.canvasSize.height)\">"
                    + contents.joined() + "</svg>"
                do {
                    let parsed = try SVGParser.parse(data: Data(svg.utf8), sourceName: "routing-\(layer.rawValue)")
                    if layer == .background { result.background = parsed }
                    let refs = references[layer] ?? []
                    if layer != .background, refs.count != parsed.objects.count {
                        result.warnings.append("\(layer.title): 도형과 UUID를 대응하지 못해 장소 선택을 제한합니다.")
                    }
                    result.shapes[layer, default: []] += parsed.objects.enumerated().map { i, object in
                        RoutingMapShape(path: object.geometry.swiftUIPath, style: object.style,
                                        reference: refs.count == parsed.objects.count ? refs[i] : nil)
                    }
                } catch { result.warnings.append("\(layer.title): \(error.localizedDescription)") }
            }
            // 오류가 있어도 원본 합성 SVG로 되돌아가 Unit/Fixture를 다시 표시하지 않는다.
        } else {
            result.shapes[.background] = document.objects.map {
                RoutingMapShape(path: env.segmentation.effectiveGeometry(for: $0.id, fallback: $0.geometry).swiftUIPath, style: $0.style)
            }
        }
        key = next; drawing = result; buildCount += 1
        return result
    }
}

extension AppEnvironment {
    var currentRoutingMapLayerSettings: RoutingMapLayerSettings {
        routingFloorID.flatMap { routingMapLayerSettings[$0] } ?? RoutingMapLayerSettings()
    }

    func setRoutingMapOpacity(_ value: Double, for layer: RoutingMapLayer) {
        guard let floorID = routingFloorID, value.isFinite else { return }
        var settings = currentRoutingMapLayerSettings
        settings[layer] = value
        guard settings != currentRoutingMapLayerSettings else { return }
        routingMapLayerSettings[floorID] = settings
    }
}

struct RoutingMapLayersPanel: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("현재 층 레이어").font(.caption.bold())
            ForEach(RoutingMapLayer.allCases.reversed()) { layer in
                HStack(spacing: 8) {
                    Text(layer.title).frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { env.currentRoutingMapLayerSettings[layer] },
                                          set: { env.setRoutingMapOpacity($0, for: layer) }), in: 0...1, step: 0.01)
                        .accessibilityLabel("\(layer.title) 불투명도")
                    Text("\(Int((env.currentRoutingMapLayerSettings[layer] * 100).rounded()))%")
                        .monospacedDigit().frame(width: 35, alignment: .trailing)
                }
            }
            if let doc = env.routingDocument,
               let drawing = env.routingMapDrawingCache.value(env: env, document: doc), !drawing.warnings.isEmpty {
                Label("일부 도형을 표시하지 못했습니다", systemImage: "exclamationmark.triangle")
                    .help(drawing.warnings.joined(separator: "\n"))
            }
        }
        .font(.caption).padding(10).frame(width: 270)
        .toolbarCard(cornerRadius: 8)
        .disabled(env.routingDocument == nil)
    }
}
