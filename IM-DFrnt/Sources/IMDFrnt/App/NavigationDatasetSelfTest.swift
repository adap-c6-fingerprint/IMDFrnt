import Foundation

@MainActor
enum NavigationDatasetSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); check(name, false) } catch { check(name, true) }
        }
        var ground = ProjectLevel(info: RoutingFloor(name: "1층", ordinal: 0, svg: "invalid SVG is not parsed"))
        ground.info.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "a")
        ground.info.anchors.add(local: LocalPoint(1_000, 0), geo: GeoPoint(longitude: 129.001, latitude: 36), label: "b")
        ground.info.anchors.add(local: LocalPoint(0, 700), geo: GeoPoint(longitude: 129, latitude: 35.999), label: "c")
        var upper = ProjectLevel(info: RoutingFloor(name: "2층", ordinal: 1))
        upper.info.anchors = ground.info.anchors
        // No polygons or required IMDF properties: navigation references need only live identities.
        let unit = FeatureGroup(featureType: .unit, serialNumber: "unit-001", memberIDs: [])
        let fixture = FeatureGroup(featureType: .fixture, serialNumber: "fixture-001", memberIDs: [])
        ground.editing.features.insert(unit); ground.editing.features.insert(fixture)
        let legacy = UUID()
        ground.editing.ids.adopt(fixture.id, id: legacy)
        let u = RoutingFeatureReference(kind: .unit, featureID: unit.id, source: .authored)
        let f = RoutingFeatureReference(kind: .fixture, featureID: fixture.id, source: .authored)
        let a = RoutingNode(floorID: ground.id, point: LocalPoint(100, 100), name: "계단", category: "stairs",
                            metadataJSON: "{\"description\":\"entry\"}", verticalGroupID: UUID(), featureLinks: [u, f])
        let b = RoutingNode(floorID: ground.id, point: LocalPoint(200, 100))
        let c = RoutingNode(floorID: upper.id, point: LocalPoint(100, 100), category: "stairs", verticalGroupID: a.verticalGroupID)
        let group = RoutingEdgeGroup(name: "직진 구간"), empty = RoutingEdgeGroup(name: "미사용 그룹")
        ground.nodes = [a, b]; upper.nodes = [c]
        ground.edges = [RoutingEdge(from: a.id, to: b.id, groupID: group.id)]
        let cross = RoutingEdge(from: a.id, to: c.id, accessible: false, category: .stairs, groupID: group.id)
        let project = BuildingProject(levels: [ground, upper], crossLevelEdges: [cross], edgeGroups: [group, empty])
        do {
            let output = try NavigationDataset.build(project: project)
            let graphData = try RoutingExporter.encoded(project.routingGraph)
            check("#99 출력은 길안내 JSON3개뿐이며 IMDF/도형 없음", Set(output.files.keys) == ["navigation.json", "routing-graph.geojson", "navigation-feature-links.json"])
            check("#99 모든 층·층간 엣지·기존 그래프 형식 유지", output.nodeCount == 3 && output.edgeCount == 2 && output.files[ClientDataset.routingFile] == graphData)
            let manifest = try ProjectJSON.parse(output.files[NavigationDataset.manifestFile]!)
            let mapping = try ProjectJSON.parse(output.files[NavigationFeatureLinks.fileName]!)
            let records = mapping["features"]!.array
            check("#99 관계 DB는 장소당 노드1개/노드당 여러 장소", records.count == 2 && Set(records.compactMap { $0["node_id"]?.uuid }) == [a.id] && mapping["nodes"]?.array.first?["features"]?.array.count == 2)
            check("#99 신규/기존 IMDF UUID 재사용", Set(records.compactMap { $0["feature_id"]?.uuid }) == [unit.id, legacy] && output.ids[ground.id]?.peek(unit.id) == unit.id)
            check("#99 층 정보·사용/미사용 그룹 보존", manifest["kind"]?.string == "navigation-only" && manifest["levels"]?.array.count == 2 && Set(manifest["edge_groups"]!.array.compactMap { $0["id"]?.uuid }) == [group.id, empty.id])
            check("#99 최종 바이트 해시", manifest["routing_sha256"]?.string == ClientDataset.sha256(output.files[ClientDataset.routingFile]!) && manifest["feature_links_sha256"]?.string == ClientDataset.sha256(output.files[NavigationFeatureLinks.fileName]!))
            var file = ProjectFile.empty(); file.buildingProject = project
            rejects("#99 동일 불완전 IMDF는 기존 지도 묶음에서 차단 유지") {
                _ = try ClientDataset.build(projectData: file.encoded(), datasetID: "nav-test", documents: [:])
            }
            var persisted = project
            for i in persisted.levels.indices { persisted.levels[i].editing.ids = output.ids[persisted.levels[i].id]! }
            file.buildingProject = persisted
            let reopened = try ProjectFile.decoded(from: file.encoded()).commonProject()
            let again = try NavigationDataset.build(project: reopened)
            check("#99 저장 v9·재열기/반복 출력 UUID·바이트 유지", file.version == 9 && again.files == output.files)
            check("#99 도형·그래프·기존 대장은 원본에서 불변", project.levels[0].editing.ids.peek(unit.id) == nil && project.routingGraph == persisted.routingGraph && project.imdfFiles() == persisted.imdfFiles())
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntNavOnly-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let target = folder.appendingPathComponent("navigation")
            try ClientDataset.write(output.files, to: target, replacing: false)
            check("#99 실제 폴더 파일·바이트 유지", try output.files.allSatisfy { try Data(contentsOf: target.appendingPathComponent($0.key)) == $0.value })
            rejects("#99 기존 결과를 확인 없이 덮어쓰지 않음") { try ClientDataset.write(output.files, to: target, replacing: false) }
            var changed = project; changed.levels[0].nodes[1].featureLinks = [u]
            rejects("#99 중복 장소 배정 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = project; changed.levels[0].editing.features.remove(unit.id)
            rejects("#99 없는 장소 연결 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = project; changed.levels[0].nodes[0].featureLinks = nil
            let noLinks = try NavigationDataset.build(project: changed)
            check("#99 연결 없어도 빈 DB 제공", try ProjectJSON.parse(noLinks.files[NavigationFeatureLinks.fileName]!)["features"]?.array.isEmpty == true)
            changed = project
            changed.levels[0].editing.features.remove(unit.id)
            changed.levels[0].geoJSON["unit.geojson"] = [.object(["id": .string(unit.id.uuidString), "geometry": .null,
                "properties": .object(["level_id": .string(ground.id.uuidString)])])]
            changed.levels[0].nodes[0].featureLinks = [RoutingFeatureReference(kind: .unit, featureID: unit.id, source: .imported), f]
            let imported = try NavigationDataset.build(project: changed)
            check("#99 가져온 장소는 도형 변환 없이 원본 UUID 유지", try ProjectJSON.parse(imported.files[NavigationFeatureLinks.fileName]!)["features"]!.array.contains { $0["feature_id"]?.uuid == unit.id })
            changed = project
            changed.levels[0].editing.ids.adopt(unit.id, id: unit.id); changed.levels[0].editing.ids.retire(unit.id)
            let retired = try NavigationDataset.build(project: changed)
            check("#99 폐기 UUID를 다시 쓰지 않고 대장 반환", retired.ids[ground.id]?.peek(unit.id) != unit.id && retired.ids[ground.id]?.retired.contains(unit.id) == true)
            changed = project; changed.levels[0].info.anchors = AnchorStore()
            rejects("#99 실제 좌표 없는 그래프 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = project; changed.levels[0].edges[0].groupID = UUID()
            rejects("#99 없는 그룹 참조 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = project; changed.levels[0].nodes[1].floorID = upper.id
            rejects("#99 저장된 노드와 소속 층 불일치 차단") { _ = try NavigationDataset.build(project: changed) }
        } catch { check("#99 길안내 전용 내보내기", false); print(error) }
    }
}
