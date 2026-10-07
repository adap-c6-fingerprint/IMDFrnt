import AppKit
import Foundation

@MainActor
enum RoutingCommandClickSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let env = AppEnvironment()
        env.openSample()
        env.enterRoutingScreen()
        let floorID = env.currentRoutingFloor!.id
        for tool in [RoutingTool.place, .select, .connect] {
            env.setRoutingTool(tool)
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 9)
            check("\(tool.title): 일반 빈 곳 클릭은 노드를 추가하지 않음", env.routing.nodes.isEmpty)
        }
        env.setRoutingTool(.place)
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 9, modifiers: .command)
        let first = env.routingSelectedNodeID!
        check("Command 클릭은 현재 층의 해당 위치에 노드 한 개 추가", env.routing.nodes.count == 1 &&
              env.routing.node(first)?.floorID == floorID && env.routing.node(first)?.point == LocalPoint(100, 100))
        env.undo()
        check("Command 클릭 추가는 한 번의 실행취소로 제거", env.routing.nodes.isEmpty)
        env.redo()
        check("Command 클릭 추가 다시실행은 같은 UUID 유지", env.routing.nodes.count == 1 && env.routing.node(first) != nil)

        for (index, tool) in [RoutingTool.select, .connect, .calibrate].enumerated() {
            env.setRoutingTool(tool)
            env.handleRoutingClick(at: LocalPoint(Double(200 + 100 * index), 100), tolerance: 9, modifiers: .command)
            check("\(tool.title)에서도 Command 클릭 추가·도구 유지", env.routing.nodes.count == index + 2 &&
                  env.routingTool == tool && env.routingPendingAnchor == nil && env.routingConnectStart == nil)
        }
        env.setRoutingTool(.connect)
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 9)
        env.handleRoutingClick(at: LocalPoint(200, 100), tolerance: 9, modifiers: .command)
        check("기존 핀 Command 클릭은 선택·중복 생성이나 연결 없음", env.routing.nodes.count == 4 &&
              env.selectedRoutingNode?.point == LocalPoint(200, 100) && env.routing.edges.isEmpty && env.routingConnectStart == nil)
        let before = env.routing
        env.handleRoutingClick(at: LocalPoint(-100, 100), tolerance: 9, modifiers: .command)
        env.handleRoutingClick(at: LocalPoint(.nan, 100), tolerance: 9, modifiers: .command)
        env.handleRoutingClick(at: LocalPoint(600, 200), tolerance: 9, modifiers: [.command, .option])
        env.handleRoutingClick(at: LocalPoint(600, 200), tolerance: 9, modifiers: [.command, .control])
        check("도면 밖·유효하지 않은 좌표·다른 modifier 조합은 노드 추가 안 함", env.routing == before)
        env.isImportingIMDF = true
        env.handleRoutingClick(at: LocalPoint(600, 200), tolerance: 9, modifiers: .command)
        check("IMDF 가져오기 중 Command 클릭은 작업 변경 안 함", env.routing == before)
        env.isImportingIMDF = false
        env.addRoutingFloor()
        let secondFloor = env.currentRoutingFloor!.id
        do {
            try env.setRoutingDrawing(secondFloor, data: Data(SampleFloorplan.svg.utf8), name: "2층.svg")
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 9, modifiers: .command)
            check("같은 위치 Command 클릭도 현재 층에만 추가", env.routing.nodes(on: floorID).count == 4 &&
                  env.routing.nodes(on: secondFloor).count == 1 && env.selectedRoutingNode?.floorID == secondFloor)
        } catch { check("Command 클릭 층별 추가", false) }
    }
}
