import Foundation

/// 이웃 도형에 꼭짓점을 맞춰 실오라기(아주 얇은 겹침·틈)를 막는다(2026-10-18 요청).
///
/// 포스텍 도서관 2층의 겹침 8곳을 재 보니 원인은 둘이었다.
/// ① T자 접점 — 한 unit의 꼭짓점이 이웃 unit의 변 한가운데 닿는데, 찍힌 도면 점이 그 변에서 0.002~0.05 벗어나 있다.
/// ② 거의 같은 꼭짓점 — 같은 모서리를 0.01~0.02 떨어진 다른 점(도면 점과 이웃 꼭짓점)으로 찍었다.
/// 그래서 점을 찍을 때와 저장할 때 모두, 이웃의 꼭짓점·변에서 `alignTolerance` 안이면 그 좌표로 맞춘다.
/// 0.1은 이 도면의 벽 두께(약 2)보다 훨씬 작아 엉뚱한 점에 붙을 일이 없다.
@MainActor
extension AppEnvironment {
    static let alignTolerance = 0.1

    /// 맞출 대상. 같은 type의 저장된 다각형이고, unit은 level 외곽선에도 맞춘다.
    func alignmentNeighbors(for type: IMDFFeatureType?, excluding: FeatureGroupID?) -> [FeatureGroup] {
        guard let type else { return [] }
        return features.features.filter { f in
            !f.isInTrash && f.id != excluding && !f.polygonRings.isEmpty
                && (f.featureType == type || (type == .unit && f.featureType == .level))
        }
    }

    /// 이웃 꼭짓점이 가까우면 그 점, 아니면 이웃 변이 가까우면 그 변 위로 정확히 투영한 점.
    func alignPoint(_ p: LocalPoint, to neighbors: [FeatureGroup], tolerance: Double = AppEnvironment.alignTolerance) -> LocalPoint {
        var best: (LocalPoint, Double)?
        for f in neighbors {
            for ring in f.polygonRings {
                for v in ring {
                    let d = v.distance(to: p)
                    if d <= tolerance, d < (best?.1 ?? .infinity) { best = (v, d) }
                }
            }
        }
        if let best { return best.0 }
        var edge: (LocalPoint, Double)?
        for f in neighbors {
            for ring in f.polygonRings where ring.count >= 2 {
                for i in ring.indices {
                    let q = Self.projection(of: p, onto: ring[i], ring[(i + 1) % ring.count])
                    let d = q.distance(to: p)
                    if d <= tolerance, d < (edge?.1 ?? .infinity) { edge = (q, d) }
                }
            }
        }
        return edge?.0 ?? p
    }

    /// 저장 직전의 링을 이웃에 맞춘다. 맞춘 결과가 꼬이거나 무너지면 원래 링을 그대로 쓴다.
    func alignRings(_ rings: [[LocalPoint]], type: IMDFFeatureType?, excluding: FeatureGroupID?) -> (rings: [[LocalPoint]], moved: Int) {
        let neighbors = alignmentNeighbors(for: type, excluding: excluding)
        guard !neighbors.isEmpty else { return (rings, 0) }
        var moved = 0
        let aligned = rings.map { ring -> [LocalPoint] in
            var out: [LocalPoint] = []
            for p in ring {
                let q = alignPoint(p, to: neighbors)
                if q != p { moved += 1 }
                if out.last != q { out.append(q) }
            }
            if out.count > 1, out.first == out.last { out.removeLast() }
            return out
        }
        let valid = aligned.allSatisfy { $0.count >= 3 && !PolygonValidity.selfIntersects($0) && !PolygonValidity.isDegenerate($0) }
            && RingNesting.isValid(aligned)
        return valid ? (aligned, moved) : (rings, 0)
    }

    /// 이 링들의 꼭짓점이 이웃(같은 type)의 변 한가운데 놓이면 그 이웃의 변에도 꼭짓점을 넣는다.
    /// 두 도형이 같은 꼭짓점을 함께 써야 나중에 한쪽 꼭짓점을 옮겨도 경계가 어긋나지 않는다. `perform` 안에서 부른다.
    @discardableResult
    func insertSharedVertices(of rings: [[LocalPoint]], type: IMDFFeatureType, excluding: FeatureGroupID?) -> [String] {
        let points = rings.flatMap { $0 }
        var touched: [String] = []
        for f in features.features where !f.isInTrash && f.id != excluding && f.featureType == type && !f.polygonRings.isEmpty {
            var newRings = f.polygonRings
            var changed = false
            for r in newRings.indices {
                var ring = newRings[r]
                var i = 0
                while i < ring.count {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    let inside = points.filter { p in
                        p != a && p != b && Self.projection(of: p, onto: a, b).distance(to: p) < 1e-9
                    }
                    .sorted { $0.distance(to: a) < $1.distance(to: a) }
                    if let first = inside.first {
                        ring.insert(first, at: i + 1)
                        changed = true
                    }
                    i += 1
                    // 끼운 점 뒤의 변을 다음 차례에 다시 본다. 한 변에 점이 여럿이어도 차례로 들어간다.
                }
                newRings[r] = ring
            }
            if changed, RingNesting.isValid(newRings) {
                features.update(f.id) { $0.polygonRings = newRings; $0.polygonFaceIDs = [] }
                touched.append(f.serialNumber)
            }
        }
        return touched
    }

    /// 알림 끝에 붙일 한 줄.
    static func alignmentNote(moved: Int, shared: [String]) -> String {
        var parts: [String] = []
        if moved > 0 { parts.append("이웃에 맞춘 꼭짓점 \(moved)개") }
        if !shared.isEmpty { parts.append("꼭짓점을 함께 넣은 이웃: \(shared.joined(separator: ", "))") }
        return parts.isEmpty ? "" : " (" + parts.joined(separator: " · ") + ")"
    }
}
