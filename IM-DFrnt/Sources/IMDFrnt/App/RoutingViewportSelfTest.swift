import Foundation

@MainActor
enum RoutingViewportSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let full = CGSize(width: 900, height: 650), narrow = CGSize(width: 760, height: 650)
        check("#90 초기 0 크기에서 유효 화면이 되면 맞춤 재시도", CanvasZoom.routingResizeNeedsFit(from: .zero, to: full))
        check("#90 초기 가로/세로가 없는 화면도 맞춤 재시도",
              CanvasZoom.routingResizeNeedsFit(from: CGSize(width: 0, height: 650), to: full) &&
              CanvasZoom.routingResizeNeedsFit(from: CGSize(width: 900, height: 0), to: full))
        check("#90 선택 패널로 폭이 바뀌어도 자동 맞춤 안 함",
              !CanvasZoom.routingResizeNeedsFit(from: full, to: narrow) &&
              !CanvasZoom.routingResizeNeedsFit(from: narrow, to: full))
        check("#90 높이 변경·같은 크기에서도 자동 맞춤 안 함",
              !CanvasZoom.routingResizeNeedsFit(from: full, to: CGSize(width: 900, height: 600)) &&
              !CanvasZoom.routingResizeNeedsFit(from: full, to: full))
        check("#90 화면을 크게 줄여도 사용자 확대/이동 유지",
              !CanvasZoom.routingResizeNeedsFit(from: full, to: CGSize(width: 360, height: 200)))
        check("#90 유효하지 않은 새 크기에서 맞춤 안 함",
              !CanvasZoom.routingResizeNeedsFit(from: full, to: .zero) &&
              !CanvasZoom.routingResizeNeedsFit(from: .zero, to: CGSize(width: CGFloat.infinity, height: 650)) &&
              !CanvasZoom.routingResizeNeedsFit(from: .zero, to: CGSize(width: 900, height: CGFloat.nan)))

        let env = AppEnvironment()
        env.openSample()
        env.enterRoutingScreen()
        let fingerprint = env.routingDocument?.fingerprint, floorID = env.routingFloorID
        func fitTriggersUnchanged() -> Bool {
            fingerprint != nil && env.routingDocument?.fingerprint == fingerprint && env.routingFloorID == floorID
        }
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 9, modifiers: .command)
        let a = env.routingSelectedNodeID!
        env.handleRoutingClick(at: LocalPoint(300, 100), tolerance: 9, modifiers: .command)
        let b = env.routingSelectedNodeID!
        check("#90 노드 추가는 도면/층 맞춤 트리거 불변", env.routing.nodes.count == 2 && fitTriggersUnchanged())
        env.selectRoutingNode(a)
        env.moveRoutingNode(a, to: LocalPoint(120, 140))
        check("#90 노드 선택/이동은 도면/층 맞춤 트리거 불변", env.routing.node(a)?.point == LocalPoint(120, 140) && fitTriggersUnchanged())
        env.beginRoutingConnectionDrag(from: a)
        env.finishRoutingConnectionDrag(at: LocalPoint(300, 100), tolerance: 9)
        let edge = env.routingSelectedEdgeID!
        check("#90 연결 생성/선택은 도면/층 맞춤 트리거 불변",
              env.routing.edge(edge)?.to == b && fitTriggersUnchanged())
        let group = env.addRoutingEdgeGroup(name: "확대 검사")!
        env.assignRoutingEdgeGroup(group)
        env.setRoutingEdgeFilter(.group(group))
        check("#90 그룹/필터 편집은 도면/층 맞춤 트리거 불변",
              env.routing.edge(edge)?.groupID == group && fitTriggersUnchanged())
        env.undo()
        check("#90 같은 도면의 실행취소는 맞춤 트리거 불변", fitTriggersUnchanged())
        env.addRoutingFloor()
        check("#90 층 전환은 기존 맞춤 트리거 변경 유지", env.routingFloorID != floorID)
    }
}
