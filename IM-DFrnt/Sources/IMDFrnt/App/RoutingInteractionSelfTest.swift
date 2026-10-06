import AppKit
import Foundation

@MainActor
enum RoutingInteractionSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let env = AppEnvironment()
        env.openSample()
        env.enterRoutingScreen()
        for point in [LocalPoint(100, 100), LocalPoint(240, 100), LocalPoint(360, 200)] {
            env.handleRoutingClick(at: point, tolerance: 9)
        }
        let nodes = env.routing.nodes
        let a = nodes[0].id, b = nodes[1].id
        env.beginRoutingConnectionDrag(from: a)
        env.updateRoutingConnectionDrag(to: LocalPoint(180, 120), tolerance: 9)
        check("연결 미리보기는 포인터를 따라가며 노드·연결을 변경하지 않음", env.routingConnectionDrag?.pointer == LocalPoint(180, 120) &&
              env.routingConnectionDrag?.target == nil && env.routing.nodes == nodes && env.routing.edges.isEmpty)
        env.updateRoutingConnectionDrag(to: LocalPoint(242, 102), tolerance: 9)
        check("포인터 아래 노드에 연결 미리보기 스냅", env.routingConnectionDrag?.target == b && env.routing.nodes == nodes)
        env.finishRoutingConnectionDrag(at: LocalPoint(240, 100), tolerance: 9)
        check("마우스 놓기로 연결 확정·출발 노드는 이동하지 않음", env.routing.edges.count == 1 &&
              env.routing.edges[0].from == a && env.routing.edges[0].to == b && env.routing.nodes == nodes && env.routingConnectionDrag == nil)
        let createdEdge = env.routing.edges[0]
        env.undo()
        check("드래그 연결은 한 번의 실행취소로 제거", env.routing.edges.isEmpty && env.routing.nodes == nodes && env.routingConnectionDrag == nil)
        env.redo()
        let edge = env.routing.edges[0]
        check("드래그 연결 다시실행은 같은 UUID로 복원", env.routing.edges == [createdEdge] && env.routingConnectionDrag == nil)
        env.beginRoutingConnectionDrag(from: b)
        env.finishRoutingConnectionDrag(at: LocalPoint(100, 100), tolerance: 9)
        check("역방향 중복 드래그는 기존 연결 선택", env.routing.edges == [edge] && env.routingSelectedEdgeID == edge.id)
        let undoTitle = env.undoMenuTitle
        env.beginRoutingConnectionDrag(from: a)
        env.finishRoutingConnectionDrag(at: LocalPoint(500, 300), tolerance: 9)
        check("빈 곳에 놓으면 미리보기만 취소·새 노드 없음", env.routing.edges == [edge] && env.routing.nodes == nodes &&
              env.routingConnectionDrag == nil && env.undoMenuTitle == undoTitle)
        env.beginRoutingConnectionDrag(from: a)
        env.finishRoutingConnectionDrag(at: LocalPoint(101, 102), tolerance: 9)
        check("출발 노드에 놓으면 자기 연결을 만들지 않음", env.routing.edges == [edge] && env.routingConnectionDrag == nil)
        env.beginRoutingConnectionDrag(from: a)
        env.updateRoutingConnectionDrag(to: LocalPoint(360, 200), tolerance: 9)
        let monitor = RoutingKeyMonitor(env: env)
        let escaped = monitor.handle(keyCode: 53, modifiers: .option)
        env.finishRoutingConnectionDrag(at: LocalPoint(360, 200), tolerance: 9)
        check("Option을 누른 상태의 Escape는 연결 취소", escaped && env.routing.edges == [edge] && env.routingConnectionDrag == nil)
        env.beginRoutingConnectionDrag(from: a)
        env.updateRoutingConnectionDrag(to: LocalPoint(240, 100), tolerance: 9)
        env.selectRoutingNode(b)
        env.deleteRoutingSelection()
        env.finishRoutingConnectionDrag(at: LocalPoint(240, 100), tolerance: 9)
        check("드래그 대상 삭제 후 유효하지 않은 연결을 남기지 않음", env.routing.node(b) == nil &&
              env.routing.edges.isEmpty && env.routingConnectionDrag == nil)
        env.undo()
        env.beginRoutingConnectionDrag(from: a)
        env.addRoutingFloor()
        env.finishRoutingConnectionDrag(at: LocalPoint(240, 100), tolerance: 9)
        check("층이 바뀌면 진행 중인 연결 드래그 취소", env.routing.edges == [edge] && env.routingConnectionDrag == nil)

        let first = UUID(uuidString: "12345678-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "12345678-1111-0000-0000-000000000002")!
        env.routing.nodes[0].id = first
        env.routing.nodes[1].id = second
        env.routing.edges[0].from = first
        env.routing.edges[0].to = second
        let labels = env.routing.nodeDisplayIDs
        check("짧은 ID가 겹쳐도 핀의 표시 ID로 구분 가능", labels[first] != labels[second] &&
              labels[first]?.hasPrefix("12345678") == true && labels[second]?.hasPrefix("12345678") == true)
        do {
            let reopened = AppEnvironment()
            try reopened.adopt(ProjectFile.decoded(from: env.makeProjectFile()!.encoded()), from: nil)
            check("핀 ID 표시는 저장·재열기에 유지", reopened.routing.nodeDisplayIDs == labels)
        } catch { check("핀 ID 표시 저장·재열기", false) }
    }
}
