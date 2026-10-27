import AppKit
import Foundation

@MainActor
enum RoutingEdgeGroupSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let env = AppEnvironment()
        env.openSample()
        env.enterRoutingScreen()
        let floorID = env.currentRoutingFloor!.id
        let nodes = [LocalPoint(100, 100), LocalPoint(300, 100), LocalPoint(500, 100), LocalPoint(500, 300)]
            .map { RoutingNode(floorID: floorID, point: $0) }
        env.perform("검사용 노드") { env.routing.nodes = nodes }
        let a = env.addRoutingEdgeGroup(name: "중앙 복도")!
        let b = env.addRoutingEdgeGroup(name: "자료실 복도")!
        check("#88 빈 이름 그룹 생성 방지", env.addRoutingEdgeGroup(name: "  ") == nil)
        env.routingNewEdgeGroupID = a
        var first: UUID!, second: UUID!, third: UUID!
        env.perform("그룹 연결") { first = env.connectRoutingNodes(nodes[0].id, nodes[1].id) }
        env.beginRoutingConnectionDrag(from: nodes[1].id)
        env.finishRoutingConnectionDrag(at: nodes[2].point, tolerance: 10)
        second = env.routing.edges.first { $0.id != first }!.id
        check("#88 클릭/드래그 연결에 사전 그룹 지정", env.routing.edge(first)?.groupID == a && env.routing.edge(second)?.groupID == a)
        env.routingNewEdgeGroupID = b
        env.perform("중복 연결") { _ = env.connectRoutingNodes(nodes[1].id, nodes[0].id) }
        check("#88 기존 연결 재선택은 그룹 불변", env.routing.edges.count == 2 && env.routing.edge(first)?.groupID == a)
        env.routingNewEdgeGroupID = nil
        env.perform("미배정 연결") { third = env.connectRoutingNodes(nodes[2].id, nodes[3].id) }
        env.setRoutingTool(.edges)
        env.handleRoutingClick(at: LocalPoint(200, 100), tolerance: 10)
        env.handleRoutingClick(at: LocalPoint(400, 100), tolerance: 10, modifiers: .shift)
        check("#88 Shift 엣지 복수 선택", env.routingSelectedEdgeIDs == [first, second] && env.routingSelectedNodeID == nil)
        env.handleRoutingClick(at: LocalPoint(400, 100), tolerance: 10, modifiers: .shift)
        check("#88 Shift 재클릭은 선택 해제", env.routingSelectedEdgeIDs == [first])
        env.selectRoutingEdges(in: CGRect(x: 190, y: 90, width: 220, height: 20), projecting: \.cg, additive: false)
        check("#88 양 끝점이 밖인 교차 엣지도 드래그 선택", env.routingSelectedEdgeIDs == [first, second])
        env.assignRoutingEdgeGroup(b)
        check("#88 일괄 그룹 배정", env.routing.edge(first)?.groupID == b && env.routing.edge(second)?.groupID == b && env.routing.edge(third)?.groupID == nil)
        env.undo()
        check("#88 일괄 배정 실행취소 및 다중 선택 복원", env.routing.edge(first)?.groupID == a && env.routing.edge(second)?.groupID == a && env.routingSelectedEdgeIDs == [first, second])
        env.redo()
        check("#88 일괄 배정 다시실행", env.routing.edge(first)?.groupID == b && env.routing.edge(second)?.groupID == b)
        env.setRoutingEdgeFilter(.unassigned)
        check("#88 필터 변경은 숨겨진 선택 정리", env.visibleRoutingEdges.map(\.id) == [third] && env.routingSelectedEdgeIDs.isEmpty)
        check("#88 숨긴 엣지 히트테스트 제외", env.nearestRoutingEdge(to: LocalPoint(200, 100), tolerance: 10) == nil)
        env.selectRoutingEdges(in: CGRect(x: 0, y: 0, width: 800, height: 600), projecting: \.cg, additive: false)
        check("#88 드래그 선택에도 같은 필터", env.routingSelectedEdgeIDs == [third])
        env.selectRoutingEdge(first, additive: true)
        check("#88 숨긴 엣지 Shift 선택 차단", env.routingSelectedEdgeIDs == [third])
        env.assignRoutingEdgeGroup(a)
        check("#88 필터에서 배정 뒤 숨겨진 선택 정리", env.routing.edge(third)?.groupID == a && env.routingSelectedEdgeIDs.isEmpty)
        env.setRoutingEdgeFilter(.group(b))
        check("#88 지정 그룹 필터", Set(env.visibleRoutingEdges.map(\.id)) == [first, second])
        env.selectRoutingEdges(in: CGRect(x: 190, y: 90, width: 20, height: 20), projecting: \.cg, additive: false)
        env.selectRoutingEdges(in: CGRect(x: 390, y: 90, width: 20, height: 20), projecting: \.cg, additive: true)
        check("#88 Shift 드래그 추가 선택", env.routingSelectedEdgeIDs == [first, second])
        let monitor = RoutingKeyMonitor(env: env)
        let beforeDeletion = env.routing
        check("#88 다중 Delete는 확인 전 보존", monitor.handle(keyCode: 51) && env.routing == beforeDeletion && env.pendingDeletion != nil)
        env.cancelDeletion()
        check("#88 다중 삭제 취소 보존", env.routing == beforeDeletion && env.routingSelectedEdgeIDs == [first, second])
        _ = monitor.handle(keyCode: 51)
        if let request = env.pendingDeletion { env.confirmDeletion(request.id) }
        check("#88 다중 삭제는 노드·다른 엣지 보존", env.routing.nodes == nodes && env.routing.edges.map(\.id) == [third])
        env.undo()
        check("#88 다중 삭제 실행취소", env.routing == beforeDeletion && env.routingSelectedEdgeIDs == [first, second])
        env.assignRoutingEdgeGroup(nil)
        check("#88 선택 그룹 해제", env.routing.edge(first)?.groupID == nil && env.routing.edge(second)?.groupID == nil)
        env.undo()
        env.routingNewEdgeGroupID = b
        env.removeRoutingEdgeGroup(b)
        check("#88 그룹 삭제는 엣지/노드 유지·참조 해제", env.routing.edgeGroup(b) == nil && env.routing.edges.count == 3 && env.routing.edge(first)?.groupID == nil && env.routingNewEdgeGroupID == nil && env.routingEdgeFilter == .all)
        env.undo()
        check("#88 그룹 삭제 실행취소는 UUID·배정 복원", env.routing.edgeGroup(b)?.name == "자료실 복도" && env.routing.edge(first)?.groupID == b)
        env.renameRoutingEdgeGroup(b, name: "새 이름")
        check("#88 이름 수정은 UUID 불변", env.routing.edgeGroup(b)?.name == "새 이름" && env.routing.edge(first)?.groupID == b)
        env.undo()
        check("#88 이름 수정 실행취소", env.routing.edgeGroup(b)?.name == "자료실 복도")
        do {
            let original = env.projectContents
            let data = try env.makeProjectFile()!.encoded()
            let file = try ProjectFile.decoded(from: data)
            let reopened = AppEnvironment()
            try reopened.adopt(file, from: nil)
            check("#88 v8 저장·재열기 그룹/배정 보존", file.version == 8 && reopened.routing == env.routing)
            check("#88 기존 IMDF 데이터·도형 불변", original.imdfFiles() == reopened.projectContents.imdfFiles())
            var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            legacy["version"] = 7
            var building = legacy["buildingProject"] as! [String: Any]
            building.removeValue(forKey: "edgeGroups")
            var levels = building["levels"] as! [[String: Any]]
            for i in levels.indices {
                var edges = levels[i]["edges"] as! [[String: Any]]
                for j in edges.indices { edges[j].removeValue(forKey: "groupID") }
                levels[i]["edges"] = edges
            }
            building["levels"] = levels; legacy["buildingProject"] = building
            let old = try ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: legacy)).commonProject()
            try old.validate()
            check("#88 그룹 없는 v7 파일 호환", old.edgeGroups == nil && old.routingGraph.edges.allSatisfy { $0.groupID == nil })
            let source = original.levels.first!
            var target = BuildingProject(levels: [ProjectLevel(info: ProjectLevelInfo(name: "대상", ordinal: 1))])
            target.edgeGroups = [RoutingEdgeGroup(id: a, name: "다른 의미")]
            let imported = try RoutingEdgeGroupImport.prepare(source, source: original, target: target)
            let newID = imported.level.edges.first { $0.id == third }!.groupID
            check("#88 층 가져오기 그룹 충돌 재발급", newID != a && imported.groups?.first { $0.id == a }?.name == "다른 의미" && imported.groups?.first { $0.id == newID }?.name == "중앙 복도")
            let same = try RoutingEdgeGroupImport.prepare(source, source: original, target: original)
            check("#88 동일 그룹은 가져오기에서 재사용", same.groups == original.edgeGroups && same.level.edges == source.edges)
            let targetID = env.addProjectLevel()
            check("#88 실제 층 가져오기에 그룹 함께 보존", env.importLevel(source, into: targetID, metadata: original) && env.buildingProject.edgeGroups == original.edgeGroups && env.activeLevel?.edges.allSatisfy { $0.groupID != nil } == true)
            env.undo()
            check("#88 층 가져오기 실행취소는 그래프 복원", env.routing.edges.count == original.routingGraph.edges.count)
            var graph = original.routingGraph
            for i in graph.floors.indices {
                for (p, g) in [(LocalPoint(0, 0), GeoPoint(longitude: 129, latitude: 36)),
                               (LocalPoint(1000, 0), GeoPoint(longitude: 129.001, latitude: 36)),
                               (LocalPoint(0, 700), GeoPoint(longitude: 129, latitude: 35.999))] {
                    graph.floors[i].anchors.add(local: p, geo: g, label: "기준")
                }
            }
            let exported = try RoutingExporter.collection(graph)
            let features = exported["features"] as! [[String: Any]]
            let props = features.first { $0["id"] as? String == first.uuidString.lowercased() }!["properties"] as! [String: Any]
            check("#88 내보내기에 그룹 UUID·이름", props["group_id"] as? String == b.uuidString.lowercased() && props["group_name"] as? String == "자료실 복도")
            graph.edges[0].groupID = nil
            let plain = try RoutingExporter.collection(graph)["features"] as! [[String: Any]]
            let plainProps = plain.first { $0["id"] as? String == graph.edges[0].id.uuidString.lowercased() }!["properties"] as! [String: Any]
            check("#88 미배정 엣지는 기존 출력 유지", plainProps["group_id"] == nil && plainProps["group_name"] == nil)
            check("#88 그룹 정보 포함 반복 출력 결정적", try RoutingExporter.encoded(graph) == RoutingExporter.encoded(graph))
            graph.edges[0].groupID = UUID()
            do { _ = try RoutingExporter.encoded(graph); check("#88 누락 그룹 참조 내보내기 차단", false) }
            catch { check("#88 누락 그룹 참조 내보내기 차단", true) }
            graph = original.routingGraph
            let duplicate = graph.edgeGroups!.first!
            graph.edgeGroups?.append(duplicate)
            do { try graph.validateEdgeGroups(); check("#88 그룹 UUID 중복 차단", false) }
            catch { check("#88 그룹 UUID 중복 차단", true) }
        } catch { check("#88 저장·가져오기·내보내기", false); print(error) }
        let box = CGRect(x: 10, y: 10, width: 10, height: 10)
        check("#88 사각형 밖 평행선 제외", !RoutingEdgeSelection.intersects(box, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 0)))
        check("#88 사각형 밖 대각선 제외", !RoutingEdgeSelection.intersects(box, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 5)))
        check("#88 경계 접점 포함", RoutingEdgeSelection.intersects(box, from: CGPoint(x: 0, y: 10), to: CGPoint(x: 10, y: 10)))
        check("#88 NaN 좌표 선택 제외", !RoutingEdgeSelection.intersects(box, from: CGPoint(x: Double.nan, y: 0), to: CGPoint(x: 10, y: 10)))
        env.selectRoutingNode(nil)
        env.setRoutingEdgeFilter(.all)
        env.resetProjectState()
        check("#88 프로젝트 전환은 임시 그룹/필터/선택 초기화", env.routingEdgeFilter == .all && env.routingNewEdgeGroupID == nil && env.routingSelectedEdgeIDs.isEmpty)
    }
}
