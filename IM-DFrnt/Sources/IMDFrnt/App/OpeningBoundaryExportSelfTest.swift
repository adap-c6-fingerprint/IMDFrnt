import Foundation

enum OpeningBoundaryExportSelfTest {
    static func run(_ check: (String, Bool) -> Void) throws {
        let boundaryMessage = "Opening은 같은 Level의 Unit 경계 위에 있어야 합니다."
        let now = Date(timeIntervalSince1970: 0)
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> ProjectJSON {
            .object(["type": .string("LineString"), "coordinates": .array([
                .array([.number(Decimal(x1)), .number(Decimal(y1))]),
                .array([.number(Decimal(x2)), .number(Decimal(y2))])])])
        }
        func data(_ project: BuildingProject) throws -> Data {
            var file = ProjectFile.empty(); file.buildingProject = project
            return try file.encoded()
        }
        func build(_ bytes: Data, _ policy: IMDFValidation.OpeningBoundaryPolicy = .strict) throws -> IMDFArchive.Output {
            try IMDFArchive.build(projectData: bytes, documents: [:], now: now, openingBoundaryPolicy: policy)
        }
        let valid = IMDFTestFixtures.validProject()
        let strict = try build(data(valid))
        let sandbox = try build(data(valid), .allowMismatchForSandbox)
        check("#82 정상 파일은 일반·Sandbox 출력 바이트가 같음", strict.files == sandbox.files)
        check("#82 Sandbox 출력에 검사 전용 안내 유지", sandbox.warnings.contains { $0.contains("Sandbox 검사용 파일") })

        var mismatch = valid
        let opening = IMDFTestFixtures.feature("opening", properties: [
            "category": .string("pedestrian"), "level_id": valid.globalGeoJSON["level.geojson"]![0]["id"]!
        ], geometry: line(129.0002, 36.0005, 129.0008, 36.0005))
        mismatch.globalGeoJSON["opening.geojson"] = [opening]
        let bytes = try data(mismatch)
        let initial = IMDFValidation.check(files: try IMDFTestFixtures.files(mismatch))
        check("#82 경계 오류만 있는 합성 fixture", initial.errors.count == 1 && initial.errors[0].contains(boundaryMessage))
        do { _ = try build(bytes); check("#82 일반 ZIP은 경계 오류를 계속 차단", false) }
        catch let blocked as IMDFArchive.Blocked {
            check("#82 일반 ZIP은 경계 오류를 계속 차단", blocked.messages.contains { $0.contains(boundaryMessage) })
        }
        let preview = try build(bytes, .allowMismatchForSandbox)
        let relaxed = IMDFValidation.check(files: preview.files, openingBoundaryPolicy: .allowMismatchForSandbox)
        check("#82 Sandbox ZIP은 경계 오류만 허용", relaxed.errors.isEmpty)
        check("#82 우회된 Opening UUID와 검사 결과 안내 보존", preview.warnings.contains {
            $0.contains(String(opening["id"]!.string!.prefix(8))) && $0.contains("경계 불일치")
        })
        let writtenOpening = try ProjectJSON.parse(preview.files["opening.geojson"]!)["features"]!.array
        check("#82 Opening 삭제·도형/속성/UUID 자동 수정 없음", writtenOpening == [opening])
        let rechecked = IMDFValidation.check(files: preview.files)
        check("#82 검사 전용 출력도 일반 검증 시 여전히 오류", rechecked.errors.count == 1 && rechecked.errors[0].contains(boundaryMessage))
        check("#82 다른 타입 출력 바이트는 변경하지 않음", strict.files.allSatisfy { preview.files[$0.key] == $0.value })
        check("#82 원본 프로젝트 바이트와 모델 유지", try ProjectFile.decoded(from: bytes).commonProject() == mismatch)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpeningBoundaryExport-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("opening-sandbox.zip")
        try IMDFArchive.writeZip(preview.files, to: url)
        let reopened = try IMDFImporter.load(url)
        check("#82 실제 ZIP 저장·재가져오기에서 Opening 보존", reopened.files["opening.geojson"]?["features"]?.array == [opening])
        do { _ = try build(bytes); check("#82 Sandbox 실행 후에도 일반 내보내기는 엄격", false) }
        catch let blocked as IMDFArchive.Blocked {
            check("#82 Sandbox 실행 후에도 일반 내보내기는 엄격", blocked.messages.contains { $0.contains(boundaryMessage) })
        }
        do {
            _ = try ClientDataset.build(projectData: bytes, datasetID: "opening-boundary-test", documents: [:], now: now)
            check("#82 클라이언트 묶음은 경계 오류를 계속 차단", false)
        } catch let blocked as ClientDataset.Blocked {
            check("#82 클라이언트 묶음은 경계 오류를 계속 차단", blocked.messages.contains { $0.contains(boundaryMessage) })
        }

        func rejects(_ label: String, _ project: BuildingProject, _ error: String) throws {
            do { _ = try build(data(project), .allowMismatchForSandbox); check(label, false) }
            catch let blocked as IMDFArchive.Blocked {
                check(label, blocked.messages.contains { $0.contains(error) } && !blocked.messages.contains { $0.contains(boundaryMessage) })
            }
        }
        var invalid = mismatch
        invalid.globalGeoJSON["opening.geojson"]!.append(opening)
        try rejects("#82 혼합 오류: UUID 중복은 Sandbox에서도 차단", invalid, "중복")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["id"] = .string("invalid-id")
        try rejects("#82 혼합 오류: 잘못된 UUID는 계속 차단", invalid, "UUID v4")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["properties"]?["level_id"] = .string(UUID().uuidString.lowercased())
        try rejects("#82 다른 Level 참조 오류는 계속 차단", invalid, "실제 level")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["properties"]?["category"] = .null
        try rejects("#82 혼합 오류: 필수 속성은 계속 차단", invalid, "category")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["geometry"] = line(181, 36, 181.1, 36)
        try rejects("#82 좌표 범위 오류는 계속 차단", invalid, "경도")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["geometry"] = .null
        try rejects("#82 잘못된 Opening geometry는 계속 차단", invalid, "LineString")
        invalid = mismatch; invalid.globalGeoJSON["unit.geojson"]![0]["geometry"] = IMDFTestFixtures.polygon(129, 36, 129.0005, 36.0005)
        try rejects("#82 혼합 오류: Unit–Level 빈틈은 계속 차단", invalid, "합집합")
        invalid = mismatch; invalid.globalGeoJSON["opening.geojson"]![0]["geometry"] = line(131, 38, 131.0001, 38)
        try rejects("#82 혼합 오류: Venue 바깥 도형은 계속 차단", invalid, "Venue 경계")
        invalid = mismatch; invalid.globalGeoJSON["venue.geojson"]![0]["properties"]?["display_point"] = IMDFTestFixtures.point(131, 38)
        try rejects("#82 혼합 오류: 표시점 공간 검사는 계속 차단", invalid, "display_point")
        invalid = mismatch; invalid.manifest["language"] = .string("en")
        try rejects("#82 혼합 오류: Manifest 언어 검사는 계속 차단", invalid, "기본 언어 en")
        invalid = mismatch; invalid.legacyManifests = [.object(["language": .string("en")])]
        try rejects("#82 미해결 Manifest 사전 차단 유지", invalid, "Manifest 값이")
        invalid = mismatch; invalid.sharedFootprint = SharedFootprint(pendingMigrationFeatureIDs: [UUID()])
        try rejects("#82 Footprint 이전 미완료 사전 차단 유지", invalid, "이전하지 못한")
        var corrupt = preview.files; corrupt["opening.geojson"] = Data("{not JSON}".utf8)
        check("#82 JSON 해석 오류는 검사용 검증에서도 차단", IMDFValidation.check(files: corrupt,
            openingBoundaryPolicy: .allowMismatchForSandbox).errors.contains { $0.contains("JSON을 읽을 수 없습니다") })

        var onBoundary = mismatch
        onBoundary.globalGeoJSON["opening.geojson"]![0]["geometry"] = line(129, 36.0002, 129, 36.0008)
        let correct = try build(data(onBoundary))
        check("#82 정상 경계 Opening의 일반 내보내기 유지", IMDFValidation.check(files: correct.files).errors.isEmpty)
    }
}
