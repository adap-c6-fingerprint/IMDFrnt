import AppKit
import Foundation

/// 레이어의 작업 방식(#21, 2026-10-15).
///
/// 모든 레이어는 꼭짓점·교점을 찍어 도형을 만들고, polygon·multipolygon type(footprint 제외)은 면 단위 선택을
/// 함께 쓸 수 있다(`05) IM-DFrnt 신기능.md` 10번).
///
/// **fixture는 선 단위도 고를 수 있다**(2026-10-19 요청). 도면 개체를 클릭·드래그로 골라 fixture 하나로 저장하는
/// 종전 개체 선택 방식이다 — 변기·세면대처럼 도면에 이미 그려진 기호를 점으로 다시 따라 그리지 않아도 된다.
enum LayerEditMode: String, CaseIterable {
    case point
    case face
    case object

    var title: String {
        switch self {
        case .point: return "점 단위"
        case .face: return "면 단위"
        case .object: return "선 단위"
        }
    }

    /// 이 type 레이어에서 고를 수 있는가.
    func isAvailable(for type: IMDFFeatureType?) -> Bool {
        switch self {
        case .point: return true
        case .face: return type?.allowsFaceSelection ?? false
        case .object: return type?.allowsObjectSelection ?? false
        }
    }
}

/// 작성 중인 도형(DraftShape). 원본 SVG 개체와 무관한 좌표 목록이다.
struct PointDraft: Equatable {
    var points: [LocalPoint] = []
    /// 끊긴 자리. `i`가 있으면 i번 점과 i+1번 점 사이에 선분이 없다(엔진 디버깅 5-7).
    var breaks: Set<Int> = []
    /// Control 개체 편집 중이면 채워진다. 실행취소 칸에 점과 함께 담겨 같이 되돌아간다.
    var edit: PointEditSession?
    /// 저장된 도형을 고치는 중이면 그 도형의 링. 닫으면 새 feature가 아니라 이 링을 바꾼다.
    var source: PointDraftSource?
    var isEmpty: Bool { points.isEmpty }

    /// 흐리게 보이는 점. 편집을 시작한 점과 그 뒤 순번의 점들이다.
    func isDimmed(_ i: Int) -> Bool { edit.map { i >= $0.dimStart } ?? false }

    /// i번 점과 i+1번 점이 선분으로 이어져 있는가. 편집 중에는 새 점과 흐린 점 사이가 아직 비어 있다.
    func isConnected(_ i: Int) -> Bool {
        guard !breaks.contains(i) else { return false }
        if let edit, i == edit.dimStart - 1 { return false }
        return true
    }

    /// 점을 지우면 양옆 변이 하나로 합쳐진다. 둘 중 하나라도 끊겨 있었으면 합친 변도 끊긴 채다.
    mutating func remove(at i: Int) {
        points.remove(at: i)
        breaks = Set(breaks.compactMap { b -> Int? in
            if b < i - 1 { return b }
            if b == i - 1 || b == i { return i - 1 >= 0 ? i - 1 : nil }
            return b - 1
        }.filter { $0 < points.count - 1 })
    }

    /// i 자리에 점을 끼운다. i-1번 점 뒤가 끊겨 있었으면 끊긴 자리는 새 점 뒤로 밀린다.
    mutating func insert(_ p: LocalPoint, at i: Int) {
        points.insert(p, at: i)
        breaks = Set(breaks.map { $0 >= i - 1 ? $0 + 1 : $0 })
    }
}

/// 고치는 중인 저장된 도형의 링.
struct PointDraftSource: Equatable {
    var featureID: FeatureGroupID
    var ring: Int
}

/// Control 개체 편집(엔진 디버깅 5번). 이미 찍은 점을 Control+클릭하면 시작한다.
///
/// 점 순서가 `… anchor | 새 점들 | 흐린 점들 …`로 나뉜다. 새 점을 찍은 뒤 흐린 점을 누르면
/// 그 사이의 흐린 점이 빠지고 새 점이 그 순번에 들어간다. 예: 1…4,5,6에서 4를 누르고 a, 5를 누르면 1…a,5,6.
struct PointEditSession: Equatable {
    /// 새 점을 이어 붙일 마지막 활성 점의 순번. -1이면 맨 앞에 붙인다.
    var anchor: Int
    var insertedCount = 0
    /// 첫 흐린 점의 순번.
    var dimStart: Int { anchor + 1 + insertedCount }
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
        return type.requiredGeometry != .none && !isPolygonWorkMode && !isObjectWorkMode
    }

    /// 지금 화면이 도면 개체를 골라 feature로 묶는 선 단위인가(fixture 전용).
    var isObjectWorkMode: Bool {
        guard document != nil, !showRoutingScreen, layerEditMode == .object else { return false }
        return layers.activePropertyType?.allowsObjectSelection ?? false
    }

    var activeGeometryKind: GeoJSONGeometryKind { layers.activePropertyType?.requiredGeometry ?? .none }

    /// 지금 무엇을 해야 하는지 한 줄로. 상단바가 그대로 띄운다.
    var pointStageHint: String {
        let n = pointDraft.points.count
        if let tool = unitToolInUse { return tool.hint(points: n) }
        switch activeGeometryKind {
        case .point:
            return "점 하나를 찍으면 바로 저장합니다."
        case .lineString:
            return n == 0 ? "선의 시작점을 찍으세요." : "끝점을 찍으면 선으로 저장합니다."
        case .polygon, .multiPolygon:
            if let edit = pointDraft.edit {
                return edit.insertedCount == 0
                    ? "개체 편집: 새 점을 찍거나, 흐린 점을 눌러 다시 살리세요. (Control 유지)"
                    : "개체 편집: 이어 붙일 흐린 점을 누르면 새 점이 그 순번에 들어갑니다. (Control 유지)"
            }
            if !pointDraft.breaks.isEmpty {
                return "선분이 \(pointDraft.breaks.count)곳 끊겨 있습니다. Control을 누른 채 끊긴 뒤쪽 점을 두 번 누르면 이어집니다."
            }
            if pointDraft.source == nil, let type = layers.activePropertyType,
               let target = multiPolygonTarget(for: type), let f = features.feature(target) {
                return "\(f.serialNumber)에 다각형을 더하는 중입니다. 다각형을 닫으면 이 feature에 들어갑니다(감싸면 기존이 구멍, 안쪽이면 새 것이 구멍)."
            }
            if pointDraft.source != nil {
                return "저장된 도형을 고치는 중입니다. 시작점(◎)을 누르거나 Return으로 반영하고, ESC로 취소합니다."
            }
            if n == 0 { return "꼭짓점을 순서대로 찍으세요. (0/3 이상) 저장된 도형의 꼭짓점은 Shift+클릭으로 뺍니다." }
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
    /// `editing`은 Control을 누른 채 누른 클릭이다(엔진 디버깅 5번 개체 편집).
    /// `removing`은 Shift를 누른 채 누른 클릭이다. 저장된 도형의 꼭짓점을 뺀다(2026-10-18 요청).
    func handlePointClick(at point: LocalPoint, tolerance: Double, freePoint: Bool, editing: Bool = false,
                          removing: Bool = false) {
        guard isPointWorkMode, let type = layers.activePropertyType else { return }
        let radius = tolerance * 1.5
        let kind = type.requiredGeometry
        if removing, pointDraft.isEmpty {
            removeSavedVertex(near: point, radius: radius)
            return
            // 작성 중인 도형이 있으면 아래 종전 경로가 받는다. 찍은 점을 다시 누르면 지우는 것과 같다.
        }
        if let tool = unitToolInUse {
            handleUnitToolClick(tool, at: point, radius: radius, freePoint: freePoint, editing: editing)
            return
            // unit의 보조 선분·자르기·점 끼우기 도구는 다각형을 그리지 않는다.
        }
        if editing, kind.isAreal, pointDraft.edit != nil || pointDraftIndex(near: point, radius: radius) != nil {
            handlePointEditClick(at: point, radius: radius, freePoint: freePoint)
            return
        }
        if editing, kind.isAreal, let hit = savedRingVertex(near: point, radius: radius) {
            beginSavedShapeEdit(hit.feature, ring: hit.ring, index: hit.index)
            return
        }
        if pointDraft.edit != nil { endPointEditSession() }
        // Control을 뗀 신호를 놓쳤어도 일반 클릭 전에 편집을 정리한다.
        let draft = pointDraft.points

        if kind.isAreal, draft.count >= 3, draft[0].distance(to: point) <= radius {
            closePointDraft()
            return
        }
        if let idx = pointDraftIndex(near: point, radius: radius) {
            perform("점 삭제") { pointDraft.remove(at: idx) }
            return
        }

        guard let target = pointTarget(near: point, radius: radius, freePoint: freePoint) else { return }

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

    private func pointDraftIndex(near point: LocalPoint, radius: Double) -> Int? {
        pointDraft.points.firstIndex { $0.distance(to: point) <= radius }
    }

    /// 새로 찍을 자리. 꼭짓점·교점에 붙이고, 없으면 ⌥(Option)일 때만 그 자리에 만든다.
    /// `edges`면 꼭짓점이 없을 때 저장된 개체의 변·보조 선분 위에도 붙는다(보조 선분·자르기 도구).
    /// 고른 점은 마지막으로 이웃 도형의 꼭짓점·변에 맞춘다(`alignPoint`). 실오라기를 찍는 순간에 막는다.
    func pointTarget(near point: LocalPoint, radius: Double, freePoint: Bool, edges: Bool = false) -> LocalPoint? {
        rawPointTarget(near: point, radius: radius, freePoint: freePoint, edges: edges).map {
            alignPoint($0, to: alignmentNeighbors(for: layers.activePropertyType, excluding: pointDraft.source?.featureID))
        }
    }

    private func rawPointTarget(near point: LocalPoint, radius: Double, freePoint: Bool, edges: Bool) -> LocalPoint? {
        let snap = snapPointIndex.nearest(to: point, within: radius)?.point
        let saved = savedFeatureVertex(near: point, radius: radius)
        switch (snap, saved) {
        case let (s?, v?): return s.distance(to: point) < v.distance(to: point) ? s : v
        case let (s?, nil): return s
        case let (nil, v?): return v
        case (nil, nil): break
        }
        // 이미 개체로 저장된 점도 다시 고른다. 옆 unit과 같은 꼭짓점을 정확히 같은 좌표로 써야
        // unit끼리 겹치거나 틈이 생기지 않는다(IMDF: 같은 층 unit 사이 빈틈·겹침 금지).
        // ⌥로 만든 점처럼 도면 점이 아닌 꼭짓점은 도면 점 목록에 없어 예전에는 찍히지 않았다.
        if edges, let e = savedEdgePoint(near: point, radius: radius) { return e }
        if freePoint { return point }
        notify(isComputingDerivedGeometry
               ? "꼭짓점·교점을 계산하는 중입니다. 잠시 후 다시 찍으세요."
               : "꼭짓점·교점이 아닌 자리입니다. 새 점을 만들려면 ⌥(Option)을 누른 채 클릭하세요.")
        return nil
        // 아무 데나 찍게 두지 않는 것이 요점이다. 눈대중으로 찍으면 몇 단위씩 어긋나
        // 옆 도형과 틈이 생긴다(신기능 3-2와 같은 이유). 새 점은 의도했을 때만 만든다.
    }

    /// 이 층에 저장된 개체(모든 레이어)의 꼭짓점 중 가장 가까운 것. 링·선·문 닫기 선분의 끝점이다.
    private func savedFeatureVertex(near p: LocalPoint, radius: Double) -> LocalPoint? {
        var best: (LocalPoint, Double)?
        func consider(_ v: LocalPoint) {
            let d = v.distance(to: p)
            if d <= radius, best == nil || d < best!.1 { best = (v, d) }
        }
        for f in features.features where !f.isInTrash {
            for ring in f.polygonRings { ring.forEach(consider) }
            f.drawnVertices?.forEach(consider)
            if let c = f.closureSegment { consider(c.start); consider(c.end) }
        }
        return best?.0
    }

    // MARK: 개체 편집 (엔진 디버깅 5번)

    /// Control을 누른 채 클릭. 선택한 순서대로만 잇던 방식은 중간 점을 지우고 새 점을 찍으면
    /// 새 점이 맨 끝에 붙어 도형이 꼬였다. 여기서는 새 점을 빠진 순번 자리에 끼운다.
    private func handlePointEditClick(at point: LocalPoint, radius: Double, freePoint: Bool) {
        let hit = pointDraftIndex(near: point, radius: radius)
        guard let edit = pointDraft.edit else {
            guard let i = hit else { return }
            perform("개체 편집 시작") { pointDraft.edit = PointEditSession(anchor: i - 1) }
            return
            // 누른 점과 그 뒤 순번이 흐려진다. 예: 1…4,5,6에서 4를 누르면 4,5,6이 흐려진다.
        }
        guard let i = hit else {
            guard let target = pointTarget(near: point, radius: radius, freePoint: freePoint) else { return }
            perform("점 끼우기") {
                pointDraft.insert(target, at: edit.dimStart)
                pointDraft.edit?.insertedCount += 1
            }
            return
        }
        if i >= edit.dimStart {
            if edit.insertedCount == 0 {
                perform("점 다시 살리기") {
                    pointDraft.breaks.subtract(Set(max(0, edit.anchor)..<i))
                    pointDraft.edit?.anchor = i
                    if i >= pointDraft.points.count - 1 { pointDraft.edit = nil }
                }
                return
                // 새 점 없이 흐린 점을 누르면 그 점까지 다시 잇는다(5-5: 4를 두 번 누르면 4 뒤에 끼운다).
                // 끊긴 자리도 함께 이어지므로, 끊긴 뒤쪽 점을 두 번 누르면 끊긴 곳이 붙는다.
            }
            perform("새 점 이어 붙이기") {
                for j in (edit.dimStart..<i).reversed() { pointDraft.remove(at: j) }
                pointDraft.breaks.remove(edit.dimStart - 1)
                pointDraft.edit = nil
            }
            notify("새 점 \(edit.insertedCount)개를 \(edit.anchor + 2)번 자리에 넣었습니다. Control을 떼도 됩니다.")
            // 기존 점 - 새 점 - 기존 점이 이어지면 흐린 점이 모두 살아난다(5-6).
            return
        }
        if i > edit.anchor {
            perform("점 삭제") {
                pointDraft.remove(at: i)
                pointDraft.edit?.insertedCount -= 1
            }
            return
            // 방금 끼운 새 점을 다시 누르면 뺀다.
        }
        guard edit.insertedCount == 0 else {
            notify("새 점을 이을 흐린 점을 누르세요. 처음부터 다시 하려면 cmd+z로 새 점을 지우세요.", isError: true)
            return
        }
        perform("개체 편집 시작") { pointDraft.edit = PointEditSession(anchor: i - 1) }
        // 아직 새 점을 찍지 않았으면 다른 점에서 다시 시작한다.
    }

    /// Control을 떼면 개체 편집을 끝낸다. 새 점이 흐린 점과 이어지지 않았으면 그 사이가 끊긴 채 남는다(5-7).
    func endPointEditSession() {
        if let edit = pointDraft.edit {
            if edit.insertedCount == 0 {
                pointDraft.edit = nil
                // 아무것도 바꾸지 않았으면 조용히 원래대로 둔다. 실수로 누른 Control 클릭이 도형을 끊지 않게 한다.
            } else {
                perform("개체 편집 끝내기") {
                    if edit.dimStart < pointDraft.points.count { pointDraft.breaks.insert(edit.dimStart - 1) }
                    pointDraft.edit = nil
                }
            }
        }
        if activeGeometryKind.isAreal, !pointDraft.breaks.isEmpty {
            notify("선분이 \(pointDraft.breaks.count + 1)개로 끊겨 있습니다. 끊긴 곳을 이어야 도형을 닫을 수 있습니다.", isError: true)
            return
        }
        guard let source = pointDraft.source, pointDraft.edit == nil else { return }
        if let rings = features.feature(source.featureID)?.polygonRings, rings.indices.contains(source.ring),
           rings[source.ring] == pointDraft.points {
            pointDraft = PointDraft()
            return
            // 저장된 도형을 열었다가 바꾼 것 없이 떼면 그냥 닫는다.
        }
        closePointDraft()
        // 저장된 도형은 이어진 상태로 Control을 떼는 순간 반영한다. 꼬이면 경고하고 작성 중으로 남긴다.
    }

    /// Shift+클릭한 자리의 저장된 꼭짓점을 뺀다. 지금 레이어의 링·선만 대상이다.
    /// 3점 미만이 되거나, 꼬이거나, 같은 feature의 다른 다각형과 어긋나게 겹치면 빼지 않는다.
    /// 같은 점을 쓰는 이웃 도형은 건드리지 않는다 — 함께 빼면 이웃의 경계까지 바뀌어 틈·겹침이 생길 수 있다.
    func removeSavedVertex(near p: LocalPoint, radius: Double) {
        guard let type = layers.activePropertyType else { return }
        var hit: (FeatureGroup, ring: Int, index: Int, LocalPoint)?
        var bestDistance = Double.infinity
        for f in features.features(ofType: type) {
            for (r, ring) in f.polygonRings.enumerated() {
                for (i, v) in ring.enumerated() where v.distance(to: p) <= radius && v.distance(to: p) < bestDistance {
                    hit = (f, r, i, v); bestDistance = v.distance(to: p)
                }
            }
            for (i, v) in (f.drawnVertices ?? []).enumerated() where v.distance(to: p) <= radius && v.distance(to: p) < bestDistance {
                hit = (f, -1, i, v); bestDistance = v.distance(to: p)
            }
        }
        guard let (f, r, i, v) = hit else {
            notify("Shift+클릭한 자리에 지울 꼭짓점이 없습니다. 저장된 도형의 꼭짓점을 누르세요.", isError: true)
            return
        }
        let sharing = features.features.filter { o in
            !o.isInTrash && o.id != f.id
                && (o.polygonRings.contains { $0.contains { $0.distance(to: v) < 1e-9 } }
                    || (o.drawnVertices ?? []).contains { $0.distance(to: v) < 1e-9 })
        }.map(\.serialNumber)
        let note = sharing.isEmpty ? "" : " \(sharing.joined(separator: ", "))도 이 점을 씁니다(그쪽은 그대로 둠)."
        if r < 0 {
            guard var line = f.drawnVertices, line.count > 2 else {
                notify("\(f.serialNumber)는 점이 \(f.drawnVertices?.count ?? 0)개뿐이라 뺄 수 없습니다. 지우려면 우측 패널에서 feature를 지우세요.", isError: true)
                return
            }
            line.remove(at: i)
            perform("\(f.serialNumber) 꼭짓점 빼기") { features.update(f.id) { $0.drawnVertices = line } }
            notify("\(f.serialNumber)에서 꼭짓점을 뺐습니다.\(note)")
            return
        }
        var rings = f.polygonRings
        rings[r].remove(at: i)
        guard rings[r].count >= 3 else {
            notify("\(f.serialNumber)의 다각형은 꼭짓점이 3개 이상이어야 해서 더 뺄 수 없습니다.", isError: true)
            return
        }
        if PolygonValidity.selfIntersects(rings[r]) || PolygonValidity.isDegenerate(rings[r]) || !RingNesting.isValid(rings) {
            notify("이 꼭짓점을 빼면 도형이 꼬이거나 면이 사라지거나 다른 다각형과 겹칩니다. 빼지 않았습니다.", isError: true)
            return
        }
        perform("\(f.serialNumber) 꼭짓점 빼기") {
            features.update(f.id) { $0.polygonRings = rings; $0.polygonFaceIDs = [] }
        }
        notify("\(f.serialNumber)에서 꼭짓점을 뺐습니다. (남은 꼭짓점 \(rings[r].count)개)\(note)")
    }

    /// Control+클릭한 자리에 지금 레이어의 저장된 도형 꼭짓점이 있는가.
    private func savedRingVertex(near p: LocalPoint, radius: Double) -> (feature: FeatureGroupID, ring: Int, index: Int)? {
        guard let type = layers.activePropertyType else { return nil }
        for f in features.features(ofType: type) where f.isPointDrawn {
            for (r, ring) in f.polygonRings.enumerated() {
                if let i = ring.firstIndex(where: { $0.distance(to: p) <= radius }) { return (f.id, r, i) }
            }
        }
        return nil
    }

    /// 저장된 도형의 꼭짓점을 Control+클릭하면 그 링을 작성 중 도형으로 꺼내 같은 방식으로 고친다.
    /// 원래 도형은 반영 전까지 그대로 두므로 ESC로 취소하면 아무것도 바뀌지 않는다.
    func beginSavedShapeEdit(_ fid: FeatureGroupID, ring r: Int, index i: Int) {
        guard let f = features.feature(fid), f.polygonRings.indices.contains(r) else { return }
        guard pointDraft.isEmpty else {
            notify("작성 중인 도형을 먼저 닫거나 ESC로 취소하세요.", isError: true)
            return
        }
        pointDraft = PointDraft(points: f.polygonRings[r], edit: PointEditSession(anchor: i - 1),
                                source: PointDraftSource(featureID: fid, ring: r))
        // 실행취소 칸을 쌓지 않는다. 바꾸기 전의 모습은 원래 도형이 그대로 갖고 있다.
        notify("\(f.serialNumber) 편집: 새 점을 찍고 흐린 점을 누르면 그 순번에 들어갑니다.")
    }

    /// 시작점 재선택(또는 상단바 버튼)으로 도형을 닫고 저장한다.
    /// **미완성·자기 교차·넓이 0인 도형은 확정하지 않는다**(#21 완료 조건).
    func closePointDraft() {
        if let tool = unitToolInUse {
            if tool == .cut { cutUnitsAlongDraft() }
            return
            // 보조 선분·자르기는 닫을 다각형이 없다. Return은 자르기 도구에서만 '자르기'다.
        }
        guard let type = layers.activePropertyType, type.requiredGeometry.isAreal else { return }
        guard pointDraft.edit == nil, pointDraft.breaks.isEmpty else {
            notify("선분이 끊겨 있어 닫을 수 없습니다. Control을 누른 채 끊긴 뒤쪽 점을 두 번 누르거나 새 점으로 이으세요.",
                   isError: true)
            return
        }
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
        if let source = pointDraft.source, let f = features.feature(source.featureID),
           f.polygonRings.indices.contains(source.ring) {
            let (alignedRing, moved) = alignRings([ring], type: type, excluding: source.featureID)
            var rings = f.polygonRings
            rings[source.ring] = alignedRing[0]
            guard RingNesting.isValid(rings) else {
                notify("고친 다각형이 같은 feature의 다른 다각형과 어긋나게 겹칩니다. 완전히 감싸거나 떨어지게 고치세요.", isError: true)
                return
            }
            var shared: [String] = []
            perform("\(f.serialNumber) 개체 편집") {
                features.update(source.featureID) { $0.polygonRings[source.ring] = alignedRing[0] }
                shared = insertSharedVertices(of: alignedRing, type: type, excluding: source.featureID)
                pointDraft = PointDraft()
            }
            notify("\(f.serialNumber)을 고쳤습니다. (꼭짓점 \(alignedRing[0].count)개)" + Self.alignmentNote(moved: moved, shared: shared))
            return
        }
        if let target = multiPolygonTarget(for: type) {
            addRingToMultiPolygon(ring, target: target)
            return
            // 우측 패널에서 MultiPolygon으로 지정한 feature가 있으면 새 feature 대신 그 feature에 더한다.
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
        perform("점 삭제") {
            pointDraft.edit = nil
            pointDraft.remove(at: pointDraft.points.count - 1)
        }
    }

    /// Save point/line geometry with a serial reserved at the actual creation boundary.
    private func savePointDrawnFeature(type: IMDFFeatureType, vertices: [LocalPoint]) {
        if type.requiredGeometry == .lineString,
           vertices.count >= 2, vertices[0].distance(to: vertices[1]) <= SnapPointExtractor.mergeTolerance {
            notify("두 점이 같은 자리입니다. 선의 양 끝을 찍으세요.", isError: true)
            return
            // 길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다.
        }
        let serial = nextFeatureSerial(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        f.drawnVertices = vertices
        perform("\(serial) 저장") {
            features.insert(f)
            pointDraft = PointDraft()
        }
        notify("\(serial) 로 저장했습니다.")
        if type == .amenity {
            expandedFeature = f.id
            tagEditorRequest = f.id
        }
        // amenity는 점 하나라 찍는 순간이 곧 저장이다. 이름표를 다시 누르지 않아도 category·name 창을 바로 연다.
        // 이름표를 누른 것과 같게 그 feature를 고른 상태로 둔다 — 창은 고른 feature에만 뜬다.
    }

    /// Save a local ring; shared Footprint serials are reserved without mutating other floors.
    private func savePolygonDrawnFeature(type: IMDFFeatureType, ring: [LocalPoint]) {
        let serial = nextFeatureSerial(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        let (aligned, moved) = alignRings([ring], type: type, excluding: nil)
        f.polygonRings = aligned
        // 링이 정본이다(`VertexExtractor`). 원본 개체를 구성원으로 갖지 않으므로 소유권도 주장하지 않는다.
        let twins = type == .fixture && savesFixtureTwins ? fixtureTwinPlacements(for: pointDraft.points) : []
        var added = 0
        var shared: [String] = []
        perform("\(serial) 저장") {
            features.insert(f)
            shared = insertSharedVertices(of: aligned, type: type, excluding: f.id)
            pointDraft = PointDraft()
            added = insertFixtureTwins(rings: f.polygonRings, properties: f.properties,
                                       placements: twins, except: f.id).added
        }
        // 쌍둥이 자리도 같은 실행취소 칸에 넣는다. cmd+z 한 번에 함께 사라진다.
        notify("\(serial) 로 저장했습니다. (꼭짓점 \(aligned[0].count)개)"
               + (added > 0 ? " 똑같이 생긴 \(added)곳에도 개별 fixture로 저장했습니다." : "")
               + Self.alignmentNote(moved: moved, shared: shared))
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
                var rings = f.polygonRings
                rings[r] = ring
                if PolygonValidity.selfIntersects(ring) || PolygonValidity.isDegenerate(ring) || !RingNesting.isValid(rings) {
                    notify("옮기면 도형이 꼬이거나 면이 사라지거나 다른 다각형과 겹칩니다. 꼭짓점을 원래 자리에 둡니다.", isError: true)
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
            if !pointCoveredObjectIDs.isEmpty { pointCoveredObjectIDs = [] }
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
        let covered = pointCoveredObjects(tagged: tagged)
        if pointCoveredObjectIDs != covered { pointCoveredObjectIDs = covered }
    }

    /// 점 단위로 그린 feature가 덮은 도면 개체. 전체 진행률(개체 기준)의 '저장'에 들어간다.
    ///
    /// 두 가지 경우를 센다.
    /// ① **제 꼭짓점·끝점이 전부 태깅된 개체** — 방 둘레를 찍으면 그 둘레의 벽선이 여기 든다.
    ///    교차점은 빼고 본다. 가구 선이 벽을 가로지른 자리까지 요구하면 벽이 영영 안 끝난다.
    /// ② **문 자리 안에 통째로 든 개체** — opening 선(두 점)·임시 문을 지름으로 한 문 자리
    ///    (선을 따라 그 길이만큼, 양옆으로 그 길이만큼) 안에 모든 점이 든 개체. 문짝과 문 호가 여기 든다.
    ///    문 선은 양쪽 벽 끝(문설주)만 찍으므로 ①로는 문짝·호가 잡히지 않는다.
    func pointCoveredObjects(tagged: Set<Int>, usingGrid: Bool = true) -> Set<VectorObjectID> {
        // `usingGrid`는 자체점검이 격자 없이 전부 훑은 결과와 견주는 데만 끈다.
        var total: [VectorObjectID: Int] = [:], hit: [VectorObjectID: Int] = [:]
        for (i, p) in snapPoints.enumerated() where p.kind != .crossing {
            let isTagged = tagged.contains(i)
            for o in p.owners {
                total[o, default: 0] += 1
                if isTagged { hit[o, default: 0] += 1 }
            }
        }
        var covered = Set(total.compactMap { id, n in hit[id] == n ? id : nil })

        var doors: [(LocalPoint, LocalPoint)] = doorClosures.doors.map { ($0.start, $0.end) }
        for f in features.features where !f.isInTrash {
            if let c = f.closureSegment { doors.append((c.start, c.end)) }
            if f.featureType == .opening, let v = f.drawnVertices, v.count == 2 { doors.append((v[0], v[1])) }
        }
        guard !doors.isEmpty, let doc = document else { return covered }
        let segmentation = segmentation, renderCache = renderCache, index = spatialIndex
        // 문마다 6만 개를 돌며 `@Published` 저장소를 읽던 것이 feature를 고칠 때마다 300 ms였다(2026-10-19).
        // 저장소는 한 번만 읽고, 개체는 격자로 문 자리 근처만 본다.
        for (a, b) in doors {
            let length = a.distance(to: b)
            guard length > 1e-9 else { continue }
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
            let tol = length * 0.05
            let zone = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                .insetBy(dx: -length - tol, dy: -length - tol)
            let nearby = (usingGrid ? index.candidates(in: zone) : nil).map { ids in ids.compactMap { doc.object($0) } } ?? doc.objects
            // 격자는 칸에 걸친 개체를 모두 담으므로 문 자리 안의 개체를 빠뜨리지 않는다. 격자가 없으면 전체를 본다.
            for o in nearby where !covered.contains(o.id) {
                guard zone.contains(renderCache.entry(for: o, segmentation: segmentation).box) else { continue }
                let inside = segmentation.effectiveGeometry(for: o.id, fallback: o.geometry).subpaths.allSatisfy { sp in
                    sp.points.allSatisfy { p in
                        let dx = p.x - a.x, dy = p.y - a.y
                        let along = dx * ux + dy * uy, across = abs(-dx * uy + dy * ux)
                        return along >= -tol && along <= length + tol && across <= length + tol
                    }
                }
                if inside { covered.insert(o.id) }
            }
        }
        return covered
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
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .flagsChanged {
                MainActor.assumeIsolated { self?.handleFlags(event.modifierFlags) }
                return event
            }
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

    private var controlDown = false

    /// Control을 떼면 개체 편집이 끝난다(엔진 디버깅 5-6·5-7).
    /// 떼는 순간만 본다. 끊긴 도형을 둔 채 Shift 같은 다른 키를 누를 때마다 경고가 다시 뜨지 않게 한다.
    func handleFlags(_ modifiers: NSEvent.ModifierFlags) {
        let wasDown = controlDown
        controlDown = modifiers.contains(.control)
        guard let env, !controlDown, wasDown || env.pointDraft.edit != nil,
              env.pointDraft.edit != nil || env.pointDraft.source != nil else { return }
        env.endPointEditSession()
    }

    func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
}
