import AppKit
import SwiftUI

@MainActor
enum RoutingMapLayersSelfTest {
    static func run(check: (String, Bool) -> Void) {
        var settings = RoutingMapLayerSettings()
        check("#92 배경→Unit→Fixture 합성 순서", RoutingMapLayer.allCases == [.background, .unit, .fixture])
        settings[.unit] = -1; settings[.fixture] = 2
        check("#92 0~100% 경계 제한", settings.unit == 0 && settings.fixture == 1)
        settings[.fixture] = .nan; settings[.unit] = .infinity
        check("#92 비유한 불투명도 무시", settings.unit == 0 && settings.fixture == 1)
        let env = AppEnvironment()
        env.openSample(); env.enterRoutingScreen()
        let first = env.routingFloorID!
        let original = env.snapshot, file = env.makeProjectFile()!, undo = env.undoStack.undoName
        let fingerprint = env.routingDocument!.fingerprint
        env.setRoutingMapOpacity(0, for: .unit); env.setRoutingMapOpacity(0.42, for: .fixture)
        check("#92 슬라이더는 모델/Undo/맞춤 트리거 불변",
              env.snapshot == original && env.undoStack.undoName == undo && env.routingDocument?.fingerprint == fingerprint)
        do {
            var current = env.makeProjectFile()!; current.savedAt = file.savedAt
            check("#92 보기 설정은 프로젝트 저장 데이터 불변", try current.encoded() == file.encoded())
        } catch { check("#92 프로젝트 저장 비교", false) }
        env.addRoutingFloor(); let second = env.routingFloorID!
        check("#92 다른 층은 독립 기본값", env.currentRoutingMapLayerSettings == RoutingMapLayerSettings())
        env.setRoutingMapOpacity(0.6, for: .background)
        env.selectRoutingFloor(first)
        check("#92 층 전환 후 이전 설정 유지", env.currentRoutingMapLayerSettings.unit == 0 && env.currentRoutingMapLayerSettings.fixture == 0.42)
        env.selectRoutingFloor(second)
        check("#92 배경 설정도 층별 유지", env.currentRoutingMapLayerSettings.background == 0.6)
        env.selectRoutingFloor(first)
        // openSample 직후의 첫 층은 아직 비동기 도면 캐시에 없을 수 있다.
        do { try env.loadLevelEditor(first) }
        catch { check("#92 테스트 도면 불러오기", false); return }
        let ring = [LocalPoint(10, 10), LocalPoint(100, 10), LocalPoint(100, 100), LocalPoint(10, 100)]
        let hole = [LocalPoint(40, 40), LocalPoint(60, 40), LocalPoint(60, 60), LocalPoint(40, 60)]
        var unit = FeatureGroup(featureType: .unit, serialNumber: "unit-test", memberIDs: [])
        unit.polygonRings = [ring, hole]
        env.features.insert(unit)
        var fixture = FeatureGroup(featureType: .fixture, serialNumber: "fixture-test", memberIDs: [])
        fixture.polygonRings = [ring]
        env.features.insert(fixture)
        let doc = env.routingDocument!
        let drawing = env.routingMapDrawingCache.value(env: env, document: doc)!
        check("#92 직접 그린 Unit/Fixture 분리", drawing.shapes[.unit]?.count == 1 && drawing.shapes[.fixture]?.count == 1)
        let path = drawing.shapes[.unit]![0].path
        check("#92 저장한 면의 구멍 유지", path.contains(CGPoint(x: 20, y: 20), eoFill: true) && !path.contains(CGPoint(x: 50, y: 50), eoFill: true))
        let builds = env.routingMapDrawingCache.buildCount
        env.setRoutingMapOpacity(0.2, for: .unit)
        env.handleRoutingClick(at: LocalPoint(200, 200), tolerance: 5, modifiers: .command)
        _ = env.routingMapDrawingCache.value(env: env, document: doc)
        check("#92 슬라이더/노드 생성은 도형 캐시 재사용", env.routingMapDrawingCache.buildCount == builds)
        env.features.update(unit.id) { $0.isInTrash = true }
        let hidden = env.routingMapDrawingCache.value(env: env, document: doc)!
        check("#92 휴지통 도형 제외·캐시 갱신", hidden.shapes[.unit]?.isEmpty != false && env.routingMapDrawingCache.buildCount == builds + 1)
        if let object = doc.objects.first(where: { $0.geometry.subpaths.contains(where: \.isClosed) }) {
            let member = FeatureGroup(featureType: .unit, serialNumber: "unit-member", memberIDs: [object.id])
            env.features.insert(member)
            check("#92 구성원 개체 기반 기존 Unit도 표시", env.routingMapDrawingCache.value(env: env, document: doc)?.shapes[.unit]?.count == 1)
        } else { check("#92 구성원 개체 기반 기존 Unit도 표시", false) }
        env.resetProjectState()
        check("#92 프로젝트 전환 시 설정 초기화", env.routingMapLayerSettings.isEmpty)
        imported(check: check)
        pixels(check: check)
    }

    private static func imported(check: (String, Bool) -> Void) {
        func data(_ features: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
        }
        let first = UUID(), second = UUID(), unitID = UUID()
        let ring = [[129.0, 36.0], [129.0002, 36.0], [129.0002, 36.0002], [129.0, 36.0002], [129.0, 36.0]]
        let hole = [[129.00008, 36.00008], [129.00012, 36.00008], [129.00012, 36.00012], [129.00008, 36.00012], [129.00008, 36.00008]]
        func feature(_ id: UUID, type: String, properties: [String: Any], geometry: [String: Any]) -> [String: Any] {
            ["type": "Feature", "id": id.uuidString, "feature_type": type, "properties": properties, "geometry": geometry]
        }
        do {
            let files = [
                "level.geojson": try data([feature(first, type: "level", properties: ["ordinal": 0], geometry: ["type": "Polygon", "coordinates": [ring]]),
                                          feature(second, type: "level", properties: ["ordinal": 1], geometry: ["type": "Polygon", "coordinates": [ring]])]),
                "unit.geojson": try data([feature(unitID, type: "unit", properties: ["level_id": first.uuidString], geometry: ["type": "MultiPolygon", "coordinates": [[ring, hole]]])]),
                "fixture.geojson": try data([feature(UUID(), type: "fixture", properties: ["level_ids": [first.uuidString, second.uuidString]], geometry: ["type": "MultiPolygon", "coordinates": [[ring]]])]),
                "amenity.geojson": try data([feature(UUID(), type: "amenity", properties: ["unit_ids": [unitID.uuidString]], geometry: ["type": "Point", "coordinates": [129.00005, 36.00005]])])
            ]
            let env = AppEnvironment()
            let input = try IMDFImporter.decode(files: files, sourceName: "layers.zip")
            try env.adoptIMDF(input); env.selectRoutingFloor(first)
            let doc = env.routingDocument!, canonical = env.buildingProject.imdfFiles()
            let plan = env.routingMapDrawingCache.value(env: env, document: doc)!
            check("#92 가져온 IMDF는 Unit/Fixture/나머지 배경으로 분리", plan.shapes[.unit]?.count == 1 && plan.shapes[.fixture]?.count == 1 && plan.background.objects.count == 2 && plan.warnings.isEmpty)
            let center = input.coordinates.localPoint(longitude: 129.0001, latitude: 36.0001)
            check("#92 IMDF MultiPolygon 구멍과 기존 도면 좌표 유지", !plan.shapes[.unit]![0].path.contains(center.cg, eoFill: true) && plan.background.canvasSize == doc.canvasSize)
            var edited = FeatureGroup(id: unitID, featureType: .unit, serialNumber: "unit-override", memberIDs: [])
            edited.polygonRings = [[LocalPoint(10, 10), LocalPoint(20, 10), LocalPoint(20, 20)]]
            env.features.insert(edited)
            let override = env.routingMapDrawingCache.value(env: env, document: doc)!
            check("#92 같은 UUID의 원본/편집 도형 중복 방지", override.shapes[.unit]?.count == 1 && override.shapes[.unit]?.first?.bounds.maxX == 20)
            env.features.update(unitID) { $0.isInTrash = true }
            check("#92 삭제된 가져온 Unit을 원본에서 되살리지 않음", env.routingMapDrawingCache.value(env: env, document: doc)?.shapes[.unit]?.isEmpty != false)
            env.features = FeatureStore()
            env.setRoutingMapOpacity(0, for: .unit)
            check("#92 표시 조절 후 원본 IMDF 데이터/합성 SVG 유지", env.buildingProject.imdfFiles() == canonical && env.routingDocument?.fingerprint == doc.fingerprint)
            env.selectRoutingFloor(second)
            let other = env.routingMapDrawingCache.value(env: env, document: env.routingDocument!)!
            check("#92 다른 층 Unit 숨김/공통 Fixture 표시/빈 레이어 정상", other.shapes[.unit]?.isEmpty != false && other.shapes[.fixture]?.count == 1 && other.background.objects.count == 1 && other.warnings.isEmpty)
            env.resetProjectState(); try env.adoptIMDF(input); env.selectRoutingFloor(first)
            check("#92 다른 프로젝트에서 도형 캐시 갱신", env.routingMapDrawingCache.value(env: env, document: env.routingDocument!)?.shapes[.unit]?.count == 1)
        } catch { check("#92 IMDF 레이어 검증", false); print(error) }
    }

    /// 실제 Canvas 합성을 작은 이미지로 검사한다. 창/마우스 GUI 검사를 대신하지는 않는다.
    private static func pixels(check: (String, Bool) -> Void) {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        func shape(_ color: RGBAColor) -> RoutingMapShape {
            RoutingMapShape(path: Path(rect), style: VectorStyle(stroke: color, fill: color, strokeWidth: 1, dashPattern: []))
        }
        let drawing = RoutingMapDrawing(background: DrawingDocument(objects: [], canvasSize: rect.size, sourceName: "pixel-test"),
            shapes: [.background: [shape(RGBAColor(r: 1, g: 0, b: 0, a: 1))],
                     .unit: [shape(RGBAColor(r: 0, g: 0.6, b: 0, a: 1))],
                     .fixture: [shape(RGBAColor(r: 0, g: 0, b: 1, a: 1))]])
        func pixel(_ settings: RoutingMapLayerSettings, map: RoutingMapDrawing? = nil, reference: Bool = false) -> NSColor? {
            let renderer = ImageRenderer(content: Canvas { ctx, _ in
                (map ?? drawing).draw(in: ctx, settings: settings, backgroundColors: .light, scale: 1, visible: rect) { ctx in
                    if reference { ctx.fill(Path(rect), with: .color(.red)) }
                }
            }.frame(width: 20, height: 20))
            guard let image = renderer.cgImage else { return nil }
            return NSBitmapImageRep(cgImage: image).colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)
        }
        let top = pixel(RoutingMapLayerSettings(background: 1, unit: 1, fixture: 1))
        check("#92 실제 합성에서 Fixture 최상단", top != nil && top!.blueComponent > 0.95 && top!.redComponent < 0.05)
        let middle = pixel(RoutingMapLayerSettings(background: 1, unit: 1, fixture: 0))
        check("#92 Fixture 0%에서 Unit 표시", middle != nil && middle!.greenComponent > 0.55 && middle!.blueComponent < 0.05)
        let bottom = pixel(RoutingMapLayerSettings(background: 1, unit: 0, fixture: 0))
        check("#92 Unit/Fixture 0%에서 배경만 표시", bottom != nil && bottom!.redComponent > bottom!.greenComponent + 0.5 && bottom!.redComponent > bottom!.blueComponent + 0.5)
        let clear = pixel(RoutingMapLayerSettings(background: 0, unit: 0, fixture: 0))
        check("#92 세 레이어 0%에서 면/선 완전 숨김", clear != nil && clear!.alphaComponent < 0.01)
        let half = pixel(RoutingMapLayerSettings(background: 0, unit: 0, fixture: 0.5))
        check("#92 레이어 50% 실제 알파 적용", half != nil && abs(half!.alphaComponent - 0.5) < 0.02)
        let empty = DrawingDocument(objects: [], canvasSize: rect.size, sourceName: "empty")
        let referenceOnly = RoutingMapDrawing(background: empty, shapes: [:])
        let visibleReference = pixel(RoutingMapLayerSettings(background: 1, unit: 0, fixture: 0), map: referenceOnly, reference: true)
        let hiddenReference = pixel(RoutingMapLayerSettings(background: 0, unit: 1, fixture: 1), map: referenceOnly, reference: true)
        check("#92 참고 도면도 배경 0%에서 숨김", visibleReference?.alphaComponent == 1 && hiddenReference?.alphaComponent == 0)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.red, atX: 0, y: 0)
        let raster = DrawingRasterImage(image: bitmap.cgImage!, rect: rect, transform: .identity, digest: "test")
        let imageOnly = RoutingMapDrawing(background: DrawingDocument(objects: [], canvasSize: rect.size, sourceName: "image", rasterImages: [raster]), shapes: [:])
        // NSApplication 시작 전의 ImageRenderer는 이 환경에서 CGImage를 렌더하지 않는다.
        // 이미지 픽셀은 GUI 확인 대상으로 남기고 원본 내장 이미지 보존만 확인한다.
        check("#92 배경 레이어는 내장 이미지 원본 유지", imageOnly.background.rasterImages.count == 1 && imageOnly.background.rasterImages[0].digest == "test")
    }
}
