import CoreGraphics
import Foundation

/// 명세 7-3-5)를 그대로 옮긴 파일.
/// feature 그룹 하나의 "좌표 변환 대상 꼭짓점 목록"을 낸다.
enum VertexExtractor {

    /// 다각형 선택으로 저장한 feature의 링 전부. 내보내기가 MultiPolygon을 만들 때 쓴다.
    static func rings(for feature: FeatureGroup) -> [[LocalPoint]] { feature.polygonRings }

    /// 좌표 추출은 항상 원본 좌표를 쓴다.
    /// 임시 이동(`TransientOffsetStore`)은 보기 편의일 뿐이므로 여기 반영하지 않는다.
    static func vertices(for feature: FeatureGroup,
                         document: DrawingDocument,
                         segmentation: SegmentationStore,
                         kind: GeoJSONGeometryKind,
                         borrowed: Set<VectorObjectID> = []) -> [LocalPoint] {
        if let closure = feature.closureSegment, kind == .lineString {
            return [closure.start, closure.end]
            // 신기능 3항: '문 임시로 닫기'로 만든 opening.
            // 좌표는 사용자가 찍은 두 점이 정본이다 — 구성원(문짝·호)은 도면에 그려진
            // 문의 **모양**이지 문이 지나는 **자리**가 아니라, 그걸로 LineString을 만들면
            // 호를 따라 휘어진 엉뚱한 선이 나온다.
        }

        if let ring = feature.polygonRings.first, kind == .polygon || kind == .multiPolygon {
            return ring
            // MultiPolygon은 링이 여럿일 수 있다. 여기서는 첫 링만 주고,
            // 내보내기는 `rings(for:)`로 전부 가져간다 — 이 함수의 반환형(점 목록 하나)으로는
            // 여러 링을 구분해 담을 수 없기 때문이다.
            // 신기능 5항: '닫힌 다각형 보기'로 고른 면.
            // 화면에서 닫혀 있는 것을 확인하고 고른 좌표라 이것이 정본이다.
            // 구성원으로 다시 조립하면 옆방과 나눠 쓰는 벽선이 빠져 링이 열린다.
        }

        let ids = feature.memberIDs.union(kind.usesBorrowedOpenings ? borrowed : [])
        // 명세 10-3-1: 빌려온 opening은 **좌표 계산에만** 참여한다.
        // 구성원(`memberIDs`)에는 안 들어가므로 여기서 합쳐 준다.
        // 닫힌 링이 필요 없는 geometry에는 넣지 않는다 — LineString에 남의 문을 이으면
        // 선이 엉뚱한 데로 뻗고, Point는 중심이 문 쪽으로 끌려간다.
        let members = ids.compactMap { document.object($0) }
            .sorted { $0.ordinal < $1.ordinal }
        guard !members.isEmpty else { return [] }

        let geometries = members.map { segmentation.effectiveGeometry(for: $0.id, fallback: $0.geometry) }

        switch kind {
        case .point:
            return feature.displayPoint.map { [$0] } ?? [centroid(of: geometries)]

        case .lineString:
            return lineStringVertices(geometries)

        case .polygon, .multiPolygon:
            return polygonVertices(geometries)

        case .none:
            return []
        }
    }

    /// 명세 7-3-5-2) 선분의 양 끝점.
    private static func lineStringVertices(_ gs: [PathGeometry]) -> [LocalPoint] {
        let segs = gs.flatMap { $0.lineSegments() }
        guard let first = segs.first else { return [] }
        if segs.count == 1 { return [first.start, first.end] }
        return orderedChain(segs)
    }

    /// 명세 7-3-5-1) 그룹의 모든 꼭짓점(선분과 선분의 교차점) + 한쪽만 교차하는 선분의 끝점.
    ///
    /// 프로토타입 구현 노트: 닫힌 단일 경로(rect·polygon·닫힌 path)는 경로 순서 자체가
    /// 유효한 GeoJSON 링이므로 그대로 쓴다. 흩어진 선분 집합일 때만 교차점 계산으로 넘어간다.
    private static func polygonVertices(_ gs: [PathGeometry]) -> [LocalPoint] {
        if gs.count == 1, let sp = gs[0].subpaths.first, gs[0].subpaths.count == 1, sp.isClosed {
            let ring = gs[0].lineSegments()
            if crossings(in: ring).overshot.isEmpty {
                return dedup(ring.map(\.start))
            }
            // 닫힌 경로라도 스스로를 가로지르면 교차점을 지나쳐 찍힌 꼭짓점이 섞여 있다.
            // 경로 순서를 그대로 믿을 수 없으므로 아래 일반 경로로 넘긴다(디버깅 5번).
        }
        return polygonRing(from: gs.flatMap { $0.lineSegments() })
    }

    /// 흩어진 선분 집합에서 GeoJSON 링의 꼭짓점을 뽑는다.
    ///
    /// 「디버깅 5번」(2026-08-25 확정): 두 선분이 꼭짓점에서 만나지 않고 서로를 **가로질러**
    /// 지나가면, 실제 꼭짓점은 교차점이고 교차점을 지나쳐 뻗은 끝점은 도면 작도 흔적일 뿐이다.
    /// 그 끝점을 좌표로 내보내면 링이 별 모양으로 삐져나온다.
    static func polygonRing(from segs: [LineSegment]) -> [LocalPoint] {
        guard !segs.isEmpty else { return [] }
        let cross = crossings(in: segs)
        var pts = cross.points

        // 끝점이 다른 선분의 끝점과 맞닿는 지점도 꼭짓점이다.
        var endpointHits: [String: Int] = [:]
        for s in segs {
            for p in [s.start, s.end] { endpointHits[gridKey(p), default: 0] += 1 }
        }

        for (i, s) in segs.enumerated() {
            for p in [s.start, s.end] {
                if cross.overshot.contains(i), endpointHits[gridKey(p), default: 0] < 2 { continue }
                // 가로질린 선분의 자유 끝점 = 교차점을 지나쳐 찍힌 꼬리다. 꼭짓점은 교차점 쪽이다.
                // 다른 선분의 끝점과 맞닿아 있으면 작도 흔적이 아니라 실제 접합이므로 남긴다.
                pts.append(p)
            }
        }

        let unique = dedup(pts)
        if unique.count <= 2 { return unique }
        return sortAroundCentroid(unique)
        // 흩어진 선분에서 뽑은 점 집합에는 순서가 없다.
        // GeoJSON Polygon은 순서 있는 링을 요구하므로 중심 기준 각도로 정렬한다.
    }

    /// 선분 쌍의 교차점과, 교차점에 가로질린 선분의 인덱스.
    private struct CrossResult {
        var points: [LocalPoint] = []
        var overshot = Set<Int>()
    }

    /// 교차 판정은 `OverlapDetector.crossing`을 그대로 쓴다.
    /// '만나는 점'(양쪽 다 끝점에서 만나는 꼭짓점 접합)은 거기서 이미 nil로 걸러지므로,
    /// 겹침 윤곽 표시와 좌표 추출이 같은 기준을 보게 된다(같은 계산을 두 벌 두지 않는다).
    private static func crossings(in segs: [LineSegment]) -> CrossResult {
        var out = CrossResult()
        guard segs.count > 1 else { return out }
        for i in 0..<segs.count {
            for j in (i + 1)..<segs.count {
                guard let p = OverlapDetector.crossing(segs[i], segs[j]) else { continue }
                out.points.append(p)

                guard isInterior(p, of: segs[i]), isInterior(p, of: segs[j]) else { continue }
                // 한쪽 끝점이 상대 선분 위에 얹힌 T자 접합은 지나친 꼬리가 없다 — 자를 것이 없다.
                // 양쪽 모두 내부를 지날 때만 X자로 가로지른 것이고, 그때만 끝점이 꼬리가 된다.
                out.overshot.insert(i)
                out.overshot.insert(j)
            }
        }
        return out
    }

    /// 점이 선분의 끝점이 아니라 내부에 있는지. 길이로 정규화해 도면 축척과 무관하게 판정한다.
    private static func isInterior(_ p: LocalPoint, of s: LineSegment) -> Bool {
        let len = s.length
        guard len > 1e-9 else { return false }
        let t = ((p.x - s.start.x) * (s.end.x - s.start.x)
                 + (p.y - s.start.y) * (s.end.y - s.start.y)) / (len * len)
        return t > endpointEpsilon && t < 1 - endpointEpsilon
    }

    private static let endpointEpsilon = 1e-6

    /// 부동소수 오차를 흡수하는 끝점 동일성 키. 도면 좌표 단위에서 0.1μm이면 같은 점이다.
    private static func gridKey(_ p: LocalPoint) -> String {
        String(format: "%.4f_%.4f", p.x, p.y)
    }

    /// 선분들을 끝점 연결을 따라 하나의 사슬로 잇는다.
    private static func orderedChain(_ segs: [LineSegment]) -> [LocalPoint] {
        var pts: [LocalPoint] = [segs[0].start, segs[0].end]
        var used = Set([0])
        var progress = true
        while used.count < segs.count && progress {
            progress = false
            for (i, s) in segs.enumerated() where !used.contains(i) {
                if let last = pts.last, last.distance(to: s.start) < 1e-6 {
                    pts.append(s.end); used.insert(i); progress = true
                } else if let last = pts.last, last.distance(to: s.end) < 1e-6 {
                    pts.append(s.start); used.insert(i); progress = true
                } else if let first = pts.first, first.distance(to: s.end) < 1e-6 {
                    pts.insert(s.start, at: 0); used.insert(i); progress = true
                } else if let first = pts.first, first.distance(to: s.start) < 1e-6 {
                    pts.insert(s.end, at: 0); used.insert(i); progress = true
                }
            }
        }
        for (i, s) in segs.enumerated() where !used.contains(i) {
            pts.append(s.start); pts.append(s.end)
        }
        return dedup(pts)
    }

    static func sortAroundCentroid(_ pts: [LocalPoint]) -> [LocalPoint] {
        let cx = pts.map(\.x).reduce(0, +) / Double(pts.count)
        let cy = pts.map(\.y).reduce(0, +) / Double(pts.count)
        return pts.sorted { atan2($0.y - cy, $0.x - cx) < atan2($1.y - cy, $1.x - cx) }
    }

    static func dedup(_ pts: [LocalPoint], epsilon: Double = 1e-6) -> [LocalPoint] {
        var out: [LocalPoint] = []
        for p in pts where !out.contains(where: { $0.distance(to: p) < epsilon }) {
            out.append(p)
        }
        return out
    }

    static func centroid(of gs: [PathGeometry]) -> LocalPoint {
        let pts = gs.flatMap(\.allPoints)
        guard !pts.isEmpty else { return LocalPoint(0, 0) }
        return LocalPoint(pts.map(\.x).reduce(0, +) / Double(pts.count),
                          pts.map(\.y).reduce(0, +) / Double(pts.count))
    }

    static func boundingBox(of ids: Set<VectorObjectID>, document: DrawingDocument) -> CGRect {
        let boxes = ids.compactMap { document.object($0)?.boundingBox }
        guard let first = boxes.first else { return .zero }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// 그룹의 개체 구성으로 GeoJSON geometry 종류를 판정한다.
enum GeometryClassifier {

    static func classify(_ feature: FeatureGroup, document: DrawingDocument) -> GeoJSONGeometryKind {
        let required = feature.featureType.requiredGeometry
        if required != .none { return required }
        return .none
        // property type이 geometry를 규정하므로 그 값을 그대로 따른다.
        // 규정과 실제 도형이 어긋나면 아래 mismatchWarning이 잡는다.
    }

    static func mismatchWarning(_ feature: FeatureGroup, document: DrawingDocument) -> String? {
        let required = feature.featureType.requiredGeometry
        let members = feature.memberIDs.compactMap { document.object($0) }
        guard !members.isEmpty else { return nil }
        let anyClosed = members.contains { $0.geometry.subpaths.contains(where: \.isClosed) }

        switch required {
        case .lineString where anyClosed:
            return "\(feature.featureType.displayName)은 LineString이어야 하는데 닫힌 도형이 포함되어 있습니다."
        case .polygon, .multiPolygon:
            return nil
            // **여기서 '닫힌 도형이 있는가'를 보지 않는다.** 이전에는 닫힌 subpath가 하나도 없으면
            // 경고했는데, 그것은 틀린 판정이었다 — 벽 선분 네 개로 그린 방은 닫힌 subpath가
            // 하나도 없어도 링이 닫힌다. 문을 빌려 닫는 경우(명세 10항)는 더더욱 그렇다.
            // 이 경고가 `ExportValidator`를 거쳐 **내보내기 차단**으로 이어졌으므로,
            // 정상 도면의 정상 작업을 막고 있었다.
            // 링이 실제로 닫히는지는 `RingClosureValidator`가 판정해 인스펙터와 저장 배너로 알린다.
            // 그쪽은 경고일 뿐 차단하지 않는다 — 도면을 고쳐 다시 저장하는 것이 정상 흐름이라
            // 저장·내보내기를 막으면 작업이 통째로 묶인다(명세 7-4의 차단 조건에도 링 열림은 없다).
        case .none where !members.isEmpty:
            return "\(feature.featureType.displayName)은 geometry가 null이어야 합니다. 선택한 개체는 좌표로 변환되지 않습니다."
        default:
            return nil
        }
    }
}
