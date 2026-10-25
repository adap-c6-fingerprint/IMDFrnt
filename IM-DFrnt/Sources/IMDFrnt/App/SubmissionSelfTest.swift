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
        let buildingID = env.addMetadataFeature(.building)!
        env.updateProperty("category", value: .string("unspecified"), in: buildingID)
        env.setDisplayPoint(LocalPoint(20, 20), for: buildingID)
        check("#79 겹친 ground/aerial 안 Building display point 허용", env.features.feature(buildingID)?.displayPoint == LocalPoint(20, 20))
        env.setDisplayPoint(LocalPoint(150, 150), for: buildingID)
        check("#79 Building 외곽 밖 거부 및 이전 점 보존", env.features.feature(buildingID)?.displayPoint == LocalPoint(20, 20))

        var level = FeatureGroup(featureType: .level, serialNumber: "level-001", memberIDs: [])
        level.polygonRings = [outer, hole, island]; level.multiPolygon = true
        env.features.insert(level)
        check("#79 ordinal 0 외곽 맞추기 사용 가능", env.groundFootprintUnavailableReason == nil)
        env.matchFootprintToGroundLevel(footprint.id)
        check("#79 기준층 외곽·구멍·MultiPolygon으로 Footprint 교체", env.features.feature(footprint.id)?.polygonRings == level.polygonRings
            && env.features.feature(footprint.id)?.multiPolygon == true)
        env.undo()
        check("#79 외곽 맞추기 Undo", env.features.feature(footprint.id)?.polygonRings == [outer])
        env.updateProjectLevel(env.routingFloorID!) { $0.ordinal = 1 }
        check("#79 ordinal 0이 없으면 비활성화 사유", env.groundFootprintUnavailableReason?.contains("ordinal 0") == true)

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
        var anchors = AnchorStore()
        for p in [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)] {
            anchors.add(local: p, geo: GeoPoint(longitude: 129 + p.x / 100_000, latitude: 36 - p.y / 100_000), label: "검증")
        }
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
        let snapshot = env.makeProjectFile()!
        let archive = try IMDFArchive.build(projectData: snapshot.encoded(), documents: [:])
        let levelJSON = try ProjectJSON.parse(archive.files["level.geojson"]!).arrayFeatures.first { $0["id"]?.uuid == sourceID }!
        let footprints = try ProjectJSON.parse(archive.files["footprint.geojson"]!).arrayFeatures
        let groundJSON = footprints.first { $0["id"]?.uuid == footprint.id }!
        let levelCoords = try FootprintGeometry.rings(levelJSON["geometry"]!).flatMap { $0 }
        let groundCoords = try FootprintGeometry.rings(groundJSON["geometry"]!).flatMap { $0 }
        check("#79 IMDF 내보낸 기준층과 ground Footprint 좌표 일치", levelCoords.count == groundCoords.count
            && zip(levelCoords, groundCoords).allSatisfy { abs($0[0] - $1[0]) < 1e-10 && abs($0[1] - $1[1]) < 1e-10 })
    }
}

private extension ProjectJSON {
    var arrayFeatures: [ProjectJSON] { self["features"]?.array ?? [] }
}
