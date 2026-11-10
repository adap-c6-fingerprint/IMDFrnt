import Foundation

@MainActor
enum RoutingNodeGroupSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func rejects(_ name: String, _ body: () throws -> Void) {
            do { try body(); check(name, false) } catch { check(name, true) }
        }
        func floor(_ ordinal: Int) -> RoutingFloor {
            var f = RoutingFloor(name: "\(ordinal)층", ordinal: ordinal)
            f.anchors.add(local: LocalPoint(0,0), geo: GeoPoint(longitude:129, latitude:36), label:"A")
            f.anchors.add(local: LocalPoint(100,0), geo: GeoPoint(longitude:129.001, latitude:36), label:"B")
            f.anchors.add(local: LocalPoint(0,100), geo: GeoPoint(longitude:129, latitude:36.001), label:"C")
            return f
        }
        let floors = [floor(1), floor(2), floor(3), floor(5)]
        let nodes = floors.map { RoutingNode(floorID:$0.id, point:LocalPoint(10,10), category:"elevator") }
        let group = RoutingNodeGroup(name:"동쪽 엘리베이터")
        var base = RoutingGraph(floors:floors, nodes:nodes, nodeGroups:[group])
        do {
            for node in nodes { try base.assignNodeGroup(node.id, to:group.id) }
            check("#120 이웃 ordinal만 자동 연결·5층 건너뜀", base.edges.count == 2 && base.edges.allSatisfy { $0.autoVerticalGroupID == group.id && $0.category == .elevator && $0.accessible })
            let stable = base
            try base.assignNodeGroup(nodes[1].id, to:group.id)
            check("#120 같은 그룹 재배정은 중복/UUID 변경 없음", base == stable)
            try base.assignNodeGroup(nodes[1].id, to:nil)
            check("#120 중간 노드 미배정은 자동 연결만 제거·1–3 연결 금지", base.edges.isEmpty && base.node(nodes[1].id)?.verticalGroupID == nil && base.nodes.count == 4)
            try base.assignNodeGroup(nodes[1].id, to:group.id)
            check("#120 재배정으로 이웃 연결 복원", base.edges.count == 2)
            var moved = base
            let second = RoutingNodeGroup(name:"다른 엘리베이터")
            moved.nodeGroups?.append(second)
            try moved.assignNodeGroup(nodes[2].id,to:second.id)
            try moved.assignNodeGroup(nodes[1].id,to:second.id)
            check("#120 다른 그룹으로 이동하면 옛 자동 연결 해제·새 그룹만 연결", moved.edges.count == 1 && moved.edges[0].autoVerticalGroupID == second.id)
            var invalid = base
            let duplicate = RoutingNode(floorID:floors[0].id, point:LocalPoint(20,20), category:"elevator")
            invalid.nodes.append(duplicate)
            rejects("#120 같은 층에 두 노드 배정 거절") { try invalid.assignNodeGroup(duplicate.id, to:group.id) }
            check("#120 거절한 노드와 기존 연결 불변", invalid.node(duplicate.id)?.verticalGroupID == nil && invalid.edges == base.edges)
            rejects("#120 존재하지 않는 그룹 거절") { try invalid.assignNodeGroup(duplicate.id, to:UUID()) }
            invalid.nodes[invalid.nodes.count-1].category = "stairs"
            rejects("#120 서로 다른 시설 종류 혼합 거절") { try invalid.assignNodeGroup(duplicate.id, to:group.id) }
            invalid.nodes[invalid.nodes.count-1].category = "waypoint"
            let empty = RoutingNodeGroup(name:"빈 시설")
            invalid.nodeGroups?.append(empty)
            rejects("#120 일반 노드의 시설 배정 거절") { try invalid.assignNodeGroup(duplicate.id, to:empty.id) }
            try base.validateNodeGroups()
            check("#120 정상 그룹/자동 연결 검증", true)

            for category in ["stairs","escalator"] {
                var graph = RoutingGraph(floors:floors, nodes:nodes.map { var n = $0; n.category = category; return n }, nodeGroups:[group])
                for node in nodes { try graph.assignNodeGroup(node.id, to:group.id) }
                check("#120 \(category) 그룹 배정과 연결 정책", graph.nodes.allSatisfy { $0.verticalGroupID == group.id }
                      && (category == "stairs" ? graph.edges.count == 2 && graph.edges.allSatisfy { !$0.accessible && $0.category == .stairs } : graph.edges.isEmpty))
            }
            var manual = RoutingGraph(floors:floors, nodes:nodes, nodeGroups:[group])
            let manualID = manual.connect(nodes[0].id,nodes[1].id)!
            for node in nodes { try manual.assignNodeGroup(node.id, to:group.id) }
            check("#120 기존 수동 연결을 자동 소유로 바꾸지 않음", manual.edge(manualID)?.autoVerticalGroupID == nil && manual.edges.count == 2)
            manual.removeNodeGroup(group.id)
            check("#120 그룹 삭제는 수동 연결/노드 유지", manual.nodes.count == nodes.count && manual.edges.map(\.id) == [manualID] && manual.nodes.allSatisfy { $0.verticalGroupID == nil })
            var legacy = RoutingGraph(floors:floors, nodes:base.nodes, edges:[RoutingEdge(from:nodes[0].id,to:nodes[1].id,category:.elevator)])
            let originalEdges = legacy.edges
            legacy.migrateNodeGroups()
            check("#120 이전 그룹 UUID 보존·이름만 이전", legacy.nodeGroup(group.id) != nil && legacy.nodes == base.nodes && legacy.edges == originalEdges)
            let migrated = legacy
            legacy.migrateNodeGroups()
            check("#120 그룹 이전은 반복해도 불변", legacy == migrated)
            let legacyEnv = AppEnvironment()
            var oldStairs = legacy
            oldStairs.edges = []
            for i in oldStairs.nodes.indices { oldStairs.nodes[i].category = "stairs" }
            legacyEnv.routing = oldStairs
            legacyEnv.updateRoutingFloor(floors[1].id,field:"ordinal") { $0.ordinal = 4 }
            check("#120 층 번호 편집만으로 이전 계단 그룹의 연결을 만들지 않음", legacyEnv.routing.edges.isEmpty)

            var boundary = base
            boundary.edges = []
            boundary.floors[0].ordinal = Int.max
            boundary.floors[1].ordinal = Int.max
            _ = boundary.reconcileNodeGroup(group.id)
            check("#120 중복 ordinal/Int.max에서 연결·오버플로 없음", boundary.edges.isEmpty)
            boundary.floors[0].ordinal = Int.min
            boundary.floors[1].ordinal = Int.min + 1
            _ = boundary.reconcileNodeGroup(group.id)
            check("#120 Int.min 인접 ordinal 처리", boundary.edges.count == 1)
            var broken = base
            broken.nodeGroups?.append(group)
            rejects("#120 그룹 UUID 중복 차단") { try broken.validateNodeGroups() }
            broken = base; broken.nodeGroups = []
            rejects("#120 사라진 그룹 참조 차단") { try broken.validateNodeGroups() }
            broken = base; broken.edges[0].autoVerticalGroupID = UUID()
            rejects("#120 자동 연결의 없는 그룹 참조 차단") { try broken.validateNodeGroups() }

            let env = AppEnvironment()
            env.routing = RoutingGraph(floors:floors, nodes:nodes)
            let before = env.routing
            check("#120 빈 이름 생성 거절", env.addRoutingNodeGroup(name:" \n ") == nil)
            let id = env.addRoutingNodeGroup(name:" 시설 A ", assigning:nodes[0].id)!
            check("#120 그룹 생성·첫 노드 배정 한 동작", env.routing.nodeGroup(id)?.name == "시설 A" && env.routing.node(nodes[0].id)?.verticalGroupID == id)
            env.undo()
            check("#120 생성·배정 Undo 전체 복원", env.routing == before)
            env.redo()
            check("#120 생성·배정 Redo UUID 유지", env.routing.nodeGroup(id) != nil && env.routing.node(nodes[0].id)?.verticalGroupID == id)
            env.assignRoutingNodeGroup(nodes[1].id,to:id)
            let assigned = env.routing
            env.assignRoutingNodeGroup(nodes[1].id,to:nil)
            check("#120 미배정은 자동 연결 해제", env.routing.edges.isEmpty)
            env.undo()
            check("#120 미배정 Undo 연결 UUID/소유 복원", env.routing == assigned)
            env.renameRoutingNodeGroup(id,name:"시설 B")
            check("#120 이름 변경은 그룹 UUID/배정 유지", env.routing.nodeGroup(id)?.name == "시설 B" && env.routing.node(nodes[0].id)?.verticalGroupID == id)
            env.undo()
            check("#120 이름 편집 Undo", env.routing.nodeGroup(id)?.name == "시설 A")
            let snapshot = env.routing
            env.updateRoutingFloor(floors[1].id,field:"ordinal") { $0.ordinal = 8 }
            check("#120 층 번호 변경은 인접하지 않은 자동 연결 정리", env.routing.edges.isEmpty)
            env.undo()
            check("#120 층 번호 변경 Undo는 연결 UUID까지 복원", env.routing == snapshot)
            env.updateRoutingNode(nodes[1].id,field:"category") { $0.category = "stairs" }
            check("#120 종류 변경은 배정/자동 연결 해제", env.routing.node(nodes[1].id)?.verticalGroupID == nil && env.routing.edges.isEmpty)
            env.undo()
            check("#120 종류 변경 Undo 그룹과 연결 복원", env.routing == snapshot)
            let edgeID = env.routing.edges[0].id
            env.updateRoutingEdge(edgeID) { $0.accessible = false }
            env.assignRoutingNodeGroup(nodes[1].id,to:nil)
            check("#120 사용자가 수정한 연결은 수동으로 유지", env.routing.edge(edgeID)?.autoVerticalGroupID == nil && env.routing.edges.count == 1)
            env.undo(); env.undo()
            env.removeRoutingNodeGroup(id)
            check("#120 그룹 삭제·노드는 보존", env.routing.nodeGroups == nil && env.routing.edges.isEmpty && env.routing.nodes.count == 4)
            env.undo()
            check("#120 그룹 삭제 Undo 복구", env.routing == snapshot)
            guard let file = env.makeProjectFile() else { throw CocoaError(.fileWriteUnknown) }
            let bytes = try file.encoded()
            let reopened = AppEnvironment()
            try reopened.adopt(ProjectFile.decoded(from:bytes), from:nil)
            check("#120 v10 저장·재열기 그룹 이름/배정/자동 연결 보존", file.version == 10 && reopened.routing == env.routing)
            let exported = try RoutingExporter.collection(env.routing)
            let definitions = exported["node_groups"] as? [[String:Any]]
            check("#120 그래프 출력에 그룹 UUID/이름 포함", definitions?.contains { $0["id"] as? String == id.uuidString.lowercased() && $0["name"] as? String == "시설 A" } == true)
            let features = exported["features"] as! [[String:Any]]
            check("#120 노드 출력에 그룹 이름·기존 group ID 유지", features.filter { ($0["properties"] as? [String:Any])?["vertical_group_name"] as? String == "시설 A" }.count == 2)
            let navigation = try NavigationDataset.build(project:env.projectContents)
            let manifest = try ProjectJSON.parse(navigation.files[NavigationDataset.manifestFile]!)
            check("#120 길안내 전용 묶음에도 그룹 정의 보존", manifest["node_groups"]?.array.count == 1)
            let source = env.projectContents
            var target = BuildingProject(levels:[ProjectLevel(info:floor(8))], nodeGroups:[RoutingNodeGroup(id:id,name:"다른 시설")])
            let incoming = try RoutingNodeGroupImport.prepare(source.levels[0],source:source,target:target)
            let changedID = incoming.level.nodes[0].verticalGroupID
            check("#120 층 가져오기 이름 충돌은 그룹 UUID 재발급", changedID != id && incoming.groups?.first { $0.id == id }?.name == "다른 시설")
            let same = try RoutingNodeGroupImport.prepare(source.levels[0],source:source,target:source)
            check("#120 같은 그룹/이름은 가져오기에서 재사용", same.groups == source.nodeGroups && same.level == source.levels[0])
            target.nodeGroups = nil
            let importEnv = AppEnvironment()
            importEnv.buildingProject = target
            check("#120 실제 층 가져오기 그룹 함께 저장", importEnv.importLevel(source.levels[0],into:target.levels[0].id,metadata:source)
                  && importEnv.buildingProject.nodeGroups == source.nodeGroups)
            var old = file
            old.version = 9; old.buildingProject?.nodeGroups = nil
            old.buildingProject?.crossLevelEdges = []
            let migratedProject = try ProjectFile.decoded(from:old.encoded()).commonProject()
            check("#120 v9 파일의 그룹 ID를 이름 있는 그룹으로 이전", migratedProject.nodeGroups?.map(\.id) == [id])
            check("#120 그룹 편집은 원본 IMDF/도면 불변", source.imdfFiles() == beforeProject(before).imdfFiles()
                  && zip(source.levels,before.floors).allSatisfy { $0.info.svg == $1.svg && $0.info.anchors == $1.anchors })
        } catch { check("#120 노드 그룹 검사 실행", false); print(error) }
    }

    private static func beforeProject(_ graph:RoutingGraph) -> BuildingProject {
        var project = BuildingProject(); project.applyRouting(graph); return project
    }
}
