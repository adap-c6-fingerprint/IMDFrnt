import Foundation

@MainActor
enum MetadataReviewSelfTest {
    static func run(_ check: (String, Bool) -> Void) async throws {
        func named(_ labels: [String: ProjectJSON]) -> FeatureGroup {
            var feature = FeatureGroup(featureType: .unit, serialNumber: "name-fallback", memberIDs: [])
            feature.properties["name"] = .json(.object(labels))
            return feature
        }
        check("#80 공백 라벨 건너뛰고 다른 언어 표시", AppEnvironment.nameText(of: named([
            "fr": .string("  \n\t"), "ja": .string(" 図書館\n")])) == "図書館")
        check("#80 비문자열·빈 라벨 모두 안전", AppEnvironment.nameText(of: named([
            "de": .number(1), "fr": .string("\n "), "ko": .null])).isEmpty)
        check("#80 한국어·영어 우선순위 및 줄바꿈 제거", AppEnvironment.nameText(of: named([
            "de": .string("Bibliothek"), "ko-KR": .string("\n도서관 "), "en": .string(" Library\n")])) == "도서관(Library)")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MetadataReview-\(UUID())")
        let suite = "MetadataReview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject()
        env.layers.addPropertyTypeLayer(.unit)
        check("#80 메타데이터 미편집 시 활성 레이어 내보내기 유지", env.individualExportType == .unit)
        for type in IMDFFeatureType.globalMetadataTypes + [.manifest] {
            env.openMetadataEditor(type)
            check("#80 \(type.rawValue) 편집기가 Unit보다 개별 내보내기 우선", env.individualExportType == type && env.layers.activePropertyType == .unit)
        }
        env.metadataEditorType = nil
        check("#80 편집기 닫으면 기존 Unit 내보내기 복원", env.individualExportType == .unit)
        env.layers.close(env.layers.layer(for: .unit)!.id)
        check("#80 내보낼 대상 없는 경우 유지", env.individualExportType == nil)

        let a = UUID(), b = UUID(), addressA = UUID(), addressB = UUID(), directAddress = UUID()
        func ref(_ id: UUID) -> ProjectJSON { .string(id.uuidString.lowercased()) }
        let buildings = [
            IMDFTestFixtures.feature("building", id: a, properties: ["address_id": ref(addressA)]),
            IMDFTestFixtures.feature("building", id: b, properties: ["address_id": ref(addressB)])]
        let addresses = [addressA, addressB, directAddress].map {
            IMDFTestFixtures.feature("address", id: $0, properties: ["address": .string($0.uuidString)])
        }
        var source = ProjectLevel(info: ProjectLevelInfo(name: "선택 건물 A", ordinal: 0))
        source.geoJSON["level.geojson"] = [IMDFTestFixtures.feature("level", id: source.id,
            properties: ["building_ids": .array([.string(a.uuidString.uppercased())])])]
        var section = FeatureGroup(featureType: .section, serialNumber: "section-address", memberIDs: [])
        section.properties["address_id"] = .string(directAddress.uuidString.uppercased())
        // Explicit Building prevents unrelated implicit-default branches in this multi-Building fixture.
        section.properties["building_ids"] = .stringArray([a.uuidString.lowercased()])
        source.editing.features.insert(section)
        let other = ProjectLevel(info: ProjectLevelInfo(name: "다른 건물 B", ordinal: 1))
        var incoming = BuildingProject(levels: [source, other])
        incoming.globalGeoJSON["building.geojson"] = buildings
        incoming.globalGeoJSON["address.geojson"] = addresses
        func selected(_ project: BuildingProject, venue: Bool = false, footprint: Bool = false) -> [String: [ProjectJSON]] {
            LevelImportMetadata.records(in: project, source: source, targetID: source.id,
                includingVenue: venue, includingFootprint: footprint)
        }
        func ids(_ values: [String: [ProjectJSON]], _ name: String) -> Set<UUID> {
            Set((values[name + ".geojson"] ?? []).compactMap { $0["id"]?.uuid })
        }
        let scoped = selected(incoming)
        check("#80 선택 층 Building만 포함·UUID 대소문자 무시", ids(scoped, "building") == [a])
        check("#80 Building 경유 및 편집 도형 직접 참조 Address 보존", ids(scoped, "address") == [addressA, directAddress])
        incoming.globalGeoJSON["venue.geojson"] = [IMDFTestFixtures.feature("venue", properties: ["address_id": ref(addressB)])]
        check("#80 실제 복사하는 Venue의 주소만 추가", ids(selected(incoming, venue: true), "address").contains(addressB)
            && !ids(selected(incoming), "address").contains(addressB))
        var footprint = FeatureGroup(featureType: .footprint, serialNumber: "공통 건물 B", memberIDs: [])
        footprint.properties["building_ids"] = .stringArray([b.uuidString.lowercased()])
        incoming.sharedFootprint = SharedFootprint(features: [footprint])
        check("#80 실제 복사하는 공통 Footprint의 건물·주소 종속 보존", ids(selected(incoming, footprint: true), "building") == [a, b]
            && ids(selected(incoming, footprint: true), "address") == [addressA, addressB, directAddress]
            && ids(selected(incoming), "building") == [a])
        let originalFootprint = IMDFTestFixtures.feature("footprint", id: footprint.id,
            properties: ["building_ids": .array([ref(b)])])
        incoming.sharedFootprint!.originals[footprint.id.uuidString] = originalFootprint
        incoming.globalGeoJSON["footprint.geojson"] = [originalFootprint]
        footprint.properties["building_ids"] = .stringArray([a.uuidString.lowercased()])
        incoming.sharedFootprint!.features = [footprint]
        check("#80 Footprint의 이전 원본 대신 현재 건물 참조 사용", ids(selected(incoming, footprint: true), "building") == [a]
            && ids(selected(incoming, footprint: true), "address") == [addressA, directAddress])
        incoming.sharedFootprint = nil
        incoming.globalGeoJSON["footprint.geojson"] = nil
        let anchorID = UUID(), otherAnchor = UUID()
        source.geoJSON["anchor.geojson"] = [IMDFTestFixtures.feature("anchor", id: anchorID, properties: [:])]
        incoming.levels[0] = source
        incoming.globalGeoJSON["occupant.geojson"] = [anchorID, otherAnchor].map {
            IMDFTestFixtures.feature("occupant", properties: ["anchor_id": ref($0)])
        }
        incoming.globalGeoJSON["relationship.geojson"] = [anchorID, otherAnchor].map {
            IMDFTestFixtures.feature("relationship", properties: ["origin": .object(["id": ref($0)]), "destination": .null])
        }
        check("#80 Occupant·Relationship 기존 선택 층 필터 유지", selected(incoming)["occupant.geojson"]?.count == 1
            && selected(incoming)["relationship.geojson"]?.count == 1)
        var occupantAddress = incoming
        occupantAddress.globalGeoJSON["occupant.geojson"]![0]["properties"]?["address_id"] = ref(addressB)
        check("#80 선택 층 Occupant가 직접 참조하는 주소도 보존", ids(selected(occupantAddress), "address").contains(addressB))
        var legacy = incoming; legacy.levels = [source]
        check("#80 구형 단일 층의 미연결 공통 정보 보존", selected(legacy) == legacy.globalGeoJSON)
        var implicit = BuildingProject(levels: [source, other])
        implicit.globalGeoJSON["building.geojson"] = [IMDFTestFixtures.feature("building", id: a, properties: [:])]
        implicit.globalGeoJSON["address.geojson"] = [addresses[0]]
        check("#80 단일 Building·Address의 기존 암시적 기본값 보존", ids(selected(implicit), "address") == [addressA])
        var unlinked = ProjectLevel(info: ProjectLevelInfo(name: "기본 참조", ordinal: 0))
        unlinked.editing.features.insert(FeatureGroup(featureType: .level, serialNumber: "level-default", memberIDs: []))
        let implicitRecords = LevelImportMetadata.records(in: implicit, source: unlinked, targetID: unlinked.id,
            includingVenue: false, includingFootprint: false)
        check("#80 참조가 비어 있는 편집 Level의 단일 건물·주소 기본값 보존", ids(implicitRecords, "building") == [a]
            && ids(implicitRecords, "address") == [addressA])

        // Exercise the production transaction, not only the selector. Unrelated UUID conflicts must be ignored.
        let target = env.addProjectLevel()
        await env.waitForLevelDrawing()
        env.buildingProject.globalGeoJSON["venue.geojson"] = [IMDFTestFixtures.feature("venue", properties: [:])]
        var unrelated = buildings[1]; unrelated["properties"]?["name"] = .object(["ko": .string("현재 B")])
        var unrelatedAddress = addresses[1]; unrelatedAddress["properties"]?["address"] = .string("현재 B 주소")
        env.buildingProject.globalGeoJSON["building.geojson"] = [unrelated]
        env.buildingProject.globalGeoJSON["address.geojson"] = [unrelatedAddress]
        let before = env.projectContents
        check("#80 무관한 건물·주소 충돌은 층 가져오기를 막지 않음", env.importLevel(source, into: target, metadata: incoming))
        await env.waitForLevelDrawing()
        check("#80 관련 공통 정보 추가·기존 무관 정보 덮어쓰기 없음", env.buildingProject.globalGeoJSON["building.geojson"] == [unrelated, buildings[0]]
            && Set(env.buildingProject.globalGeoJSON["address.geojson"] ?? []) == Set([unrelatedAddress, addresses[0], addresses[2]]))
        let imported = env.projectContents
        env.undo()
        check("#80 범위 지정 가져오기 Undo는 공통 정보·층 전체 복구", env.projectContents == before)
        env.redo()
        await env.waitForLevelDrawing()
        check("#80 범위 지정 가져오기 Redo", env.projectContents == imported)
        let restored = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded()).commonProject()
        check("#80 필요한 공통 정보 저장 왕복", restored.globalGeoJSON == env.buildingProject.globalGeoJSON)
        var conflicting = incoming
        conflicting.globalGeoJSON["building.geojson"]![0]["properties"]?["category"] = .string("다른 값")
        let beforeConflict = env.projectContents, undo = env.undoStack.undoEntries, redo = env.undoStack.redoEntries
        check("#80 실제 참조 Building 충돌은 여전히 전체 중단", !env.importLevel(source, into: target, metadata: conflicting)
            && env.projectContents == beforeConflict && env.undoStack.undoEntries == undo && env.undoStack.redoEntries == redo)
        conflicting = incoming
        conflicting.globalGeoJSON["address.geojson"]![0]["properties"]?["address"] = .string("다른 주소")
        check("#80 간접 참조 Address 충돌도 전체 중단", !env.importLevel(source, into: target, metadata: conflicting)
            && env.projectContents == beforeConflict && env.undoStack.undoEntries == undo)
        conflicting = incoming
        var duplicate = buildings[0]; duplicate["properties"]?["category"] = .string("중복 내용 충돌")
        conflicting.globalGeoJSON["building.geojson"]!.append(duplicate)
        check("#80 도달 가능한 원본 내 중복 UUID도 기존 충돌 검사 유지", !env.importLevel(source, into: target, metadata: conflicting)
            && env.projectContents == beforeConflict && env.undoStack.undoEntries == undo)
    }
}
