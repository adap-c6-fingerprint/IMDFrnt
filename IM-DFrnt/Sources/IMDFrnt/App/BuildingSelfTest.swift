import AppKit
import Foundation

@MainActor
enum BuildingSelfTest {
    /// Verify building ownership, Footprint metadata, persistence and legacy-file migration.
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--building-selftest") else { return }
        var total = 0, failures = 0
        /// Report an assertion while allowing independent scenarios to continue.
        func check(_ name: String, _ valid: Bool) {
            total += 1; if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntBuildingTest-\(UUID())")
        let suite = "IMDFrntBuildingTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        /// Isolate autosaves and preferences from the user's real projects.
        func environment() -> AppEnvironment {
            AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        }
        do {
            let legacyID = UUID()
            let legacyLevelID = UUID()
            var legacyFootprint = BuildingProject(levels: [ProjectLevel(info: ProjectLevelInfo(id: legacyLevelID, name: "1층", ordinal: 0))])
            let legacyFeature: ProjectJSON = .object([
                "type": .string("Feature"), "feature_type": .string("footprint"),
                "id": .string(legacyID.uuidString.lowercased()), "geometry": .null,
                "properties": .object(["category": .string("ground")])
            ])
            legacyFootprint.levels[0].geoJSON["footprint.geojson"] = [legacyFeature]
            legacyFootprint.migrateLevelFootprintsToGlobal()
            check("기존 층별 Footprint를 전역으로 자동 이전", legacyFootprint.levels[0].geoJSON["footprint.geojson"] == nil
                  && legacyFootprint.globalGeoJSON["footprint.geojson"] == [legacyFeature]
                  && legacyFootprint.globalGeoJSON["footprint.geojson"]?.first?["id"]?.uuid == legacyID)

            let env = environment()
            try env.createNewProject()
            env.createBuilding()
            let initialBuilding = env.globalFeatures("building")
            env.autosaveTick()
            let recovered = environment()
            let autosaved = try env.projectURL.map { try ProjectFile.decoded(from: Data(contentsOf: $0)) }
            if let autosaved { try recovered.adopt(autosaved, from: env.projectURL) }
            check("Level 없이 작성한 건물 정보도 자동 저장 파일로 복원", autosaved != nil && !recovered.hasUnsavedChanges && recovered.globalFeatures("building") == initialBuilding)
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
            await env.waitForLevelDrawing()
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
            env.projectURL = url
            check("공통 건물·여러 층 저장", env.persist(showingBanner: false))
            let file = try ProjectFile.decoded(from: Data(contentsOf: url))
            check("현재 형식은 Level 내부에 저장, 중복 RoutingGraph 없음", file.version == ProjectFile.currentVersion && file.routing == nil && file.hasDrawing == false && file.buildingProject?.levels.count == 2)
            let reopened = environment()
            try reopened.adopt(file, from: url)
            check("재열기 후 모든 층·건물·Footprint·층간 연결 동일", reopened.projectContents == env.projectContents && !reopened.hasUnsavedChanges)
            reopened.selectProjectLevel(changed)
            await reopened.waitForLevelDrawing()
            check("층 선택만으로 저장 상태가 바뀌지 않음", !reopened.hasUnsavedChanges && reopened.document?.sourceName == "second.svg" && reopened.currentRoutingFloor?.shortName == "2F")
            reopened.showRoutingScreen = false
            reopened.requestRoutingFloorDeletion(changed)
            check("Level 삭제는 확인 전 모든 데이터 보존", reopened.routing.floors.count == 2 && reopened.pendingDeletion != nil)
            reopened.confirmDeletion(reopened.pendingDeletion!.id)
            check("Level 삭제는 소속 SVG·노드·층간 연결 정리", reopened.routing.floors.count == 1 && reopened.routing.node(secondNode) == nil && reopened.routing.edges.isEmpty && reopened.document?.sourceName == "first.svg")
            reopened.undo()
            await reopened.waitForLevelDrawing()
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
                /// Normalize array order to compare identity and metadata across migrations.
                func ordered(_ graph: RoutingGraph) -> RoutingGraph {
                    var result = graph
                    result.floors.sort { $0.id.uuidString < $1.id.uuidString }
                    result.nodes.sort { $0.id.uuidString < $1.id.uuidString }
                    result.edges.sort { $0.id.uuidString < $1.id.uuidString }
                    return result
                }
                let original = legacy.routing ?? legacy.commonProject().routingGraph
                // Partitioning by Level changes array order, not identity or data.
                let originalOrdered = ordered(original), actualOrdered = ordered(actual.routing)
                check("사용자 파일의 모든 층·노드 UUID·연결·메타데이터 보존", actualOrdered.nodes == originalOrdered.nodes
                    && actualOrdered.edges == originalOrdered.edges && actualOrdered.floors.map(\.id) == originalOrdered.floors.map(\.id))
                if legacy.version < 5 {
                    check("사용자 실제 v4 → v5의 클라이언트 GeoJSON 바이트 동일", try RoutingExporter.encoded(actual.routing) == RoutingExporter.encoded(original))
                }
                let reopened = environment()
                try reopened.adopt(ProjectFile.decoded(from: actual.makeProjectFile()!.encoded()), from: nil)
                check("사용자 실제 프로젝트 왕복 후 동일", reopened.projectContents == actual.projectContents)
            }
        } catch { check("공통 층 통합 검증", false); print(error) }

        // 신기능 12항: feature type 상태·층 완료·순서·최근 작업.
        do {
            let ws = environment()
            try ws.createNewProject()
            let l1 = ws.addProjectLevel()
            let l2 = ws.addProjectLevel()
            ws.selectProjectLevel(l1)
            await ws.waitForLevelDrawing()
            func level(_ id: UUID) -> ProjectLevel { ws.buildingProject.levels.first { $0.id == id }! }
            check("상태: 처음은 Todo", ws.workStatus(.unit) == .todo)
            ws.setWorkStatus(.complete, for: .unit)
            check("상태: 층마다 따로 둔다", ws.workStatus(.unit) == .complete && ws.workStatus(.unit, level: level(l2)) == .todo)
            ws.setWorkStatus(.inReview, for: .occupant)
            check("상태: 정보 type은 프로젝트에 하나다",
                  ws.buildingProject.metadataWorkStatus?["occupant"] == .inReview
                  && ws.workStatus(.occupant, level: level(l2)) == .inReview)
            check("층 완료: 일부만 Complete면 층은 미완료", !ws.isLevelComplete(level(l1)))
            for type in AppEnvironment.levelFeatureTypes { ws.setWorkStatus(.complete, for: type) }
            check("층 완료: 좌측 type이 모두 Complete면 층도 Complete(정보 type은 보지 않는다)",
                  ws.isLevelComplete(level(l1)) && !ws.isLevelComplete(level(l2))
                  && ws.workStatus(.address) == .todo)

            let ordinals = ws.buildingProject.levels.map { $0.info.ordinal }
            ws.moveLevel(l2, to: l1)
            check("층 순서: 끌면 화면 순서만 바뀌고 층 번호는 그대로",
                  ws.displayedLevels.map(\.id) == [l2, l1] && ws.buildingProject.levels.map { $0.info.ordinal } == ordinals)

            ws.setWorkStatus(.todo, for: .fixture)
            ws.setWorkStatus(.inProgress, for: .opening)
            check("정렬: 미완료 순은 Todo가 먼저", ws.sortedFeatureTypes(.incompleteFirst).prefix(2) == [.fixture, .opening])
            check("정렬: 완료 순은 Todo가 마지막", ws.sortedFeatureTypes(.completeFirst).suffix(2) == [.opening, .fixture])
            let shown = ws.sortedFeatureTypes(.custom)
            ws.moveFeatureType(.unit, to: shown[0], shown: shown)
            check("정렬: 끌어 옮긴 순서가 사용자 지정 순서로 저장된다",
                  ws.customFeatureTypeOrder.first == .unit && ws.buildingProject.featureTypeOrder?.first == "unit")

            check("최근 작업: 상태만 바꾼 것은 작업이 아니다", ws.activeLevel?.lastEdited?["fixture"] == nil)
            ws.perform("amenity 추가") {
                ws.features.insert(FeatureGroup(featureType: .amenity, serialNumber: "amenity-901", memberIDs: []))
            }
            check("최근 작업: feature를 고친 type의 시각이 남는다",
                  ws.activeLevel?.lastEdited?["amenity"] != nil && ws.sortedFeatureTypes(.recent).first == .amenity)
            ws.undo()
            check("최근 작업: 실행취소하면 시각도 되돌아간다", ws.activeLevel?.lastEdited?["amenity"] == nil)

            let decoded = try JSONDecoder().decode(BuildingProject.self, from: JSONEncoder().encode(ws.projectContents))
            check("상태·순서는 프로젝트 파일에 저장된다",
                  decoded.levels.first { $0.id == l1 }?.workStatus?["unit"] == .complete
                  && decoded.metadataWorkStatus?["occupant"] == .inReview
                  && decoded.levelDisplayOrder == [l2, l1] && decoded.featureTypeOrder?.first == "unit")
        } catch { check("신기능 12항 검증", false); print(error) }

        // #31: 빈 층에서 .imdfrnt 불러오기는 프로젝트를 바꾸지 않고 그 층에 넣는다.
        do {
            let env = environment()
            try env.createNewProject()
            let drawn = env.addProjectLevel()
            try env.setRoutingDrawing(drawn, data: Data(SampleFloorplan.svg.utf8), name: "first.svg")
            let blank = env.addProjectLevel()
            await env.waitForLevelDrawing()
            check("빈 층 + 다른 층에 작업 있음 → 층에 넣기", env.routingFloorID == blank && env.importsProjectIntoActiveLevel)
            env.selectProjectLevel(drawn)
            await env.waitForLevelDrawing()
            check("작업된 층에서는 예전처럼 프로젝트 전환", !env.importsProjectIntoActiveLevel)
            env.selectProjectLevel(blank)
            await env.waitForLevelDrawing()

            let sourceID = UUID(), stamp = Date(timeIntervalSince1970: 1_000_000)
            var source = ProjectLevel(info: ProjectLevelInfo(id: sourceID, name: "5층", ordinal: 4, sourceName: "fifth.svg", svg: SampleFloorplan.svg))
            source.editing.features.insert(FeatureGroup(featureType: .amenity, serialNumber: "amenity-501", memberIDs: []))
            let a = RoutingNode(floorID: sourceID, point: LocalPoint(1, 2)), b = RoutingNode(floorID: sourceID, point: LocalPoint(3, 4))
            source.nodes = [a, b]
            source.edges = [RoutingEdge(from: a.id, to: b.id)]
            source.workStatus = ["amenity": .complete]
            source.lastEdited = ["amenity": stamp]
            let before = env.buildingProject.levels.first { $0.id == blank }!.info
            let projectID = env.projectID
            env.importLevel(source, into: blank)
            await env.waitForLevelDrawing()
            let level = env.buildingProject.levels.first { $0.id == blank }!
            check("층 불러오기: 프로젝트는 그대로, 층 ID·이름·번호 유지",
                  env.projectID == projectID && env.buildingProject.levels.count == 2
                  && level.info.name == before.name && level.info.ordinal == before.ordinal)
            check("층 불러오기: 도면·태깅·노드·연결·상태가 들어온다",
                  level.info.svg == SampleFloorplan.svg && env.document?.sourceName == "fifth.svg"
                  && env.features.features.count == 1 && level.nodes.allSatisfy { $0.floorID == blank }
                  && level.nodes.count == 2 && level.edges.count == 1 && level.workStatus?["amenity"] == .complete)
            check("층 불러오기: 불러온 것은 '최근 작업'으로 찍지 않는다", level.lastEdited?["amenity"] == stamp)
            let third = env.addProjectLevel()
            env.importLevel(source, into: third)
            check("층 불러오기: 같은 층을 두 번 넣어도 노드 ID가 겹치지 않는다", (try? env.projectContents.validate()) != nil)
            env.undo(); env.undo(); env.undo()
            await env.waitForLevelDrawing()
            check("층 불러오기: 실행취소하면 빈 층으로 돌아간다",
                  AppEnvironment.isBlankLevel(env.projectContents.levels.first { $0.id == blank }!))
        } catch { check("#31 빈 층 .imdfrnt 불러오기 검증", false); print(error) }

        // 정보 type 스펙 점검(2026-10-20): 칸별 문제와 내보내기 차단.
        do {
            func feature(_ type: IMDFFeatureType, _ props: [String: PropertyValue]) -> FeatureGroup {
                var f = FeatureGroup(featureType: type, serialNumber: "\(type.rawValue)-001", memberIDs: [])
                for field in PropertySchema.fields(for: type) { f.properties[field.key] = props[field.key] ?? .null }
                return f
            }
            func severity(_ f: FeatureGroup, _ key: String) -> FieldProblem.Severity? { PropertyRules.problem(f.featureType, key, in: f)?.severity }
            let empty = feature(.address, [:])
            check("address: 필수 address·locality·country가 비면 위반, postal_code는 경고",
                  severity(empty, "address") == .violation && severity(empty, "locality") == .violation
                  && severity(empty, "country") == .violation && severity(empty, "postal_code") == .warning
                  && severity(empty, "unit") == nil)
            let good = feature(.address, ["address": .string("청암로 77"), "locality": .string("포항시"),
                                          "country": .string("KR"), "province": .string("KR-47"), "postal_code": .string("37673")])
            check("address: 올바른 값은 문제 없음", PropertyRules.problems(in: good).isEmpty)
            let wrong = feature(.address, ["address": .string("  "), "locality": .string("포항시"),
                                           "country": .string("대한민국"), "province": .string("경상북도")])
            check("address: 공백만·글자 국가명·글자 시도명은 위반",
                  severity(wrong, "address") == .violation && severity(wrong, "country") == .violation
                  && severity(feature(.address, ["country": .string("KR"), "province": .string("경상북도")]), "province") == .violation
                  && severity(feature(.address, ["country": .string("KR")]), "province") == .violation)
            check("address: 국가·시도는 목록에서 고른다(한국 17개)",
                  PropertyRules.choices(.address, "country", in: good)?.contains { $0.value == "KR" } == true
                  && PropertyRules.choices(.address, "province", in: good)?.count == 17
                  && PropertySchema.fields(for: .address).first { $0.key == "unit" }?.type == .string)
            let occupant = feature(.occupant, ["name": .localized(en: "Cafe", ko: "카페"), "category": .string("cafe"),
                                               "anchor_id": .string("anchor-001"), "hours": .string("Mo-Fr 09:00-18:00; Sa off"),
                                               "phone": .string("+82542792114"), "website": .string("https://example.com")])
            check("occupant: 올바른 값은 문제 없음", PropertyRules.problems(in: occupant).isEmpty)
            let badOccupant = feature(.occupant, ["name": .localized(en: "Cafe", ko: ""), "category": .string("커피"),
                                                  "hours": .string("평일 9시"), "phone": .string("054-279-2114"), "website": .string("example.com")])
            check("occupant: ko 없는 이름·목록 밖 category·anchor 없음·형식 틀린 hours·phone·website는 위반",
                  ["name", "category", "anchor_id", "hours", "phone", "website"].allSatisfy { severity(badOccupant, $0) == .violation })
            check("occupant: category 목록은 Apple 범주 파일 전량", PropertySchema.categoryOptions(for: .occupant).count == 1116)
            check("phone 칸은 공백·하이픈을 떼고, 공백만 넣으면 null",
                  PropertySlotRow.text(" +82 54-279-2114 ", key: "phone") == .string("+82542792114")
                  && PropertySlotRow.text("   ", key: "address") == .null)
            let building = feature(.building, ["category": .string("unspecified"), "restriction": .string("private")])
            check("building: restriction은 employeesonly·restricted만, 이름 없음은 경고",
                  severity(building, "restriction") == .violation && severity(building, "name") == .warning
                  && severity(building, "category") == nil)
            check("manifest: 언어 태그 점검",
                  severity(feature(.manifest, ["language": .string("korean")]), "language") == .violation
                  && severity(feature(.manifest, ["language": .string("ko-KR")]), "language") == nil)

            let env = environment()
            try env.createNewProject()
            let l = env.addProjectLevel()
            await env.waitForLevelDrawing()
            env.addMetadataFeature(.address)
            var project = env.projectContents
            var blocked: [String] = []
            do { guard var file = env.makeProjectFile() else { throw CocoaError(.fileWriteUnknown) }; file.buildingProject = project; _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:]) }
            catch let b as IMDFArchive.Blocked { blocked = b.messages }
            check("내보내기: 빈 address는 막고 고칠 칸을 알려준다", blocked.contains { $0.contains("address-001 country") })
            let i = project.levels.firstIndex { $0.id == l }!
            let id = project.levels[i].editing.features.features(ofType: .address)[0].id
            project.levels[i].editing.features.update(id) { f in
                f.properties["address"] = .string("청암로 77"); f.properties["locality"] = .string("포항시")
                f.properties["country"] = .string("KR"); f.properties["province"] = .string("KR-47")
            }
            blocked = []
            do { guard var file = env.makeProjectFile() else { throw CocoaError(.fileWriteUnknown) }; file.buildingProject = project; _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:]) }
            catch let b as IMDFArchive.Blocked { blocked = b.messages }
            check("내보내기: address를 채우면 그 칸 때문에 막히지 않는다", !blocked.contains { $0.contains("address-001") })
            check("manifest created는 소수 초 없는 DATE-TIME",
                  (IMDFArchive.manifest(imported: nil, feature: nil, now: Date(timeIntervalSince1970: 0))["created"] as? String) == "1970-01-01T00:00:00Z")
        } catch { check("정보 type 스펙 점검", false); print(error) }
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
