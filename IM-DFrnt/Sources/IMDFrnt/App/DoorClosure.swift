import AppKit
import Foundation

/// '문 임시로 닫기' 창의 상태와 명령(신기능 3항).
///
/// **왜 별도 창인가:** 이 작업은 도면 전체를 훑으며 문 자리마다 점 두 개를 정확히 찍는 일이다.
/// 메인 캔버스에 얹으면 개체 선택과 점 찍기가 같은 클릭을 두고 다투고, 무엇이 잡혔는지
/// 매번 확인해야 한다. Anchor 화면·보조 개체 창과 같은 이유로 화면을 나눈다(명세 9항 전례).
@MainActor
extension AppEnvironment {

    // MARK: 창 열고 닫기

    /// 신기능 3항: **Openings 레이어에 한해** 쓸 수 있다.
    /// 다른 type에서 열어 주면 사용자가 만든 opening이 엉뚱한 레이어에 쌓인다.
    var canEnterDoorClosure: Bool {
        document != nil && layers.activePropertyType == .opening
    }

    func enterDoorClosureScreen() {
        guard document != nil else {
            notify("먼저 도면을 여세요.", isError: true)
            return
        }
        guard layers.activePropertyType == .opening else {
            notify("'문 임시로 닫기'는 Openings 레이어에서만 쓸 수 있습니다.", isError: true)
            return
        }
        selection.clear()
        resetDoorDraft()
        rebuildDoorSnapPoints()
        // 여기서 처음 만든다. 도면을 열 때마다 만들면 실도면에서 그 자리에서 멈춘다.
        showDoorClosureScreen = true
    }

    func exitDoorClosureScreen() {
        showDoorClosureScreen = false
        resetDoorDraft()
    }

    /// 만들다 만 것은 창을 나갈 때 버린다. 남겨 두면 다음에 들어왔을 때
    /// 점 하나가 이미 찍힌 채로 시작해 "내가 찍은 적 없는 점"이 화면에 있다.
    func resetDoorDraft() {
        doorDraftPoints = []
        doorDraftDoorID = nil
        doorDraftArcID = nil
    }

    // MARK: 점 찍기 (신기능 3-2·3-3)

    /// 지금 창에서 찍을 수 있는 점 전부.
    ///
    /// **창에 들어갈 때 한 번 만들고, 그 뒤로는 캐시를 읽기만 한다.**
    /// 매 프레임 계산하면 쌍둥이 인덱스에서 겪은 정지가 그대로 재현되고(엔진 디버깅 1-1),
    /// 도면을 열 때마다 계산하면 **앱 시작이 멈춘다** — 자동 저장본을 복원하는 경로에서
    /// 실제로 그렇게 됐다. 계산량이 개체 수의 제곱에 붙는 것은 만드는 시점으로 풀어야 한다.
    var doorSnapPoints: [SnapPointExtractor.SnapPoint] { doorSnapCache }

    func rebuildDoorSnapPoints() {
        guard let doc = document else { doorSnapCache = []; return }
        doorSnapCache = SnapPointExtractor.points(in: doc.objects, segmentation: segmentation)
    }

    /// 지금 클릭이 무엇을 고르는가.
    ///
    /// **점과 개체를 같은 클릭으로 다투게 두면 개체를 영영 못 고른다.** 예전에는 점을 언제나
    /// 먼저 봤는데, 호는 곡선이라 경로 위 꼭짓점이 그 자체로 후보 점이다 — 호를 누르면
    /// 반드시 그 위의 점이 먼저 잡혀 **호가 선택되는 일이 아예 없었다.** 문짝도 짧은 선이라
    /// 양 끝점이 허용 반경 안에 들어오면 같은 일이 벌어진다.
    /// 그래서 순서를 **작업 순서와 같게** 나눴다 — 점 2개를 먼저 찍고, 그다음 문짝과 호를 고른다.
    enum DoorClickStage { case pickingPoints, pickingObjects }

    var doorClickStage: DoorClickStage {
        doorDraftPoints.count < 2 ? .pickingPoints : .pickingObjects
    }

    /// 지금 무엇을 고르는 중인지 한 줄로. 상단바가 그대로 띄운다 —
    /// 클릭이 단계에 따라 다르게 동작하면 그 사실이 화면에 있어야 한다.
    var doorStageHint: String {
        switch doorClickStage {
        case .pickingPoints:
            return "① 문 자리의 양쪽 끝(○ 끝점 · □ 교차점)을 \(2 - doorDraftPoints.count)개 더 찍으세요."
        case .pickingObjects:
            return "② 이제 열려 있는 문짝과 호를 클릭하세요. 찍은 점을 다시 누르면 지워집니다."
        }
    }

    /// 도면을 클릭했을 때.
    ///
    /// 순서가 규칙이다. ① 이미 찍은 점을 다시 누르면 **언제나** 지운다(되돌릴 길이 없으면
    /// 창을 나갔다 다시 들어와야 한다) ② 점이 2개가 되기 전에는 점만 찍는다
    /// ③ 점 2개가 놓이면 클릭은 개체를 고른다.
    func handleDoorClosureClick(at point: LocalPoint, tolerance: Double) {
        guard let doc = document else { return }
        let radius = tolerance * 1.5

        // ① 찍은 점 취소. 단계와 무관하게 통한다.
        if let idx = doorDraftPoints.firstIndex(where: { $0.distance(to: point) <= radius }) {
            doorDraftPoints.remove(at: idx)
            return
        }

        // ② 점을 찍는 단계.
        if doorClickStage == .pickingPoints {
            if let snap = SnapPointExtractor.nearest(to: point, among: doorSnapCache,
                                                     within: radius) {
                toggleDoorPoint(snap.point)
            }
            return
            // 점 단계에서는 개체를 잡지 않는다. 문 자리는 개체가 빽빽한 곳이라,
            // 개체를 함께 보면 점을 겨냥한 클릭이 그 아래 개체로 새어 나간다.
        }

        // ③ 개체를 고르는 단계.
        let candidates = doc.objects.filter { !auxiliary.isExcluded($0.id) }
        // 신기능 3-1: 제외된 보조 개체는 조작 불가. 후보에서 빼면 클릭이 통과해
        // 그 아래 개체가 잡힌다 — "안 눌린다"보다 "다른 게 눌린다"가 덜 헷갈린다.
        if let hit = HitTester.hitTest(point, candidates: candidates,
                                       cached: renderCache.geometryProvider(segmentation),
                                       tolerance: tolerance) {
            toggleDoorObject(hit)
            return
        }

        // 개체는 못 잡았는데 후보 점 위를 눌렀다면, 사용자는 점을 더 찍으려던 것이다.
        // 아무 일도 안 일어나면 고장으로 읽히므로 왜 안 되는지 밝힌다.
        if SnapPointExtractor.nearest(to: point, among: doorSnapCache, within: radius) != nil {
            notify("점은 이미 2개입니다. 다시 찍으려면 찍어 둔 점을 눌러 지우세요.")
        }
    }

    /// 점 쌍은 **두 개까지만** 받는다. 세 번째를 찍으면 가장 오래된 것을 밀어낸다 —
    /// 매번 지우고 다시 찍게 하면 손이 두 배로 든다.
    func toggleDoorPoint(_ p: LocalPoint) {
        if let idx = doorDraftPoints.firstIndex(where: {
            $0.distance(to: p) < SnapPointExtractor.mergeTolerance
        }) {
            doorDraftPoints.remove(at: idx)
            return
        }
        doorDraftPoints.append(p)
        if doorDraftPoints.count > 2 { doorDraftPoints.removeFirst() }
    }

    /// 개체 하나를 문짝/호 자리에 넣는다.
    ///
    /// **어느 자리인지는 사용자가 아니라 도형이 정한다.** 곡선이면 호, 아니면 문짝이다.
    /// 버튼으로 "지금 문짝을 고르는 중"을 먼저 정하게 하면 클릭 한 번에 모드 전환이 하나씩 더 붙는다.
    /// 호는 회전 궤적이라 반드시 곡선이고 문짝은 직선이라, 이 판정은 도면이 보장한다.
    func toggleDoorObject(_ id: VectorObjectID) {
        guard let obj = document?.object(id) else { return }

        if let used = doorClosures.user(of: id) {
            notify("이미 저장된 임시 문(\(used.label))이 쓰고 있는 개체입니다.", isError: true)
            return
            // 같은 문짝을 두 opening이 나눠 갖는 상황은 도면상 있을 수 없다.
        }

        let isArc = obj.isCurved
        if isArc {
            doorDraftArcID = (doorDraftArcID == id) ? nil : id
        } else {
            doorDraftDoorID = (doorDraftDoorID == id) ? nil : id
        }
    }

    /// 이 개체가 지금 화면에서 어떤 역할인가. 도면 패널이 색을 정하는 데 쓴다.
    enum DoorRole { case none, door, arc, saved }

    func doorRole(of id: VectorObjectID) -> DoorRole {
        if doorDraftDoorID == id { return .door }
        if doorDraftArcID == id { return .arc }
        if doorClosures.user(of: id) != nil { return .saved }
        return .none
    }

    // MARK: 저장 (신기능 3-4·3-5)

    /// 신기능 3-4: 점 2개 + 문짝 + 호, **넷이 모두 갖춰져야** 저장할 수 있다.
    var canSaveTemporaryDoor: Bool {
        doorDraftPoints.count == 2 && doorDraftDoorID != nil && doorDraftArcID != nil
    }

    /// 왜 아직 저장할 수 없는지. 비활성 버튼만 있고 이유가 없으면 고장으로 읽힌다
    /// — 상단바 가시성(뷰 디버깅 10번)에서 겪은 것과 같은 오해다.
    var temporaryDoorHint: String {
        var missing: [String] = []
        if doorDraftPoints.count < 2 { missing.append("점 \(2 - doorDraftPoints.count)개") }
        if doorDraftDoorID == nil { missing.append("열려 있는 문") }
        if doorDraftArcID == nil { missing.append("호") }
        return missing.isEmpty
            ? "Openings 개체로 저장합니다."
            : "\(missing.joined(separator: " · "))를 더 고르세요."
    }

    func saveTemporaryDoor() {
        guard canSaveTemporaryDoor,
              let doorID = doorDraftDoorID, let arcID = doorDraftArcID else { return }
        let a = doorDraftPoints[0], b = doorDraftPoints[1]
        guard a.distance(to: b) > SnapPointExtractor.mergeTolerance else {
            notify("두 점이 같은 자리입니다. 문 자리의 양쪽 끝을 찍으세요.", isError: true)
            return
            // 길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다.
        }

        let door = TemporaryDoor(id: UUID(), start: a, end: b,
                                 doorObjectID: doorID, arcObjectID: arcID,
                                 createdAt: Date())
        perform("임시 문 저장") { doorClosures.insert(door) }
        resetDoorDraft()
        notify("임시 문을 저장했습니다. 모두 찍은 뒤 '모두 Openings 레이어에 반영하기'를 누르세요.")
    }

    func removeTemporaryDoor(_ id: UUID) {
        perform("임시 문 삭제") { doorClosures.remove(id) }
    }

    // MARK: 레이어 반영 (신기능 3-6)

    var canApplyTemporaryDoors: Bool { !doorClosures.isEmpty }

    /// 모아 둔 임시 문을 Openings 레이어의 feature로 만든다.
    ///
    /// **한 번에 넘기는 것이 요점이다.** 문 하나마다 즉시 반영하면 도면 전체를 훑는 동안
    /// 우측 인스펙터가 계속 흔들리고 실행취소 칸이 문 개수만큼 쌓인다. 여기서는 칸 하나다.
    func applyTemporaryDoors() {
        guard !doorClosures.isEmpty else {
            notify("먼저 임시 문을 저장하세요.", isError: true)
            return
        }
        guard layers.activePropertyType == .opening else {
            notify("Openings 레이어에서만 반영할 수 있습니다.", isError: true)
            return
        }

        var made = 0
        var blocked: [String] = []
        perform("임시 문 레이어 반영") {
            for door in doorClosures.doors {
                let members = door.consumedObjectIDs
                guard members.isDisjoint(with: ownership.claimedObjectIDs) else {
                    blocked.append(door.label)
                    continue
                    // 그 사이에 문짝이나 호가 다른 feature로 저장됐다면 덮지 않는다.
                    // 소유권 배타 규칙은 이 경로에서도 똑같이 적용된다(신기능 3-8).
                }
                var f = FeatureGroup(featureType: .opening,
                                     serialNumber: serials.next(for: .opening),
                                     memberIDs: members)
                f.closureSegment = door.segment
                features.insert(f)
                try? ownership.claim(members, for: f.id)
                made += 1
            }
            if blocked.isEmpty { doorClosures.clear() }
            else { for d in doorClosures.doors where !blocked.contains(d.label) {
                doorClosures.remove(d.id)
            } }
            // 막힌 것은 목록에 남긴다. 지워 버리면 사용자가 무엇을 잃었는지 알 수 없다.
        }

        if blocked.isEmpty {
            notify("임시 문 \(made)개를 Openings 레이어에 반영했습니다.")
        } else {
            notify("\(made)개 반영 · \(blocked.count)개는 개체가 이미 다른 feature에 저장돼 건너뛰었습니다.",
                   isError: true)
        }
    }
}
