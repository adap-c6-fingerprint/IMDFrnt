import Foundation

/// 명세 8-4)의 '선분화'. 곡률에 맞춰 적응 분할한다(균등 분할이 아니다 —
/// 완만한 구간에 점을 낭비하지 않기 위해).
enum CurveFlattener {

    static let defaultTolerance: Double = 0.6

    /// 반환 타입이 `PathGeometry`가 아니라 `[LineSegment]`인 것이 중요하다.
    /// 명세 8-4-3)이 "하나로 이어진 폴리라인이 아니라 개별 선분"을 요구하기 때문이다.
    static func flatten(_ geometry: PathGeometry, tolerance: Double = defaultTolerance) -> [LineSegment] {
        geometry.lineSegments(tolerance: tolerance)
    }

    /// de Casteljau 적응 분할. 반환값은 시작점을 포함한 점 목록이다.
    static func subdivideCubic(_ p0: LocalPoint, _ p1: LocalPoint,
                               _ p2: LocalPoint, _ p3: LocalPoint,
                               tolerance: Double) -> [LocalPoint] {
        var out: [LocalPoint] = [p0]
        recurse(p0, p1, p2, p3, tolerance: max(tolerance, 0.01), depth: 0, into: &out)
        out.append(p3)
        return out
    }

    private static func recurse(_ p0: LocalPoint, _ p1: LocalPoint,
                                _ p2: LocalPoint, _ p3: LocalPoint,
                                tolerance: Double, depth: Int, into out: inout [LocalPoint]) {
        if depth > 16 { return }
        if flatEnough(p0, p1, p2, p3, tolerance: tolerance) { return }

        func mid(_ a: LocalPoint, _ b: LocalPoint) -> LocalPoint {
            LocalPoint((a.x + b.x) / 2, (a.y + b.y) / 2)
        }
        let p01 = mid(p0, p1), p12 = mid(p1, p2), p23 = mid(p2, p3)
        let p012 = mid(p01, p12), p123 = mid(p12, p23)
        let center = mid(p012, p123)

        recurse(p0, p01, p012, center, tolerance: tolerance, depth: depth + 1, into: &out)
        out.append(center)
        recurse(center, p123, p23, p3, tolerance: tolerance, depth: depth + 1, into: &out)
    }

    /// 제어점이 시작-끝 직선에서 얼마나 벗어났는지로 평탄도를 판정한다.
    private static func flatEnough(_ p0: LocalPoint, _ p1: LocalPoint,
                                   _ p2: LocalPoint, _ p3: LocalPoint,
                                   tolerance: Double) -> Bool {
        let base = LineSegment(start: p0, end: p3)
        return base.distance(to: p1) <= tolerance && base.distance(to: p2) <= tolerance
    }
}
