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
    /// unit 전용. level 다각형 안에서 **unit이 아직 덮지 않은 곳**만 면으로 고른다(2026-10-18 요청).
    /// unit은 level을 빈틈없이 덮어야 해서, 남은 빈틈을 바로 골라 unit으로 채우게 한다.
    /// 경계는 level 외곽선·unit 경계·보조 선분·문 선이고, 안쪽에 떠 있는 unit은 구멍으로 빠진다.
    case level
    /// section 전용. 저장된 unit 하나하나가 그대로(구멍 포함) 면이 된다(2026-10-19 요청). 누르면 그 unit과 같은
    /// 모양의 section으로 저장한다 — 경계선으로 면을 다시 찾으면 이웃 unit·보조 선분에 잘려 unit과 모양이 달라진다.
    case unitShapes

    /// 이 레이어에서 고를 수 있는 기준.
    static func options(for type: IMDFFeatureType?) -> [FaceBoundaryScope] {
        switch type {
        case .unit: return [.currentLayer, .allLayers, .level]
        case .section: return [.currentLayer, .allLayers, .unitShapes]
        default: return [.currentLayer, .allLayers]
        }
    }

    var title: String {
        switch self {
        case .currentLayer: return "현재 레이어 기준"
        case .allLayers: return "모든 레이어 기준"
        case .level: return "level 기준"
        case .unitShapes: return "unit 모양 기준"
        }
    }

    var help: String {
        switch self {
        case .currentLayer: return "지금 레이어에 저장한 개체의 경계로 막힌 면만 고릅니다."
        case .allLayers: return "모든 레이어에 저장한 개체(문 선 포함)의 경계로 막힌 면을 고릅니다."
        case .level: return "level 다각형 안에서 unit이 아직 덮지 않은 곳을 고릅니다. 보조 선분·문 선으로 나뉘고, 안쪽의 unit은 구멍으로 빠집니다."
        case .unitShapes: return "저장된 unit을 하나씩 고릅니다. 고른 unit과 똑같은 모양(구멍 포함)으로 section을 저장합니다."
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
    /// level 기준 면의 구멍(안쪽에 떠 있는 unit 자리). 저장하면 구멍 있는 MultiPolygon이 된다.
    var holes: [String: [[LocalPoint]]] = [:]
    /// 만들 때의 `geometryRevision`. 같으면 선분을 다시 모으지 않고 그대로 쓴다.
    var revision = -1
}

@MainActor
extension AppEnvironment {

    /// 면 단위에서 고를 수 있는 면 전체(이미 저장된 면 포함). 화면·클릭·저장이 모두 이 목록을 쓴다.
    var faceModeFaces: [ClosedPolygonFinder.Face] { savedFeatureFaces().faces }

    /// 이 면과 같은 모양으로 지금 레이어에 저장된 feature.
    func faceOwner(_ face: ClosedPolygonFinder.Face) -> FeatureGroupID? { savedFeatureFaces().owners[face.id] }

    /// 이 면의 구멍. level 기준 면만 가질 수 있다.
    func faceHoles(_ face: ClosedPolygonFinder.Face) -> [[LocalPoint]] { savedFeatureFaces().holes[face.id] ?? [] }

    /// 구멍을 뺀 면 안에 있는가. 구멍(이미 덮인 unit) 자리를 눌러 바깥 면이 잡히지 않게 한다.
    func faceContains(_ face: ClosedPolygonFinder.Face, _ p: LocalPoint) -> Bool {
        face.contains(p) && !faceHoles(face).contains { RingNesting.contains($0, p) }
    }

    /// 지금 레이어에서 실제로 쓰는 기준. level 기준은 unit 레이어에서만, unit 모양 기준은 section 레이어에서만 뜻이 있다.
    var effectiveFaceBoundaryScope: FaceBoundaryScope {
        FaceBoundaryScope.options(for: layers.activePropertyType).contains(faceBoundaryScope) ? faceBoundaryScope : .currentLayer
    }

    func setFaceBoundaryScope(_ scope: FaceBoundaryScope) {
        guard scope != faceBoundaryScope else { return }
        faceBoundaryScope = scope
        faceSelection = []
        // 기준이 바뀌면 면이 통째로 달라진다. 이전 기준에서 고른 면은 남겨 둘 수 없다.
    }

    private func savedFeatureFaces() -> SavedFeatureFaceCache {
        let type = layers.activePropertyType
        let scope = effectiveFaceBoundaryScope
        if let cache = savedFaceCache, cache.scope == scope, cache.type == type, cache.revision == geometryRevision {
            return cache
        }
        // 면 하나마다 owners·holes를 물어 프레임마다 수백 번 불린다. 바뀐 것이 없으면 여기서 끝낸다.
        let segments: [LineSegment]
        switch scope {
        case .level: segments = levelBoundarySegments()
        case .unitShapes: segments = unitShapeSegments()
        default: segments = faceBoundarySegments(scope: scope, type: type)
        }
        if var cache = savedFaceCache, cache.scope == scope, cache.type == type, cache.segments == segments {
            cache.revision = geometryRevision
            savedFaceCache = cache
            return cache
        }
        if scope == .level {
            let (faces, holes) = levelGapFaces(segments: segments)
            let cache = SavedFeatureFaceCache(scope: scope, type: type, segments: segments,
                                              faces: faces, owners: [:], holes: holes, revision: geometryRevision)
            savedFaceCache = cache
            return cache
        }
        if scope == .unitShapes {
            let (faces, holes) = unitShapeFaces()
            let cache = SavedFeatureFaceCache(scope: scope, type: type, segments: segments,
                                              faces: faces, owners: savedFaceOwners(faces, type: type),
                                              holes: holes, revision: geometryRevision)
            savedFaceCache = cache
            return cache
        }
        let faces = ClosedPolygonFinder.faces(in: segments.map { .init(segment: $0, objectID: nil) })
        let cache = SavedFeatureFaceCache(scope: scope, type: type, segments: segments,
                                          faces: faces, owners: savedFaceOwners(faces, type: type),
                                          revision: geometryRevision)
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
        return out + features.guides
        // 보조 선분은 어느 기준에서나 면을 나눈다. 도면에 벽선이 없는 자리를 막거나 긴 복도를 끊는 선이다.
    }

    // MARK: unit 모양 기준

    /// unit·section 링의 변. 캐시 비교용이다 — unit 모양이 바뀌면 면을, section이 바뀌면 '이미 저장된 자리'를 다시 판정한다.
    /// section을 빼면 저장해도 캐시가 그대로 쓰여 같은 unit을 또 고를 수 있었다.
    private func unitShapeSegments() -> [LineSegment] {
        var out: [LineSegment] = []
        for f in features.features where !f.isInTrash && (f.featureType == .unit || f.featureType == .section) {
            for ring in f.polygonRings where ring.count >= 2 {
                for i in ring.indices { out.append(LineSegment(start: ring[i], end: ring[(i + 1) % ring.count])) }
            }
        }
        return out
    }

    /// 저장된 unit의 다각형마다 면 하나. 바깥 링이 면이고 그 안쪽 링은 구멍이다. MultiPolygon unit은 섬마다 면이 된다.
    private func unitShapeFaces() -> ([ClosedPolygonFinder.Face], [String: [[LocalPoint]]]) {
        var faces: [ClosedPolygonFinder.Face] = []
        var holes: [String: [[LocalPoint]]] = [:]
        for f in features.features(ofType: .unit) where !f.isInTrash && !f.polygonRings.isEmpty {
            for (n, polygon) in RingNesting.polygons(f.polygonRings).enumerated() {
                let outer = f.polygonRings[polygon.outer]
                guard outer.count >= 3 else { continue }
                let inner = polygon.holes.map { f.polygonRings[$0] }
                let area = abs(UnitCoverage.area(UnitCoverage.path([outer] + inner)))
                guard area >= 0.5 else { continue }
                let id = "unit-shape:\(f.id.uuidString):\(n)"
                faces.append(ClosedPolygonFinder.Face(id: id, ring: outer, memberIDs: [], usesTemporaryDoor: false,
                                                      area: area, boundingBox: ClosedPolygonFinder.boundingBox(outer)))
                if !inner.isEmpty { holes[id] = inner }
            }
        }
        return (faces, holes)
    }

    // MARK: level 기준

    /// level 기준 면의 경계. level 외곽선, unit 경계, 보조 선분, 문 선(opening 두 점·임시 문)이다.
    private func levelBoundarySegments() -> [LineSegment] {
        var out: [LineSegment] = []
        for f in features.features where !f.isInTrash {
            if f.featureType == .level || f.featureType == .unit {
                for ring in f.polygonRings where ring.count >= 3 {
                    for i in ring.indices { out.append(LineSegment(start: ring[i], end: ring[(i + 1) % ring.count])) }
                }
            }
            if f.featureType == .opening, let v = f.drawnVertices, v.count >= 2 {
                for i in 0..<(v.count - 1) { out.append(LineSegment(start: v[i], end: v[i + 1])) }
            }
            if let c = f.closureSegment { out.append(c) }
        }
        return out + features.guides
    }

    /// level에서 unit을 뺀 곳을 경계선으로 나눈 면들. 면마다 안쪽에 떠 있는 unit 자리는 구멍이다.
    ///
    /// 면 추적은 섬(떨어진 unit 묶음)을 구멍으로 빼지 못한다. 그래서 면을 찾은 뒤 'level − unit'과
    /// 겹치는 부분만 CoreGraphics로 잘라 내고, 흔들린 좌표는 원래 꼭짓점·교점으로 되돌린다.
    private func levelGapFaces(segments: [LineSegment]) -> ([ClosedPolygonFinder.Face], [String: [[LocalPoint]]]) {
        let levels = features.features(ofType: .level).filter { !$0.polygonRings.isEmpty }.map(\.polygonRings)
        guard !levels.isEmpty else { return ([], [:]) }
        let units = features.features(ofType: .unit).filter { !$0.polygonRings.isEmpty }.map(\.polygonRings)
        var open = levels.dropFirst().reduce(UnitCoverage.path(levels[0])) { $0.union(UnitCoverage.path($1), using: .evenOdd) }
        if let first = units.first {
            let covered = units.dropFirst().reduce(UnitCoverage.path(first)) { $0.union(UnitCoverage.path($1), using: .evenOdd) }
            open = open.subtracting(covered, using: .evenOdd)
        }
        let source = levels.flatMap { $0 } + units.flatMap { $0 }
        let lines = segments.map { [$0.start, $0.end] }
        let openBox = open.boundingBoxOfPath
        var faces: [ClosedPolygonFinder.Face] = []
        var holes: [String: [[LocalPoint]]] = [:]
        for face in ClosedPolygonFinder.faces(in: segments.map { .init(segment: $0, objectID: nil) }, minimumArea: 0.5) {
            guard face.boundingBox.intersects(openBox) else { continue }
            let region = UnitCoverage.path([face.ring]).intersection(open, using: .evenOdd)
            for piece in region.componentsSeparated(using: .evenOdd) {
                let rings = Self.rings(of: piece).map { ring in
                    ring.map { Self.restore($0, from: source + [face.ring], polylines: lines) }
                }
                guard let outer = rings.max(by: { abs(ClosedPolygonFinder.signedArea($0)) < abs(ClosedPolygonFinder.signedArea($1)) })
                else { continue }
                let area = abs(UnitCoverage.area(UnitCoverage.path(rings)))
                guard area >= 0.5 else { continue }
                let box = ClosedPolygonFinder.boundingBox(outer)
                let id = String(format: "level-gap:%d:%.3f:%.3f:%.3f", outer.count, area, box.minX, box.minY)
                faces.append(ClosedPolygonFinder.Face(id: id, ring: outer, memberIDs: [], usesTemporaryDoor: false,
                                                      area: area, boundingBox: box))
                let inner = rings.filter { $0 != outer }
                if !inner.isEmpty { holes[id] = inner }
            }
        }
        return (faces, holes)
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
            if let near { owners[face.id] = near.0; continue }
            if let cover = coveringFeature(of: face, type: type) { owners[face.id] = cover }
        }
        return owners
    }

    /// 같은 모양은 아니어도 이 면을 거의 다(99%) 덮는 지금 레이어의 feature.
    /// 구멍이 많은 MultiPolygon unit(예: level 기준으로 저장한 복도)은 면 추적에서 여러 조각으로 잘려
    /// 같은 모양 검사에 걸리지 않는다. 그대로 두면 이미 저장한 자리가 다시 고를 수 있는 면으로 뜨고 강조도 안 된다.
    private func coveringFeature(of face: ClosedPolygonFinder.Face, type: IMDFFeatureType) -> FeatureGroupID? {
        for f in features.features(ofType: type) where !f.isInTrash && !f.polygonRings.isEmpty {
            let box = ClosedPolygonFinder.boundingBox(f.polygonRings.flatMap { $0 })
            guard box.insetBy(dx: -1e-6, dy: -1e-6).contains(face.boundingBox) else { continue }
            if Self.overlapArea([face.ring], f.polygonRings) >= face.area * 0.99 { return f.id }
        }
        return nil
    }

    private static func bounds(of ring: [LocalPoint]) -> CGRect {
        let xs = ring.map(\.x), ys = ring.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
