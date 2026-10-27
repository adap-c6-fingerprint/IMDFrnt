import Foundation

/// Regression fixtures for PR #77's data-integrity, state, performance and compatibility reviews.
@MainActor
enum FootprintReviewSelfTest {
    private static let basis = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)]
    private static let ring = [LocalPoint(20, 20), LocalPoint(200, 20), LocalPoint(200, 160), LocalPoint(20, 160)]

    /// Exercise all fixes without opening or overwriting the user's project files.
    static func run(_ check: (String, Bool) -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FootprintReview-\(UUID())")
        let suite = "FootprintReview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject(); env.openSample()
        env.selectPropertyType(.footprint)
        env.pointDraft = PointDraft(points: ring); env.closePointDraft()
        let source = env.routingFloorID!
        let liveID = env.features.features(ofType: .footprint)[0].id
        check("확정 전 첫 Footprint 조회도 최신 작도 상태 보존", env.sharedFootprint.features[0].polygonRings == [ring] && !env.georeferencer.isConfigured)
        env.storeActiveLevel()
        env.selection.selected = [env.document!.objects.first!.id]
        env.enterAnchorScreen()
        check("정상 Anchor 진입은 선택 해제·입력 모드 설정", env.showAnchorScreen && env.selection.isEmpty && env.mode == .anchorPicking)
        env.pendingAnchorLocal = basis[0]
        env.enterLevelFootprintScreen()
        check("Anchor→Level 전환은 입력 모드와 미완성 선택 초기화", env.showLevelFootprintScreen && !env.showAnchorScreen && env.mode == .idle && env.pendingAnchorLocal == nil)
        env.enterAnchorScreen()
        check("Level→Anchor 전환은 화면 우선순위 충돌 없음", !env.showLevelFootprintScreen && env.showAnchorScreen && env.mode == .anchorPicking)
        env.exitAnchorScreen()
        let other = env.addProjectLevel()
        try env.setRoutingDrawing(other, data: Data(SampleFloorplan.svg.utf8), name: "native.svg")
        env.anchors = anchors(longitude: 130, latitude: 37)
        env.storeActiveLevel()
        let native = env.activeLevel!.info.geoPoint(for: basis[1])!
        env.editLevelRegistration(other, name: "표시 설정") { $0.opacity = 0.2; $0.isVisible = false }
        check("공유 GPS가 없어도 미정렬 층의 표시 설정은 자체 GPS 보존", env.activeLevel!.info.footprintGeoAnchors == nil && env.activeLevel!.info.geoPoint(for: basis[1]) == native)
        env.editFootprintAnchors("공유 GPS") { $0 = anchors(longitude: 129, latitude: 36) }
        env.editLevelRegistration(other, name: "표시 설정") { $0.opacity = 0.4; $0.isVisible = true }
        check("공유 GPS가 있어도 불투명도는 미정렬 층 좌표를 바꾸지 않음", env.activeLevel!.info.footprintGeoAnchors == nil && env.georeferencer.geoPoint(for: basis[1]) == native)
        env.editLevelRegistration(other, name: "미완성 대응점") {
            $0.pairs = basis.map { LevelFootprintPair(level: $0, footprint: $0) }
        }
        check("대응점 입력만으로 GPS 정렬을 확정하지 않음", env.activeLevel!.info.footprintGeoAnchors == nil)
        env.fitLevelToFootprint(other)
        check("항등 대응점 정렬도 명시적으로 적용됨", env.activeLevel!.info.footprintRegistration?.isAligned == true && env.activeLevel!.info.geoPoint(for: basis[1]) != native)
        env.editFootprintAnchors("공유 GPS 삭제") { $0 = AnchorStore() }
        check("정렬한 층의 공유 GPS 삭제는 옛 좌표 fallback 대신 차단", env.activeLevel!.info.footprintGeoAnchors == [] && !env.activeLevel!.info.hasGeographicCoordinates)
        env.editFootprintAnchors("공유 GPS 복원") { $0 = anchors(longitude: 129, latitude: 36) }

        env.undoStack.clear()
        let before = env.projectContents
        for index in 1...80 {
            env.editLevelRegistration(other, name: "슬라이더", coalescingKey: "drag-1") { $0.opacity = Double(index) / 100 }
        }
        check("80회 슬라이더 변경은 Undo 한 칸", env.undoStack.undoEntries.count == 1)
        env.undo()
        check("슬라이더 한 번 Undo로 시작 상태 복원", env.projectContents == before)
        env.redo()
        env.editLevelRegistration(other, name: "슬라이더", coalescingKey: "drag-2") { $0.opacity = 0.9 }
        check("서로 다른 드래그는 별도 Undo", env.undoStack.undoEntries.count == 2)

        env.selectProjectLevel(source); await env.waitForLevelDrawing()
        let sharedBefore = env.buildingProject.sharedFootprint!
        env.features.update(liveID) { $0.polygonRings[0][0] = LocalPoint(22, 22) }
        check("가벼운 Footprint 조회는 미저장 편집을 즉시 반영", env.sharedFootprint.features[0].polygonRings[0][0] == LocalPoint(22, 22)
            && env.buildingProject.sharedFootprint == sharedBefore)
        env.storeActiveLevel()
        let original = env.globalFeatures("footprint")[0]
        env.buildingProject.collectionHeaders["footprint.geojson"] = .array([])
        env.selectPropertyType(.footprint)
        do {
            _ = try IMDFArchive.build(projectData: env.makeProjectFile()!.encoded(), documents: [:])
            check("잘못된 Footprint JSON은 강제 캐스트 종료 대신 안내", false)
        } catch let blocked as IMDFArchive.Blocked {
            check("잘못된 Footprint JSON은 강제 캐스트 종료 대신 안내", blocked.messages.contains { $0.contains("footprint.geojson") && $0.contains("FeatureCollection") })
        }
        env.buildingProject.collectionHeaders.removeValue(forKey: "footprint.geojson")
        let exportID = original["id"]!.uuid!
        let geometry = "{\"type\":\"Polygon\",\"coordinates\":[[[129,36],[129.002,36],[129.002,35.998],[129,36]]]}"
        _ = try env.saveFootprint(id: exportID, geometryText: geometry, category: "ground")
        let edited = env.sharedFootprint.features.first { $0.id == liveID }!
        check("옛 GPS 편집 API도 캔버스의 같은 Feature 갱신", edited.polygonRings != sharedBefore.features[0].polygonRings && env.features.feature(liveID)?.polygonRings == edited.polygonRings)
        let secondID = try env.saveFootprint(id: nil, geometryText: geometry, category: "aerial")
        check("추가 GPS Footprint도 캔버스와 전역 모델에 동시 반영", env.features.feature(secondID) != nil && env.sharedFootprint.features.count == 2)
        env.requestFootprintDeletion(secondID); env.confirmDeletion(env.pendingDeletion!.id)
        check("Footprint 삭제는 캔버스와 내보내기 모두 제거", env.features.feature(secondID) == nil && !env.projectContents.imdfFiles()["footprint.geojson"]!["features"]!.array.contains { $0["id"]?.uuid == secondID })
        env.undo()
        check("Footprint API 삭제 Undo도 공유 모델 복원", env.features.feature(secondID) != nil)

        let file = env.makeProjectFile()!
        let loaded = try ProjectFile.decoded(from: file.encoded())
        check("현재 버전 저장으로 구버전 앱의 무손실인 척하는 재저장 방지", loaded.version == ProjectFile.currentVersion && loaded.buildingProject == env.projectContents)
        var oldFile = file; oldFile.version = 5
        check("기존 v5 프로젝트는 계속 읽기 가능", try ProjectFile.decoded(from: oldFile.encoded()).version == 5)
        var oldRegistration = try ProjectJSON.parse(JSONEncoder().encode(env.buildingProject.levels.first { $0.id == other }!.info.footprintRegistration!))
        oldRegistration["isAligned"] = nil
        let migratedRegistration = try JSONDecoder().decode(LevelFootprintRegistration.self, from: oldRegistration.data())
        check("기존 항등 대응점 정렬은 새 명시적 상태로 보존", migratedRegistration.isAligned)
        let reopened = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try reopened.adopt(loaded, from: nil)
        check("GPS API 편집·삭제 Undo 후 재열기 동일", reopened.projectContents == env.projectContents)
        reopened.selectProjectLevel(other); await reopened.waitForLevelDrawing()
        check("공유 Footprint를 다른 층에서 보기만 하면 저장 상태 불변", !reopened.hasUnsavedChanges)
        let globalSerials = Set(reopened.sharedFootprint.features.map(\.serialNumber))
        let nextSerial = reopened.nextFeatureSerial(for: .footprint)
        check("다른 층에서 새 Footprint 번호는 기존 전역 번호와 중복 없음", !globalSerials.contains(nextSerial))
        try migrationChecks(check)
        try exportChecks(check)
        cacheChecks(check)
    }

    /// Construct a reversible native drawing frame with a deliberately distinct geographic origin.
    private static func anchors(longitude: Double, latitude: Double) -> AnchorStore {
        var store = AnchorStore()
        for point in basis {
            store.add(local: point, geo: GeoPoint(longitude: longitude + point.x / 100_000, latitude: latitude - point.y / 100_000), label: "native")
        }
        return store
    }

    /// Compare cross-frame migration with original GPS and retain unconvertible source data verbatim.
    private static func migrationChecks(_ check: (String, Bool) -> Void) throws {
        var a = ProjectLevel(info: ProjectLevelInfo(name: "source", ordinal: 0))
        var b = ProjectLevel(info: ProjectLevelInfo(name: "other", ordinal: 1))
        a.info.anchors = anchors(longitude: 129, latitude: 36)
        b.info.anchors = anchors(longitude: 130, latitude: 37)
        var footprint = FeatureGroup(featureType: .footprint, serialNumber: "footprint-001", memberIDs: [])
        footprint.polygonRings = [ring]
        footprint.properties["category"] = .string("ground")
        a.editing.features.insert(footprint)
        var second = FeatureGroup(featureType: .footprint, serialNumber: "footprint-002", memberIDs: [])
        second.polygonRings = [ring]; second.displayPoint = ring[0]
        b.editing.features.insert(second)
        let exportID = b.editing.ids.id(for: second.id)
        var project = BuildingProject(levels: [a, b])
        project.migrateSharedFootprint()
        let shared = project.sharedFootprint!
        let converted = shared.features.first { $0.id == second.id }!
        let expected = b.info.geoPoint(for: ring[0])!
        let actual = shared.geoPoint(converted.polygonRings[0][0])!
        check("다른 층 Footprint는 각 층 GPS를 거쳐 공통 평면으로 이전", abs(actual.longitude - expected.longitude) < 1e-8 && abs(actual.latitude - expected.latitude) < 1e-8)
        check("이전은 displayPoint·수명 UUID도 보존", converted.displayPoint == converted.polygonRings[0][0] && shared.originals[second.id.uuidString]?["id"]?.uuid == exportID)
        let firstMigration = project
        project.migrateSharedFootprint()
        check("여러 층 Footprint 이전은 재실행해도 동일", project == firstMigration)
        b.info.anchors = AnchorStore()
        var pending = BuildingProject(levels: [a, b])
        pending.migrateSharedFootprint()
        check("변환 불가 Footprint는 원래 층 도형·소유권 보존", pending.levels[1] == b && pending.sharedFootprint?.pendingMigrationFeatureIDs == [second.id])
        var file = ProjectFile.empty(); file.buildingProject = pending
        let roundtrip = try ProjectFile.decoded(from: file.encoded()).commonProject()
        check("변환 불가 원본은 저장 재열기에도 보존", roundtrip.levels[1] == b && roundtrip.sharedFootprint?.pendingMigrationFeatureIDs == [second.id])
        do {
            _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
            check("이전 미완료 내보내기 차단", false)
        } catch let blocked as IMDFArchive.Blocked {
            check("이전 미완료 내보내기 차단", blocked.messages.contains { $0.contains("이전하지 못한 층별 Footprint") })
        }
        pending.levels[1].info.anchors = anchors(longitude: 130, latitude: 37)
        pending.migrateSharedFootprint()
        check("GPS 보완 후 보류한 이전 재시도 가능", pending.sharedFootprint?.pendingMigrationFeatureIDs == nil && pending.levels[1].editing.features.count(ofType: .footprint) == 0)
        let raw = shared.geographicFeatures()[0]
        var imported = BuildingProject(globalGeoJSON: ["footprint.geojson": [raw]])
        imported.migrateSharedFootprint()
        imported.sharedFootprint?.features.removeAll()
        imported.migrateSharedFootprint()
        check("보관한 원본 JSON 때문에 삭제한 공유 Footprint가 부활하지 않음", imported.sharedFootprint?.features.isEmpty == true
            && imported.imdfFiles()["footprint.geojson"]?["features"]?.array.isEmpty == true)
    }

    /// Verify building references in the actual archive, including preservation of explicit references.
    private static func exportChecks(_ check: (String, Bool) -> Void) throws {
        var footprint = FeatureGroup(featureType: .footprint, serialNumber: "footprint-001", memberIDs: [])
        footprint.polygonRings = [ring]
        let buildingID = UUID()
        footprint.properties["category"] = .string("ground")
        var shared = SharedFootprint(features: [footprint], anchors: anchors(longitude: 129, latitude: 36))
        var project = BuildingProject()
        project.sharedFootprint = shared
        project.globalGeoJSON["building.geojson"] = [IMDFTestFixtures.feature("building", id: buildingID, properties: ["category": .string("unspecified")])]
        project = IMDFTestFixtures.metadata(project)
        var file = ProjectFile.empty(); file.buildingProject = project
        let archive = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
        let json = try ProjectJSON.parse(archive.files["footprint.geojson"]!)
        check("새 공유 Footprint 내보내기에 building_ids 자동 연결", json["features"]!.array[0]["properties"]?["building_ids"]?.array == [.string(buildingID.uuidString.lowercased())])
        let explicit = UUID().uuidString.lowercased()
        shared.features[0].properties["building_ids"] = .stringArray([explicit])
        project.sharedFootprint = shared; file.buildingProject = project
        do {
            _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
            check("명시한 잘못된 building_ids는 덮어쓰지 않고 오류로 차단", false)
        } catch let blocked as IMDFArchive.Blocked {
            check("명시한 잘못된 building_ids는 덮어쓰지 않고 오류로 차단", blocked.messages.contains { $0.contains("building_ids") && $0.contains("실제 building") })
        }
    }

    /// Ensure opacity changes reuse outlines and cached snapping still honors current zoom tolerance.
    private static func cacheChecks(_ check: (String, Bool) -> Void) {
        var level = ProjectLevel(info: ProjectLevelInfo(name: "cache", ordinal: 0))
        var outline = FeatureGroup(featureType: .level, serialNumber: "level-001", memberIDs: [])
        outline.polygonRings = [ring]; level.editing.features.insert(outline)
        let cache = RegistrationGeometryCache()
        _ = cache.rings(for: level)
        level.info.footprintRegistration = LevelFootprintRegistration()
        level.info.footprintRegistration?.opacity = 0.1
        _ = cache.rings(for: level)
        check("불투명도 변경은 Level 링을 다시 만들지 않음", cache.buildCount == 1)
        level.editing.features.update(outline.id) { $0.polygonRings[0][0] = LocalPoint(22, 20) }
        check("Level 도형 변경은 캐시 무효화", cache.rings(for: level)[0][0] == LocalPoint(22, 20) && cache.buildCount == 2)
        let snap = RegistrationSnapData(rings: [ring])
        check("캐시된 스냅은 꼭짓점 우선 유지", snap.snapped(LocalPoint(20.1, 20.1), tolerance: 1) == ring[0])
        check("캐시된 스냅도 호출별 tolerance 반영", snap.snapped(LocalPoint(70, 20.2), tolerance: 1) == LocalPoint(70, 20)
            && snap.snapped(LocalPoint(70, 20.2), tolerance: 0.1) == nil)
    }
}
