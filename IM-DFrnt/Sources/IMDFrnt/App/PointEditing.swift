import AppKit
import Foundation

/// 레이어의 작업 방식(#21, 2026-10-15).
///
/// **선분(개체) 단위 작업은 더 이상 하지 않는다.** 모든 레이어는 꼭짓점·교점을 찍어 도형을 만들고,
/// polygon·multipolygon type(footprint 제외)은 면 단위 선택을 함께 쓸 수 있다(`05) IM-DFrnt 신기능.md` 10번).
enum LayerEditMode: String, CaseIterable {
    case point
    case face

    var title: String {
        switch self {
        case .point: return "점 단위"
        case .face: return "면 단위"
        }
    }
}

/// 작성 중인 도형(DraftShape). 원본 SVG 개체와 무관한 좌표 목록이다.
struct PointDraft: Equatable {
    var points: [LocalPoint] = []
    var isEmpty: Bool { points.isEmpty }
}

/// 끌고 있는 꼭짓점.
struct VertexDrag: Equatable {
    enum Target: Equatable {
        /// 작성 중인 도형의 몇 번째 점.
        case draft(Int)
        /// 저장된 feature의 링(또는 선·점)의 몇 번째 점. 선·점은 `ring`이 -1이다.
        case feature(FeatureGroupID, ring: Int, index: Int)
    }
    let target: Target
    var location: LocalPoint
}

/// 자기 교차 판정. 도형이 스스로 꼬이면(변끼리 X자로 가로지르면) 확정하지 않는다(#21 완료 조건).
enum PolygonValidity {

    /// 이웃하지 않는 두 변이 만나거나 겹치면 참이다.
    static func selfIntersects(_ ring: [LocalPoint]) -> Bool {
        let n = ring.count
        guard n >= 4 else { return false }
        // 삼각형은 스스로 가로지를 수 없다.
        for i in 0..<n {
            let a1 = ring[i], a2 = ring[(i + 1) % n]
            for j in (i + 1)..<n {
                guard j != i + 1, !(i == 0 && j == n - 1) else { continue }
                // 이웃한 변은 꼭짓점 하나를 공유하는 것이 정상이다.
                if segmentsTouch(a1, a2, ring[j], ring[(j + 1) % n]) { return true }
            }
        }
        return false
    }

    /// 넓이가 사실상 0이면(점이 한 줄에 놓이면) 면이 아니다.
    static func isDegenerate(_ ring: [LocalPoint]) -> Bool {
        guard ring.count >= 3 else { return true }
        return abs(ClosedPolygonFinder.signedArea(ring)) < 1e-9
    }

    private static func orientation(_ p: LocalPoint, _ q: LocalPoint, _ r: LocalPoint) -> Double {
        (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
    }

    private static func onSegment(_ p: LocalPoint, _ q: LocalPoint, _ r: LocalPoint) -> Bool {
        min(p.x, r.x) - 1e-9 <= q.x && q.x <= max(p.x, r.x) + 1e-9
            && min(p.y, r.y) - 1e-9 <= q.y && q.y <= max(p.y, r.y) + 1e-9
    }

    static func segmentsTouch(_ p1: LocalPoint, _ p2: LocalPoint, _ q1: LocalPoint, _ q2: LocalPoint) -> Bool {
        let eps = 1e-9
        let d1 = orientation(q1, q2, p1), d2 = orientation(q1, q2, p2)
        let d3 = orientation(p1, p2, q1), d4 = orientation(p1, p2, q2)
        if ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps))
            && ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps)) { return true }
        if abs(d1) <= eps && onSegment(q1, p1, q2) { return true }
        if abs(d2) <= eps && onSegment(q1, p2, q2) { return true }
        if abs(d3) <= eps && onSegment(p1, q1, p2) { return true }
        if abs(d4) <= eps && onSegment(p1, q2, p2) { return true }
        return false
    }
}

@MainActor
extension AppEnvironment {

    // MARK: 모드

    /// 지금 화면이 점을 찍는 모드인가. geometry가 있는 property type 레이어에서 면 단위가 아닐 때다.
    var isPointWorkMode: Bool {
        guard document != nil, !showRoutingScreen, let type = layers.activePropertyType else { return false }
        return type.requiredGeometry != .none && !isPolygonWorkMode
    }

    var activeGeometryKind: GeoJSONGeometryKind { layers.activePropertyType?.requiredGeometry ?? .none }

    /// 지금 무엇을 해야 하는지 한 줄로. 상단바가 그대로 띄운다.
    var pointStageHint: String {
        let n = pointDraft.points.count
        switch activeGeometryKind {
        case .point:
            return "점 하나를 찍으면 바로 저장합니다."
        case .lineString:
            return n == 0 ? "선의 시작점을 찍으세요." : "끝점을 찍으면 선으로 저장합니다."
        case .polygon, .multiPolygon:
            if n < 3 { return "꼭짓점을 순서대로 찍으세요. (\(n)/3 이상)" }
            return "시작점(◎)을 다시 누르면 도형이 닫히고 저장됩니다."
        case .none:
            return ""
        }
    }

    // MARK: 점 찍기

    /// 캔버스 클릭. 순서가 규칙이다.
    /// ① 점이 셋 이상이면 시작점을 눌러 닫는다 ② 이미 찍은 점을 다시 누르면 지운다
    /// ③ 꼭짓점·교점 근처면 그 점에 붙인다 ④ ⌥(Option)을 누른 채면 그 자리에 새 점을 만든다.
    func handlePointClick(at point: LocalPoint, tolerance: Double, freePoint: Bool) {
        guard isPointWorkMode, let type = layers.activePropertyType else { return }
        let radius = tolerance * 1.5
        let kind = type.requiredGeometry
        let draft = pointDraft.points

        if kind.isAreal, draft.count >= 3, draft[0].distance(to: point) <= radius {
            closePointDraft()
            return
        }
        if let idx = draft.firstIndex(where: { $0.distance(to: point) <= radius }) {
            perform("점 삭제") { pointDraft.points.remove(at: idx) }
            return
        }

        let target: LocalPoint
        if let snap = snapPointIndex.nearest(to: point, within: radius) {
            target = snap.point
        } else if freePoint {
            target = point
        } else {
            notify(isComputingDerivedGeometry
                   ? "꼭짓점·교점을 계산하는 중입니다. 잠시 후 다시 찍으세요."
                   : "꼭짓점·교점이 아닌 자리입니다. 새 점을 만들려면 ⌥(Option)을 누른 채 클릭하세요.")
            return
            // 아무 데나 찍게 두지 않는 것이 요점이다. 눈대중으로 찍으면 몇 단위씩 어긋나
            // 옆 도형과 틈이 생긴다(신기능 3-2와 같은 이유). 새 점은 의도했을 때만 만든다.
        }

        switch kind {
        case .point:
            savePointDrawnFeature(type: type, vertices: [target])
        case .lineString:
            if let last = draft.last, last.distance(to: target) <= SnapPointExtractor.mergeTolerance { return }
            if draft.count + 1 >= 2 {
                savePointDrawnFeature(type: type, vertices: draft + [target])
                // opening은 두 점 선분이다(#37). 문 선의 양 끝을 찍으면 바로 저장한다.
            } else {
                perform("점 추가") { pointDraft.points.append(target) }
            }
        case .polygon, .multiPolygon:
            perform("점 추가") { pointDraft.points.append(target) }
        case .none:
            return
        }
    }

    /// 시작점 재선택(또는 상단바 버튼)으로 도형을 닫고 저장한다.
    /// **미완성·자기 교차·넓이 0인 도형은 확정하지 않는다**(#21 완료 조건).
    func closePointDraft() {
        guard let type = layers.activePropertyType, type.requiredGeometry.isAreal else { return }
        let ring = VertexExtractor.dedup(pointDraft.points, epsilon: SnapPointExtractor.mergeTolerance)
        guard ring.count >= 3 else {
            notify("꼭짓점이 3개 이상이어야 닫을 수 있습니다.", isError: true)
            return
        }
        if PolygonValidity.selfIntersects(ring) {
            notify("도형의 변끼리 가로지릅니다(자기 교차). 점을 지우거나 옮겨 꼬임을 풀어야 저장할 수 있습니다.",
                   isError: true)
            return
        }
        if PolygonValidity.isDegenerate(ring) {
            notify("점이 한 줄에 놓여 면이 되지 않습니다.", isError: true)
            return
        }
        savePolygonDrawnFeature(type: type, ring: ring)
    }

    /// ESC. 작성 중인 도형을 버린다. 실행취소로 되살릴 수 있다.
    func escapePointDraft() {
        if vertexDrag != nil { vertexDrag = nil; return }
        guard !pointDraft.isEmpty else { return }
        perform("작성 중인 도형 취소") { pointDraft = PointDraft() }
    }

    /// 레이어 전환 등에서 조용히 비운다. 실행취소 칸을 쌓지 않는다.
    func cancelPointDraft() {
        pointDraft = PointDraft()
        vertexDrag = nil
    }

    func removeLastDraftPoint() {
        guard !pointDraft.isEmpty else { return }
        perform("점 삭제") { _ = pointDraft.points.popLast() }
    }

    private func savePointDrawnFeature(type: IMDFFeatureType, vertices: [LocalPoint]) {
        if type.requiredGeometry == .lineString,
           vertices.count >= 2, vertices[0].distance(to: vertices[1]) <= SnapPointExtractor.mergeTolerance {
            notify("두 점이 같은 자리입니다. 선의 양 끝을 찍으세요.", isError: true)
            return
            // 길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다.
        }
        let serial = serials.next(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        f.drawnVertices = vertices
        perform("\(serial) 저장") {
            features.insert(f)
            pointDraft = PointDraft()
        }
        notify("\(serial) 로 저장했습니다.")
    }

    private func savePolygonDrawnFeature(type: IMDFFeatureType, ring: [LocalPoint]) {
        let serial = serials.next(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        f.polygonRings = [ring]
        // 링이 정본이다(`VertexExtractor`). 원본 개체를 구성원으로 갖지 않으므로 소유권도 주장하지 않는다.
        perform("\(serial) 저장") {
            features.insert(f)
            pointDraft = PointDraft()
        }
        notify("\(serial) 로 저장했습니다. (꼭짓점 \(ring.count)개)")
    }

    // MARK: 꼭짓점 이동·고정

    /// 이 자리에 끌 수 있는 꼭짓점이 있는가. 작성 중인 도형이 먼저, 그다음 지금 레이어의 저장된 feature다.
    func vertexHit(at p: LocalPoint, tolerance: Double) -> VertexDrag.Target? {
        let radius = tolerance * 1.5
        if let i = pointDraft.points.firstIndex(where: { $0.distance(to: p) <= radius }) { return .draft(i) }
        guard let type = layers.activePropertyType else { return nil }
        for f in features.features(ofType: type) where f.isPointDrawn {
            for (r, ring) in f.polygonRings.enumerated() {
                if let i = ring.firstIndex(where: { $0.distance(to: p) <= radius }) {
                    return .feature(f.id, ring: r, index: i)
                }
            }
            if let v = f.drawnVertices, let i = v.firstIndex(where: { $0.distance(to: p) <= radius }) {
                return .feature(f.id, ring: -1, index: i)
            }
        }
        return nil
    }

    func beginVertexDrag(_ target: VertexDrag.Target, at p: LocalPoint) {
        guard isVertexMoveEnabled else { return }
        vertexDrag = VertexDrag(target: target, location: p)
    }

    /// 끄는 동안에도 꼭짓점·교점 근처면 그 점에 붙여 보여준다. 놓았을 때와 같은 자리를 미리 보여야 한다.
    func updateVertexDrag(to p: LocalPoint, tolerance: Double, freePoint: Bool) {
        guard var drag = vertexDrag else { return }
        if let snap = snapPointIndex.nearest(to: p, within: tolerance * 1.5) {
            drag.location = snap.point
        } else {
            drag.location = p
        }
        vertexDrag = drag
    }

    /// 놓으면 한 번에 반영한다(실행취소 칸 하나). 자기 교차가 생기면 되돌린다.
    func endVertexDrag() {
        guard let drag = vertexDrag else { return }
        vertexDrag = nil
        switch drag.target {
        case .draft(let i):
            guard pointDraft.points.indices.contains(i) else { return }
            perform("점 이동") { pointDraft.points[i] = drag.location }
        case .feature(let fid, let r, let i):
            guard let f = features.feature(fid) else { return }
            if r >= 0 {
                guard f.polygonRings.indices.contains(r), f.polygonRings[r].indices.contains(i) else { return }
                var ring = f.polygonRings[r]
                ring[i] = drag.location
                if PolygonValidity.selfIntersects(ring) || PolygonValidity.isDegenerate(ring) {
                    notify("옮기면 도형이 꼬이거나 면이 사라집니다. 꼭짓점을 원래 자리에 둡니다.", isError: true)
                    return
                }
                perform("\(f.serialNumber) 꼭짓점 이동") {
                    features.update(fid) { $0.polygonRings[r] = ring }
                }
            } else {
                guard var v = f.drawnVertices, v.indices.contains(i) else { return }
                v[i] = drag.location
                if f.featureType.requiredGeometry == .lineString, v.count >= 2,
                   v[0].distance(to: v[1]) <= SnapPointExtractor.mergeTolerance {
                    notify("두 끝점이 같은 자리가 됩니다. 꼭짓점을 원래 자리에 둡니다.", isError: true)
                    return
                }
                perform("\(f.serialNumber) 꼭짓점 이동") {
                    features.update(fid) { $0.drawnVertices = v }
                }
            }
        }
    }

    /// 끄는 중인 꼭짓점을 반영한 링. 화면 미리보기용이다.
    func previewRing(of f: FeatureGroup, ring r: Int) -> [LocalPoint] {
        var ring = f.polygonRings[r]
        if let d = vertexDrag, case .feature(let fid, let rr, let i) = d.target, fid == f.id, rr == r,
           ring.indices.contains(i) { ring[i] = d.location }
        return ring
    }

    func previewDrawnVertices(of f: FeatureGroup) -> [LocalPoint] {
        var v = f.drawnVertices ?? []
        if let d = vertexDrag, case .feature(let fid, let rr, let i) = d.target, fid == f.id, rr == -1,
           v.indices.contains(i) { v[i] = d.location }
        return v
    }

    var previewDraftPoints: [LocalPoint] {
        var pts = pointDraft.points
        if let d = vertexDrag, case .draft(let i) = d.target, pts.indices.contains(i) { pts[i] = d.location }
        return pts
    }

    // MARK: 점 기준 진행률 (#21)
    //
    // **분모는 보조 개체를 포함한 전체 점(꼭짓점·끝점·교차점) 수다.** 보조 개체를 제외하면
    // 분모를 줄이지 않고 '제외된 점'으로 분자에 얹는다(5-5-2의 사노 결정을 점 기준으로 옮긴 것).
    // 면 단위로 저장해도 그 면의 꼭짓점이 태깅된 점으로 셈해지므로 기준은 늘 점이다(10번 지침).

    /// 태깅된 점을 다시 센다. feature·소유권·점 목록이 바뀔 때 부른다.
    func refreshPointProgress() {
        guard !snapPoints.isEmpty else {
            if taggedPointCount != 0 { taggedPointCount = 0 }
            return
        }
        var tagged = Set<Int>()
        for f in features.features where !f.isInTrash {
            var vertices: [LocalPoint] = f.polygonRings.flatMap { $0 }
            vertices += f.drawnVertices ?? []
            if let c = f.closureSegment { vertices += [c.start, c.end] }
            for v in vertices { if let i = snapPointIndex.index(at: v) { tagged.insert(i) } }
        }
        for door in doorClosures.doors {
            for v in [door.start, door.end] { if let i = snapPointIndex.index(at: v) { tagged.insert(i) } }
        }
        let claimed = ownership.claimedObjectIDs
        if !claimed.isEmpty {
            for (i, p) in snapPoints.enumerated() where !p.owners.isDisjoint(with: claimed) { tagged.insert(i) }
            // 예전 방식(개체 소유)으로 저장한 feature의 점도 태깅된 것으로 센다.
        }
        if taggedPointCount != tagged.count { taggedPointCount = tagged.count }
    }

    /// 보조 개체 제외로 사라진 점. 전체 점 수에서 지금 고를 수 있는 점 수를 뺀 값이다.
    var excludedPointCount: Int { max(0, totalPointCount - snapPoints.count) }

    var taggedPointFraction: Double {
        guard totalPointCount > 0 else { return 0 }
        return Double(min(totalPointCount, taggedPointCount)) / Double(totalPointCount)
    }

    var excludedPointFraction: Double {
        guard totalPointCount > 0 else { return 0 }
        return Double(min(totalPointCount, excludedPointCount)) / Double(totalPointCount)
    }

    var pointProgressFraction: Double {
        guard totalPointCount > 0 else { return 0 }
        return Double(min(totalPointCount, taggedPointCount + excludedPointCount)) / Double(totalPointCount)
    }

    var pointProgressText: String {
        "\(min(totalPointCount, taggedPointCount + excludedPointCount)) / \(totalPointCount)"
    }
}

extension GeoJSONGeometryKind {
    /// 면을 이루는 geometry인가.
    var isAreal: Bool { self == .polygon || self == .multiPolygon }
}

/// 점 단위 편집의 키보드. ESC는 작성 취소, Delete는 마지막 점 지우기, Return은 닫고 저장이다.
/// **글자를 입력하는 중에는 건드리지 않는다** — 속성 입력칸의 Delete를 가로채면 글자가 안 지워진다.
@MainActor
final class PointKeyMonitor {
    weak var env: AppEnvironment?
    private var token: Any?
    init(env: AppEnvironment) { self.env = env }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handle(keyCode: event.keyCode, modifiers: event.modifierFlags,
                             textIsEditing: NSApp.keyWindow?.firstResponder is NSTextView,
                             hasModal: NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil) ?? false
            }
            return handled ? nil : event
        }
    }

    func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], textIsEditing: Bool = false,
                hasModal: Bool = false) -> Bool {
        guard let env, env.isPointWorkMode, !hasModal, !textIsEditing,
              modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        switch keyCode {
        case 53:
            guard !env.pointDraft.isEmpty || env.vertexDrag != nil else { return false }
            env.escapePointDraft(); return true
        case 51, 117:
            guard !env.pointDraft.isEmpty else { return false }
            env.removeLastDraftPoint(); return true
        case 36, 76:
            guard env.activeGeometryKind.isAreal, env.pointDraft.points.count >= 3 else { return false }
            env.closePointDraft(); return true
        default:
            return false
        }
    }

    func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
}
