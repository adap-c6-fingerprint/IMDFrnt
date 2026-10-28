import Foundation

@MainActor
enum NavigationDatasetSelfTest {
    static func run(check: (String, Bool) -> Void) async {
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
            let env = AppEnvironment()
            env.buildingProject = project
            let asyncTarget = folder.appendingPathComponent("async-navigation")
            let saving = env.saveNavigationDataset(to: asyncTarget, replacing: false)
            check("#99 비동기 저장 시작 즉시 중복 실행 차단", saving != nil && env.isProjectBusy && env.longTask != nil && env.saveNavigationDataset(to: asyncTarget, replacing: false) == nil)
            await saving?.value
            let asyncBytesMatch = try output.files.allSatisfy { try Data(contentsOf: asyncTarget.appendingPathComponent($0.key)) == $0.value }
            check("#99 비동기 저장 바이트·성공 후 UUID 반영·잠금 해제", asyncBytesMatch && env.buildingProject.levels[0].editing.ids.peek(unit.id) == unit.id && !env.isProjectBusy && env.longTask == nil)
            env.buildingProject = project
            await env.saveNavigationDataset(to: asyncTarget, replacing: false)?.value
            check("#99 비동기 저장 실패 시 UUID 불변·잠금 해제", env.buildingProject == project && !env.isProjectBusy && env.longTask == nil)
            await env.saveNavigationDataset(to: asyncTarget, replacing: true)?.value
            check("#99 확인한 비동기 교체 성공 후 UUID 반영", env.buildingProject.levels[0].editing.ids.peek(unit.id) == unit.id && !env.isProjectBusy && env.longTask == nil)
            env.buildingProject = project
            env.buildingProject.levels[0].info.anchors = AnchorStore()
            let invalidProject = env.buildingProject
            await env.saveNavigationDataset(to: asyncTarget, replacing: true)?.value
            let previousBytesMatch = try output.files.allSatisfy { try Data(contentsOf: asyncTarget.appendingPathComponent($0.key)) == $0.value }
            check("#99 생성 실패 시 기존 파일·UUID 불변·잠금 해제", previousBytesMatch && env.buildingProject == invalidProject && !env.isProjectBusy && env.longTask == nil)
            env.buildingProject = project
            let staleTarget = folder.appendingPathComponent("snapshot-navigation")
            let staleSaving = env.saveNavigationDataset(to: staleTarget, replacing: false)
            env.buildingProject = BuildingProject()
            await staleSaving?.value
            let snapshotBytesMatch = try output.files.allSatisfy { try Data(contentsOf: staleTarget.appendingPathComponent($0.key)) == $0.value }
            check("#99 저장 중 프로젝트 교체 시 스냅샷 출력·오래된 UUID 미반영", snapshotBytesMatch && env.buildingProject == BuildingProject() && !env.isProjectBusy && env.longTask == nil)
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
            changed.levels[0].geoJSON["unit.geojson"]![0]["properties"] = .object(["level_id": .string(upper.id.uuidString)])
            rejects("#99 local imported Unit의 다른 층 참조 차단") { _ = try NavigationDataset.build(project: changed) }
            changed.levels[0].geoJSON["unit.geojson"]![0]["properties"] = .object([:])
            rejects("#99 local imported 장소의 층 참조 누락 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = project
            changed.levels[0].editing.features.remove(fixture.id)
            changed.levels[0].nodes[0].featureLinks = [u, RoutingFeatureReference(kind: .fixture, featureID: legacy, source: .imported)]
            changed.levels[0].geoJSON["fixture.geojson"] = [.object(["id": .string(legacy.uuidString), "geometry": .null,
                "properties": .object(["level_ids": .array([.string(ground.id.uuidString), .string(upper.id.uuidString)])])])]
            let sharedFixture = try NavigationDataset.build(project: changed)
            check("#99 imported Fixture의 현재 층 포함 다중 층 참조 허용", sharedFixture.linkCount == 2)
            changed.levels[0].geoJSON["fixture.geojson"]![0]["properties"] = .object(["level_ids": .array([.string(upper.id.uuidString)])])
            rejects("#99 local imported Fixture의 다른 층 참조 차단") { _ = try NavigationDataset.build(project: changed) }
            changed.levels[0].geoJSON["fixture.geojson"]![0]["properties"] = .object(["unit_id": .string(unit.id.uuidString.lowercased())])
            changed.levels[0].geoJSON["unit.geojson"] = [.object(["id": .string(unit.id.uuidString.uppercased()), "geometry": .null,
                "properties": .object(["level_id": .string(ground.id.uuidString)])])]
            let indirect = try NavigationDataset.build(project: changed)
            let indirectLinks = try ProjectJSON.parse(indirect.files[NavigationFeatureLinks.fileName]!)["features"]!.array
            check("#99 unit_id 간접 층 Fixture·UUID 대소문자·관계 보존", indirect.linkCount == 2 && indirectLinks.contains { $0["feature_id"]?.uuid == legacy && $0["level_id"]?.uuid == ground.id && $0["node_id"]?.uuid == a.id })
            let unitLinked = changed
            let importedInput = ImportedIMDF(sourceName: "unit-linked-fixture", layoutVersion: "layout-1",
                coordinates: IMDFCoordinateSpace(west: 129, north: 36, unitsPerLongitudeDegree: 1_000, unitsPerLatitudeDegree: 1_000, padding: 0),
                floors: [ImportedIMDFFloor(id: ground.id, name: "1층", ordinal: 0, svg: "")], files: [
                    "unit.geojson": .object(["type": .string("FeatureCollection"), "features": .array(changed.levels[0].geoJSON["unit.geojson"]!)]),
                    "fixture.geojson": .object(["type": .string("FeatureCollection"), "features": .array(changed.levels[0].geoJSON["fixture.geojson"]!)])])
            var fromIMDF = try BuildingProject.importing(importedInput)
            fromIMDF.levels[0].nodes = [RoutingNode(floorID: ground.id, point: LocalPoint(100, 100),
                featureLinks: [RoutingFeatureReference(kind: .fixture, featureID: legacy, source: .imported)])]
            let importedOutput = try NavigationDataset.build(project: fromIMDF)
            check("#99 실제 프로젝트 가져오기 후 unit_id Fixture 내보내기", fromIMDF.levels[0].geoJSON["fixture.geojson"]?.count == 1 && importedOutput.linkCount == 1)
            let upperUnit = UUID()
            changed.levels[1].geoJSON["unit.geojson"] = [.object(["id": .string(upperUnit.uuidString),
                "properties": .object(["level_id": .string(upper.id.uuidString)])])]
            changed.levels[0].geoJSON["fixture.geojson"]![0]["properties"] = .object(["unit_ids": .array([.string(unit.id.uuidString), .string(upperUnit.uuidString)])])
            check("#99 unit_ids 간접 다중 층 Fixture 허용", try NavigationDataset.build(project: changed).linkCount == 2)
            var commonInput = importedInput
            let unrelated = UUID()
            commonInput.floors += [ImportedIMDFFloor(id: upper.id, name: "2층", ordinal: 1, svg: ""),
                ImportedIMDFFloor(id: unrelated, name: "3층", ordinal: 2, svg: "")]
            commonInput.files["unit.geojson"]?["features"] = .array(changed.levels[0].geoJSON["unit.geojson"]! + changed.levels[1].geoJSON["unit.geojson"]!)
            var commonFixture = changed.levels[0].geoJSON["fixture.geojson"]![0]
            commonFixture["properties"]?["name"] = .object(["ko": .string("공통 서가")])
            commonInput.files["fixture.geojson"]?["features"] = .array([commonFixture])
            var commonProject = try BuildingProject.importing(commonInput)
            let commonRef = RoutingFeatureReference(kind: .fixture, featureID: legacy, source: .imported)
            commonProject.levels[0].nodes = [RoutingNode(floorID: ground.id, point: LocalPoint(100, 100), featureLinks: [commonRef])]
            check("#99 실제 공통 Fixture 가져오기·참조 층 가용성·이름", commonProject.globalGeoJSON["fixture.geojson"]?.count == 1 && commonProject.levels[0].geoJSON["fixture.geojson"] == nil && commonRef.isAvailable(in: commonProject, levelID: ground.id) && commonRef.isAvailable(in: commonProject, levelID: upper.id) && !commonRef.isAvailable(in: commonProject, levelID: unrelated) && commonRef.label(in: commonProject, levelID: ground.id).contains("공통 서가"))
            let commonOutput = try NavigationDataset.build(project: commonProject)
            let commonLinks = try ProjectJSON.parse(commonOutput.files[NavigationFeatureLinks.fileName]!)["features"]!.array
            check("#99 unit_ids 공통 Fixture의 노드·층·UUID 출력", commonOutput.linkCount == 1 && commonLinks.first?["feature_id"]?.uuid == legacy && commonLinks.first?["level_id"]?.uuid == ground.id)
            var commonFile = ProjectFile.empty(); commonFile.buildingProject = commonProject
            let reopenedCommon = try ProjectFile.decoded(from: commonFile.encoded()).commonProject()
            check("#99 공통 간접 Fixture 재열기·출력 불변", try NavigationDataset.build(project: reopenedCommon).files == commonOutput.files)
            let preparedCommon = RoutingFeatureLinks.preparingImport(commonProject.levels[0], metadata: commonProject)
            check("#99 층 가져오기 준비에도 연결된 공통 Fixture 보존", preparedCommon.geoJSON["fixture.geojson"]?.first?["id"]?.uuid == legacy)
            var invalidCommon = commonProject
            invalidCommon.levels[1].nodes = [RoutingNode(floorID: upper.id, point: LocalPoint(100, 100), featureLinks: [commonRef])]
            rejects("#99 공통 간접 Fixture에도 장소당 노드1개 유지") { _ = try NavigationDataset.build(project: invalidCommon) }
            invalidCommon = commonProject
            invalidCommon.globalGeoJSON["fixture.geojson"]![0]["properties"] = .object(["unit_ids": .array([.string(UUID().uuidString)])])
            rejects("#99 공통 Fixture의 없는 Unit 참조 차단") { _ = try NavigationDataset.build(project: invalidCommon) }
            invalidCommon = commonProject
            invalidCommon.globalGeoJSON["fixture.geojson"]![0]["properties"] = .object(["level_ids": .array([.string(ground.id.uuidString), .string(upper.id.uuidString)])])
            check("#99 기존 직접 층 참조 공통 Fixture 출력 유지", try NavigationDataset.build(project: invalidCommon).linkCount == 1)
            changed.levels[0].geoJSON["fixture.geojson"]![0]["properties"] = .object(["unit_id": .string(upperUnit.uuidString)])
            rejects("#99 다른 층 Unit만 참조하는 Fixture 차단") { _ = try NavigationDataset.build(project: changed) }
            changed = unitLinked
            changed.levels[0].geoJSON["fixture.geojson"]![0]["properties"] = .object(["unit_id": .string(UUID().uuidString)])
            rejects("#99 없는 Unit으로 층을 추정하지 않음") { _ = try NavigationDataset.build(project: changed) }
            changed = unitLinked
            changed.levels[0].geoJSON["unit.geojson"]![0]["properties"] = .object(["level_id": .string(upper.id.uuidString)])
            rejects("#99 Unit 저장 위치 대신 실제 층 참조 사용") { _ = try NavigationDataset.build(project: changed) }
            changed = unitLinked
            changed.globalGeoJSON["unit.geojson"] = changed.levels[0].geoJSON.removeValue(forKey: "unit.geojson")
            check("#99 공통 Unit의 실제 층 참조도 간접 해석", try NavigationDataset.build(project: changed).linkCount == 2)
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
