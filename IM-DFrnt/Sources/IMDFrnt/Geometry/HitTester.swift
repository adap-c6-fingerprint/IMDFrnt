import CoreGraphics
import Foundation

/// 캔버스 클릭 좌표 → 개체 판정.
enum HitTester {

    /// stroke만 있는 개체는 두께 기반 허용오차를 준다.
    static func hitTest(_ point: LocalPoint,
                        candidates: [VectorObject],
                        cached: (VectorObject) -> (segments: [LineSegment], box: CGRect),
                        offsets: [VectorObjectID: CGSize] = [:],
                        tolerance: Double) -> VectorObjectID? {
        var best: (id: VectorObjectID, distance: Double)?

        for obj in candidates.reversed() {
            // 위에 그려진 개체가 먼저 잡히도록 역순으로 본다.
            let entry = cached(obj)
            let off = offsets[obj.id] ?? .zero
            // 화면에서 옮긴 개체는 옮긴 자리에서 클릭이 맞아야 한다(명세 2-3, 2026-08-25 재도입).
            // 개체를 옮긴 사본을 만드는 대신 **클릭 좌표를 반대로 옮겨** 원본과 견준다 —
            // 개체 수천 개짜리 도면에서 사본을 만드는 비용이 클릭 한 번마다 들었다.
            let p = off == .zero ? point
                                 : LocalPoint(point.x - off.width, point.y - off.height)
            let pad = tolerance + obj.style.strokeWidth / 2
            guard entry.box.insetBy(dx: -pad, dy: -pad).contains(p.cg) else { continue }

            if obj.style.fill != nil, containsPoint(p, inSegments: entry.segments) {
                return obj.id
            }
            let d = entry.segments.map { $0.distance(to: p) }.min() ?? .infinity
            if d <= pad, d < (best?.distance ?? .infinity) {
                best = (obj.id, d)
            }
        }
        return best?.id
    }

    /// 캐시가 없는 곳에서 쓰는 기본 조회 함수.
    static func directGeometry(_ segmentation: SegmentationStore)
    -> (VectorObject) -> (segments: [LineSegment], box: CGRect) {
        OverlapDetector.directGeometry(segmentation)
    }

    /// ray casting. 채워진 개체의 내부 클릭 판정에 쓴다.
    static func containsPoint(_ p: LocalPoint, in geometry: PathGeometry) -> Bool {
        containsPoint(p, inSegments: geometry.lineSegments())
    }

    static func containsPoint(_ p: LocalPoint, inSegments segs: [LineSegment]) -> Bool {
        var inside = false
        for s in segs {
            let (a, b) = (s.start, s.end)
            if (a.y > p.y) != (b.y > p.y) {
                let t = (p.y - a.y) / (b.y - a.y)
                if p.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
        }
        return inside
    }

    static func containsPoint(_ p: LocalPoint, inAnyOf ids: Set<VectorObjectID>,
                              document: DrawingDocument) -> Bool {
        for id in ids {
            guard let o = document.object(id) else { continue }
            if containsPoint(p, in: o.geometry) { return true }
            if o.boundingBox.insetBy(dx: -4, dy: -4).contains(p.cg) { return true }
        }
        return false
    }
}

// MARK: 드래그 사각형 선택 (명세 디버깅 9번)

extension HitTester {

    /// 드래그 사각형의 판정 방식. 도면 CAD의 관례를 그대로 따른다.
    ///
    /// 도면에서는 벽선 하나가 화면 밖까지 길게 뻗어 있는 일이 흔하다.
    /// '완전히 감싸야 선택'만 있으면 그런 선은 영영 못 고르고,
    /// '스치면 선택'만 있으면 방 하나를 고르려다 지나가는 벽까지 딸려 온다.
    /// 두 방향을 다 열어 두고, 드래그 방향으로 어느 쪽인지 고르게 한다.
    enum MarqueeMode {
        /// 좌 → 우 드래그. 사각형 안에 **완전히 들어온** 개체만 고른다.
        case enclose
        /// 우 → 좌 드래그. 사각형에 **닿기만 해도** 고른다.
        case crossing

        /// 드래그 시작점보다 끝점이 왼쪽이면 crossing.
        static func from(start: CGPoint, end: CGPoint) -> MarqueeMode {
            end.x < start.x ? .crossing : .enclose
        }
    }

    /// 드래그 사각형에 걸린 개체들. 화면에 보이는 후보만 넘겨받는 것을 전제한다.
    static func objects(in rect: CGRect,
                        mode: MarqueeMode,
                        candidates: [VectorObject],
                        cached: (VectorObject) -> (segments: [LineSegment], box: CGRect),
                        offsets: [VectorObjectID: CGSize] = [:]) -> [VectorObjectID] {
        guard rect.width > 0 || rect.height > 0 else { return [] }

        return candidates.compactMap { obj in
            let entry = cached(obj)
            let off = offsets[obj.id] ?? .zero
            let box = off == .zero ? entry.box
                                   : entry.box.offsetBy(dx: off.width, dy: off.height)

            switch mode {
            case .enclose:
                // bounding box가 다 들어왔다는 것은 개체 전체가 들어왔다는 뜻이다.
                return rect.contains(box) ? obj.id : nil

            case .crossing:
                guard box.intersects(rect) else { return nil }
                // box가 겹친다고 개체가 겹치는 것은 아니다(대각선으로 지나가는 선).
                // 실제 선분까지 봐야 "닿았다"가 성립한다.
                let localRect = off == .zero ? rect
                                             : rect.offsetBy(dx: -off.width, dy: -off.height)
                // 옮긴 개체는 사본을 만드는 대신 **사각형을 반대로 옮겨** 원본 선분과 견준다.
                if entry.segments.contains(where: { segment($0, intersects: localRect) }) {
                    return obj.id
                }
                // 채워진 개체 안에서 작게 드래그한 경우 — 선분은 하나도 안 닿지만
                // 사용자 눈에는 그 개체를 긁은 것이다.
                if obj.style.fill != nil,
                   containsPoint(LocalPoint(localRect.midX, localRect.midY),
                                 inSegments: entry.segments) {
                    return obj.id
                }
                return nil
            }
        }
    }

    /// 선분이 사각형과 닿는가. 끝점이 안에 있거나, 사각형의 네 변 중 하나와 교차하면 참이다.
    static func segment(_ s: LineSegment, intersects rect: CGRect) -> Bool {
        if rect.contains(s.start.cg) || rect.contains(s.end.cg) { return true }

        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            if segmentsCross(s.start.cg, s.end.cg, a, b) { return true }
        }
        return false
    }

    /// 두 선분이 실제로 교차하는가. 방향(외적 부호)이 양쪽 모두 갈리면 교차다.
    private static func segmentsCross(_ p1: CGPoint, _ p2: CGPoint,
                                      _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            Double((a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x))
        }
        let d1 = cross(p1, p2, q1), d2 = cross(p1, p2, q2)
        let d3 = cross(q1, q2, p1), d4 = cross(q1, q2, p2)
        return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
    }
}
