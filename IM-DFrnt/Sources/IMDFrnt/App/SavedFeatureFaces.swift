import Foundation

/// 면 단위 편집에서 면을 둘러싸는 경계로 무엇을 쓰는가(엔진 디버깅, 2026-10-18 요청).
///
/// 예전에는 도면 개체(SVG 선분)로 닫힌 면을 골랐다. 이제는 **이미 저장한 feature의 경계로 막힌 면**만 고른다.
/// 예: 방(unit)들을 점으로 저장해 두면 그 사이에 갇힌 복도가 면 하나로 잡힌다.
enum FaceBoundaryScope: String, CaseIterable {
    /// 지금 작업 중인 레이어(property type)에 저장한 feature만.
    case currentLayer
    /// 모든 레이어에 저장한 feature. opening 선이 방을 닫는 데 함께 쓰인다.
    case allLayers

    var title: String {
        switch self {
        case .currentLayer: return "현재 레이어 기준"
        case .allLayers: return "모든 레이어 기준"
        }
    }

    var help: String {
        switch self {
        case .currentLayer: return "지금 레이어에 저장한 개체의 경계로 막힌 면만 고릅니다."
        case .allLayers: return "모든 레이어에 저장한 개체(문 선 포함)의 경계로 막힌 면을 고릅니다."
        }
    }
}

/// 저장된 feature로 찾은 면. 경계가 바뀌지 않으면 다시 찾지 않는다.
struct SavedFeatureFaceCache {
    var scope: FaceBoundaryScope
    var type: IMDFFeatureType?
    var segments: [LineSegment]
    var faces: [ClosedPolygonFinder.Face]
    /// 지금 레이어에 이미 같은 모양으로 저장된 면 → 그 feature. 다시 고르지 못하게 한다.
    var owners: [String: FeatureGroupID]
}

@MainActor
extension AppEnvironment {

    /// 면 단위에서 고를 수 있는 면 전체(이미 저장된 면 포함). 화면·클릭·저장이 모두 이 목록을 쓴다.
    var faceModeFaces: [ClosedPolygonFinder.Face] { savedFeatureFaces().faces }

    /// 이 면과 같은 모양으로 지금 레이어에 저장된 feature.
    func faceOwner(_ face: ClosedPolygonFinder.Face) -> FeatureGroupID? { savedFeatureFaces().owners[face.id] }

    func setFaceBoundaryScope(_ scope: FaceBoundaryScope) {
        guard scope != faceBoundaryScope else { return }
        faceBoundaryScope = scope
        faceSelection = []
        // 기준이 바뀌면 면이 통째로 달라진다. 이전 기준에서 고른 면은 남겨 둘 수 없다.
    }

    private func savedFeatureFaces() -> SavedFeatureFaceCache {
        let type = layers.activePropertyType
        let segments = faceBoundarySegments(scope: faceBoundaryScope, type: type)
        if let cache = savedFaceCache, cache.scope == faceBoundaryScope, cache.type == type, cache.segments == segments {
            return cache
        }
        let faces = ClosedPolygonFinder.faces(in: segments.map { .init(segment: $0, objectID: nil) })
        let cache = SavedFeatureFaceCache(scope: faceBoundaryScope, type: type, segments: segments,
                                          faces: faces, owners: savedFaceOwners(faces, type: type))
        savedFaceCache = cache
        return cache
        // 저장된 feature는 도면 개체보다 훨씬 적어 바로 계산한다. 경계가 같으면 그대로 돌려준다.
    }

    /// 면을 둘러쌀 선분. 점으로 그린 링·선, 문 닫기 선분, 예전 방식으로 저장한 feature의 도면 개체 선분이다.
    private func faceBoundarySegments(scope: FaceBoundaryScope, type: IMDFFeatureType?) -> [LineSegment] {
        var out: [LineSegment] = []
        for f in features.features where !f.isInTrash && (scope == .allLayers || f.featureType == type) {
            for ring in f.polygonRings where ring.count >= 2 {
                for i in ring.indices { out.append(LineSegment(start: ring[i], end: ring[(i + 1) % ring.count])) }
            }
            if let v = f.drawnVertices, v.count >= 2 {
                for i in 0..<(v.count - 1) { out.append(LineSegment(start: v[i], end: v[i + 1])) }
            }
            if let c = f.closureSegment { out.append(c) }
            if f.polygonRings.isEmpty, let doc = document {
                for id in f.memberIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard let o = doc.object(id) else { continue }
                    out += segmentation.effectiveGeometry(for: o.id, fallback: o.geometry).lineSegments()
                }
                // 링이 없는 예전 feature는 구성원 개체의 선이 경계다. 링이 있으면 링이 정본이라 겹쳐 넣지 않는다.
            }
        }
        return out
    }

    /// 지금 레이어의 다각형(구멍 제외)과 같은 모양인 면을 찾는다. 같은 방을 두 번 저장하지 않게 한다.
    private func savedFaceOwners(_ faces: [ClosedPolygonFinder.Face], type: IMDFFeatureType?) -> [String: FeatureGroupID] {
        guard let type else { return [:] }
        var outers: [(FeatureGroupID, [LocalPoint], CGRect)] = []
        for f in features.features(ofType: type) where !f.isInTrash {
            let depth = f.polygonRings.count > 1 ? RingNesting.depths(f.polygonRings) : [0]
            for (r, ring) in f.polygonRings.enumerated() where ring.count >= 3 && depth[r] % 2 == 0 {
                outers.append((f.id, ring, Self.bounds(of: ring)))
            }
        }
        var owners: [String: FeatureGroupID] = [:]
        for face in faces {
            let near = outers.first { _, ring, box in
                abs(box.minX - face.boundingBox.minX) < 0.5 && abs(box.minY - face.boundingBox.minY) < 0.5
                    && abs(box.maxX - face.boundingBox.maxX) < 0.5 && abs(box.maxY - face.boundingBox.maxY) < 0.5
                    && RingNesting.relation(face.ring, to: ring) == .duplicate
            }
            if let near { owners[face.id] = near.0 }
        }
        return owners
    }

    private static func bounds(of ring: [LocalPoint]) -> CGRect {
        let xs = ring.map(\.x), ys = ring.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
