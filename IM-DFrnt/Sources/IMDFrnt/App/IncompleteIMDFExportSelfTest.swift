import Foundation

enum IncompleteIMDFExportSelfTest {
    static func run(_ check: (String, Bool) -> Void) throws {
        let now = Date(timeIntervalSince1970: 0)
        func data(_ project: BuildingProject) throws -> Data {
            var file = ProjectFile.empty()
            file.buildingProject = project
            return try file.encoded()
        }
        func build(_ bytes: Data, allow: Bool = false) throws -> IMDFArchive.Output {
            try IMDFArchive.build(projectData: bytes, documents: [:], now: now, allowValidationErrors: allow)
        }
        let valid = IMDFTestFixtures.validProject()
        let original = try data(valid)
        let strict = try build(original)
        let candidate = try build(original, allow: true)
        check("#112 정상 ZIP은 확인용 생성에서도 바이트 유지", candidate.files == strict.files && candidate.validationErrors.isEmpty)

        var incomplete = valid
        incomplete.globalGeoJSON["unit.geojson"]![0]["geometry"] = IMDFTestFixtures.polygon(129, 36, 129.0005, 36.001)
        incomplete.globalGeoJSON["amenity.geojson"] = [IMDFTestFixtures.feature("amenity", properties: [
            "category": .string("information"), "unit_ids": .null
        ], geometry: IMDFTestFixtures.point(129.0002, 36.0002))]
        let before = incomplete
        let bytes = try data(incomplete)
        do { _ = try build(bytes); check("#112 기본 빌더는 완결성 위반을 계속 차단", false) }
        catch let error as IMDFArchive.Blocked {
            check("#112 기본 빌더는 완결성 위반을 계속 차단", error.messages.contains { $0.contains("합집합") })
        }
        let output = try build(bytes, allow: true)
        check("#112 빈틈과 누락 Unit 참조를 함께 확인 목록에 보존", output.validationErrors.contains { $0.contains("합집합") }
              && output.validationErrors.contains { $0.contains("unit_ids") })
        for type in ["unit", "amenity", "level"] {
            let features = try ProjectJSON.parse(output.files[type + ".geojson"]!)["features"]?.array
            check("#112 \(type) 도형·UUID·미입력 속성을 임의 수정하지 않음", features == incomplete.globalGeoJSON[type + ".geojson"])
        }
        check("#112 후보 생성만으로 원본 프로젝트·UUID 대장 변경 없음", incomplete == before)
        check("#112 강제 후보도 일반 검사에서 기존 오류 유지", IMDFValidation.check(files: output.files).errors == output.validationErrors)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IncompleteIMDF-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = directory.appendingPathComponent("incomplete.zip")
        try IMDFArchive.writeZip(output.files, to: zip)
        let imported = try IMDFImporter.load(zip)
        check("#112 불완전 IMDF 실제 ZIP 저장·재가져오기", imported.files["unit.geojson"]?["features"]?.array == incomplete.globalGeoJSON["unit.geojson"])
        do {
            _ = try ClientDataset.build(projectData: bytes, datasetID: "incomplete-test", documents: [:], now: now)
            check("#112 지도+길찾기 묶음은 엄격한 검증 유지", false)
        } catch let error as ClientDataset.Blocked {
            check("#112 지도+길찾기 묶음은 엄격한 검증 유지", error.messages.contains { $0.contains("합집합") })
        }

        var authored = ProjectLevel(info: ProjectLevelInfo(name: "미완성 층", ordinal: 0))
        authored.info.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "A")
        authored.info.anchors.add(local: LocalPoint(100, 0), geo: GeoPoint(longitude: 129.001, latitude: 36), label: "B")
        authored.info.anchors.add(local: LocalPoint(0, 100), geo: GeoPoint(longitude: 129, latitude: 36.001), label: "C")
        var unit = FeatureGroup(featureType: .unit, serialNumber: "unit-001", memberIDs: [])
        unit.polygonRings = [[LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)]]
        authored.editing.features.insert(unit)
        let partial = IMDFTestFixtures.authored([authored])
        let partialOutput = try build(data(partial), allow: true)
        check("#112 Level 미작도 사전 검사도 확인 후 출력 가능", partialOutput.validationErrors.contains { $0.contains("level 다각형이 없습니다") }
              && partialOutput.files["unit.geojson"] != nil)

        authored.info.anchors = AnchorStore()
        do { _ = try build(data(IMDFTestFixtures.authored([authored])), allow: true); check("#112 GPS 변환 불가로 좌표 유실 시 계속 차단", false) }
        catch let error as IMDFArchive.Blocked {
            check("#112 GPS 변환 불가로 좌표 유실 시 계속 차단", error.messages.contains { $0.contains("Anchor") })
        }
        var corrupt = valid
        corrupt.extraFiles["broken.geojson"] = .object(["type": .string("FeatureCollection"), "features": .string("broken")])
        do { _ = try build(data(corrupt), allow: true); check("#112 손상된 원본 컬렉션은 강제 출력에서도 차단", false) }
        catch let error as IMDFArchive.Blocked {
            check("#112 손상된 원본 컬렉션은 강제 출력에서도 차단", error.messages.contains { $0.contains("broken.geojson") })
        }
        corrupt = valid
        corrupt.extraFiles["../outside.json"] = .object([:])
        do { _ = try build(data(corrupt), allow: true); check("#112 ZIP 밖으로 나가는 파일 경로는 계속 차단", false) }
        catch let error as IMDFArchive.Blocked {
            check("#112 ZIP 밖으로 나가는 파일 경로는 계속 차단", error.messages.contains { $0.contains("파일명") })
        }
        do { _ = try build(Data("not JSON".utf8), allow: true); check("#112 읽을 수 없는 프로젝트는 계속 차단", false) }
        catch { check("#112 읽을 수 없는 프로젝트는 계속 차단", true) }
    }
}
