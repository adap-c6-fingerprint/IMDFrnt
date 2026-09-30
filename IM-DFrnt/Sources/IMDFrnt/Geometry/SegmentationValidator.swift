import Foundation

/// 명세 8-4-3)의 두 제약을 기하학적으로 검사한다.
/// `SegmentationStore`가 선분화 결과를 받아들이기 전에 반드시 통과해야 한다.
enum SegmentationValidator {

    static func validate(_ segments: [LineSegment], epsilon: Double = 1e-6) -> [SegmentationDefect] {
        var defects: [SegmentationDefect] = []
        defects.append(contentsOf: checkContiguity(segments, epsilon: epsilon))
        defects.append(contentsOf: checkNonCrossing(segments, epsilon: epsilon))
        return defects
    }

    /// 인접 선분의 끝점이 epsilon 안에서 반드시 만나는지.
    private static func checkContiguity(_ s: [LineSegment], epsilon: Double) -> [SegmentationDefect] {
        var out: [SegmentationDefect] = []
        for i in 0..<max(0, s.count - 1) {
            let d = s[i].end.distance(to: s[i + 1].start)
            if d > epsilon { out.append(.gap(index: i, distance: d)) }
        }
        return out
    }

    /// 인접하지 않은 선분끼리 내부를 가로지르는지.
    /// 인접 선분이 공유 끝점에서 만나는 것은 교차가 아니다.
    private static func checkNonCrossing(_ s: [LineSegment], epsilon: Double) -> [SegmentationDefect] {
        var out: [SegmentationDefect] = []
        guard s.count > 2 else { return out }
        for i in 0..<s.count {
            guard i + 2 < s.count else { break }
            // i가 끝에 가까우면 비교 상대가 없다. 범위를 만들기 전에 빠져나간다.
            for j in (i + 2)..<s.count {
                if i == 0 && j == s.count - 1 { continue }
                // 닫힌 경로의 첫·마지막 선분은 서로 인접이다.
                if let p = properIntersection(s[i], s[j], epsilon: epsilon) {
                    out.append(.crossing(i, j, at: p))
                }
            }
        }
        return out
    }

    /// 두 선분이 끝점이 아닌 내부에서 만나는 지점. 끝점 접촉은 nil.
    static func properIntersection(_ a: LineSegment, _ b: LineSegment, epsilon: Double) -> LocalPoint? {
        let r = (a.end.x - a.start.x, a.end.y - a.start.y)
        let s = (b.end.x - b.start.x, b.end.y - b.start.y)
        let denom = r.0 * s.1 - r.1 * s.0
        if abs(denom) < 1e-12 { return nil }
        let qp = (b.start.x - a.start.x, b.start.y - a.start.y)
        let t = (qp.0 * s.1 - qp.1 * s.0) / denom
        let u = (qp.0 * r.1 - qp.1 * r.0) / denom
        let margin = 1e-7
        guard t > margin, t < 1 - margin, u > margin, u < 1 - margin else { return nil }
        return LocalPoint(a.start.x + t * r.0, a.start.y + t * r.1)
    }
}
