import Foundation

@MainActor
enum FootprintRegistrationSelfTest {
    /// Run both the original Footprint workflow and review-specific regression fixtures.
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--footprint-selftest") else { return }
        var failures = 0, count = 0
        /// Count and report assertions without stopping at the first failed scenario.
        func check(_ name: String, _ value: Bool) {
            count += 1; if !value { failures += 1 }
            print("[\(value ? "PASS" : "FAIL")] \(name)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FootprintTest-\(UUID())")
        let suite = "FootprintTest-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        do {
            let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
            try env.createNewProject()
            env.openSample()
            let first = env.routingFloorID!
            env.selectPropertyType(.footprint)
            check("Footprint는 opening 완료 및 GPS 없이 메인 레이어에서 작도", env.layers.activePropertyType == .footprint && env.anchors.pairs.isEmpty)
            let ring = [LocalPoint(20, 20), LocalPoint(200, 20), LocalPoint(200, 160), LocalPoint(20, 160)]
            env.pointDraft = PointDraft(points: ring)
            env.closePointDraft()
            let featureID = env.features.features(ofType: .footprint).first!.id
            check("GPS 없이 Footprint 저장", env.sharedFootprint.features.count == 1 && !env.sharedFootprint.isGeoreferenced)
            do {
                _ = try IMDFArchive.build(projectData: env.makeProjectFile()!.encoded(), documents: [:])
                check("GPS 없는 Footprint 내보내기 차단 메시지", false)
            } catch let blocked as IMDFArchive.Blocked {
                check("GPS 없는 Footprint 내보내기 차단 메시지", blocked.messages.contains("전역 Footprint의 GPS Anchor를 먼저 설정하세요. 서로 일직선이 아닌 대응점 최소 3쌍이 필요합니다."))
            } catch { check("GPS 없는 Footprint 내보내기 차단 메시지", false) }
            env.storeActiveLevel()
            check("층 편집 저장소와 전역 저장소 중복 없음", env.projectContents.levels[0].editing.features.count(ofType: .footprint) == 0)

            let second = env.addProjectLevel()
            try env.setRoutingDrawing(second, data: Data(SampleFloorplan.svg.utf8), name: "second.svg")
            check("다른 층에서 같은 Footprint ID·꼭짓점 표시", env.features.feature(featureID)?.polygonRings == [ring])
            env.perform("전역 꼭짓점 수정") { env.features.update(featureID) { $0.polygonRings[0][0] = LocalPoint(25, 20) } }
            env.selectProjectLevel(first); await env.waitForLevelDrawing()
            check("다른 층의 편집이 전역으로 반영", env.features.feature(featureID)?.polygonRings[0][0] == LocalPoint(25, 20))
            env.enterAnchorScreen()
            check("Anchor 지정은 전역 Footprint 기준", env.showAnchorScreen && env.mode == .anchorPicking && env.selection.isEmpty)
            env.editFootprintAnchors("GPS 기준 3쌍") { store in
                for p in [LocalPoint(0, 0), LocalPoint(200, 0), LocalPoint(0, 200)] {
                    store.add(local: p, geo: GeoPoint(longitude: 129 + p.x / 100_000, latitude: 36 - p.y / 100_000), label: "GPS")
                }
            }
            env.exitAnchorScreen()
            check("Footprint GPS 좌표 생성", env.sharedFootprint.isGeoreferenced && env.projectContents.imdfFiles()["footprint.geojson"]?["features"]?.array.count == 1)

            let expected = LevelFootprintTransform(x: 40, y: -12, scale: 1.5, rotation: 15)
            let basis = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)]
            env.editLevelRegistration(second, name: "층 대응점") { r in r.pairs = basis.map { LevelFootprintPair(level: $0, footprint: expected.apply($0)) } }
            env.fitLevelToFootprint(second)
            let info = env.projectContents.levels.first { $0.id == second }!.info
            let fitted = info.footprintRegistration!.transform
            check("대응점으로 층 이동·회전·균일 크기 정렬", basis.allSatisfy { fitted.apply($0).distance(to: expected.apply($0)) < 1e-7 })
            let local = LocalPoint(30, 45), geo = info.geoPoint(for: local)!
            check("층 좌표 변환은 Footprint GPS와 일치", abs(geo.longitude - (129 + expected.apply(local).x / 100_000)) < 1e-8
                && info.localPoint(for: geo)!.distance(to: local) < 1e-5)
            let before = env.projectContents
            env.editLevelRegistration(second, name: "미세조정") { $0.transform.x += 1 }
            let adjusted = env.projectContents.levels.first { $0.id == second }!.info.footprintRegistration!
            check("미세조정은 대응점 위치도 갱신", adjusted.pairs.allSatisfy { adjusted.transform.apply($0.level).distance(to: $0.footprint) < 1e-8 })
            env.undo()
            check("층 정렬 Undo", env.projectContents == before)
            let file = env.makeProjectFile()!
            if let flag = CommandLine.arguments.firstIndex(of: "--footprint-ui-fixture"), CommandLine.arguments.indices.contains(flag + 1) {
                var fixture = file
                var project = fixture.buildingProject!
                for i in project.levels.indices {
                    var outline = FeatureGroup(featureType: .level, serialNumber: "level-001", memberIDs: [])
                    outline.polygonRings = [ring]
                    project.levels[i].editing.features.insert(outline)
                }
                fixture.buildingProject = project
                try fixture.encoded().write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            }
            let data = try file.encoded()
            let loaded = try ProjectFile.decoded(from: data)
            let reopened = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
            try reopened.adopt(loaded, from: nil)
            check("전역 도형·GPS·층 정렬 저장 재열기", reopened.projectContents == env.projectContents && !reopened.hasUnsavedChanges)

            // An imported floor must export transformed geometry, while its native
            // data and Feature IDs/properties remain unchanged.
            var imported = env.projectContents.levels.first { $0.id == second }!
            imported.info.imdfCoordinates = IMDFCoordinateSpace(west: 129, north: 36, unitsPerLongitudeDegree: 100_000, unitsPerLatitudeDegree: 100_000, padding: 0)
            let raw: ProjectJSON = .object(["id": .string(UUID().uuidString), "feature_type": .string("amenity"),
                "properties": .object(["name": .string("보존")]),
                "geometry": .object(["type": .string("Point"), "coordinates": .array([.number(Decimal(string: "129.0003")!), .number(Decimal(string: "35.99955")!)])])])
            let exported = imported.registeredFeatureForExport(raw)
            check("가져온 IMDF 좌표도 정렬 반영·ID/속성 보존", exported["geometry"] != raw["geometry"] && exported["id"] == raw["id"] && exported["properties"] == raw["properties"])
            let snap = RegistrationGeometry.snapped(LocalPoint(20.1, 20.1), rings: [ring], tolerance: 1)
            check("Footprint 꼭짓점 자석", snap == ring[0])
            check("Footprint 변 자석", RegistrationGeometry.snapped(LocalPoint(70, 20.2), rings: [ring], tolerance: 1) == LocalPoint(70, 20))
            var migration = BuildingProject(levels: [ProjectLevel(info: ProjectLevelInfo(name: "기존 층", ordinal: 0))])
            var old = FeatureGroup(id: featureID, featureType: .footprint, serialNumber: "footprint-001", memberIDs: [])
            old.polygonRings = [ring]; old.properties["category"] = .string("ground")
            migration.levels[0].editing.features.insert(old)
            let lifetimeID = migration.levels[0].editing.ids.id(for: featureID)
            migration.migrateSharedFootprint()
            check("기존 작도 Footprint 자동 이전·수명 ID 보존", migration.sharedFootprint?.features.first == old
                && migration.levels[0].editing.features.count(ofType: .footprint) == 0
                && migration.sharedFootprint?.originals[featureID.uuidString]?["id"]?.uuid == lifetimeID)
            do {
                _ = try LevelFootprintTransform.fit([LevelFootprintPair(level: local, footprint: local), LevelFootprintPair(level: local, footprint: local)])
                check("중복 대응점은 정렬 거부", false)
            } catch { check("중복 대응점은 정렬 거부", true) }
            try await FootprintReviewSelfTest.run(check)
            try SubmissionSelfTest.run(check)
        } catch { check("테스트 실행: \(error)", false) }
        print("== Footprint: \(count - failures)/\(count) \(failures == 0 ? "PASS" : "FAIL") ==")
        exit(failures == 0 ? 0 : 1)
    }
}
