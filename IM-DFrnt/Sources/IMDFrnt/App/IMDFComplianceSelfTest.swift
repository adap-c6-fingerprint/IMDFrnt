import Foundation

/// Complete synthetic delivery metadata for engine fixtures; never used to repair user data.
enum IMDFTestFixtures {
    static let addressID = UUID()
    static let buildingID = UUID()
    static let venueID = UUID()

    static func feature(_ type: String, id: UUID = UUID(), properties: [String: ProjectJSON], geometry: ProjectJSON = .null) -> ProjectJSON {
        .object(["type": .string("Feature"), "feature_type": .string(type), "id": .string(id.uuidString.lowercased()),
                 "geometry": geometry, "properties": .object(properties)])
    }
    static func polygon(_ west: Double = 128.9, _ south: Double = 35.9, _ east: Double = 129.4, _ north: Double = 36.1) -> ProjectJSON {
        let coordinates = [[west, south], [east, south], [east, north], [west, north], [west, south]]
        return .object(["type": .string("Polygon"), "coordinates": .array([.array(coordinates.map { .array($0.map { .number(Decimal($0)) }) })])])
    }
    static func point(_ x: Double, _ y: Double) -> ProjectJSON {
        .object(["type": .string("Point"), "coordinates": .array([.number(Decimal(x)), .number(Decimal(y))])])
    }
    static func metadata(_ source: BuildingProject) -> BuildingProject {
        var p = source
        if p.manifest["language"] == nil { p.manifest["language"] = .string("ko") }
        if (p.globalGeoJSON["address.geojson"] ?? []).isEmpty {
            p.globalGeoJSON["address.geojson"] = [feature("address", id: addressID, properties: [
                "address": .string("청암로 77"), "locality": .string("포항시"), "country": .string("KR"), "province": .string("KR-47")])]
        }
        if (p.globalGeoJSON["building.geojson"] ?? []).isEmpty {
            p.globalGeoJSON["building.geojson"] = [feature("building", id: buildingID, properties: ["category": .string("unspecified")])]
        }
        let hasLocalVenue = p.levels.contains { !$0.editing.features.features(ofType: .venue).isEmpty }
        if (p.globalGeoJSON["venue.geojson"] ?? []).isEmpty && !hasLocalVenue {
            let id = p.globalGeoJSON["address.geojson"]![0]["id"]!
            p.globalGeoJSON["venue.geojson"] = [feature("venue", id: venueID, properties: [
                "category": .string("university"), "name": .object(["ko": .string("검증용 장소")]),
                "display_point": point(129.1, 36), "address_id": id], geometry: polygon())]
        }
        return p
    }
    static func authored(_ levels: [ProjectLevel], cross: [RoutingEdge] = []) -> BuildingProject {
        var project = metadata(BuildingProject(levels: levels, crossLevelEdges: cross))
        for i in project.levels.indices {
            let name = project.levels[i].info.name
            let features = project.levels[i].editing.features.features
            for f in features {
                project.levels[i].editing.features.update(f.id) { value in
                    if [.level, .unit, .venue].contains(f.featureType), value.value("category").isNull {
                        value.properties["category"] = .string(f.featureType == .venue ? "university" : f.featureType == .unit ? "walkway.island" : "unspecified")
                    }
                    if f.featureType == .level {
                        value.properties["outdoor"] = .boolean(false)
                        value.properties["short_name"] = .localized(en: "", ko: name)
                    }
                    if f.featureType == .venue {
                        value.properties["name"] = .localized(en: "", ko: "검증용 장소")
                        value.displayPoint = LocalPoint(100, 100)
                    }
                }
            }
        }
        return project
    }
    static func files(_ project: BuildingProject) throws -> [String: Data] {
        var files = try project.imdfFiles().mapValues { try $0.data() }
        let manifest = IMDFArchive.manifest(imported: project.manifest, feature: nil, now: Date(timeIntervalSince1970: 0))
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        return files
    }
    static func validProject() -> BuildingProject {
        let level = UUID(), unit = UUID()
        let geometry = polygon(129, 36, 129.001, 36.001)
        var p = metadata(BuildingProject())
        p.globalGeoJSON["level.geojson"] = [feature("level", id: level, properties: [
            "category": .string("unspecified"), "outdoor": .bool(false), "ordinal": .number(0),
            "name": .object(["ko": .string("1층")]), "short_name": .object(["ko": .string("1")]),
            "building_ids": .array([.string(buildingID.uuidString.lowercased())])], geometry: geometry)]
        p.globalGeoJSON["unit.geojson"] = [feature("unit", id: unit, properties: [
            "category": .string("walkway.island"), "level_id": .string(level.uuidString.lowercased())], geometry: geometry)]
        return p
    }
}

@MainActor
enum IMDFComplianceSelfTest {
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--imdf-compliance-selftest") else { return }
        var total = 0, failures = 0
        func check(_ label: String, _ pass: Bool) {
            total += 1; if !pass { failures += 1 }
            print("[\(pass ? "PASS" : "FAIL")] \(label)")
        }
        func report(_ project: BuildingProject) throws -> IMDFValidation.Report { IMDFValidation.check(files: try IMDFTestFixtures.files(project)) }
        func rejects(_ label: String, _ project: BuildingProject, containing key: String) throws {
            let errors = try report(project).errors
            check(label, errors.contains { $0.contains(key) })
            if !errors.contains(where: { $0.contains(key) }) { print(errors) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFCompliance-\(UUID())")
        let suite = "IMDFCompliance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        do {
            let valid = IMDFTestFixtures.validProject()
            let initial = try report(valid)
            check("완전한 합성 IMDF의 필수 속성·참조·공간 검증 통과", initial.errors.isEmpty)
            if !initial.errors.isEmpty { print(initial.errors) }
            var file = ProjectFile.empty(); file.buildingProject = valid
            let output = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
            check("공식 ZIP build도 동일한 검증 통과", !output.files.isEmpty)
            try rejects("빈 Address 거절", BuildingProject(), containing: "Address가 최소")
            var invalid = valid
            invalid.globalGeoJSON["venue.geojson"]! += valid.globalGeoJSON["venue.geojson"]!
            try rejects("Venue 중복 거절", invalid, containing: "정확히 1개")
            try rejects("UUID 중복 거절", invalid, containing: "UUID가")
            for key in ["category", "outdoor", "short_name"] {
                invalid = valid; invalid.globalGeoJSON["level.geojson"]![0]["properties"]?[key] = .null
                try rejects("Level \(key) 필수", invalid, containing: key)
            }
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["properties"]?["level_id"] = .string("level-001")
            try rejects("해결하지 못한 일련번호 거절", invalid, containing: "실제 level")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["properties"]?["level_id"] = valid.globalGeoJSON["address.geojson"]![0]["id"]
            try rejects("참조 대상 타입 오류 거절", invalid, containing: "실제 level")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["properties"]?["category"] = .string("not-a-category")
            try rejects("비공식 category 거절", invalid, containing: "category 값")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["geometry"] = IMDFTestFixtures.polygon(129, 36, 129.0005, 36.0005)
            try rejects("Unit–Level 빈틈 거절", invalid, containing: "합집합")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["properties"]?["category"] = .string("room")
            try rejects("Level의 Opening 누락 거절", invalid, containing: "Opening이 필요")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["geometry"] = IMDFTestFixtures.polygon(130, 37, 130.001, 37.001)
            try rejects("Venue 바깥 Feature 거절", invalid, containing: "Venue 경계")
            invalid = valid; invalid.globalGeoJSON["venue.geojson"]![0]["properties"]?["display_point"] = IMDFTestFixtures.point(131, 38)
            try rejects("도형 바깥 display_point 거절", invalid, containing: "display_point")
            invalid = valid; invalid.manifest["language"] = .string("en")
            try rejects("Manifest–LABELS 언어 불일치 거절", invalid, containing: "기본 언어 en")
            check("BCP 47 변형/스크립트 태그 허용", IMDFValidation.validLanguageTag("de-DE-1996") && IMDFValidation.validLanguageTag("zh-Hant-HK"))
            check("UUID v4 이외의 ID 거절", !IMDFValidation.validID("11111111-1111-1111-1111-111111111111"))
            invalid = valid
            invalid.globalGeoJSON["unit.geojson"]![0]["geometry"] = .object(["type": .string("Polygon"),
                "coordinates": .array([.array([.array([.number(129), .number(36)]), .array([.number(129.001), .number(36)]), .array([.number(129), .number(36)])])])])
            try rejects("점 두 개 Polygon 거절", invalid, containing: "링은 점 4개")
            invalid = valid; invalid.globalGeoJSON["unit.geojson"]![0]["geometry"] = IMDFTestFixtures.polygon(181, 36, 182, 37)
            try rejects("WGS84 좌표 범위 오류 거절", invalid, containing: "경도")
            invalid = valid
            invalid.globalGeoJSON["anchor.geojson"] = [IMDFTestFixtures.feature("anchor", properties: [
                "unit_id": valid.globalGeoJSON["unit.geojson"]![0]["id"]!], geometry: IMDFTestFixtures.point(129.005, 36.005))]
            try rejects("Unit 바깥 Anchor 거절", invalid, containing: "Anchor는")
            invalid = valid
            let sectionA = UUID(), sectionB = UUID()
            let levelReference = valid.globalGeoJSON["level.geojson"]![0]["id"]!
            invalid.globalGeoJSON["section.geojson"] = [
                IMDFTestFixtures.feature("section", id: sectionA, properties: ["category": .string("retail"), "level_id": levelReference,
                    "parents": .array([.string(sectionB.uuidString.lowercased())])], geometry: IMDFTestFixtures.polygon(129, 36, 129.001, 36.001)),
                IMDFTestFixtures.feature("section", id: sectionB, properties: ["category": .string("retail"), "level_id": levelReference,
                    "parents": .array([.string(sectionA.uuidString.lowercased())])], geometry: IMDFTestFixtures.polygon(129, 36, 129.001, 36.001))]
            try rejects("Section 부모 순환 거절", invalid, containing: "순환")
            invalid = valid
            invalid.globalGeoJSON["opening.geojson"] = [IMDFTestFixtures.feature("opening", properties: [
                "category": .string("pedestrian"), "level_id": levelReference], geometry: .object([
                    "type": .string("LineString"), "coordinates": .array([
                        .array([.number(129.0001), .number(36.0001)]), .array([.number(129.0002), .number(36.0002)])])]))]
            try rejects("Unit 경계에서 떨어진 Opening 거절", invalid, containing: "Unit 경계")
            invalid.globalGeoJSON["opening.geojson"]![0]["geometry"] = .object([
                "type": .string("LineString"), "coordinates": .array([
                    .array([.number(129), .number(36)]), .array([.number(129.0001), .number(36)])])])
            check("Unit 경계 위 Opening 허용", try report(invalid).errors.isEmpty)
            invalid.globalGeoJSON["opening.geojson"]![0]["properties"]?["door"] = .object(["type": .string("sliding"), "automatic": .bool(true)])
            check("Door JSON 공식 속성 허용", try report(invalid).errors.isEmpty)
            invalid.globalGeoJSON["opening.geojson"]![0]["properties"]?["door"] = .object(["type": .string("not-a-door")])
            try rejects("잘못된 Door 열거값 거절", invalid, containing: "door.type")

            let levelID = valid.globalGeoJSON["level.geojson"]![0]["id"]!
            let unitID = valid.globalGeoJSON["unit.geojson"]![0]["id"]!
            var expanded = valid
            expanded.globalGeoJSON["detail.geojson"] = [IMDFTestFixtures.feature("detail", properties: ["level_id": levelID], geometry: .object([
                "type": .string("MultiLineString"), "coordinates": .array([.array([.array([.number(129), .number(36)]), .array([.number(129.0001), .number(36.0001)])])])]))]
            expanded.globalGeoJSON["kiosk.geojson"] = [IMDFTestFixtures.feature("kiosk", properties: ["level_id": levelID], geometry: IMDFTestFixtures.polygon(129.0001, 36.0001, 129.0002, 36.0002))]
            expanded.globalGeoJSON["relationship.geojson"] = [IMDFTestFixtures.feature("relationship", properties: [
                "category": .string("traversal"), "direction": .string("undirected"),
                "origin": .object(["id": unitID, "feature_type": .string("unit")])])]
            file.buildingProject = expanded
            let expandedOutput = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
            check("Detail·Kiosk·Relationship 재내보내기 보존", ["detail", "kiosk", "relationship"].allSatisfy { expandedOutput.featureCounts[$0 + ".geojson"] == 1 })
            expanded.globalGeoJSON["geofence.geojson"] = []
            expanded.collectionHeaders["detail.geojson"] = .object(["type": .string("FeatureCollection"), "custom_header": .string("preserved")])
            expanded.globalGeoJSON["detail.geojson"]![0]["custom_member"] = .object(["opaque": .array([.bool(true), .null])])
            file.buildingProject = expanded
            let lossless = try IMDFArchive.build(projectData: file.encoded(), documents: [:])
            let detail = try ProjectJSON.parse(lossless.files["detail.geojson"]!)
            check("컬렉션 헤더·Feature foreign member 보존", detail["custom_header"]?.string == "preserved" && detail["features"]!.array[0]["custom_member"] == expanded.globalGeoJSON["detail.geojson"]![0]["custom_member"])
            check("빈 선택 컬렉션도 파일 보존", lossless.files["geofence.geojson"] != nil)
            expanded.extraFiles["broken.geojson"] = .object(["broken": .bool(true)])
            file.buildingProject = expanded
            do { _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:]); check("손상된 원본 컬렉션은 누락 대신 오류", false) }
            catch let b as IMDFArchive.Blocked { check("손상된 원본 컬렉션은 누락 대신 오류", b.messages.contains { $0.contains("broken.geojson") }) }

            let local = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)]
            let hole = [LocalPoint(20, 20), LocalPoint(20, 40), LocalPoint(40, 40), LocalPoint(40, 20)]
            var calibration = AnchorStore()
            calibration.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "A")
            calibration.add(local: LocalPoint(100, 0), geo: GeoPoint(longitude: 129.001, latitude: 36), label: "B")
            calibration.add(local: LocalPoint(0, 100), geo: GeoPoint(longitude: 129, latitude: 36.001), label: "C")
            var spatial = FeatureGroup(featureType: .unit, serialNumber: "unit-001", memberIDs: [])
            spatial.polygonRings = [local, hole]
            let exporter = GeoJSONExporter(document: DrawingDocument(objects: [], canvasSize: .zero, sourceName: "test"),
                segmentation: SegmentationStore(), georeferencer: Georeferencer(pairs: calibration.pairs))
            var ids = IDAssigner()
            let polygon = exporter.serialize(spatial, ids: &ids, serialToUUID: [:])["geometry"] as! [String: Any]
            check("MultiPolygon 플래그 없는 Polygon 구멍 보존", polygon["type"] as? String == "Polygon" && (polygon["coordinates"] as? [Any])?.count == 2)
            let draw = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
            draw.openSample(); draw.features.insert(spatial)
            draw.setDisplayPoint(LocalPoint(50, 50), for: spatial.id)
            check("점 작도 다각형의 display_point 지정", draw.features.feature(spatial.id)?.displayPoint == LocalPoint(50, 50))
            draw.setDisplayPoint(LocalPoint(30, 30), for: spatial.id)
            check("구멍 안 display_point 거절", draw.features.feature(spatial.id)?.displayPoint == LocalPoint(50, 50))
            var entrance = FeatureGroup(featureType: .opening, serialNumber: "opening-001", memberIDs: [])
            entrance.drawnVertices = [LocalPoint(0, 0), LocalPoint(100, 0)]
            draw.features.insert(entrance); draw.setDisplayPoint(LocalPoint(50, 3), for: entrance.id)
            check("Opening display_point를 선 위로 정렬", draw.features.feature(entrance.id)?.displayPoint == LocalPoint(50, 0))
            var oldLevel = ProjectLevel(info: ProjectLevelInfo(name: "기존 층", ordinal: 0))
            var address = FeatureGroup(featureType: .address, serialNumber: "address-001", memberIDs: [])
            address.properties["address"] = .string("보존할 주소")
            oldLevel.editing.features.insert(address)
            let oldID = oldLevel.editing.ids.id(for: address.id)
            spatial.properties["custom_address_id"] = .string("unchanged")
            oldLevel.editing.features.insert(spatial)
            var migration = BuildingProject(levels: [oldLevel])
            migration.migrateGlobalMetadata()
            check("층별 Address 공통 이전·기존 ID 보존", migration.globalGeoJSON["address.geojson"]?.first?["id"]?.uuid == oldID && migration.levels[0].editing.features.count(ofType: .address) == 0)
            let once = migration; migration.migrateGlobalMetadata()
            check("메타데이터 이전 멱등성", migration == once)
            var ownedLevel = oldLevel
            let member = draw.document!.objects[0].id
            ownedLevel.editing.features.update(address.id) { $0.memberIDs = [member] }
            try ownedLevel.editing.ownership.claim([member], for: address.id)
            var owned = BuildingProject(levels: [ownedLevel]); owned.migrateGlobalMetadata()
            check("옛 메타데이터의 개체 소유권 해제·편집 원본 보관", owned.levels[0].editing.ownership.claimedCount == 0
                && owned.legacyMetadataGroups?.values.contains { $0.id == address.id && $0.memberIDs.contains(member) } == true)
            var anchor = FeatureGroup(featureType: .anchor, serialNumber: "anchor-001", memberIDs: [])
            anchor.properties["address_id"] = .string("address-001")
            oldLevel.editing.features.insert(anchor)
            var withReferences = BuildingProject(levels: [oldLevel]); withReferences.migrateGlobalMetadata()
            check("이전 시 기존 층의 주소 일련번호 참조를 UUID로 변환", withReferences.levels[0].editing.features.feature(anchor.id)?.value("address_id") == .string(oldID.uuidString.lowercased()))
            let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
            try env.createNewProject()
            let first = env.addProjectLevel()
            await env.waitForLevelDrawing()
            let addressID = env.addMetadataFeature(.address)!
            env.updateProperty("address", value: .string("공통 주소"), in: addressID)
            env.removeProjectLevel(first)
            check("층 삭제 후 공통 주소 유지", env.globalFeatures("address").first?["properties"]?["address"]?.string == "공통 주소")
            env.trash(addressID); check("공통 정보 휴지통", env.globalFeatures("address").isEmpty)
            env.restore(addressID); check("공통 정보 복원", env.globalFeatures("address").first?["id"]?.uuid == addressID)
            env.undo(); check("공통 정보 Undo", env.globalFeatures("address").isEmpty)
            env.redo(); check("공통 정보 Redo", env.globalFeatures("address").count == 1)
            let target = env.addProjectLevel()
            await env.waitForLevelDrawing()
            check("층 단위 가져오기도 공통 주소를 함께 보존", env.importLevel(migration.levels[0], into: target, metadata: migration)
                && env.globalFeatures("address").contains { $0["id"]?.uuid == oldID })
            let beforeRepeat = env.globalFeatures("address")
            check("동일 UUID·내용의 공통 정보는 재사용", env.importLevel(migration.levels[0], into: target, metadata: migration)
                && env.globalFeatures("address") == beforeRepeat)
            var uppercase = migration
            uppercase.globalGeoJSON["address.geojson"]![0]["id"] = .string(oldID.uuidString.uppercased())
            check("UUID 대소문자만 다른 공통 정보도 재사용", env.importLevel(uppercase.levels[0], into: target, metadata: uppercase)
                && env.globalFeatures("address") == beforeRepeat)
            for type in ["address", "building", "occupant", "relationship"] {
                let recordID = UUID()
                let original = IMDFTestFixtures.feature(type, id: recordID, properties: ["custom": .string("현재 값")])
                env.buildingProject.globalGeoJSON[type + ".geojson", default: []].append(original)
                var incoming = migration
                var changed = original
                changed["properties"]?["custom"] = .string("사본의 다른 값")
                incoming.globalGeoJSON[type + ".geojson", default: []].append(changed)
                // A preceding new record must not leak into the target when a later conflict aborts.
                incoming.globalGeoJSON["address.geojson", default: []].insert(
                    IMDFTestFixtures.feature("address", properties: ["address": .string("부분 반영 금지")]), at: 0)
                var changedFloor = incoming.levels[0]
                changedFloor.info.svg = "충돌 시 교체하면 안 되는 도면"
                let beforeConflict = env.projectContents
                let documentBefore = env.document?.fingerprint
                let snapshotBefore = env.snapshot
                let undoBefore = env.undoStack.undoEntries, redoBefore = env.undoStack.redoEntries
                let modeBefore = env.mode
                check("\(type) 동일 UUID 내용 충돌은 가져오기 중단", !env.importLevel(changedFloor, into: target, metadata: incoming))
                check("\(type) 충돌 시 층·공통 정보·도면·모드 보존", env.projectContents == beforeConflict
                    && env.document?.fingerprint == documentBefore && env.mode == modeBefore
                    && env.snapshot == snapshotBefore && env.undoStack.undoEntries == undoBefore
                    && env.undoStack.redoEntries == redoBefore)
                check("\(type) 충돌 UUID 안내", env.banner?.text.contains(recordID.uuidString.lowercased()) == true)
                env.buildingProject.globalGeoJSON[type + ".geojson"]?.removeAll { $0["id"]?.uuid == recordID }
            }
            env.updateProperty("language", value: .string("en"), in: env.manifestEditorID)
            check("Manifest 입력 경로 단일화", env.buildingProject.manifest["language"]?.string == "en")
            check("공통 주소를 모든 층의 참조 선택창에서 조회", env.referenceChoices(.address).contains { $0.id == addressID.uuidString.lowercased() })
            let english = FeatureGroup(featureType: .building, serialNumber: "building", memberIDs: [])
            var localized = english; localized.properties["name"] = .json(.object(["en": .string("Library"), "ja": .string("図書館")]))
            check("한국어를 고정 필수 언어로 취급하지 않음", PropertyRules.problem(.building, "name", in: localized) == nil)
            var manifestA = FeatureGroup(featureType: .manifest, serialNumber: "manifest-001", memberIDs: [])
            manifestA.properties["language"] = .string("ko")
            var conflict = BuildingProject(levels: [oldLevel])
            conflict.manifest = .object(["language": .string("en")]); conflict.levels[0].editing.features.insert(manifestA)
            conflict.migrateGlobalMetadata()
            check("이전 Manifest 충돌 보존·공통값 무단 덮어쓰기 없음", conflict.manifest["language"]?.string == "en" && conflict.legacyManifests?.count == 1 && conflict.manifestConflictsResolved == false)
            file.buildingProject = conflict
            do { _ = try IMDFArchive.build(projectData: file.encoded(), documents: [:]); check("미해결 Manifest 충돌 내보내기 차단", false) }
            catch let b as IMDFArchive.Blocked { check("미해결 Manifest 충돌 내보내기 차단", b.messages.contains { $0.contains("Manifest 값이") }) }
            check("구버전이 v7 새 속성을 조용히 삭제하지 않도록 형식 상향", ProjectFile.currentVersion == 7)
        } catch { check("IMDF 준수 테스트 실행", false); print(error) }
        print("== IMDF Compliance: \(total - failures)/\(total) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
