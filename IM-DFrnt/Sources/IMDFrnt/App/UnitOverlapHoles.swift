import CoreGraphics
import Foundation

/// unit 카드를 펼치면 그 unit과 겹치는 다른 unit을 빨간색으로 보이고, 펼친 unit이 MultiPolygon이면
/// 빨간 unit의 이름표를 눌러 **그 모양대로 구멍을 뚫는다**(2026-10-18 요청).
///
/// 겹침은 넓이가 있는 교집합만 센다. 벽을 나눠 쓰며 맞닿기만 한 이웃은 겹친 것이 아니다(`UnitCoverage`와 같은 기준).
struct UnitOverlapCache {
    var expanded: Set<FeatureGroupID>
    var units: [[[LocalPoint]]]
    var overlapping: Set<FeatureGroupID>
}

@MainActor
extension AppEnvironment {

    /// 펼친 unit과 넓이 있게 겹치는 다른 unit. unit 레이어를 보고 있을 때만 채운다.
    var unitsOverlappingExpanded: Set<FeatureGroupID> {
        guard layers.activePropertyType == .unit else { return [] }
        let all = features.features(ofType: .unit).filter { !$0.isInTrash && !$0.polygonRings.isEmpty }
        let expanded = expandedFeatures.filter { id in all.contains { $0.id == id } }
        guard !expanded.isEmpty else { return [] }
        let units = all.map(\.polygonRings)
        if let c = unitOverlapCache, c.expanded == expanded, c.units == units { return c.overlapping }
        var out = Set<FeatureGroupID>()
        for base in all where expanded.contains(base.id) {
            for other in all where other.id != base.id && !expanded.contains(other.id) {
                if Self.overlapArea(base.polygonRings, other.polygonRings) >= UnitCoverage.minimumArea { out.insert(other.id) }
            }
        }
        unitOverlapCache = UnitOverlapCache(expanded: expanded, units: units, overlapping: out)
        return out
    }

    static func overlapArea(_ a: [[LocalPoint]], _ b: [[LocalPoint]]) -> Double {
        let pa = UnitCoverage.path(a), pb = UnitCoverage.path(b)
        guard pa.boundingBoxOfPath.intersects(pb.boundingBoxOfPath) else { return 0 }
        return pa.intersection(pb, using: .evenOdd).componentsSeparated(using: .evenOdd)
            .map { abs(UnitCoverage.area($0)) }.reduce(0, +)
    }

    /// 이름표 클릭. 펼친 MultiPolygon unit과 겹치는 unit이면 구멍을 뚫고 true. 아니면 종전 클릭으로 넘긴다.
    func handleFeatureTagClick(_ other: FeatureGroupID) -> Bool {
        guard unitsOverlappingExpanded.contains(other), let g = features.feature(other) else {
            guard features.feature(other) != nil else { return false }
            if focusedFeature == other, expandedFeatures == [other] { toggleFeatureExpansion(other) }
            else { expandedFeature = other }
            return true
            // 빨간 이름표가 아니면 그 feature를 고른다 — 우측 패널 카드를 펼친 것과 같다(모든 레이어).
            // 이미 그것만 골라져 있으면 다시 눌러 접는다. 이름표를 누른 클릭은 점 찍기·면 고르기로 넘어가지 않는다.
        }
        let targets = expandedFeatures.compactMap { features.feature($0) }
            .filter { $0.featureType == .unit && $0.isMultiPolygon
                && Self.overlapArea($0.polygonRings, g.polygonRings) >= UnitCoverage.minimumArea }
        guard let f = targets.first(where: { $0.id == focusedFeature }) ?? targets.first else {
            notify("\(g.serialNumber)는 펼친 unit과 겹칩니다. 펼친 unit을 MultiPolygon으로 지정하면 이름표를 눌러 그 모양대로 구멍을 뚫을 수 있습니다.")
            return true
            // 이름표를 누른 것이라 점을 찍지 않는다. 겹친 사실과 할 일만 알린다.
        }
        punchHole(in: f.id, shapeOf: g.id)
        return true
    }

    /// `target`에서 `shape` 모양을 뺀다. 통째로 안쪽이면 그 링을 구멍으로 더하고(좌표 그대로),
    /// 걸쳐 있으면 겹친 만큼 깎아 낸 링으로 바꾼다.
    func punchHole(in target: FeatureGroupID, shapeOf shape: FeatureGroupID) {
        guard let f = features.feature(target), let g = features.feature(shape) else { return }
        let gOuters = g.polygonRings.enumerated()
            .filter { RingNesting.depths(g.polygonRings)[$0.offset] % 2 == 0 }.map(\.element)
        var rings = f.polygonRings
        let insideOnly = gOuters.allSatisfy { ring in
            f.polygonRings.contains { RingNesting.relation(ring, to: $0) == .inside }
                && !f.polygonRings.contains { [RingNesting.Relation.overlap, .duplicate].contains(RingNesting.relation(ring, to: $0)) }
        }
        if insideOnly {
            rings += gOuters
        } else {
            let cut = UnitCoverage.path(f.polygonRings).subtracting(UnitCoverage.path(g.polygonRings), using: .evenOdd)
            let source = f.polygonRings + g.polygonRings
            rings = Self.rings(of: cut).map { ring in ring.map { Self.restore($0, from: source) } }
            // CoreGraphics 계산을 지나면 꼭짓점이 1e-6쯤 흔들린다. 원래 두 unit의 좌표로 되돌려야
            // 이웃 unit과 좌표가 정확히 같아 틈이 생기지 않는다.
        }
        // 통째로 안쪽인 구멍은 상대 unit의 꼭짓점을 그대로 쓴다. 같은 좌표라야 두 unit 사이에 틈이 생기지 않는다.
        guard !rings.isEmpty, RingNesting.isValid(rings) else {
            notify("\(g.serialNumber) 모양으로 구멍을 낼 수 없습니다. 남는 모양이 서로 어긋나게 겹칩니다.", isError: true)
            return
        }
        perform("\(f.serialNumber)에 \(g.serialNumber) 모양 구멍") {
            features.update(target) {
                $0.polygonRings = rings
                $0.polygonFaceIDs = []
            }
        }
        let s = multiPolygonSummary(features.feature(target)!)
        notify("\(f.serialNumber)에서 \(g.serialNumber) 모양을 뺐습니다. (다각형 \(s.polygons) · 구멍 \(s.holes))")
    }

    /// 흔들린 점을 원래 좌표로. 원래 꼭짓점이 가까우면 그 점, 아니면 지나는 원래 변 두 개의 정확한 교점이다.
    /// `polylines`는 닫히지 않은 선(자르는 선·보조 선분)이다. 끝점과 첫 점 사이를 변으로 보지 않는다.
    static func restore(_ p: LocalPoint, from rings: [[LocalPoint]], polylines: [[LocalPoint]] = [],
                        tolerance: Double = 1e-3) -> LocalPoint {
        let vertices = (rings + polylines).flatMap { $0 }
        if let v = vertices.first(where: { $0.distance(to: p) < tolerance }) { return v }
        var candidates: [(LocalPoint, LocalPoint)] = []
        for ring in rings where ring.count >= 2 {
            for i in ring.indices { candidates.append((ring[i], ring[(i + 1) % ring.count])) }
        }
        for line in polylines where line.count >= 2 {
            for i in 0..<(line.count - 1) { candidates.append((line[i], line[i + 1])) }
        }
        var edges: [(LocalPoint, LocalPoint)] = []
        for (a, b) in candidates {
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            guard len2 > 0 else { continue }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            if LocalPoint(a.x + t * dx, a.y + t * dy).distance(to: p) < tolerance { edges.append((a, b)) }
        }
        for i in edges.indices {
            for j in edges.indices where j > i {
                let (a, b) = edges[i], (c, d) = edges[j]
                let den = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
                guard abs(den) > 1e-12 else { continue }
                let t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / den
                let q = LocalPoint(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y))
                if q.distance(to: p) < tolerance { return q }
            }
        }
        return p
    }

    /// 직선만 있는 경로를 링 목록으로. 같은 자리 점과 넓이 없는 조각은 버린다.
    static func rings(of path: CGPath) -> [[LocalPoint]] {
        var out: [[LocalPoint]] = []
        var current: [LocalPoint] = []
        func flush() {
            let ring = VertexExtractor.dedup(current, epsilon: SnapPointExtractor.mergeTolerance / 10)
            var r = ring
            if r.count > 1, r.first!.distance(to: r.last!) < 1e-9 { r.removeLast() }
            if r.count >= 3, !PolygonValidity.isDegenerate(r) { out.append(r) }
            current = []
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: flush(); current = [LocalPoint(Double(e.points[0].x), Double(e.points[0].y))]
            case .addLineToPoint: current.append(LocalPoint(Double(e.points[0].x), Double(e.points[0].y)))
            case .addQuadCurveToPoint: current.append(LocalPoint(Double(e.points[1].x), Double(e.points[1].y)))
            case .addCurveToPoint: current.append(LocalPoint(Double(e.points[2].x), Double(e.points[2].y)))
            case .closeSubpath: flush()
            @unknown default: break
            }
        }
        flush()
        return out.filter { abs(UnitCoverage.area(UnitCoverage.path([$0]))) >= UnitCoverage.minimumArea }
    }
}
