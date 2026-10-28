import Foundation

@MainActor
enum RoutingFeatureLinksSelfTest {
    static func run(check: (String, Bool) -> Void) async {
        func rejects(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); check(name, false) } catch { check(name, true) }
        }
        let env = AppEnvironment()
        env.openSample(); env.enterRoutingScreen()
        let floor = env.routingFloorID!, fingerprint = env.document!.fingerprint
        func feature(_ type: IMDFFeatureType, _ serial: String) -> FeatureGroup {
            var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
            f.polygonRings = [[LocalPoint(10, 10), LocalPoint(100, 10), LocalPoint(100, 100), LocalPoint(10, 100)]]
            return f
        }
        var unit = feature(.unit, "unit-001"), fixture = feature(.fixture, "fixture-001")
        unit.polygonRings.append([LocalPoint(40, 40), LocalPoint(60, 40), LocalPoint(60, 60), LocalPoint(40, 60)])
        fixture.polygonRings = [[LocalPoint(10, 10), LocalPoint(30, 10), LocalPoint(30, 30), LocalPoint(10, 30)]]
        env.features.insert(unit); env.features.insert(fixture)
        env.handleRoutingClick(at: LocalPoint(200, 100), tolerance: 5, modifiers: .command)
        let a = env.routingSelectedNodeID!
        env.handleRoutingClick(at: LocalPoint(300, 100), tolerance: 5, modifiers: .command)
        let b = env.routingSelectedNodeID!
        let u = RoutingFeatureReference(kind: .unit, featureID: unit.id, source: .authored)
        let f = RoutingFeatureReference(kind: .fixture, featureID: fixture.id, source: .authored)
        let imdfBefore = env.projectContents.imdfFiles(), nodePoints = env.routing.nodes.map(\.point)
        env.setRoutingTool(.featureLinks)
        env.handleRoutingClick(at: LocalPoint(200, 100), tolerance: 5)
        env.handleRoutingClick(at: LocalPoint(20, 20), tolerance: 5)
        check("#95 겹친 Unit/Fixture는 자동 추정하지 않고 선택 대기", env.routingFeatureCandidates.count == 2 && env.routing.node(a)?.featureLinks == nil)
        env.chooseRoutingFeature(u); env.chooseRoutingFeature(f)
        check("#95 노드 하나에 여러 장소 연결", Set(env.routing.node(a)?.featureLinks ?? []) == [u, f])
        check("#95 장소에서 노드 역조회", RoutingFeatureLinks.owner(of: u, on: floor, in: env.projectContents)?.id == a)
        let undo = env.undoStack.undoName
        env.linkRoutingFeature(u, to: a)
        check("#95 같은 연결 중복·불필요 Undo 방지", env.routing.node(a)?.featureLinks?.count == 2 && env.undoStack.undoName == undo)
        env.linkRoutingFeature(u, to: b)
        check("#95 교체 확인 전 기존 연결 유지", env.routingFeatureReplacement?.previousNodeID == a && env.routing.node(b)?.featureLinks == nil)
        env.routingFeatureReplacement = nil
        check("#95 교체 취소는 데이터 유지", env.routing.node(a)?.featureLinks?.contains(u) == true)
        env.linkRoutingFeature(u, to: b); env.confirmRoutingFeatureReplacement()
        check("#95 교체 후 장소당 노드 하나", env.routing.node(a)?.featureLinks == [f] && env.routing.node(b)?.featureLinks == [u])
        env.undo()
        check("#95 교체 한 번 Undo로 이전 노드 복원", Set(env.routing.node(a)?.featureLinks ?? []) == [u, f] && env.routing.node(b)?.featureLinks == nil)
        env.redo()
        env.linkRoutingFeature(u, to: a)
        let stale = env.routingFeatureReplacement!
        env.unlinkRoutingFeature(u, from: b)
        env.confirmRoutingFeatureReplacement(stale)
        check("#95 확인 중 연결이 바뀌면 오래된 교체 요청 취소", RoutingFeatureLinks.owner(of: u, on: floor, in: env.projectContents) == nil)
        env.undo()
        env.linkRoutingFeature(u, to: a)
        let oldContext = env.routingFeatureReplacement!
        do { try env.loadLevelEditor(floor) } catch { check("#95 도면 재열기 검사 준비", false) }
        env.confirmRoutingFeatureReplacement(oldContext)
        check("#95 같은 프로젝트/층을 재열어도 이전 확인 요청 취소", RoutingFeatureLinks.owner(of: u, on: floor, in: env.projectContents)?.id == b)
        env.unlinkRoutingFeature(u, from: b)
        check("#95 해제는 장소·노드 유지", env.routing.node(b)?.featureLinks == nil && env.routing.nodes.map(\.point) == nodePoints && env.features.feature(unit.id) != nil)
        env.undo()
        check("#95 연결 해제 Undo", env.routing.node(b)?.featureLinks == [u])
        env.deleteRoutingNode(b)
        check("#95 노드 삭제는 그 노드의 연결만 제거", RoutingFeatureLinks.owner(of: u, on: floor, in: env.projectContents) == nil && env.routing.node(a)?.featureLinks == [f])
        env.undo()
        let drawing = env.routingMapDrawingCache.value(env: env, document: env.document!)!
        check("#95 구멍 안쪽은 장소로 선택하지 않음", drawing.features(at: LocalPoint(50, 50), settings: env.currentRoutingMapLayerSettings).isEmpty)
        env.setRoutingMapOpacity(0, for: .fixture)
        check("#95 0% 레이어는 클릭 대상 제외", drawing.features(at: LocalPoint(20, 20), settings: env.currentRoutingMapLayerSettings) == [u])
        check("#95 연결은 IMDF·노드 좌표·맞춤 트리거 불변", env.projectContents.imdfFiles() == imdfBefore && env.document?.fingerprint == fingerprint && env.routingFloorID == floor && env.routing.nodes.map(\.point) == nodePoints)
        do {
            let file = env.makeProjectFile()!, data = try file.encoded(), reopened = AppEnvironment()
            try reopened.adopt(ProjectFile.decoded(from: data), from: nil)
            check("#95 v9 저장·재열기로 연결 보존", file.version == 9 && reopened.routing == env.routing)
            var legacy = try ProjectJSON.parse(data); legacy["version"] = .number(8)
            var project = legacy["buildingProject"]!
            var levels = project["levels"]!.array
            for i in levels.indices {
                var nodes = levels[i]["nodes"]!.array
                for j in nodes.indices { nodes[j]["featureLinks"] = nil }
                levels[i]["nodes"] = .array(nodes)
            }
            project["levels"] = .array(levels); legacy["buildingProject"] = project
            check("#95 기존 v8 파일 읽기 유지", try ProjectFile.decoded(from: legacy.data()).commonProject().routingGraph.nodes.allSatisfy { $0.featureLinks == nil })
            var invalid = env.projectContents
            invalid.levels[0].nodes[0].featureLinks = [u]
            invalid.levels[0].nodes[1].featureLinks = [u]
            rejects("#95 손상 파일의 중복 노드 배정 거절") { try invalid.validate() }
            let source = env.projectContents.levels[0], target = UUID()
            let remapped = try LevelImportIdentity.prepare(source, targetID: target, project: env.projectContents, metadata: nil).level
            let unitLink = remapped.nodes.flatMap { $0.featureLinks ?? [] }.first { $0.kind == .unit }!
            check("#95 층 복사 UUID 충돌 시 연결 참조도 재발급", unitLink.featureID != u.featureID && remapped.editing.features.feature(unitLink.featureID) != nil)
            let destination = env.addProjectLevel()
            check("#95 층 가져오기 성공", env.importLevel(source, into: destination, metadata: env.projectContents))
            await env.waitForLevelDrawing()
            let copied = env.projectContents.levels.first { $0.id == destination }!
            check("#95 노드 충돌 재발급 후에도 장소 연결 보존", !Set(copied.nodes.map(\.id)).contains(a) && copied.nodes.flatMap { $0.featureLinks ?? [] }.count == 2)
            env.removeProjectLevel(destination)
            check("#95 층 삭제로 복사된 연결만 삭제", env.projectContents.levels.flatMap(\.nodes).flatMap { $0.featureLinks ?? [] }.count == 2)
            await env.waitForLevelDrawing()
            let renamed = UUID()
            env.assignRoutingLevelID(floor, newID: renamed)
            await env.waitForLevelDrawing()
            check("#95 층 ID 변경 후 연결 유지", env.routing.node(a)?.floorID == renamed && RoutingFeatureLinks.owner(of: u, on: renamed, in: env.projectContents)?.id == b)
        } catch { check("#95 저장·가져오기 검사", false); print(error) }
        env.resetProjectState()
        check("#95 프로젝트 전환 시 미확정 연결·선택 제거", env.routingFeatureReplacement == nil && env.routingSelectedFeature == nil && env.routingFeatureCandidates.isEmpty)
        await exports(check: check)
    }

    private static func exports(check: (String, Bool) -> Void) async {
        do {
            let input = try IMDFImporter.decode(files: IMDFTestFixtures.files(IMDFTestFixtures.validProject()), sourceName: "link-test")
            let env = AppEnvironment(); try env.adoptIMDF(input)
            let floor = env.routingFloorID!
            let rawID = env.activeLevel!.geoJSON["unit.geojson"]![0]["id"]!.uuid!
            let rawRef = RoutingFeatureReference(kind: .unit, featureID: rawID, source: .imported)
            env.handleRoutingClick(at: LocalPoint(200, 200), tolerance: 5, modifiers: .command)
            let node = env.routingSelectedNodeID!
            var fixture = FeatureGroup(featureType: .fixture, serialNumber: "fixture-test", memberIDs: [])
            fixture.polygonRings = [[LocalPoint(30, 30), LocalPoint(60, 30), LocalPoint(60, 60), LocalPoint(30, 60)]]
            fixture.properties["category"] = .string("furniture")
            env.features.insert(fixture)
            let ref = RoutingFeatureReference(kind: .fixture, featureID: fixture.id, source: .authored)
            let beforeData = try env.makeProjectFile()!.encoded()
            let baseline = try ClientDataset.build(projectData: beforeData, datasetID: "link-test", documents: [:], now: Date(timeIntervalSince1970: 0))
            env.ids = baseline.ids[floor]!
            env.storeActiveLevel()
            let routingBefore = try RoutingExporter.encoded(env.routing)
            env.linkRoutingFeature(rawRef, to: node); env.linkRoutingFeature(ref, to: node)
            let project = env.projectContents
            let output = try ClientDataset.build(projectData: env.makeProjectFile()!.encoded(), datasetID: "link-test", documents: [:], now: Date(timeIntervalSince1970: 0))
            let sidecar = try ProjectJSON.parse(output.files[NavigationFeatureLinks.fileName]!)
            check("#95 묶음에 양방향 장소/노드 인덱스", sidecar["features"]!.array.count == 2 && sidecar["nodes"]!.array.count == 1 && sidecar["nodes"]!.array[0]["features"]!.array.count == 2)
            check("#95 IMDF·그래프 단독·묶음 그래프 출력 불변", try RoutingExporter.encoded(env.routing) == routingBefore && baseline.files.allSatisfy { path, data in path == "dataset.json" || output.files[path] == data })
            let exportedFixtureID = output.ids[floor]!.peek(fixture.id)!
            check("#95 내부 ID가 아닌 실제 출력 UUID 연결", sidecar["features"]!.array.contains { $0["feature_id"]?.uuid == exportedFixtureID && $0["feature_type"]?.string == "fixture" } && sidecar["features"]!.array.contains { $0["feature_id"]?.uuid == rawID })
            let metadata = try ProjectJSON.parse(output.files["dataset.json"]!)
            check("#95 매핑 최종 바이트 SHA-256", metadata["feature_links_file"]?.string == NavigationFeatureLinks.fileName && metadata["feature_links_sha256"]?.string == ClientDataset.sha256(output.files[NavigationFeatureLinks.fileName]!))
            check("#95 최종 매핑·IMDF·노드·프로젝트 검증", ClientDataset.verify(files: output.files, project: project, ids: output.ids).blockers.isEmpty)
            var broken = output.files, bad = sidecar
            bad["nodes"] = .array([]); broken[NavigationFeatureLinks.fileName] = try bad.data()
            check("#95 양방향 목록 불일치 차단", !NavigationFeatureLinks.problems(files: broken, project: project, ids: output.ids).isEmpty)
            bad = sidecar; var records = bad["features"]!.array
            records.append(records[0]); bad["features"] = .array(records); broken[NavigationFeatureLinks.fileName] = try bad.data()
            check("#95 출력 장소 중복 배정 차단", !NavigationFeatureLinks.problems(files: broken, project: project, ids: output.ids).isEmpty)
            broken.removeValue(forKey: NavigationFeatureLinks.fileName)
            check("#95 매핑 파일 누락 차단", !NavigationFeatureLinks.problems(files: broken, project: project, ids: output.ids).isEmpty)
            // 양쪽 인덱스를 함께 고쳐도 프로젝트와 다른 유효 노드로 바꾸면 거절한다.
            var alternative = project
            let otherNode = RoutingNode(floorID: floor, point: LocalPoint(250, 250))
            alternative.levels[0].nodes.append(otherNode)
            broken = output.files
            var graphFile = try ProjectJSON.parse(broken[ClientDataset.routingFile]!)
            var graphFeatures = graphFile["features"]!.array
            var newNode = graphFeatures.first { $0["id"]?.uuid == node }!
            newNode["id"] = .string(otherNode.id.uuidString.lowercased()); graphFeatures.append(newNode)
            graphFile["features"] = .array(graphFeatures); broken[ClientDataset.routingFile] = try graphFile.data()
            bad = sidecar; var forward = bad["features"]!.array
            for i in forward.indices { forward[i]["node_id"] = .string(otherNode.id.uuidString.lowercased()) }
            var reverse = bad["nodes"]!.array
            reverse[0]["node_id"] = .string(otherNode.id.uuidString.lowercased())
            bad["features"] = .array(forward); bad["nodes"] = .array(reverse)
            broken[NavigationFeatureLinks.fileName] = try bad.data()
            check("#95 양방향이 일치해도 프로젝트와 다른 노드 배정 차단", !NavigationFeatureLinks.problems(files: broken, project: alternative, ids: output.ids).isEmpty)
            env.features.update(fixture.id) { $0.isInTrash = true }
            do {
                _ = try ClientDataset.build(projectData: env.makeProjectFile()!.encoded(), datasetID: "link-test", documents: [:])
                check("#95 휴지통 연결은 묶음 내보내기 안내", false)
            } catch { check("#95 휴지통 연결은 묶음 내보내기 안내", true) }
            check("#95 휴지통 연결이어도 일반 IMDF 내보내기 유지", (try? IMDFArchive.build(projectData: env.makeProjectFile()!.encoded(), documents: [:])) != nil)
            let alias = FeatureGroup(id: rawID, featureType: .unit, serialNumber: "alias", memberIDs: [])
            var level = project.levels[0]; level.editing.features.insert(alias)
            let nativeAlias = RoutingFeatureReference(kind: .unit, featureID: rawID, source: .authored)
            check("#95 원본/편집본은 같은 장소 정체성", rawRef.identity(in: level) == nativeAlias.identity(in: level))
            let sharedID = UUID()
            var shared = project
            shared.globalGeoJSON["fixture.geojson"] = [IMDFTestFixtures.feature("fixture", id: sharedID,
                properties: ["level_ids": .array([.string(floor.uuidString.lowercased()), .string(UUID().uuidString.lowercased())])], geometry: IMDFTestFixtures.polygon())]
            var source = project.levels[0]
            let sharedRef = RoutingFeatureReference(kind: .fixture, featureID: sharedID, source: .imported)
            source.nodes[0].featureLinks = [sharedRef]
            let prepared = RoutingFeatureLinks.preparingImport(source, metadata: shared)
            check("#95 연결된 공통 Fixture는 층 복사에 포함", prepared.geoJSON["fixture.geojson"]?.first?["id"]?.uuid == sharedID && prepared.geoJSON["fixture.geojson"]?.first?["properties"]?["level_ids"]?.array.count == 1)
            let otherFloor = ProjectLevelInfo(name: "다른 층", ordinal: 1)
            shared.levels[0] = source
            var extra = ProjectLevel(info: otherFloor)
            extra.nodes = [RoutingNode(floorID: extra.id, point: LocalPoint(10, 10), featureLinks: [sharedRef])]
            shared.levels.append(extra)
            do { try RoutingFeatureLinks.validateUnique(in: shared); check("#95 공통 Fixture도 층마다 중복 배정 금지", false) }
            catch { check("#95 공통 Fixture도 층마다 중복 배정 금지", true) }
        } catch { check("#95 클라이언트 묶음 검사", false); print(error) }
    }
}
