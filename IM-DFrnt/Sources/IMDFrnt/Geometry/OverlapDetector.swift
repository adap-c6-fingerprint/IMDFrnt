import CoreGraphics
import Foundation

/// 선택한 개체가 다른 벡터와 겹치는 지점을 찾는다.
/// 명세 2-3)의 '위치 이동'을 대신하는 기능(2026-08-25 확정) — 개체를 옆으로 밀어
/// 아래를 확인하는 대신, 겹치는 곳의 윤곽을 제자리에 표시한다.
enum OverlapDetector {

    /// 캐시가 없는 곳에서 쓰는 기본 조회 함수. 예전 동작 그대로 그때그때 계산한다.
    static func directGeometry(_ segmentation: SegmentationStore)
    -> (VectorObject) -> (segments: [LineSegment], box: CGRect) {
        { obj in
            let geo = segmentation.effectiveGeometry(for: obj.id, fallback: obj.geometry)
            return (geo.lineSegments(), geo.boundingBox)
        }
    }

    /// 겹침의 두 형태를 나눠 담는다. 표시 모양이 다르기 때문이다
    /// (교차점은 마커, 공유 구간은 굵은 선).
    struct Result {
        var crossings: [LocalPoint] = []
        var sharedSegments: [LineSegment] = []
        var partnerIDs: Set<VectorObjectID> = []

        var isEmpty: Bool { crossings.isEmpty && sharedSegments.isEmpty }
        var count: Int { crossings.count + sharedSegments.count }
    }

    /// 꼭짓점에서 만나기만 하는 것은 겹침이 아니다.
    /// 방 폴리곤의 모서리끼리 맞닿은 정상적인 도면이 전부 겹침으로 잡히면 표시가 의미를 잃는다.
    /// 여기서 걸러낸 '만나는 점'과 실제 '교차점'의 구분은 명세 디버깅 5번과 같은 기준이다.
    private static let endpointEpsilon = 1e-6

    static func detect(selected: Set<VectorObjectID>,
                       among candidates: [VectorObject],
                       cached: (VectorObject) -> (segments: [LineSegment], box: CGRect),
                       tolerance: Double) -> Result {
        guard !selected.isEmpty else { return Result() }

        var result = Result()
        var seenCrossings = Set<GridKey>()

        // 선분 목록과 bounding box는 **호출자가 넘긴 조회 함수**에서 받는다.
        // 앱에서는 `RenderCacheStore`가 도면을 열 때 한 번 만든 것을 그대로 주고,
        // 캐시가 없는 곳(`--selftest`)은 예전처럼 그때그때 계산하는 클로저를 넘긴다.
        var cache: [VectorObjectID: (segments: [LineSegment], box: CGRect)] = [:]
        cache.reserveCapacity(candidates.count)
        for obj in candidates { cache[obj.id] = cached(obj) }

        for id in selected.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let mine = cache[id] else { continue }
            let myBox = mine.box.insetBy(dx: -tolerance, dy: -tolerance)

            for other in candidates where other.id != id {
                guard let theirs = cache[other.id] else { continue }
                guard myBox.intersects(theirs.box.insetBy(dx: -tolerance, dy: -tolerance)) else { continue }
                // 둘 다 선택된 쌍은 한 번만 본다 — 양쪽에서 같은 겹침이 두 번 나온다.
                if selected.contains(other.id), other.id.uuidString < id.uuidString { continue }

                var hitPartner = false
                for a in mine.segments {
                    for b in theirs.segments {
                        if let p = crossing(a, b) {
                            let key = GridKey(p, tolerance: tolerance)
                            if seenCrossings.insert(key).inserted {
                                result.crossings.append(p)
                            }
                            hitPartner = true
                        } else if let s = sharedRun(a, b, tolerance: tolerance) {
                            result.sharedSegments.append(s)
                            hitPartner = true
                        }
                    }
                }
                if hitPartner { result.partnerIDs.insert(other.id) }
            }
        }
        return result
    }

    // MARK: 선분 대 선분

    /// 두 선분이 실제로 가로지르는 지점. 끝점끼리 맞닿기만 한 '만나는 점'은 nil이다.
    static func crossing(_ a: LineSegment, _ b: LineSegment) -> LocalPoint? {
        let r = CGVector(dx: a.end.x - a.start.x, dy: a.end.y - a.start.y)
        let s = CGVector(dx: b.end.x - b.start.x, dy: b.end.y - b.start.y)
        let denom = r.dx * s.dy - r.dy * s.dx
        guard abs(denom) > 1e-12 else { return nil }
        // 평행·동일선상은 여기서 답이 없다. sharedRun이 맡는다.

        let qp = CGVector(dx: b.start.x - a.start.x, dy: b.start.y - a.start.y)
        let t = (qp.dx * s.dy - qp.dy * s.dx) / denom
        let u = (qp.dx * r.dy - qp.dy * r.dx) / denom
        guard t >= -endpointEpsilon, t <= 1 + endpointEpsilon,
              u >= -endpointEpsilon, u <= 1 + endpointEpsilon else { return nil }

        // 양쪽 모두 끝점에서 만나면 꼭짓점 접합이다 — 도면에서는 정상이므로 겹침으로 보지 않는다.
        let aAtEnd = t <= endpointEpsilon || t >= 1 - endpointEpsilon
        let bAtEnd = u <= endpointEpsilon || u >= 1 - endpointEpsilon
        if aAtEnd && bAtEnd { return nil }

        return LocalPoint(a.start.x + t * r.dx, a.start.y + t * r.dy)
    }

    /// 두 선분이 같은 직선 위에서 겹쳐 지나가는 구간. 벽이 이중으로 그려진 경우가 여기 잡힌다.
    static func sharedRun(_ a: LineSegment, _ b: LineSegment, tolerance: Double) -> LineSegment? {
        let len = a.length
        guard len > tolerance, b.length > tolerance else { return nil }

        let r = CGVector(dx: (a.end.x - a.start.x) / len, dy: (a.end.y - a.start.y) / len)
        let s = CGVector(dx: b.end.x - b.start.x, dy: b.end.y - b.start.y)
        // 방향이 어긋나면 겹칠 수 없다. 외적을 길이로 정규화해 각도 판정으로 쓴다.
        guard abs(r.dx * s.dy - r.dy * s.dx) / b.length <= 1e-3 else { return nil }
        guard a.distance(to: b.start) <= tolerance || a.distance(to: b.end) <= tolerance
                || b.distance(to: a.start) <= tolerance else { return nil }

        // a를 축으로 삼아 b의 양 끝을 투영하고, 겹치는 구간만 잘라낸다.
        func project(_ p: LocalPoint) -> Double {
            (p.x - a.start.x) * r.dx + (p.y - a.start.y) * r.dy
        }
        let lo = max(0, min(project(b.start), project(b.end)))
        let hi = min(len, max(project(b.start), project(b.end)))
        guard hi - lo > tolerance else { return nil }

        return LineSegment(start: LocalPoint(a.start.x + lo * r.dx, a.start.y + lo * r.dy),
                           end: LocalPoint(a.start.x + hi * r.dx, a.start.y + hi * r.dy))
    }

    /// 같은 교차점이 인접 선분마다 중복으로 잡히는 것을 막는 격자 키.
    private struct GridKey: Hashable {
        let x: Int
        let y: Int
        init(_ p: LocalPoint, tolerance: Double) {
            let cell = max(tolerance, 1e-3)
            x = Int((p.x / cell).rounded())
            y = Int((p.y / cell).rounded())
        }
    }
}
