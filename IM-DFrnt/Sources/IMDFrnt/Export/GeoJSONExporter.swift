import AppKit
import Foundation

/// 명세 7-4)의 차단 조건을 한 곳에서 검사한다.
enum ExportBlocker: Hashable {
    case noFeatures
    case anchorsInsufficient(have: Int, need: Int)
    case coordinatesMissing([String])
    case geometryMismatch([String])

    var message: String {
        switch self {
        case .noFeatures:
            return "저장된 feature가 없습니다."
        case .anchorsInsufficient(let have, let need):
            return "Anchor 미지정 상태입니다. (\(have)쌍 지정됨 · 최소 \(need)쌍 필요)"
        case .coordinatesMissing(let serials):
            return "좌표가 확보되지 않은 feature가 있습니다: \(serials.joined(separator: ", "))"
        case .geometryMismatch(let notes):
            return notes.joined(separator: "\n")
        }
    }
}

struct ExportValidator {
    let document: DrawingDocument
    let features: [FeatureGroup]
    let anchors: AnchorStore
    let georeferencer: Georeferencer
    let segmentation: SegmentationStore
    var borrow = BorrowRegistry()
    // 링이 닫히는지 판정하려면 빌려온 문까지 넣고 좌표를 뽑아야 한다.

    func validate(type: IMDFFeatureType) -> [ExportBlocker] {
        var blockers: [ExportBlocker] = []
        let live = features.filter { $0.featureType == type && !$0.isInTrash }

        if live.isEmpty { blockers.append(.noFeatures) }

        if type.requiredGeometry != .none && !georeferencer.isConfigured {
            blockers.append(.anchorsInsufficient(have: anchors.pairs.count,
                                                       need: AnchorStore.minimumPairs))
        }

        if type.requiredGeometry != .none && georeferencer.isConfigured {
            var missing: [String] = []
            for f in live {
                let kind = GeometryClassifier.classify(f, document: document)
                let v = VertexExtractor.vertices(for: f, document: document,
                                                 segmentation: segmentation, kind: kind,
                                                 borrowed: borrow.objects(borrowedBy: f.id))
                if v.isEmpty { missing.append(f.serialNumber) }
            }
            if !missing.isEmpty { blockers.append(.coordinatesMissing(missing)) }
        }

        let warnings = live.compactMap { GeometryClassifier.mismatchWarning($0, document: document) }
        if !warnings.isEmpty { blockers.append(.geometryMismatch(warnings)) }

        return blockers
    }
}

/// feature 그룹 → GeoJSON Feature 객체 직렬화 및 파일 저장.
struct GeoJSONExporter {
    let document: DrawingDocument
    let segmentation: SegmentationStore
    let georeferencer: Georeferencer
    var borrow = BorrowRegistry()

    func buildFeatureCollection(type: IMDFFeatureType,
                                features: [FeatureGroup],
                                ids: inout IDAssigner,
                                serialToUUID: [String: UUID]) -> [String: Any] {
        let live = features.filter { $0.featureType == type && !$0.isInTrash }
        var out: [[String: Any]] = []
        for f in live {
            out.append(serialize(f, ids: &ids, serialToUUID: serialToUUID))
        }
        return ["type": "FeatureCollection", "features": out]
    }

    func serialize(_ f: FeatureGroup,
                           ids: inout IDAssigner,
                           serialToUUID: [String: UUID]) -> [String: Any] {
        let uuid = ids.id(for: f.id)
        let kind = GeometryClassifier.classify(f, document: document)

        var props: [String: Any] = [:]
        for field in PropertySchema.fields(for: f.featureType) where field.key != "id" {
            if field.type == .point {
                if field.key == "display_point", let dp = f.displayPoint,
                   let g = georeferencer.geoPoint(for: dp) {
                    props[field.key] = ["type": "Point", "coordinates": g.geoJSONArray]
                } else {
                    props[field.key] = NSNull()
                }
                continue
            }
            let v = f.value(field.key)
            if case .reference = field.type {
                // 사람은 슬롯에 unit-014 같은 일련번호를 넣고, 파일에는 UUID가 들어간다.
                if case .string(let s) = v, let mapped = serialToUUID[s] {
                    props[field.key] = mapped.uuidString.lowercased()
                } else {
                    props[field.key] = v.jsonValue
                }
                continue
            }
            if field.type == .stringArray, case .stringArray(let arr) = v {
                props[field.key] = arr.map { serialToUUID[$0]?.uuidString.lowercased() ?? $0 }
                continue
            }
            props[field.key] = v.jsonValue
        }

        var feature: [String: Any] = [
            "id": uuid.uuidString.lowercased(),
            "type": "Feature",
            "feature_type": f.featureType.rawValue,
            "properties": props,
        ]
        feature["geometry"] = geometryObject(f, kind: kind) ?? NSNull()
        return feature
    }

    private func geometryObject(_ f: FeatureGroup, kind: GeoJSONGeometryKind) -> [String: Any]? {
        guard kind != .none else { return nil }

        let rings = VertexExtractor.rings(for: f)
        if (kind == .multiPolygon && rings.count > 1) || (kind.isAreal && f.multiPolygon == true && !rings.isEmpty) {
            // fixture처럼 면 여러 개가 한 feature인 경우(신기능 5-4 2번)와 우측 패널에서 MultiPolygon으로 지정한 면 feature.
            // 링마다 따로 변환한다 — 한 줄로 이으면 서로 다른 면이 하나의 링으로 뭉개진다.
            let converted = rings.compactMap { georeferencer.geoPoints(for: $0) }
            guard converted.count == rings.count else { return nil }
            let coords = converted.map { closeRing($0.map(\.geoJSONArray)) }
            return ["type": "MultiPolygon",
                    "coordinates": RingNesting.polygons(rings).map { [coords[$0.outer]] + $0.holes.map { coords[$0] } }]
            // 다른 링 안에 든 링은 바깥 다각형의 구멍(안쪽 링)으로 붙인다. 구멍 안의 링은 다시 다각형이다.
        }

        let locals = VertexExtractor.vertices(for: f, document: document,
                                              segmentation: segmentation, kind: kind,
                                              borrowed: borrow.objects(borrowedBy: f.id))
        guard !locals.isEmpty, let geo = georeferencer.geoPoints(for: locals) else { return nil }
        let coords = geo.map(\.geoJSONArray)

        switch kind {
        case .point:
            return ["type": "Point", "coordinates": coords[0]]
        case .lineString:
            return ["type": "LineString", "coordinates": coords]
        case .polygon:
            return ["type": "Polygon", "coordinates": [closeRing(coords)]]
        case .multiPolygon:
            return ["type": "MultiPolygon", "coordinates": [[closeRing(coords)]]]
        case .none:
            return nil
        }
    }

    private func closeRing(_ coords: [[Double]]) -> [[Double]] {
        guard let first = coords.first, let last = coords.last else { return coords }
        return first == last ? coords : coords + [first]
        // GeoJSON Polygon의 링은 첫 점과 끝 점이 같아야 한다.
    }

    @MainActor
    static func write(_ object: [String: Any], suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        panel.title = "GeoJSON 저장 위치 선택"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url)
        return url
    }
}
