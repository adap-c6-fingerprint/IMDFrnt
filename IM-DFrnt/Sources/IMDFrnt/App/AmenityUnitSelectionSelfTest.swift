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
    }
}
