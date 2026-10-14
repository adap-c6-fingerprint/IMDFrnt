import AppKit
import Foundation

@MainActor
enum BuildingSelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--building-selftest") else { return }
        var total = 0, failures = 0
        func check(_ name: String, _ valid: Bool) {
            total += 1; if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntBuildingTest-\(UUID())")
        let suite = "IMDFrntBuildingTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        func environment() -> AppEnvironment {
            AppEnvironment(recoveryURL: directory.appendingPathComponent("recovery.imdfrnt"), projectDefaults: defaults)
        }
        do {
            let env = environment()
            try env.createNewProject()
            env.createBuilding()
            let initialBuilding = env.globalFeatures("building")
            env.autosaveTick()
            let recovered = environment()
            try recovered.restoreRecovery(from: directory.appendingPathComponent("recovery.imdfrnt"))
            check("Level 없이 작성한 건물 정보도 복구 시 미저장으로 유지", recovered.hasUnsavedChanges && recovered.globalFeatures("building") == initialBuilding)
            env.openSample()
            check("첫 SVG 입력은 기존 건물과 프로젝트 ID 보존", env.globalFeatures("building") == initialBuilding && env.buildingProject.levels.count == 1)
            env.undo()
            check("첫 SVG 입력 Undo는 건물 정보를 유지", env.document == nil && env.buildingProject.levels.isEmpty && env.globalFeatures("building") == initialBuilding)
            let first = env.addProjectLevel()
            env.createBuilding()
            try env.setRoutingDrawing(first, data: Data(SampleFloorplan.svg.utf8), name: "first.svg")
            env.selectPropertyType(.opening)
            env.selection.selected = [env.document!.objects.first!.id]
            env.createFeature()
            let feature = env.features.features.first!
            env.anchors.add(local: LocalPoint(1, 1), geo: GeoPoint(longitude: 129, latitude: 36), label: "first")
            env.enterRoutingScreen()
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 1, modifiers: .command)
            let firstNode = env.routingSelectedNodeID!
            env.updateRoutingNode(firstNode, field: "category") { $0.category = "stairs" }
            env.updateRoutingNode(firstNode, field: "metadata") { $0.metadataJSON = "{\"test\":1}" }
            let firstSVG = env.loadedSVG
            let second = env.addProjectLevel()
            check("새 공통 층은 다른 층 도형·태깅·Anchor를 상속하지 않음", env.document == nil && env.features.features.isEmpty && env.anchors.pairs.isEmpty)
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"300\"><rect x=\"20\" y=\"20\" width=\"200\" height=\"200\"/></svg>"
            try env.setRoutingDrawing(second, data: Data(svg.utf8), name: "second.svg")
            env.updateProjectLevel(second, field: "name") { $0.name = "테스트 2층"; $0.shortName = "2F" }
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 1, modifiers: .command)
            let secondNode = env.routingSelectedNodeID!
            env.updateRoutingNode(secondNode, field: "category") { $0.category = "stairs" }
            _ = env.routing.connect(firstNode, secondNode)
            check("층간 연결은 공통 저장, 노드는 각 층에 저장", env.buildingProject.crossLevelEdges.count == 1 && env.buildingProject.levels.allSatisfy { $0.nodes.count == 1 && $0.edges.isEmpty })
            env.selectProjectLevel(first)
            check("층 전환으로 SVG·태깅·Anchor 복원", env.loadedSVG == firstSVG && env.features.feature(feature.id) != nil && env.anchors.pairs.first?.label == "first")
            env.showRoutingScreen = false
            check("도면과 노드 화면이 동일한 Level·문서를 사용", env.activeLevel?.id == first && env.currentRoutingFloor?.id == first && env.document?.fingerprint == env.routingDocument?.fingerprint)
            let changed = UUID()
            env.renameProjectLevelID(second, to: changed)
            check("공통 Level ID 변경은 노드 소속과 층간 연결 보존", env.routing.node(secondNode)?.floorID == changed && env.routing.edges.count == 1)
            let beforeDuplicate = env.projectContents
            env.renameProjectLevelID(first, to: changed)
            check("중복 LevelID 차단", env.projectContents == beforeDuplicate)
            env.updateProjectLevel(changed) { $0.ordinal = 0 }
            check("중복 ordinal 차단", env.projectContents == beforeDuplicate)
            let polygon = "{\"type\":\"Polygon\",\"coordinates\":[[[129,36],[129.001,36],[129.001,36.001],[129,36]]] }"
            let footprint = try env.saveFootprint(id: nil, geometryText: polygon, category: "ground")
            let footprintBefore = env.globalFeatures("footprint")[0]
            let edited = polygon.replacingOccurrences(of: "129.001", with: "129.002")
            _ = try env.saveFootprint(id: footprint, geometryText: edited, category: "ground")
            check("Footprint 수정은 실제 geometry 변경, Feature ID·건물 참조 보존", env.globalFeatures("footprint")[0]["geometry"] != footprintBefore["geometry"] && env.globalFeatures("footprint")[0]["id"] == footprintBefore["id"] && env.globalFeatures("footprint")[0]["properties"]?["building_ids"] == footprintBefore["properties"]?["building_ids"])
            env.undo()
            check("Footprint 좌표 Undo", env.globalFeatures("footprint")[0] == footprintBefore)
            env.redo()
            env.requestFootprintDeletion(footprint)
            check("Footprint 삭제는 확인 전 보존", env.pendingDeletion != nil && env.globalFeatures("footprint").count == 1)
            env.cancelDeletion()
            env.requestFootprintDeletion(footprint)
            env.confirmDeletion(env.pendingDeletion!.id)
            check("Footprint 확인 후 삭제", env.globalFeatures("footprint").isEmpty)
            env.undo()
            check("Footprint 삭제 Undo", env.globalFeatures("footprint").count == 1)
            let url = directory.appendingPathComponent("two-levels.imdfrnt")
            check("공통 건물·여러 층 저장", env.saveProject(to: url))
            let file = try ProjectFile.decoded(from: Data(contentsOf: url))
            check("v5 파일은 Level 내부에 저장, 중복 RoutingGraph 없음", file.version == 5 && file.routing == nil && file.hasDrawing == false && file.buildingProject?.levels.count == 2)
            let reopened = environment()
            try reopened.adopt(file, from: url)
            check("재열기 후 모든 층·건물·Footprint·층간 연결 동일", reopened.projectContents == env.projectContents && !reopened.hasUnsavedChanges)
            reopened.selectProjectLevel(changed)
            check("층 선택만으로 저장 상태가 바뀌지 않음", !reopened.hasUnsavedChanges && reopened.document?.sourceName == "second.svg" && reopened.currentRoutingFloor?.shortName == "2F")
            reopened.showRoutingScreen = false
            reopened.requestRoutingFloorDeletion(changed)
            check("Level 삭제는 확인 전 모든 데이터 보존", reopened.routing.floors.count == 2 && reopened.pendingDeletion != nil)
            reopened.confirmDeletion(reopened.pendingDeletion!.id)
            check("Level 삭제는 소속 SVG·노드·층간 연결 정리", reopened.routing.floors.count == 1 && reopened.routing.node(secondNode) == nil && reopened.routing.edges.isEmpty && reopened.document?.sourceName == "first.svg")
            reopened.undo()
            check("Level 삭제 Undo는 문서와 층별 작업까지 복원", reopened.projectContents == file.buildingProject && reopened.document?.sourceName == "second.svg")
            reopened.redo()
            check("Level 삭제 Redo", reopened.routing.floors.count == 1 && reopened.routing.edges.isEmpty)
            var legacy = file.legacyEditorView(levelID: first)
            legacy.version = 4
            try reopened.adopt(ProjectFile.decoded(from: legacy.encoded()), from: nil)
            check("v4 이전 시 SVG 태깅·UUID·노드·층간 연결 보존", reopened.features.feature(feature.id) != nil && reopened.routing == env.routing)
            legacy.version = 2; legacy.routing = nil; legacy.hasDrawing = nil
            try reopened.adopt(ProjectFile.decoded(from: legacy.encoded()), from: nil)
            check("v2 단일 SVG 작업을 공통 Level로 이전", reopened.routing.floors.count == 1 && reopened.features.feature(feature.id) != nil && reopened.document?.sourceName == "first.svg")
            var legacyJSON = try JSONSerialization.jsonObject(with: legacy.encoded()) as! [String: Any]
            legacyJSON.removeValue(forKey: "doorClosures")
            try reopened.adopt(ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: legacyJSON)), from: nil)
            check("임시 문 필드가 없는 초기 v2 파일도 이전", reopened.features.feature(feature.id) != nil && reopened.doorClosures.isEmpty)
            do { _ = try env.saveFootprint(id: nil, geometryText: "{\"type\":\"Polygon\",\"coordinates\":[[[129,36],[129.1,36],[129.1,36.1]]]}", category: "ground"); check("열린 Polygon 차단", false) }
            catch { check("열린 Polygon 차단", true) }
            try verifyIMDF(environment: environment, check: check)
            if let i = CommandLine.arguments.firstIndex(of: "--legacy-test-input"), CommandLine.arguments.indices.contains(i + 1) {
                let legacy = try ProjectFile.decoded(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
                let actual = environment()
                try actual.adopt(legacy, from: nil)
                func ordered(_ graph: RoutingGraph) -> RoutingGraph {
                    var result = graph
                    result.floors.sort { $0.id.uuidString < $1.id.uuidString }
                    result.nodes.sort { $0.id.uuidString < $1.id.uuidString }
                    result.edges.sort { $0.id.uuidString < $1.id.uuidString }
                    return result
                }
                let original = legacy.routing!
                // Partitioning by Level changes array order, not identity or data.
                check("사용자 실제 v4 파일의 모든 층·노드 UUID·연결·메타데이터 보존", ordered(actual.routing) == ordered(original) && actual.features == legacy.features)
                check("사용자 실제 v4 → v5의 클라이언트 GeoJSON 바이트 동일", try RoutingExporter.encoded(actual.routing) == RoutingExporter.encoded(original))
                let reopened = environment()
                try reopened.adopt(ProjectFile.decoded(from: actual.makeProjectFile()!.encoded()), from: nil)
                check("사용자 실제 v4 → v5 왕복 후 동일", reopened.projectContents == actual.projectContents)
            }
        } catch { check("공통 층 통합 검증", false); print(error) }
        print("== Building: \(total - failures)/\(total) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }

    private static func verifyIMDF(environment: () -> AppEnvironment, check: (String, Bool) -> Void) throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--imdf-test-input"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let imported = try IMDFImporter.load(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        let env = environment()
        try env.adoptIMDF(imported)
        let rebuilt = env.projectContents.imdfFiles()
        check("실제 C5 모든 파일명 보존", Set(rebuilt.keys) == Set(imported.files.keys))
        check("실제 C5 manifest·주소·건물·Footprint·unknown fields 보존", imported.files.allSatisfy { name, value in
            guard let output = rebuilt[name] else { return false }
            if value["type"]?.string != "FeatureCollection" { return output == value }
            var left = value, right = output
            left["features"] = nil; right["features"] = nil
            let original = value["features"]!.array, result = output["features"]!.array
            return left == right && result.count == original.count && original.allSatisfy { result.contains($0) }
        })
        check("실제 C5 층별 unit 167개와 building 1개·Footprint 2개 보존", env.buildingProject.levels.count == 6 && env.buildingProject.levels.reduce(0) { $0 + ($1.geoJSON["unit.geojson"]?.count ?? 0) } == 167 && env.globalFeatures("building").count == 1 && env.globalFeatures("footprint").count == 2)
        let first = env.buildingProject.levels.first!
        let replacement = UUID()
        env.renameProjectLevelID(first.id, to: replacement)
        let files = env.projectContents.imdfFiles()
        check("IMDF LevelID 변경은 원본 level과 모든 level_id 참조 갱신", files["level.geojson"]!["features"]!.array.contains { $0["id"]?.uuid == replacement } && !files.values.flatMap { $0["features"]?.array ?? [] }.contains { $0["properties"]?["level_id"]?.uuid == first.id || $0["properties"]?["level_ids"]?.array.contains { $0.uuid == first.id } == true })
        env.undo()
        env.updateProjectLevel(first.id, field: "name") { $0.name = "수정한 층"; $0.shortName = "NEW" }
        check("층 이름·shortName 편집은 실제 IMDF properties에 반영", env.activeLevel?.geoJSON["level.geojson"]?.first?["properties"]?["name"]?["ko"]?.string == "수정한 층" && env.activeLevel?.geoJSON["level.geojson"]?.first?["properties"]?["short_name"]?["ko"]?.string == "NEW")
        env.undo()
        let project = env.makeProjectFile()!
        let reopened = environment()
        try reopened.adopt(ProjectFile.decoded(from: project.encoded()), from: nil)
        check("IMDF 원본 geometry·properties는 .imdfrnt 재열기 후 동일", reopened.projectContents == env.projectContents)
        let decimal = try ProjectJSON.parse(Data("{\"big\":9007199254740993,\"null\":null,\"nested\":[true,{\"x\":1.1234567890123456789}]}".utf8))
        check("중첩 메타데이터·큰 정수·null 보존", try ProjectJSON.parse(decimal.data()) == decimal)
    }
}
