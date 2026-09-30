import Foundation

/// 폴리곤 링이 실제로 닫히는지 판정한다(명세 10-4).
///
/// **눈으로 붙어 보여도 미세하게 벌어져 있으면 닫히지 않는다.** CAD 도면은 선 끝이 정확히
/// 맞물리는 일이 드물어서, 허용 오차 안이면 스냅으로 붙인 것으로 간주한다.
/// Esri ArcGIS Indoors의 대응 개념이 `Door Close Buffer` — "used to account for
/// poor CAD topology — for example, line gaps between doors and walls."
enum RingClosureValidator {

    /// 링이 끊긴 지점 하나.
    struct Gap: Hashable {
        let point: LocalPoint
        // 끊긴 끝점의 위치. 캔버스에 이 자리를 표시한다(명세 10-4-3).
        let distance: Double
        // 가장 가까운 다른 끝점까지의 거리(도면 단위). 0이면 짝이 아예 없다는 뜻이 아니라
        // 짝을 못 찾았다는 뜻이므로, `nearestFound`로 구분한다.
        let nearestFound: Bool
    }

    struct Result: Equatable {
        var isClosed: Bool = true
        var gaps: [Gap] = []

        var worstGap: Double { gaps.map(\.distance).max() ?? 0 }
    }

    /// 선분들이 하나의 닫힌 링을 이루는지 본다.
    ///
    /// 판정 방식은 **끝점 짝짓기**다. 닫힌 링에서는 모든 끝점이 다른 선분의 끝점과 만나
    /// 짝수 번 쓰인다. 홀수로 남은 끝점이 곧 벽이 끊긴 자리 — 대개 문이 뚫린 곳이다.
    /// 면적이나 방향 대신 이 방식을 쓰는 이유는, **어디가 벌어졌는지를 좌표로 짚어야**
    /// 사용자에게 그 지점을 보여줄 수 있기 때문이다(명세 10-4-3).
    static func validate(segments: [LineSegment], tolerance: Double) -> Result {
        let usable = segments.filter { $0.length > tolerance }
        // 길이가 오차보다 짧은 선분은 점이나 다름없어 링의 변으로 세면 판정이 흔들린다.
        guard usable.count >= 3 else {
            return Result(isClosed: false, gaps: [])
            // 변이 3개 미만이면 애초에 폴리곤이 아니다. 벌어진 지점을 짚을 것도 없다.
        }

        var endpoints: [(point: LocalPoint, segment: Int)] = []
        for (i, s) in usable.enumerated() {
            endpoints.append((s.start, i))
            endpoints.append((s.end, i))
        }

        var gaps: [Gap] = []
        for (i, e) in endpoints.enumerated() {
            var nearest = Double.infinity
            for (j, other) in endpoints.enumerated() where i != j && e.segment != other.segment {
                // 같은 선분의 반대쪽 끝은 짝이 될 수 없다 — 그건 변 자신이다.
                nearest = min(nearest, e.point.distance(to: other.point))
            }
            if nearest > tolerance {
                gaps.append(Gap(point: e.point,
                                distance: nearest.isFinite ? nearest : 0,
                                nearestFound: nearest.isFinite))
            }
        }

        return Result(isClosed: gaps.isEmpty, gaps: dedup(gaps, tolerance: tolerance))
    }

    /// 같은 자리에서 여러 번 잡힌 틈을 하나로 줄인다.
    /// 벌어진 곳 하나가 양쪽 끝점 모두에서 잡히면 사용자에게는 두 곳으로 보인다.
    private static func dedup(_ gaps: [Gap], tolerance: Double) -> [Gap] {
        var out: [Gap] = []
        for g in gaps {
            if out.contains(where: { $0.point.distance(to: g.point) <= tolerance }) { continue }
            out.append(g)
        }
        return out.sorted { $0.distance > $1.distance }
        // 가장 크게 벌어진 곳부터 보여준다 — 손으로 고칠 때 그쪽이 먼저다.
    }
}
