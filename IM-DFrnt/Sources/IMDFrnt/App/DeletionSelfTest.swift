import Foundation

@MainActor
enum DeletionSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let env = AppEnvironment()
        env.openSample()
        env.enterRoutingScreen()
        let floor = env.currentRoutingFloor!.id
        let a = RoutingNode(floorID: floor, point: LocalPoint(100, 100), name: "A")
        let b = RoutingNode(floorID: floor, point: LocalPoint(300, 100), name: "B")
        let c = RoutingNode(floorID: floor, point: LocalPoint(500, 100), name: "C")
        let ab = RoutingEdge(from: a.id, to: b.id)
        let bc = RoutingEdge(from: b.id, to: c.id)
        env.routing.nodes = [a, b, c]
        env.routing.edges = [ab, bc]
        env.undoStack.clear()
        let monitor = RoutingKeyMonitor(env: env)
        env.selectRoutingEdge(ab.id)
        let before = env.snapshot

        check("엣지 Delete는 삭제 알림을 요청하고 확인 전 상태를 유지", monitor.handle(keyCode: 51) &&
              env.pendingDeletion?.message.contains("A ↔ B") == true && env.snapshot == before && !env.undoStack.canUndo)
        let pendingID = env.pendingDeletion!.id
        check("알림 중 반복 Delete·Escape는 삭제 요청을 바꾸지 않음", !monitor.handle(keyCode: 51) &&
              !monitor.handle(keyCode: 53) && env.pendingDeletion?.id == pendingID && env.snapshot == before)
        env.cancelDeletion()
        check("삭제 취소는 그래프·선택·실행 취소 기록을 유지", env.pendingDeletion == nil &&
              env.snapshot == before && !env.undoStack.canUndo)
        check("엣지 Forward Delete도 확인 알림을 요청", monitor.handle(keyCode: 117) && env.routing.edge(ab.id) != nil)
        env.confirmDeletion(env.pendingDeletion!.id)
        check("엣지 삭제 확정은 양 끝 노드와 다른 엣지를 유지", env.routing.edge(ab.id) == nil &&
              env.routing.nodes == before.routing.nodes && env.routing.edge(bc.id) == bc && env.routingSelectedEdgeID == nil &&
              env.undoStack.undoEntries.count == 1)
        env.undo()
        check("확인 후 엣지 삭제를 한 번 되돌려 ID·선택을 복원", env.snapshot == before)
        env.redo()
        check("확인 후 엣지 삭제 다시 실행", env.routing.edge(ab.id) == nil && env.routing.nodes.count == 3)
        env.undo()
        check("엣지 선택 상태에서 텍스트 입력·모달·명령 키 Delete 보호", !monitor.handle(keyCode: 51, textIsEditing: true) &&
              !monitor.handle(keyCode: 51, hasModal: true) && !monitor.handle(keyCode: 51, modifiers: .command) && env.pendingDeletion == nil)
        env.routingContextMenuIsOpen = true
        check("층 메뉴가 열린 동안 Escape·Delete를 메뉴에 전달", !monitor.handle(keyCode: 53) &&
              !monitor.handle(keyCode: 51) && env.pendingDeletion == nil && env.routingSelectedEdgeID == ab.id)
        env.routingContextMenuIsOpen = false

        env.requestRoutingEdgeDeletion(ab.id)
        let fixedTarget = env.pendingDeletion!.id
        env.requestRoutingNodeDeletion(c.id)
        check("중복 삭제 버튼 요청은 최초 알림 대상을 유지", env.pendingDeletion?.id == fixedTarget)
        env.selectRoutingEdge(bc.id)
        env.confirmDeletion(fixedTarget)
        check("알림 뒤 선택이 바뀌어도 원래 엣지만 삭제", env.routing.edge(ab.id) == nil &&
              env.routing.edge(bc.id) == bc && env.routingSelectedEdgeID == bc.id)
        env.undo()

        env.requestRoutingEdgeDeletion(ab.id)
        let staleID = env.pendingDeletion!.id
        env.cancelDeletion()
        env.requestRoutingEdgeDeletion(bc.id)
        let freshID = env.pendingDeletion!.id
        env.confirmDeletion(staleID)
        check("취소된 알림의 확정은 새로운 요청과 그래프를 변경하지 않음", env.pendingDeletion?.id == freshID &&
              env.routing.edge(ab.id) == ab && env.routing.edge(bc.id) == bc)
        env.cancelDeletion()

        env.requestRoutingEdgeDeletion(ab.id)
        let missingTarget = env.pendingDeletion!.id
        env.deleteRoutingEdge(ab.id)
        let undoCount = env.undoStack.undoEntries.count
        env.confirmDeletion(missingTarget)
        check("이미 없는 엣지 확정은 다른 엣지·실행 취소 기록을 유지", env.pendingDeletion == nil &&
              env.routing.edge(bc.id) == bc && env.undoStack.undoEntries.count == undoCount)
        env.undo()

        env.requestRoutingNodeDeletion(b.id)
        let nodeRequest = env.pendingDeletion!.id
        env.selectRoutingNode(c.id)
        env.confirmDeletion(nodeRequest)
        check("노드 확인은 원래 노드와 그 연결만 삭제", env.routing.node(b.id) == nil && env.routing.edges.isEmpty &&
              env.routing.node(a.id) == a && env.routing.node(c.id) == c && env.routingSelectedNodeID == c.id)
        env.undo()

        env.requestRoutingEdgeDeletion(ab.id)
        let oldProject = env.pendingDeletion!.id
        env.projectID = UUID()
        env.confirmDeletion(oldProject)
        check("프로젝트가 바뀐 삭제 요청은 실행하지 않음", env.pendingDeletion == nil && env.routing.edge(ab.id) == ab)

        env.addRoutingFloor()
        let secondFloor = env.currentRoutingFloor!.id
        let upstairs = RoutingNode(floorID: secondFloor, point: LocalPoint(100, 100), category: "stairs")
        env.routing.nodes.append(upstairs)
        let crossFloor = RoutingEdge(from: a.id, to: upstairs.id, accessible: false, category: .stairs)
        env.routing.edges.append(crossFloor)
        let allFloors = env.routing
        env.requestRoutingFloorDeletion(secondFloor)
        env.cancelDeletion()
        check("층 삭제 취소는 층간 노드·연결을 유지", env.routing == allFloors)
        env.requestRoutingFloorDeletion(secondFloor)
        env.confirmDeletion(env.pendingDeletion!.id)
        check("층 삭제 확정은 해당 층·노드·층간 연결을 정리", env.routing.floor(secondFloor) == nil &&
              env.routing.node(upstairs.id) == nil && env.routing.edge(crossFloor.id) == nil && env.routing.edge(ab.id) == ab)
        env.undo()
        check("확인 후 층 삭제 실행 취소는 전체 그래프 복원", env.routing == allFloors)

        do {
            let file = env.makeProjectFile()!
            env.requestRoutingEdgeDeletion(ab.id)
            let restored = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded())
            let requestID = env.pendingDeletion!.id
            try env.adopt(restored, from: nil)
            env.confirmDeletion(requestID)
            check("문서 재열기는 미확정 삭제 요청을 폐기", env.pendingDeletion == nil && env.routing == file.routing)
        } catch { check("삭제 알림 저장·문서 전환 검증", false) }
        env.selectRoutingNode(nil)
        check("선택 없는 Delete는 알림을 띄우지 않음", !monitor.handle(keyCode: 51) && env.pendingDeletion == nil)
    }
}
