import Foundation

@MainActor
enum SubmissionSelfTest {
    static func run(_ check: (String, Bool) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubmissionTest-\(UUID())")
        let suite = "SubmissionTest-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject(); env.openSample()
        let outer = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)]
        let hole = [LocalPoint(40, 40), LocalPoint(60, 40), LocalPoint(60, 60), LocalPoint(40, 60)]
        let island = outer.map { LocalPoint($0.x + 200, $0.y) }
        var venue = FeatureGroup(featureType: .venue, serialNumber: "venue-001", memberIDs: [])
        venue.polygonRings = [outer, hole, island]; venue.multiPolygon = true
        venue.properties["category"] = .string("university")
        venue.properties["name"] = .localized(en: "", ko: "검증용 도서관")
        env.features.insert(venue)
        env.setDisplayPoint(LocalPoint(50, 50), for: venue.id)
        check("#79 Venue 구멍 안 display point 거부", env.features.feature(venue.id)?.displayPoint == nil)
        env.setDisplayPoint(LocalPoint(150, 50), for: venue.id)
        check("#79 Venue 다각형 사이 display point 거부", env.features.feature(venue.id)?.displayPoint == nil)
        env.setDisplayPoint(LocalPoint(220, 20), for: venue.id)
        check("#79 직접 그린 MultiPolygon Venue 내부 display point 허용", env.features.feature(venue.id)?.displayPoint == LocalPoint(220, 20))
        env.clearDisplayPoint(venue.id)
        check("#79 display point 삭제", env.features.feature(venue.id)?.displayPoint == nil)
        env.undo()
        check("#79 display point 삭제 Undo", env.features.feature(venue.id)?.displayPoint == LocalPoint(220, 20))

        var footprint = FeatureGroup(featureType: .footprint, serialNumber: "footprint-001", memberIDs: [])
        footprint.polygonRings = [outer]; footprint.properties["category"] = .string("ground")
        env.features.insert(footprint); env.storeActiveLevel()
        let duplicateID = env.duplicateFootprint(footprint.id)!
        let duplicate = env.features.feature(duplicateID)!
        check("#79 Footprint 복제는 새 ID·새 일련번호·동일 geometry", duplicate.id != footprint.id && duplicate.serialNumber != footprint.serialNumber
            && duplicate.polygonRings == footprint.polygonRings && duplicate.properties == footprint.properties)
        env.updateProperty("category", value: .string("aerial"), in: duplicateID)
        check("#79 aerial 복제 수정은 ground 속성 보존", env.features.feature(footprint.id)?.value("category") == .string("ground"))
        var anchors = AnchorStore()
        for p in [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)] {
            anchors.add(local: p, geo: GeoPoint(longitude: 129 + p.x / 100_000, latitude: 36 - p.y / 100_000), label: "검증")
        }
        env.editFootprintAnchors("검증 GPS") { $0 = anchors }
        let buildingID = env.addMetadataFeature(.building)!
        env.updateProperty("category", value: .string("unspecified"), in: buildingID)
        for id in [footprint.id, duplicateID] {
            env.updateProperty("building_ids", value: .stringArray([buildingID.uuidString.lowercased()]), in: id)
        }
        env.setDisplayPoint(LocalPoint(20, 20), for: buildingID)
        let buildingPoint = env.globalFeatures("building")[0]["properties"]?["display_point"]
        check("#79 겹친 ground/aerial 안 Building display point 허용", buildingPoint?["type"]?.string == "Point")
        env.setDisplayPoint(LocalPoint(150, 150), for: buildingID)
        check("#79 Building 외곽 밖 거부 및 이전 점 보존", env.globalFeatures("building")[0]["properties"]?["display_point"] == buildingPoint)
        env.clearDisplayPoint(buildingID)
        check("#79 전역 Building 표시점 삭제", env.globalFeatures("building")[0]["properties"]?["display_point"] == .null)

        let otherBuilding = env.addMetadataFeature(.building)!
        env.updateProperty("category", value: .string("unspecified"), in: otherBuilding)
        env.setDisplayPoint(LocalPoint(20, 20), for: otherBuilding)
        check("#79 연결된 Footprint가 없는 Building 표시점 거부", env.globalFeatures("building")[1]["properties"]?["display_point"] == .null)
        var otherFootprint = FeatureGroup(featureType: .footprint, serialNumber: "footprint-review", memberIDs: [])
        otherFootprint.polygonRings = [island]
        otherFootprint.properties["category"] = .string("ground")
        otherFootprint.properties["building_ids"] = .stringArray([otherBuilding.uuidString.uppercased()])
        env.features.insert(otherFootprint)
        env.setDisplayPoint(LocalPoint(20, 20), for: buildingID)
        let ownPoint = env.globalFeatures("building")[0]["properties"]?["display_point"]
        env.setDisplayPoint(LocalPoint(220, 20), for: buildingID)
        check("#79 다른 건물 Footprint의 표시점 거부·기존 값 보존", ownPoint?["type"]?.string == "Point"
            && env.globalFeatures("building")[0]["properties"]?["display_point"] == ownPoint)
        env.setDisplayPoint(LocalPoint(220, 20), for: otherBuilding)
        check("#79 해당 건물 Footprint 표시점 허용·UUID 대소문자 무관", env.globalFeatures("building")[1]["properties"]?["display_point"]?["type"]?.string == "Point")
        env.clearDisplayPoint(buildingID)
        env.clearDisplayPoint(otherBuilding)

        var level = FeatureGroup(featureType: .level, serialNumber: "level-001", memberIDs: [])
        level.polygonRings = [outer, hole, island]; level.multiPolygon = true
        level.properties["category"] = .string("unspecified")
        level.properties["outdoor"] = .boolean(false)
        level.properties["short_name"] = .localized(en: "", ko: "1")
        env.features.insert(level)
        check("#79 ordinal 0 외곽 맞추기 사용 가능", env.groundFootprintUnavailableReason == nil)
        env.updateProjectLevel(env.routingFloorID!) { $0.ordinal = 1 }
        env.updateProperty("ordinal", value: .integer(0), in: level.id)
        check("#79 층 관리 1·Level 속성 0도 내보내기 기준으로 활성화", env.groundFootprintUnavailableReason == nil)
        let liveGround = try env.groundFootprintRings()
        check("#79 미저장 ordinal 0 변경도 외곽 복사에 즉시 반영", liveGround == level.polygonRings)
        env.matchFootprintToGroundLevel(footprint.id)
        check("#79 기준층 외곽·구멍·MultiPolygon으로 Footprint 교체", env.features.feature(footprint.id)?.polygonRings == level.polygonRings
            && env.features.feature(footprint.id)?.multiPolygon == true)
        env.undo()
        check("#79 외곽 맞추기 Undo", env.features.feature(footprint.id)?.polygonRings == [outer])
        env.updateProjectLevel(env.routingFloorID!) { $0.ordinal = 1 }
        env.updateProperty("ordinal", value: .integer(1), in: level.id)
        check("#79 ordinal 0이 없으면 비활성화 사유", env.groundFootprintUnavailableReason?.contains("ordinal 0") == true)
        env.updateProjectLevel(env.routingFloorID!) { $0.ordinal = 0 }
        check("#79 층 관리 0이어도 명시한 Level ordinal 1을 기준층으로 오인하지 않음", env.groundFootprintUnavailableReason != nil)
        env.updateProperty("ordinal", value: .null, in: level.id)
        check("#79 Level ordinal 미설정이면 층 관리 0으로 fallback", env.groundFootprintUnavailableReason == nil)
        var importedGround = ProjectLevel(info: ProjectLevelInfo(name: "가져온 1층", ordinal: 1))
        importedGround.geoJSON["level.geojson"] = [IMDFTestFixtures.feature("level", properties: ["ordinal": .number(0)])]
        check("#79 가져온 GeoJSON의 ordinal도 동일하게 검색", importedGround.exportsLevelOrdinal(0))
        importedGround.info.ordinal = 0
        importedGround.geoJSON["level.geojson"]![0]["properties"]?["ordinal"] = nil
        check("#79 가져온 원본에 없는 ordinal을 층 관리 값으로 추측하지 않음", !importedGround.exportsLevelOrdinal(0))

        let hours = "Mo-Fr 09:00-12:00,13:00-18:00; Sa 22:00-02:00; Su off"
        var weekly = WeeklyOpeningHours.parse("Mo-Fr 09:00-12:00,13:00-18:00; Sa off; Su off")
        weekly?.days[5] = WeeklyOpeningHours.Day(mode: .intervals,
            intervals: [.init(startHour: 22, startMinute: 0, endHour: 2, endMinute: 0)])
        check("#79 휴무·분할시간·자정 넘김 변환", weekly?.valid == true && weekly?.days[5].intervals[0].endHour == 2)
        check("#79 자정 넘김은 다음 날 휴무 규칙에 잘리지 않게 분리", weekly?.text.contains("Sa 22:00-24:00; Su 00:00-02:00") == true)
        check("#79 요일별 시간 문자열 왕복", weekly.flatMap { WeeklyOpeningHours.parse($0.text)?.text } == weekly?.text)
        check("#79 24시간", WeeklyOpeningHours.parse("24/7")?.text == "24/7")
        check("#79 24:30·동일 시작종료 거부", WeeklyOpeningHours.parse("Mo 09:00-24:30") == nil && WeeklyOpeningHours.parse("Mo 09:00-09:00") == nil)
        check("#79 복잡한 규칙은 요일별로 임의 축약하지 않음", WeeklyOpeningHours.parse("Jan-Mar Mo-Fr 09:00-18:00; PH off") == nil)
        check("#79 기존 자정 넘김 원문은 규칙 순서를 보존하는 고급 모드", WeeklyOpeningHours.parse(hours) == nil)
        env.updateProperty("hours", value: .string(hours), in: venue.id)
        let saved = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded()).commonProject()
        let restored = saved.levels.first(where: { $0.id == env.routingFloorID })!.editing.features.feature(venue.id)!
        check("#79 Venue 시간·display point 저장 왕복", restored.value("hours") == .string(hours) && restored.displayPoint == LocalPoint(220, 20))
        let exporter = GeoJSONExporter(document: env.document!, segmentation: env.segmentation,
            georeferencer: Georeferencer(pairs: anchors.pairs), borrow: env.borrow, levelID: env.routingFloorID)
        var ids = IDAssigner()
        let exported = exporter.serialize(restored, ids: &ids, serialToUUID: [:])
        let props = exported["properties"] as! [String: Any]
        check("#79 IMDF HOURS 문자열·display point 내보내기", props["hours"] as? String == hours && (props["display_point"] as? [String: Any])?["type"] as? String == "Point")
        check("#79 Venue hours는 편집 가능한 string", PropertySchema.fields(for: .venue).first(where: { $0.key == "hours" })?.type == .string)

        env.updateProjectLevel(env.routingFloorID!) { $0.ordinal = 0 }
        env.editFootprintAnchors("검증 GPS") { $0 = anchors }
        env.createBuilding()
        let globalID = env.globalFeatures("building")[0]["id"]!.uuid!
        env.beginGlobalDisplayPointPicking(globalID)
        env.handleCanvasClick(at: LocalPoint(20, 20), tolerance: 1)
        check("#79 가져온 전역 Building 표시점은 WGS84로 저장", env.globalFeatures("building")[0]["properties"]?["display_point"]?["type"]?.string == "Point"
            && env.mode == .idle && !env.showBuildingManager)
        env.undo()
        check("#79 전역 Building 표시점 Undo", env.globalFeatures("building")[0]["properties"]?["display_point"] == .null)

        let sourceID = env.routingFloorID!
        let otherID = env.addProjectLevel()
        try env.setRoutingDrawing(otherID, data: Data(SampleFloorplan.svg.utf8), name: "다른층.svg")
        env.editLevelRegistration(otherID, name: "검증 이동·회전·축척") {
            $0.transform = LevelFootprintTransform(x: 35, y: 60, scale: 1.8, rotation: 27)
        }
        env.matchFootprintToGroundLevel(footprint.id)
        let matched = env.projectContents.sharedFootprint!.features.first(where: { $0.id == footprint.id })!.polygonRings
        check("#79 다른 층에서 외곽 맞추기도 공유 좌표계 유지", zip(matched.flatMap { $0 }, level.polygonRings.flatMap { $0 }).allSatisfy { $0.distance(to: $1) < 1e-8 }
            && matched.count == level.polygonRings.count)
        var snapshot = env.makeProjectFile()!
        snapshot.buildingProject = IMDFTestFixtures.metadata(env.projectContents)
        // #78은 추측한 참조나 불완전한 기하를 내보내지 않는다. 합성 fixture도
        // 실제 제출에 필요한 Building 참조·Unit coverage·Venue 범위를 갖춘다.
        let buildingReference = PropertyValue.stringArray([buildingID.uuidString.lowercased()])
        for i in snapshot.buildingProject!.sharedFootprint!.features.indices {
            snapshot.buildingProject!.sharedFootprint!.features[i].properties["building_ids"] = buildingReference
        }
        let sourceIndex = snapshot.buildingProject!.levels.firstIndex(where: { $0.id == sourceID })!
        snapshot.buildingProject!.levels[sourceIndex].editing.features.update(level.id) { $0.properties["building_ids"] = buildingReference }
        snapshot.buildingProject!.levels[sourceIndex].editing.features.update(venue.id) {
            $0.polygonRings = [[LocalPoint(-10, -10), LocalPoint(400, -10), LocalPoint(400, 110), LocalPoint(-10, 110)]]
            $0.multiPolygon = false
        }
        var coverage = FeatureGroup(featureType: .unit, serialNumber: "unit-001", memberIDs: [])
        coverage.polygonRings = level.polygonRings; coverage.multiPolygon = true
        coverage.properties["category"] = .string("nonpublic")
        snapshot.buildingProject!.levels[sourceIndex].editing.features.insert(coverage)
        let archive = try IMDFArchive.build(projectData: snapshot.encoded(), documents: [:])
        let levelJSON = try ProjectJSON.parse(archive.files["level.geojson"]!).arrayFeatures.first { $0["id"]?.uuid == sourceID }!
        let footprints = try ProjectJSON.parse(archive.files["footprint.geojson"]!).arrayFeatures
        let groundJSON = footprints.first { $0["id"]?.uuid == footprint.id }!
        let levelCoords = try FootprintGeometry.rings(levelJSON["geometry"]!).flatMap { $0 }
        let groundCoords = try FootprintGeometry.rings(groundJSON["geometry"]!).flatMap { $0 }
        check("#79 IMDF 내보낸 기준층과 ground Footprint 좌표 일치", levelCoords.count == groundCoords.count
            && zip(levelCoords, groundCoords).allSatisfy { abs($0[0] - $1[0]) < 1e-10 && abs($0[1] - $1[1]) < 1e-10 })

        if let flag = CommandLine.arguments.firstIndex(of: "--submission-test-project"), CommandLine.arguments.indices.contains(flag + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            let original = try Data(contentsOf: url)
            let file = try ProjectFile.decoded(from: original)
            let roundTrip = try ProjectFile.decoded(from: file.encoded())
            check("#79 실제 v7 프로젝트 전체 모델 왕복 보존", file == roundTrip && file.version == 7)
            let project = file.commonProject()
            try project.validate()
            try env.adopt(file, from: nil)
            let reopened = env.makeProjectFile()!.commonProject()
            check("#79 실제 v7 프로젝트 앱 열기 및 metadata·trash·legacy 보존", reopened.globalGeoJSON == project.globalGeoJSON
                && reopened.metadataTrash == project.metadataTrash && reopened.legacyMetadataGroups == project.legacyMetadataGroups
                && reopened.levels.count == project.levels.count)
            let grounds = reopened.levels.filter { $0.exportsLevelOrdinal(0) }
            check("#79 실제 프로젝트의 Level 속성 ordinal 0 탐색", grounds.count == 1 && grounds.first?.info.name == "1층")
            check("#79 실제 프로젝트 Footprint 일치 버튼 활성화", env.groundFootprintUnavailableReason == nil)
            let rings = try env.groundFootprintRings()
            check("#79 실제 프로젝트 기준층 외곽 복사 계산", !rings.isEmpty && rings.allSatisfy { $0.count >= 3 })
            check("#79 실제 프로젝트 원본 바이트 불변", try Data(contentsOf: url) == original)
        }
    }
}

private extension ProjectJSON {
    var arrayFeatures: [ProjectJSON] { self["features"]?.array ?? [] }
}
