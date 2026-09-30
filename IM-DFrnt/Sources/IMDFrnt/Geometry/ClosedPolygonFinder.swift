import CoreGraphics
import Foundation

/// 도면의 선분들이 실제로 **둘러싸고 있는 면**을 찾는다(신기능 5항).
///
/// **왜 필요한가:** 지금까지 unit 같은 폴리곤 type은 사용자가 벽선 개체를 하나씩 골라 묶었다.
/// 그런데 방 하나의 경계는 벽선 여러 개가 서로 끝점에서 만나 이루는 것이고, 어느 하나라도
/// 빠지면 링이 열린다 — 그 사실을 사용자는 저장한 뒤에야 알았다(명세 10-4의 경고).
/// 이 기능은 반대로 간다. **먼저 닫혀 있는 면을 전부 찾아 보여주고, 사용자는 고르기만 한다.**
///
/// 알고리즘은 평면 그래프의 면 추적(face tracing)이다.
/// 1) 모든 선분을 서로의 교차점에서 잘라 **더 이상 가로지르지 않는 조각**으로 만든다
/// 2) 끝점을 격자로 반올림해 같은 자리의 점을 한 마디(node)로 합친다 —
///    도면은 벽선 두 개가 만나도 좌표가 소수점 아래에서 어긋나 있는 일이 흔하다
/// 3) 마디마다 뻗어 나가는 방향을 각도로 정렬하고, 들어온 변의 **바로 다음 변**을 계속 따라간다.
///    이렇게 걸으면 반드시 최소 순환(= 면 하나)으로 돌아온다
/// 4) 넓이의 부호로 바깥 면을 버린다
enum ClosedPolygonFinder {

    /// 찾아낸 면 하나.
    struct Face: Identifiable, Hashable {
        let id: String
        /// 면의 경계. 첫 점과 끝 점은 같지 않다(GeoJSON 링으로 쓸 때 닫아 준다).
        let ring: [LocalPoint]
        /// 이 면을 이루는 데 쓰인 도면 개체들.
        let memberIDs: Set<VectorObjectID>
        /// 임시 문(신기능 3항)이 경계에 포함됐는가. 사용자에게 표시해 준다 —
        /// 도면에 없는 선으로 닫힌 면이라는 것은 알고 고르는 편이 낫다.
        let usesTemporaryDoor: Bool
        let area: Double
        let boundingBox: CGRect

        func contains(_ p: LocalPoint) -> Bool {
            guard boundingBox.contains(p.cg) else { return false }
            var inside = false
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i], b = ring[j]
                if (a.y > p.y) != (b.y > p.y) {
                    let t = (p.y - a.y) / (b.y - a.y)
                    if p.x < a.x + t * (b.x - a.x) { inside.toggle() }
                }
                j = i
            }
            return inside
        }
    }

    /// 경계에 쓰이는 선분 하나. 어느 개체에서 왔는지를 함께 들고 다닌다.
    struct SourceSegment {
        let segment: LineSegment
        let objectID: VectorObjectID?
        // `nil`이면 임시 문처럼 도면에 개체가 없는 선분이다.
    }

    /// 같은 자리로 볼 거리. `SnapPointExtractor.mergeTolerance`와 같은 이유의 값이다.
    static let mergeTolerance: Double = 0.05

    /// 이보다 좁은 면은 버린다. 벽 두께 사이에 생기는 실오라기 같은 면까지 보여주면
    /// 고를 것이 수백 개로 불어나 목록이 쓸모없어진다.
    static let minimumArea: Double = 4.0

    // MARK: 찾기

    /// 반쪽 변 하나. 같은 선분의 두 방향이 짝(`index ^ 1`)으로 붙어 있다.
    private struct HalfEdge {
        let from: Int
        let to: Int
        let angle: Double
        let objectID: VectorObjectID?
        let isTemporary: Bool
    }

    static func faces(in sources: [SourceSegment],
                      minimumArea: Double = ClosedPolygonFinder.minimumArea) -> [Face] {
        let pieces = split(sources)
        guard !pieces.isEmpty else { return [] }

        var nodePoints: [LocalPoint] = []
        var nodeIndex: [GridKey: Int] = [:]
        func node(_ p: LocalPoint) -> Int {
            let k = GridKey(p, tolerance: mergeTolerance)
            if let i = nodeIndex[k] { return i }
            nodeIndex[k] = nodePoints.count
            nodePoints.append(p)
            return nodePoints.count - 1
        }

        var edges: [HalfEdge] = []
        var outgoing: [Int: [Int]] = [:]
        var seenPairs = Set<Int64>()

        for piece in pieces {
            let a = node(piece.segment.start), b = node(piece.segment.end)
            guard a != b else { continue }
            // 반올림 뒤 한 점으로 합쳐진 조각은 길이가 없다.
            let key = Int64(min(a, b)) << 32 | Int64(max(a, b))
            guard seenPairs.insert(key).inserted else { continue }
            // 같은 두 마디를 잇는 선이 여러 번 나오면(겹쳐 그린 벽선) 한 번만 쓴다.
            // 그대로 두면 같은 면이 겹친 수만큼 중복해서 나온다.

            let pa = nodePoints[a], pb = nodePoints[b]
            edges.append(HalfEdge(from: a, to: b, angle: atan2(pb.y - pa.y, pb.x - pa.x),
                                  objectID: piece.objectID, isTemporary: piece.objectID == nil))
            edges.append(HalfEdge(from: b, to: a, angle: atan2(pa.y - pb.y, pa.x - pb.x),
                                  objectID: piece.objectID, isTemporary: piece.objectID == nil))
            outgoing[a, default: []].append(edges.count - 2)
            outgoing[b, default: []].append(edges.count - 1)
        }

        // 마디마다 뻗어 나가는 방향을 각도로 정렬해 둔다. 면 추적은 "들어온 방향의
        // 바로 옆 방향"을 고르는 일이라, 정렬해 두지 않으면 갈림길마다 전부 훑어야 한다.
        var order: [Int: [Int]] = [:]
        var slot: [Int: Int] = [:]
        for (n, ids) in outgoing {
            let sorted = ids.sorted { edges[$0].angle < edges[$1].angle }
            order[n] = sorted
            for (i, e) in sorted.enumerated() { slot[e] = i }
        }

        /// 들어온 변의 **반대 방향 바로 앞** 변을 고른다.
        /// 갈림길에서 늘 같은 쪽으로 붙어 돌면 반드시 가장 작은 순환으로 돌아온다 —
        /// 이 한 규칙이 면 추적의 전부다.
        func nextEdge(after e: Int) -> Int? {
            let twin = e ^ 1
            let at = edges[twin].from
            guard let ring = order[at], let i = slot[twin], !ring.isEmpty else { return nil }
            return ring[(i - 1 + ring.count) % ring.count]
        }

        var visited = Set<Int>()
        var faces: [Face] = []

        for start in edges.indices where !visited.contains(start) {
            var ringNodes: [Int] = []
            var members = Set<VectorObjectID>()
            var usedTemporary = false
            var current = start
            var closed = false

            while visited.insert(current).inserted {
                ringNodes.append(edges[current].from)
                if let oid = edges[current].objectID { members.insert(oid) }
                if edges[current].isTemporary { usedTemporary = true }
                guard let next = nextEdge(after: current) else { break }
                if next == start { closed = true; break }
                current = next
            }
            guard closed, ringNodes.count >= 3 else { continue }

            let ring = ringNodes.map { nodePoints[$0] }
            let signed = signedArea(ring)
            guard signed > 0, signed >= minimumArea else { continue }
            // **부호가 바깥 면을 걸러낸다.** 같은 걸음 규칙으로 돌면 안쪽 면은 한 방향,
            // 도형 전체를 감싸는 바깥 면은 반대 방향으로 돌아 넓이의 부호가 뒤집힌다.

            faces.append(Face(id: "f-\(ringNodes.min() ?? 0)-\(ringNodes.count)-\(Int(signed.rounded()))",
                              ring: ring, memberIDs: members,
                              usesTemporaryDoor: usedTemporary,
                              area: signed, boundingBox: boundingBox(ring)))
        }

        return faces.sorted { $0.area > $1.area }
        // 넓은 것부터 준다. 방보다 건물 외곽이 먼저 보이는 편이 목록을 훑기 쉽다.
    }

    // MARK: 면 묶기 (신기능 5-4 2번)

    /// **선분을 나눠 쓰는 면들을 한 덩어리로 묶는다.** fixture는 MultiPolygon이라 면 여러 개가
    /// 한 feature인데, 사용자가 그 관계를 손으로 지정하게 하면 면이 수십 개일 때 감당이 안 된다.
    /// 맞닿은 면은 도면상 한 물건일 때가 많으므로 **닿아 있음을 근거로 자동으로 묶는다.**
    ///
    /// 폴리곤 type(unit 등)은 이 함수를 쓰지 않는다 — 방 둘이 벽을 나눠 쓴다고 한 방이 되면 안 된다.
    static func connectedGroups(of faces: [Face]) -> [[Face]] {
        guard faces.count > 1 else { return faces.isEmpty ? [] : [faces] }

        var parent = Array(faces.indices)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let (ra, rb) = (find(a), find(b))
            if ra != rb { parent[rb] = ra }
        }

        // 변(두 꼭짓점)을 열쇠로 삼아 같은 변을 쓰는 면끼리 잇는다.
        var ownerOfEdge: [EdgeKey: Int] = [:]
        for (i, face) in faces.enumerated() {
            for k in face.ring.indices {
                let a = face.ring[k], b = face.ring[(k + 1) % face.ring.count]
                let key = EdgeKey(a, b, tolerance: mergeTolerance)
                if let other = ownerOfEdge[key] { union(i, other) } else { ownerOfEdge[key] = i }
            }
        }

        var buckets: [Int: [Face]] = [:]
        for (i, face) in faces.enumerated() { buckets[find(i), default: []].append(face) }
        return buckets.values.sorted { ($0.first?.area ?? 0) > ($1.first?.area ?? 0) }
        // 넓은 덩어리부터 준다. 목록 순서가 매번 달라지면 같은 조작이 다른 결과로 보인다.
    }

    /// 방향을 무시한 변의 열쇠. 두 면은 같은 변을 반대 방향으로 갖는다.
    private struct EdgeKey: Hashable {
        let a: GridKey
        let b: GridKey
        init(_ p: LocalPoint, _ q: LocalPoint, tolerance: Double) {
            let k1 = GridKey(p, tolerance: tolerance), k2 = GridKey(q, tolerance: tolerance)
            if (k1.x, k1.y) <= (k2.x, k2.y) { a = k1; b = k2 } else { a = k2; b = k1 }
        }
    }

    // MARK: 선분 자르기

    /// 서로 가로지르는 선분을 교차점에서 잘라 조각으로 만든다.
    ///
    /// **경계 상자로 먼저 걸러내는 것이 이 절의 전부다.** 모든 선분 쌍을 그대로 돌면
    /// 계산이 선분 수의 제곱에 붙어 실도면에서 멈춘다(`04) 엔진 디버깅.md` 1-1과 같은 교훈).
    static func split(_ sources: [SourceSegment]) -> [SourceSegment] {
        let boxes = sources.map { box(of: $0.segment) }
        var cuts: [[Double]] = Array(repeating: [], count: sources.count)

        let eps = 1e-9
        for i in sources.indices {
            for j in (i + 1)..<sources.count {
                guard boxes[i].intersects(boxes[j]) else { continue }
                guard let hit = crossing(sources[i].segment, sources[j].segment) else { continue }
                if hit.t > eps, hit.t < 1 - eps { cuts[i].append(hit.t) }
                if hit.u > eps, hit.u < 1 - eps { cuts[j].append(hit.u) }
                // **한쪽 끝점이 다른 선의 중간에 닿는 T자 접합도 자른다.**
                // 방을 가로지르는 벽은 양 끝이 바깥 벽의 중간에 붙는 형태라, 이걸 안 자르면
                // 바깥 벽에 마디가 생기지 않아 두 방이 한 덩어리로 남는다.
                // 양쪽 모두 끝점에서 만나면 자를 것이 없다 — 그때는 두 조건 모두 거짓이다.
            }
        }

        var out: [SourceSegment] = []
        for (i, src) in sources.enumerated() {
            let ts = ([0, 1] + cuts[i]).filter { $0 >= 0 && $0 <= 1 }
                .sorted()
            var prev = ts[0]
            for t in ts.dropFirst() {
                guard t - prev > 1e-9 else { continue }
                out.append(SourceSegment(segment: LineSegment(start: point(at: prev, on: src.segment),
                                                              end: point(at: t, on: src.segment)),
                                         objectID: src.objectID))
                prev = t
            }
        }
        return out
    }

    // MARK: 계산 보조

    static func signedArea(_ ring: [LocalPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        var j = ring.count - 1
        for i in 0..<ring.count {
            sum += (ring[j].x * ring[i].y) - (ring[i].x * ring[j].y)
            j = i
        }
        return sum / 2
    }

    static func boundingBox(_ ring: [LocalPoint]) -> CGRect {
        guard let first = ring.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in ring.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func box(of s: LineSegment) -> CGRect {
        CGRect(x: min(s.start.x, s.end.x) - mergeTolerance,
               y: min(s.start.y, s.end.y) - mergeTolerance,
               width: abs(s.end.x - s.start.x) + mergeTolerance * 2,
               height: abs(s.end.y - s.start.y) + mergeTolerance * 2)
    }

    /// 두 선분이 실제로 만나는 점. 끝점끼리만 닿는 것은 자를 필요가 없다.
    /// 두 선분이 만나는 자리를 **양쪽의 매개변수로** 돌려준다.
    /// 자를지 말지는 부르는 쪽이 정한다 — 끝점에서 만난 쪽은 자를 것이 없기 때문이다.
    private static func crossing(_ a: LineSegment, _ b: LineSegment) -> (t: Double, u: Double)? {
        let r = CGVector(dx: a.end.x - a.start.x, dy: a.end.y - a.start.y)
        let s = CGVector(dx: b.end.x - b.start.x, dy: b.end.y - b.start.y)
        let denom = r.dx * s.dy - r.dy * s.dx
        guard abs(denom) > 1e-12 else { return nil }
        // 평행·동일선상은 여기서 답이 없다. 겹쳐 그린 벽선은 마디 합치기가 맡는다.
        let qp = CGVector(dx: b.start.x - a.start.x, dy: b.start.y - a.start.y)
        let t = (qp.dx * s.dy - qp.dy * s.dx) / denom
        let u = (qp.dx * r.dy - qp.dy * r.dx) / denom
        let eps = 1e-9
        guard t > -eps, t < 1 + eps, u > -eps, u < 1 + eps else { return nil }
        return (Double(t), Double(u))
    }

    private static func parameter(of p: LocalPoint, on s: LineSegment) -> Double {
        let dx = s.end.x - s.start.x, dy = s.end.y - s.start.y
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-18 else { return 0 }
        return ((p.x - s.start.x) * dx + (p.y - s.start.y) * dy) / len2
    }

    private static func point(at t: Double, on s: LineSegment) -> LocalPoint {
        LocalPoint(s.start.x + (s.end.x - s.start.x) * t,
                   s.start.y + (s.end.y - s.start.y) * t)
    }

    private struct GridKey: Hashable {
        let x: Int
        let y: Int
        init(_ p: LocalPoint, tolerance: Double) {
            x = Int((p.x / tolerance).rounded())
            y = Int((p.y / tolerance).rounded())
        }
    }
}
