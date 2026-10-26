import Foundation

@MainActor
enum ReviewFollowupSelfTest {
    static func run(_ check: (String, Bool) -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewFollowup-\(UUID())")
        let suite = "ReviewFollowup-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject(); env.openSample()
        let ring = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)]
        var level = FeatureGroup(featureType: .level, serialNumber: "level-review", memberIDs: [])
        level.polygonRings = [ring]
        level.properties = ["category": .string("unspecified"), "outdoor": .boolean(false),
            "short_name": .localized(en: "", ko: "1"),
            "building_ids": .stringArray([IMDFTestFixtures.buildingID.uuidString.lowercased()])]
        let object = env.document!.objects[0].id, borrowed = env.document!.objects[1].id
        var unit = FeatureGroup(featureType: .unit, serialNumber: "unit-review", memberIDs: [object])
        unit.polygonRings = [ring]; unit.properties["category"] = .string("nonpublic")
        let legacyExport = UUID()
        env.ids.adopt(unit.id, id: legacyExport)
        var anchor = FeatureGroup(featureType: .anchor, serialNumber: "anchor-review", memberIDs: [])
        anchor.drawnVertices = [LocalPoint(20, 20)]
        anchor.properties["unit_id"] = .string(legacyExport.uuidString.lowercased())
        for feature in [level, unit, anchor] { env.features.insert(feature) }
        try env.ownership.claim([object], for: unit.id)
        env.borrow.borrow([borrowed], by: unit.id)
        for p in [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)] {
            env.anchors.add(local: p, geo: GeoPoint(longitude: 129 + p.x / 100_000, latitude: 36 + p.y / 100_000), label: "test")
        }
        env.storeActiveLevel()
        let source = env.projectContents.levels.first { $0.id == env.routingFloorID }!
        let originalProject = env.projectContents
        let target = env.addProjectLevel()
        await env.waitForLevelDrawing()
        check("#80 동일 층을 다른 층으로 가져오기", env.importLevel(source, into: target))
        await env.waitForLevelDrawing()
        let imported = env.projectContents.levels.first { $0.id == target }!
        let newUnit = imported.editing.features.features(ofType: .unit)[0]
        let newAnchor = imported.editing.features.features(ofType: .anchor)[0]
        let newExport = imported.editing.ids.peek(newUnit.id)!
        check("#80 복사 도형의 내부 ID·기존 할당 export UUID 모두 재발급", newUnit.id != unit.id && newExport != legacyExport)
        check("#80 도형 참조·소유권·대여 동시 이전", newAnchor.value("unit_id") == .string(newExport.uuidString.lowercased())
            && imported.editing.ownership.ownerOf(object) == newUnit.id
            && imported.editing.borrow.objects(borrowedBy: newUnit.id) == [borrowed]
            && imported.editing.borrow.objects(borrowedBy: unit.id).isEmpty)
        check("#80 원본 층 identity 보존", env.projectContents.levels.first { $0.id == source.id }?.editing == source.editing)
        let roundtrip = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded()).commonProject()
        check("#80 복사 도형 identity 저장 왕복", roundtrip.levels.first { $0.id == target }?.editing == imported.editing)
        env.undo()
        check("#80 층 가져오기 Undo", env.projectContents.levels.first { $0.id == target }?.editing.features.features.isEmpty == true)
        env.redo()
        await env.waitForLevelDrawing()
        check("#80 층 가져오기 Redo identity 보존", env.projectContents.levels.first { $0.id == target }?.editing == imported.editing)
        check("#80 원래 층에 교체하는 경우 identity 유지", try LevelImportIdentity.prepare(source, targetID: source.id,
            project: originalProject, metadata: nil).level.editing == source.editing)

        var raw = source
        let rawID = UUID()
        raw.geoJSON["fixture.geojson"] = [IMDFTestFixtures.feature("fixture", id: rawID,
            properties: ["anchor_id": .string(anchor.id.uuidString.lowercased())], geometry: IMDFTestFixtures.polygon())]
        var rawProject = originalProject
        rawProject.levels[0] = raw
        var common = rawProject
        let occupantID = UUID()
        common.globalGeoJSON["occupant.geojson"] = [IMDFTestFixtures.feature("occupant", id: occupantID,
            properties: ["anchor_id": .string(anchor.id.uuidString.lowercased())])]
        rawProject.globalGeoJSON = common.globalGeoJSON
        let remapped = try LevelImportIdentity.prepare(raw, targetID: UUID(), project: rawProject, metadata: common)
        let movedAnchor = remapped.level.editing.features.features(ofType: .anchor)[0]
        check("#80 원본 GeoJSON identity·참조도 재발급", remapped.level.geoJSON["fixture.geojson"]![0]["id"]?.uuid != rawID
            && remapped.level.geoJSON["fixture.geojson"]![0]["properties"]?["anchor_id"]?.uuid == movedAnchor.id)
        check("#80 복사 Anchor의 Occupant도 새 identity·참조", remapped.metadata?.globalGeoJSON["occupant.geojson"]?[0]["id"]?.uuid != occupantID
            && remapped.metadata?.globalGeoJSON["occupant.geojson"]?[0]["properties"]?["anchor_id"]?.uuid == movedAnchor.id)

        var file = env.makeProjectFile()!
        file.buildingProject = IMDFTestFixtures.metadata(env.projectContents)
        let archive = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
        check("#80 복사한 층의 IMDF 내보내기 UUID 중복 없음", IMDFValidation.check(files: archive.files).errors.isEmpty)

        var regional = IMDFTestFixtures.validProject()
        regional.manifest["language"] = .string("ko-KR")
        regional.globalGeoJSON["venue.geojson"]![0]["properties"]?["name"]?["ja"] = .string("図書館")
        file.buildingProject = regional
        let regionalOutput = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
        let labels = try ProjectJSON.parse(regionalOutput.files["venue.geojson"]!)["features"]!.array[0]["properties"]?["name"]
        check("#80 ko-KR 출력·엄격 검증 통과 및 기존 추가 언어 유지", labels?["ko-KR"] == labels?["ko"]
            && labels?["ja"]?.string == "図書館" && IMDFValidation.check(files: regionalOutput.files).errors.isEmpty)
        env.buildingProject.manifest["language"] = .string("ko-KR")
        check("#80 이름 입력 태그도 Manifest 사용", env.nameEditingLanguages == ["ko-KR", "en"])
        env.updateLocalizedProperty("name", language: "ko-KR", text: "도서관", in: newUnit)
        check("#80 기본 언어 이름 입력 저장", env.features.feature(newUnit.id)?.value("name").projectJSON["ko-KR"]?.string == "도서관")
        file.buildingProject = IMDFTestFixtures.metadata(env.projectContents)
        let authoredOutput = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
        let levels = try ProjectJSON.parse(authoredOutput.files["level.geojson"]!)["features"]!.array
        check("#80 자동 Level name·short_name도 지역 태그 사용", levels.allSatisfy {
            $0["properties"]?["name"]?["ko-KR"] != nil && $0["properties"]?["short_name"]?["ko-KR"] != nil
        })
        env.layers.addPropertyTypeLayer(.unit); env.layerEditMode = .face
        env.beginDisplayPointPicking(newUnit.id)
        check("#80 면 선택 상태에서도 표시점 입력 우선 조건", env.isPolygonWorkMode && env.mode.blocksSelection)
        check("#80 면 선택보다 표시점 입력 처리", env.handlePriorityCanvasClick(at: LocalPoint(30, 30), tolerance: 1)
            && env.features.feature(newUnit.id)?.displayPoint == LocalPoint(30, 30))
        env.mode = .anchorPicking
        check("#80 Anchor 입력 경로 유지", env.handlePriorityCanvasClick(at: LocalPoint(40, 40), tolerance: 1)
            && env.pendingAnchorLocal == LocalPoint(40, 40))
        check("#80 일반 클릭은 우선 입력에서 소비하지 않음", !env.handlePriorityCanvasClick(at: LocalPoint(50, 50), tolerance: 1))
    }
}
