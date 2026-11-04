import Foundation

@MainActor
enum AmenityUnitSelectionSelfTest {
    static func run(_ check: (String, Bool) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AmenityUnit-\(UUID())")
        let suite = "AmenityUnit-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject(); env.openSample()
        func box(_ x: Double, _ y: Double, _ size: Double) -> [LocalPoint] {
            [LocalPoint(x, y), LocalPoint(x + size, y), LocalPoint(x + size, y + size), LocalPoint(x, y + size)]
        }
        func unit(_ serial: String, _ name: String, _ ring: [LocalPoint]) -> FeatureGroup {
            var f = FeatureGroup(featureType: .unit, serialNumber: serial, memberIDs: [])
            f.polygonRings = [ring]; f.properties["name"] = .localized(en: "", ko: name)
            return f
        }
        var amenity = FeatureGroup(featureType: .amenity, serialNumber: "amenity-test", memberIDs: [])
        amenity.drawnVertices = [LocalPoint(5, 5)]
        amenity.properties["category"] = .string("drinkingwater")
        let inside = unit("unit-inside", "자료실", box(0, 0, 100))
        let near = unit("unit-near", "", box(6, 4, 2))
        let far = unit("unit-far", "먼 방", box(20, 4, 2))
        var trash = unit("unit-trash", "휴지통", box(0, 0, 10)); trash.isInTrash = true
        let allocated = UUID()
        env.ids.adopt(inside.id, id: allocated)
        for f in [far, near, inside, trash, amenity] { env.features.insert(f) }
        var other = ProjectLevel(info: ProjectLevelInfo(name: "다른 층", ordinal: 1))
        let upstairs = unit("unit-upstairs", "윗층", box(0, 0, 10))
        other.editing.features.insert(upstairs); env.buildingProject.levels.append(other)
        let before = env.projectContents
        let choices = env.amenityUnitChoices(for: amenity)
        let allocatedID = allocated.uuidString.lowercased(), nearID = near.id.uuidString.lowercased()
        check("#113 포함 Unit 먼저·중심이 아닌 경계 거리순·다른 층은 뒤", choices.map(\.id) == [allocatedID, nearID, far.id.uuidString.lowercased(), upstairs.id.uuidString.lowercased()])
        check("#113 기존 export UUID·이름·일련번호·층·전체 UUID 표시", choices[0].label.contains("자료실") && choices[0].label.contains("unit-inside") && choices[0].label.contains(env.activeLevel!.info.name) && choices[0].label.contains(allocatedID))
        check("#113 이름 없는 Unit도 ID로 선택 가능·휴지통 제외", choices[1].label.contains(nearID) && !choices.contains { $0.id == trash.id.uuidString.lowercased() })
        check("#113 후보 조회는 프로젝트/UUID 대장 변경 없음", env.projectContents == before)
        check("#113 이름·UUID 검색 지원", SearchablePicker.filter(choices.map(\.id), query: "자료실", label: { id in choices.first { $0.id == id }!.label }) == [allocatedID])
        check("#113 구멍 안 점은 포함으로 오인하지 않음", AmenityUnitChoice.distance(from: LocalPoint(5, 5), to: [box(0, 0, 10), box(4, 4, 2)]) == 1)
        check("#113 MultiPolygon의 섬 안 점 포함", AmenityUnitChoice.distance(from: LocalPoint(25, 5), to: [box(0, 0, 10), box(20, 0, 10)]) == 0)
        check("#113 경계·빈 도형·점 없음 안전", AmenityUnitChoice.distance(from: LocalPoint(0, 5), to: [box(0, 0, 10)]) == 0 && AmenityUnitChoice.distance(from: LocalPoint(0, 0), to: []) == nil && AmenityUnitChoice.distance(from: nil, to: [box(0, 0, 10)]) == nil)

        let unknown = UUID().uuidString.uppercased()
        env.updateProperty("unit_ids", value: .stringArray([unknown]), in: amenity.id)
        env.setAmenityUnit(allocatedID, selected: true, for: amenity.id)
        env.setAmenityUnit(nearID, selected: true, for: amenity.id)
        env.setAmenityUnit(allocatedID.uppercased(), selected: true, for: amenity.id)
        check("#113 복수 선택·기존 알 수 없는 참조 보존·대소문자 중복 방지", env.features.feature(amenity.id)!.value("unit_ids") == .stringArray([unknown, allocatedID, nearID]))
        env.setAmenityUnit(unknown.lowercased(), selected: false, for: amenity.id)
        let linked = env.features.feature(amenity.id)!
        check("#113 명시한 참조만 해제", linked.value("unit_ids") == .stringArray([allocatedID, nearID]))
        let decoded = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded())
        check("#113 기존 프로젝트 형식으로 저장·재열기 참조 유지", decoded.commonProject().levels.first { $0.id == env.routingFloorID }!.editing.features.feature(amenity.id)?.value("unit_ids") == linked.value("unit_ids"))
        var ids = env.ids
        let exporter = GeoJSONExporter(document: env.document!, segmentation: env.segmentation, georeferencer: env.georeferencer)
        let output = exporter.serialize(linked, ids: &ids, serialToUUID: [:])
        check("#113 기존 IMDF 인코더가 Unit UUID 배열 출력", (output["properties"] as? [String: Any])?["unit_ids"] as? [String] == [allocatedID, nearID])
        env.setAmenityUnit(allocatedID, selected: false, for: amenity.id)
        env.setAmenityUnit(nearID, selected: false, for: amenity.id)
        check("#113 전체 연결 해제는 null", env.features.feature(amenity.id)!.value("unit_ids") == .null)
        env.undo(); check("#113 연결 변경 Undo", env.features.feature(amenity.id)!.value("unit_ids") != .null)
        env.redo(); check("#113 연결 변경 Redo", env.features.feature(amenity.id)!.value("unit_ids") == .null)
        env.setAmenityUnit(nearID, selected: true, for: inside.id)
        check("#113 Unit 등 다른 Feature 변경 금지", env.features.feature(inside.id)!.value("unit_ids") == .null)

        let projection = IMDFCoordinateSpace(west: 129, north: 36, unitsPerLongitudeDegree: 100_000, unitsPerLatitudeDegree: 100_000, padding: 0)
        let current = env.buildingProject.levels.firstIndex { $0.id == env.routingFloorID }!
        env.buildingProject.levels[current].info.imdfCoordinates = projection
        func rawUnit(_ id: UUID, x: Double) -> ProjectJSON {
            let ring = box(x, 4, 1).map { projection.geoPoint(for: $0).geoJSONArray }
            let coordinates = (ring + [ring[0]]).map { ProjectJSON.array($0.map { .number(Decimal($0)) }) }
            return IMDFTestFixtures.feature("unit", id: id, properties: ["name": .object(["ja": .string("原本")]), "level_id": .string(env.routingFloorID!.uuidString)], geometry: .object(["type": .string("Polygon"), "coordinates": .array([.array(coordinates)])]))
        }
        let imported = UUID(), global = UUID()
        env.buildingProject.levels[current].geoJSON["unit.geojson"] = [rawUnit(imported, x: 8), rawUnit(allocated, x: 50)]
        env.buildingProject.globalGeoJSON["unit.geojson"] = [rawUnit(global, x: 10), rawUnit(trash.id, x: 0)]
        let originals = env.amenityUnitChoices(for: amenity)
        check("#113 가져온 Unit·공통 Unit도 같은 좌표계로 정렬·편집본 중복 제외", originals.prefix(5).map(\.id) == [allocatedID, nearID, imported.uuidString.lowercased(), global.uuidString.lowercased(), far.id.uuidString.lowercased()])
        check("#113 가져온 Unit 다른 언어 이름 표시", originals.first { $0.id == imported.uuidString.lowercased() }?.label.contains("原本") == true)
        check("#113 공통 원본이 남아도 휴지통 Unit 제외", !originals.contains { $0.id == trash.id.uuidString.lowercased() })
        var rawAmenity = FeatureGroup(featureType: .amenity, serialNumber: "amenity-raw-unit", memberIDs: [])
        rawAmenity.drawnVertices = [LocalPoint(8.5, 4.5)]
        var sharedAmenity = FeatureGroup(featureType: .amenity, serialNumber: "amenity-global-unit", memberIDs: [])
        sharedAmenity.drawnVertices = [LocalPoint(10.5, 4.5)]
        env.features.insert(rawAmenity); env.features.insert(sharedAmenity)
        let rawBefore = env.activeLevel!.geoJSON, globalBefore = env.buildingProject.globalGeoJSON
        env.connectAmenitiesToContainingUnits([rawAmenity.id, sharedAmenity.id])
        check("#113 일괄 연결은 가져온/공통 Unit UUID 포함·원본 GeoJSON 보존", Set(env.features.feature(rawAmenity.id)!.value("unit_ids").projectJSON.array.compactMap(\.string)) == [allocatedID, imported.uuidString.lowercased()] && Set(env.features.feature(sharedAmenity.id)!.value("unit_ids").projectJSON.array.compactMap(\.string)) == [allocatedID, global.uuidString.lowercased()] && env.activeLevel!.geoJSON == rawBefore && env.buildingProject.globalGeoJSON == globalBefore)
        // Original geographic Unit data is still in the native drawing projection after Footprint alignment.
        env.buildingProject.levels[current].info.footprintGeoAnchors = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)].map {
            AnchorPair(local: $0, geo: projection.geoPoint(for: LocalPoint($0.x + 1000, $0.y)), label: "정렬 회귀")
        }
        check("#113 Footprint 정렬 뒤에도 원본 Unit 포함 판정은 native 좌표 유지", env.amenityUnitChoices(for: rawAmenity).first { $0.id == imported.uuidString.lowercased() }?.distance == 0)
        var nativeAnchors = AnchorStore()
        for point in [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)] {
            nativeAnchors.add(local: point, geo: projection.geoPoint(for: point), label: "원본 좌표")
        }
        env.anchors = nativeAnchors
        env.buildingProject.levels[current].info.imdfCoordinates = nil
        var svgAmenity = FeatureGroup(featureType: .amenity, serialNumber: "amenity-native-svg", memberIDs: [])
        svgAmenity.drawnVertices = [LocalPoint(8.5, 4.5)]
        env.features.insert(svgAmenity)
        env.connectAmenitiesToContainingUnits([svgAmenity.id])
        check("#113 SVG 원본 GPS와 Footprint 정렬이 달라도 포함 Unit 정확히 연결", env.features.feature(svgAmenity.id)!.value("unit_ids").projectJSON.array.compactMap(\.string).contains(imported.uuidString.lowercased()))
        try bulkConnection(check, env: env)
    }

    private static func bulkConnection(_ check: (String, Bool) -> Void, env: AppEnvironment) throws {
        try env.createNewProject(); env.openSample()
        func box(_ x: Double, _ size: Double) -> [LocalPoint] {
            [LocalPoint(x, 0), LocalPoint(x + size, 0), LocalPoint(x + size, size), LocalPoint(x, size)]
        }
        var a = FeatureGroup(featureType: .unit, serialNumber: "unit-a", memberIDs: [])
        a.polygonRings = [box(0, 10), [LocalPoint(4, 4), LocalPoint(6, 4), LocalPoint(6, 6), LocalPoint(4, 6)], box(20, 10)]
        a.multiPolygon = true
        var b = FeatureGroup(featureType: .unit, serialNumber: "unit-b", memberIDs: [])
        b.polygonRings = [box(30, 10)]
        var trashed = FeatureGroup(featureType: .unit, serialNumber: "unit-deleted", memberIDs: [])
        trashed.polygonRings = [box(90, 20)]; trashed.isInTrash = true
        let exportID = UUID(), unknown = UUID().uuidString.uppercased()
        env.ids.adopt(a.id, id: exportID)
        for unit in [a, b, trashed] { env.features.insert(unit) }
        var other = ProjectLevel(info: ProjectLevelInfo(name: "다른 층", ordinal: 1))
        var upstairs = FeatureGroup(featureType: .unit, serialNumber: "unit-other-level", memberIDs: [])
        upstairs.polygonRings = [box(90, 20)]
        other.editing.features.insert(upstairs); env.buildingProject.levels.append(other)
        func amenity(_ name: String, _ point: LocalPoint?) -> FeatureGroup {
            var f = FeatureGroup(featureType: .amenity, serialNumber: name, memberIDs: [])
            f.drawnVertices = point.map { [$0] }
            f.properties["category"] = .string("drinkingwater")
            return f
        }
        var first = amenity("amenity-in-a", LocalPoint(2, 2)); first.properties["unit_ids"] = .stringArray([unknown])
        let island = amenity("amenity-island", LocalPoint(25, 2))
        let boundary = amenity("amenity-boundary", LocalPoint(30, 2))
        let hole = amenity("amenity-hole", LocalPoint(5, 5))
        let outside = amenity("amenity-outside", LocalPoint(100, 2))
        let missing = amenity("amenity-no-point", nil)
        let hidden = amenity("amenity-filtered-out", LocalPoint(35, 2))
        var deleted = amenity("amenity-trash", LocalPoint(2, 2)); deleted.isInTrash = true
        var existing = amenity("amenity-existing", LocalPoint(2, 2)); existing.properties["unit_ids"] = .stringArray([exportID.uuidString.uppercased()])
        var invalid = amenity("amenity-invalid", LocalPoint(2, 2)); invalid.properties["unit_ids"] = .json(.array([.number(42)]))
        let targets = [first, island, boundary, hole, outside, missing, deleted, existing, invalid]
        for f in targets + [hidden] { env.features.insert(f) }
        let before = env.projectContents, undoCount = env.undoStack.undoEntries.count
        env.connectAmenitiesToContainingUnits(targets.map(\.id) + [first.id, a.id, UUID()])
        func links(_ f: FeatureGroup) -> PropertyValue { env.features.feature(f.id)!.value("unit_ids") }
        let aid = exportID.uuidString.lowercased(), bid = b.id.uuidString.lowercased()
        check("#113 일괄 포함 연결은 기존 참조 유지·원본 export UUID 추가", links(first) == .stringArray([unknown, aid]))
        check("#113 일괄 연결 MultiPolygon 섬·경계의 복수 Unit 포함", links(island) == .stringArray([aid]) && links(boundary) == .stringArray([aid, bid].sorted()))
        check("#113 구멍·다른 층·휴지통 Unit·좌표 없는 Amenity는 추정 연결하지 않음", links(hole) == .null && links(outside) == .null && links(missing) == .null)
        check("#113 화면 필터 제외·휴지통 Amenity·기존 대소문자 참조·비문자열 배열 보존", links(hidden) == .null && links(deleted) == .null && links(existing) == existing.value("unit_ids") && links(invalid) == invalid.value("unit_ids"))
        check("#113 일괄 작업은 Undo 한 칸·결과 요약", env.undoStack.undoEntries.count == undoCount + 1 && env.banner?.text.contains("3개 추가") == true && env.banner?.text.contains("4개 건너뜀") == true)
        let after = env.projectContents
        check("#113 일괄 연결은 Unit 도형·UUID 대장·다른 층 보존", after.levels[0].editing.ids == before.levels[0].editing.ids && after.levels[0].editing.features.features(ofType: .unit, includingTrashed: true) == before.levels[0].editing.features.features(ofType: .unit, includingTrashed: true) && after.levels[1] == before.levels[1])
        env.undo(); check("#113 일괄 연결 한 번 Undo로 전체 복원", env.projectContents == before)
        env.redo(); check("#113 일괄 연결 Redo로 전체 재적용", env.projectContents == after)
        let nextUndo = env.undoStack.undoEntries.count
        env.connectAmenitiesToContainingUnits(targets.map(\.id))
        check("#113 재실행은 참조 중복·Undo 칸 추가 없음", env.projectContents == after && env.undoStack.undoEntries.count == nextUndo)
        let saved = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded()).commonProject()
        check("#113 일괄 참조 기존 v9 저장 왕복", saved == after)
        var ids = env.ids
        let exporter = GeoJSONExporter(document: env.document!, segmentation: env.segmentation, georeferencer: env.georeferencer)
        let output = exporter.serialize(env.features.feature(first.id)!, ids: &ids, serialToUUID: [:])
        check("#113 일괄 참조 기존 IMDF 배열 직렬화", (output["properties"] as? [String: Any])?["unit_ids"] as? [String] == [unknown, aid])
        check("#113 잘못된 구멍이 있으면 바깥 링만으로 포함 추정 금지", AmenityUnitChoice.distance(from: LocalPoint(2, 2), to: [box(0, 10), []]) == nil)
    }
}
