import Foundation

/// 한 feature 안 링들의 포함 관계. 구멍은 따로 저장하지 않고 **링끼리 감싸는 관계**에서 정한다.
///
/// 다른 링에 홀수 번 둘러싸인 링이 구멍이다. 새 링이 기존 링을 감싸면 기존 링이 구멍이 되고,
/// 기존 링 안에 새 링을 그리면 새 링이 구멍이 된다. 구멍 안에 또 그리면 다시 섬(다각형)이 된다.
/// 저장 형식이 링 목록 그대로라 이전 파일도 그대로 읽힌다.
enum RingNesting {
    enum Relation: Equatable { case disjoint, inside, contains, overlap, duplicate }

    private enum Location { case inside, outside, boundary }

    /// `a`가 `b`에 대해 어디 있는가. 변이 맞닿기만 한 것(옆방과 벽을 나눠 쓰는 면)은 떨어진 것으로 본다.
    static func relation(_ a: [LocalPoint], to b: [LocalPoint]) -> Relation {
        guard a.count >= 3, b.count >= 3 else { return .disjoint }
        if edgesCross(a, b) { return .overlap }
        let (aIn, aOut) = count(samples(a), in: b)
        let (bIn, bOut) = count(samples(b), in: a)
        if aOut == 0 && bOut == 0 { return .duplicate }
        if aOut == 0 && aIn > 0 { return .inside }
        if bOut == 0 && bIn > 0 { return .contains }
        if aIn == 0 && bIn == 0 { return .disjoint }
        return .overlap
    }

    /// 점이 링 안쪽에 있는가. 변 위는 안쪽이 아니다.
    static func contains(_ ring: [LocalPoint], _ p: LocalPoint) -> Bool { locate(p, in: ring) == .inside }

    /// 링마다 자기를 감싸는 다른 링의 수. 짝수면 다각형, 홀수면 구멍이다.
    static func depths(_ rings: [[LocalPoint]]) -> [Int] {
        rings.indices.map { i in
            rings.indices.filter { j in j != i && relation(rings[i], to: rings[j]) == .inside }.count
        }
    }

    /// 내보낼 다각형들. 바깥 링마다 바로 안쪽 구멍을 붙인다.
    static func polygons(_ rings: [[LocalPoint]]) -> [(outer: Int, holes: [Int])] {
        let depth = depths(rings)
        return rings.indices.filter { depth[$0] % 2 == 0 }.map { outer in
            let holes = rings.indices.filter { h in
                depth[h] == depth[outer] + 1 && relation(rings[h], to: rings[outer]) == .inside
            }
            return (outer, holes)
        }
    }

    /// 어긋나게 겹치거나 똑같은 링이 없는가. 감싸기·떨어짐·맞닿음만 허용한다.
    static func isValid(_ rings: [[LocalPoint]]) -> Bool {
        for i in rings.indices {
            for j in rings.indices where j > i {
                let r = relation(rings[i], to: rings[j])
                if r == .overlap || r == .duplicate { return false }
            }
        }
        return true
    }

    // MARK: 계산

    private static let eps = 1e-6

    /// 꼭짓점과 변 중점. 꼭짓점만 보면 꼭짓점이 모두 상대 경계에 놓인 경우(현을 긋는 삼각형)를 놓친다.
    private static func samples(_ ring: [LocalPoint]) -> [LocalPoint] {
        var points = ring
        for i in ring.indices {
            let p = ring[i], q = ring[(i + 1) % ring.count]
            points.append(LocalPoint((p.x + q.x) / 2, (p.y + q.y) / 2))
        }
        return points
    }

    private static func count(_ points: [LocalPoint], in ring: [LocalPoint]) -> (inside: Int, outside: Int) {
        var inside = 0, outside = 0
        for p in points {
            switch locate(p, in: ring) {
            case .inside: inside += 1
            case .outside: outside += 1
            case .boundary: break
            }
        }
        return (inside, outside)
    }

    private static func locate(_ p: LocalPoint, in ring: [LocalPoint]) -> Location {
        var inside = false
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            if distance(p, toSegment: a, b) <= eps { return .boundary }
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside ? .inside : .outside
    }

    private static func distance(_ p: LocalPoint, toSegment a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return p.distance(to: LocalPoint(a.x + t * dx, a.y + t * dy))
    }

    /// 두 링의 변이 X자로 가로지르는가. 끝점에서 만나거나 겹쳐 놓인 것은 맞닿음이다.
    private static func edgesCross(_ a: [LocalPoint], _ b: [LocalPoint]) -> Bool {
        func orient(_ p: LocalPoint, _ q: LocalPoint, _ r: LocalPoint) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        for i in a.indices {
            let p1 = a[i], p2 = a[(i + 1) % a.count]
            for j in b.indices {
                let q1 = b[j], q2 = b[(j + 1) % b.count]
                let d1 = orient(q1, q2, p1), d2 = orient(q1, q2, p2)
                let d3 = orient(p1, p2, q1), d4 = orient(p1, p2, q2)
                if ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps))
                    && ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps)) { return true }
            }
        }
        return false
    }
}

extension FeatureGroup {
    /// 내보낼 때 MultiPolygon인가. fixture는 type이 MultiPolygon이고, 다른 면 type은 우측 패널에서 지정한다.
    var isMultiPolygon: Bool { featureType.requiredGeometry == .multiPolygon || multiPolygon == true }
}

@MainActor
extension AppEnvironment {

    /// 우측 패널에서 MultiPolygon으로 지정할 수 있는가. 스펙상 POLYGONAL인 모든 type이고, 링이 저장돼 있어야 한다.
    func canDesignateMultiPolygon(_ f: FeatureGroup) -> Bool {
        f.featureType.requiresClosedRing && !f.polygonRings.isEmpty
    }

    /// 지금 이 레이어에서 새 다각형을 받는 feature. 다른 레이어거나 휴지통에 있으면 없는 것으로 본다.
    func multiPolygonTarget(for type: IMDFFeatureType) -> FeatureGroupID? {
        guard let id = multiPolygonTargetID, let f = features.feature(id),
              !f.isInTrash, f.featureType == type, f.isMultiPolygon else { return nil }
        return id
    }

    func multiPolygonSummary(_ f: FeatureGroup) -> (polygons: Int, holes: Int) {
        let depth = RingNesting.depths(f.polygonRings)
        let holes = depth.filter { $0 % 2 == 1 }.count
        return (depth.count - holes, holes)
    }

    func designateMultiPolygon(_ id: FeatureGroupID) {
        guard let f = features.feature(id), canDesignateMultiPolygon(f) else { return }
        if f.multiPolygon != true, f.featureType.requiredGeometry != .multiPolygon {
            perform("\(f.serialNumber) MultiPolygon 지정") { features.update(id) { $0.multiPolygon = true } }
        }
        notify("\(f.serialNumber)을 MultiPolygon으로 지정했습니다. 다각형을 더하려면 '다각형 추가'를 누르세요.")
        // 지정만으로는 추가를 켜지 않는다(2026-10-19 요청). 예전에는 지정과 동시에 추가가 켜져,
        // 그 뒤에 그린 다른 도형이 모르는 사이 이 feature의 다각형으로 들어갔다.
    }

    /// '다각형 추가'를 눌렀을 때만 새 다각형을 이 feature로 받는다. '추가 끝내기'까지 유지된다.
    func startMultiPolygonAdding(_ id: FeatureGroupID) {
        guard let f = features.feature(id), f.isMultiPolygon else { return }
        multiPolygonTargetID = id
        notify("\(f.serialNumber)에 다각형을 더합니다. 바깥을 감싸면 기존 다각형이 구멍이 되고, 안쪽에 그리면 새 다각형이 구멍이 됩니다.")
    }

    func finishMultiPolygonAdding() { multiPolygonTargetID = nil }

    /// 다각형이 하나뿐일 때만 Polygon으로 되돌린다. 여럿이면 하나로 줄일 방법이 없어 막는다.
    func releaseMultiPolygon(_ id: FeatureGroupID) {
        guard let f = features.feature(id), f.multiPolygon == true else { return }
        guard f.polygonRings.count == 1 else {
            notify("다각형·구멍이 여러 개라 Polygon으로 되돌릴 수 없습니다. cmd+z로 추가를 되돌리세요.", isError: true)
            return
        }
        perform("\(f.serialNumber) Polygon으로 되돌리기") { features.update(id) { $0.multiPolygon = nil } }
        if multiPolygonTargetID == id { multiPolygonTargetID = nil }
    }

    /// 지정한 feature에 링을 더한다. 기존 링과 어긋나게 겹치면 받지 않는다 — 구멍인지 섬인지 정할 수 없다.
    @discardableResult
    func addRingToMultiPolygon(_ ring: [LocalPoint], target id: FeatureGroupID,
                               faceID: String? = nil, members: Set<VectorObjectID> = []) -> Bool {
        guard let f = features.feature(id) else { return false }
        let rings = f.polygonRings + [ring]
        for old in f.polygonRings {
            switch RingNesting.relation(ring, to: old) {
            case .overlap:
                notify("새 다각형이 \(f.serialNumber)의 다각형과 어긋나게 겹칩니다. 완전히 감싸거나 완전히 안쪽에 그려야 합니다.", isError: true)
                return false
            case .duplicate:
                notify("\(f.serialNumber)에 같은 다각형이 이미 있습니다.", isError: true)
                return false
            default:
                continue
            }
        }
        let isHole = RingNesting.depths(rings).last.map { $0 % 2 == 1 } ?? false
        perform("\(f.serialNumber)에 다각형 추가") {
            features.update(id) {
                $0.polygonRings.append(ring)
                if let faceID { $0.polygonFaceIDs.insert(faceID) }
            }
            let free = members.filter { ownership.ownerOf($0) == nil }
            try? ownership.claim(free, for: id)
            pointDraft = PointDraft()
        }
        let summary = multiPolygonSummary(features.feature(id)!)
        notify("\(f.serialNumber)에 \(isHole ? "구멍" : "다각형")을 더했습니다. (다각형 \(summary.polygons) · 구멍 \(summary.holes))")
        return true
    }
}
