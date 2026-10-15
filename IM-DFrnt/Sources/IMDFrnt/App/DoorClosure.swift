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
    }

    // MARK: 점 찍기 (신기능 3-2, #37)

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

    /// 지금 무엇을 해야 하는지 한 줄로. 상단바가 그대로 띄운다.
    ///
    /// #37(2026-10-15): **문짝·호를 고르는 단계를 없앴다.** 예전에는 점 2개를 찍은 뒤 열려 있는
    /// 문짝과 회전 궤적(호)까지 골라야 저장할 수 있었는데, C5 도면은 호가 점선으로 그려져
    /// 곡선 하나로 고를 수 없었다(1차 사용성 검증 #35). 문 선의 양 끝 두 점만 찍는다.
    var doorStageHint: String {
        switch doorDraftPoints.count {
        case 0: return "문 자리의 양쪽 끝(○ 끝점 · □ 교차점 · ◇ 꼭짓점)을 2개 찍으세요."
        case 1: return "반대쪽 끝을 1개 더 찍으세요. 찍은 점을 다시 누르면 지워집니다."
        default: return "'임시 문 저장'을 누르세요. 다시 찍으면 가장 먼저 찍은 점이 밀려납니다."
        }
    }

    /// 도면을 클릭했을 때. **점만 찍는다.** 이미 찍은 점을 다시 누르면 지운다
    /// (되돌릴 길이 없으면 창을 나갔다 다시 들어와야 한다).
    func handleDoorClosureClick(at point: LocalPoint, tolerance: Double) {
        guard document != nil else { return }
        let radius = tolerance * 1.5

        if let idx = doorDraftPoints.firstIndex(where: { $0.distance(to: point) <= radius }) {
            doorDraftPoints.remove(at: idx)
            return
        }
        if let snap = SnapPointExtractor.nearest(to: point, among: doorSnapCache, within: radius) {
            toggleDoorPoint(snap.point)
            return
        }
        notify("끝점·교차점·꼭짓점 위를 찍으세요. 아무 데나 찍으면 벽과 몇 단위씩 어긋나 방이 닫히지 않습니다.")
        // 아무 일도 안 일어나면 고장으로 읽히므로 왜 안 되는지 밝힌다(신기능 3-2의 이유 그대로).
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

    /// 이 개체가 화면에서 어떤 역할인가. 도면 패널이 색을 정하는 데 쓴다.
    /// 문짝·호를 고르지 않게 된 뒤로는 **예전에 저장한 임시 문이 쓰는 개체**만 표시한다.
    enum DoorRole { case none, saved }

    func doorRole(of id: VectorObjectID) -> DoorRole {
        doorClosures.user(of: id) != nil ? .saved : .none
    }

    // MARK: 저장 (신기능 3-4·3-5, #37)

    /// 점 2개가 찍혀 있으면 저장할 수 있다.
    var canSaveTemporaryDoor: Bool { doorDraftPoints.count == 2 }

    /// 왜 아직 저장할 수 없는지. 비활성 버튼만 있고 이유가 없으면 고장으로 읽힌다
    /// — 상단바 가시성(뷰 디버깅 10번)에서 겪은 것과 같은 오해다.
    var temporaryDoorHint: String {
        doorDraftPoints.count < 2
            ? "점 \(2 - doorDraftPoints.count)개를 더 찍으세요."
            : "임시 문으로 저장합니다. 모두 찍은 뒤 'Openings 레이어에 반영하기'를 누르세요."
    }

    func saveTemporaryDoor() {
        guard canSaveTemporaryDoor else { return }
        let a = doorDraftPoints[0], b = doorDraftPoints[1]
        guard a.distance(to: b) > SnapPointExtractor.mergeTolerance else {
            notify("두 점이 같은 자리입니다. 문 자리의 양쪽 끝을 찍으세요.", isError: true)
            return
            // 길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다.
        }

        let door = TemporaryDoor(id: UUID(), start: a, end: b, createdAt: Date())
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
                // 새 임시 문(#37)은 비어 있다. 예전 임시 문만 문짝·호를 구성원으로 넘긴다.
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
