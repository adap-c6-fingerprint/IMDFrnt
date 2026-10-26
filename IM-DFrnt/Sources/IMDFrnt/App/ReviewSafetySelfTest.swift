import Foundation

@MainActor
enum ReviewSafetySelfTest {
    static func run(_ check: (String, Bool) -> Void) async throws {
        var day = WeeklyOpeningHours.Day(mode: .intervals)
        let a = WeeklyOpeningHours.Interval(), b = WeeklyOpeningHours.Interval(), c = WeeklyOpeningHours.Interval()
        check("#80 운영시간 identity와 값 비교 분리", a.id != b.id && a == b)
        day.intervals = [a, b, c]
        day.removeInterval(b.id)
        check("#80 중간 구간 삭제는 나머지 identity 보존", day.intervals.map(\.id) == [a.id, c.id])
        var stale = b; stale.endHour = 20
        day.updateInterval(stale)
        check("#80 삭제된 구간의 지연 입력은 무시", day.intervals.map(\.id) == [a.id, c.id] && day.interval(b.id) == nil)
        var updated = c; updated.endHour = 21
        day.updateInterval(updated)
        check("#80 삭제 후 남은 구간 편집은 ID로 연결", day.interval(c.id)?.endHour == 21 && day.interval(a.id)?.endHour == 18)
        day.removeInterval(c.id); day.removeInterval(a.id); day.removeInterval(a.id)
        check("#80 마지막 구간·중복 삭제도 안전", day.intervals.isEmpty)
        day = .init(mode: .intervals)
        let reloadedID = day.intervals[0].id
        day.updateInterval(updated)
        check("#80 다시 불러온 시간에 이전 binding 입력 무시", day.intervals.map(\.id) == [reloadedID] && day.intervals[0].endHour == 18)
        let hours = WeeklyOpeningHours.parse("Mo-Fr 09:00-12:00,13:00-18:00; Sa off; Su off")!
        check("#80 새 구간 identity가 시간 문자열·동등성에 영향 없음", WeeklyOpeningHours.parse(hours.text) == hours)
        check("#80 IMDF 검사 실패 요약", IMDFComplianceSelfTest.summary(total: 3, failures: 1) == "== IMDF Compliance: 2/3 FAIL ==")
        check("#80 IMDF 검사 정상 요약", IMDFComplianceSelfTest.summary(total: 3, failures: 0) == "== IMDF Compliance: 3/3 PASS ==")

        func named(_ labels: [String: String]) -> FeatureGroup {
            var feature = FeatureGroup(featureType: .unit, serialNumber: "name-test", memberIDs: [])
            feature.properties["name"] = .json(.object(labels.mapValues(ProjectJSON.string)))
            return feature
        }
        check("#80 지역 한국어+영어 캔버스 이름", AppEnvironment.nameText(of: named(["ko-KR": "도서관", "en": "Library"])) == "도서관(Library)")
        check("#80 지역 영어+기본 한국어 캔버스 이름", AppEnvironment.nameText(of: named(["ko": "도서관", "en-US": "Library"])) == "도서관(Library)")
        check("#80 기본 태그 우선·태그 대소문자·공백", AppEnvironment.nameText(of: named([
            "KO": " 도서관 ", "ko-KR": "지역 이름", "EN": "Library"])) == "도서관(Library)")
        check("#80 다른 언어 fallback 유지", AppEnvironment.nameText(of: named(["ja": "図書館"])) == "図書館")
        check("#80 빈 이름도 안전", AppEnvironment.nameText(of: named([:])).isEmpty)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewSafety-\(UUID())")
        let suite = "ReviewSafety-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let env = AppEnvironment(autosaveFolder: directory, projectDefaults: defaults)
        try env.createNewProject(); env.openSample()
        env.layers.addPropertyTypeLayer(.unit); env.layerEditMode = .point; env.isVertexMoveEnabled = true
        var unit = FeatureGroup(featureType: .unit, serialNumber: "unit-safe", memberIDs: [])
        unit.polygonRings = [[LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)]]
        env.features.insert(unit)
        check("#80 일반 점 모드의 꼭짓점 이동은 유지", env.allowsCanvasVertexDrag)
        env.beginDisplayPointPicking(unit.id)
        let undoCount = env.undoStack.undoEntries.count
        let draft = env.pointDraft
        check("#80 표시점 입력 중 꼭짓점 드래그 시작 차단", !env.allowsCanvasVertexDrag)
        _ = env.handlePriorityCanvasClick(at: LocalPoint(1, 1), tolerance: 6)
        check("#80 꼭짓점 근처 클릭도 표시점만 지정", env.features.feature(unit.id)?.displayPoint == LocalPoint(1, 1)
            && env.features.feature(unit.id)?.polygonRings == unit.polygonRings
            && env.pointDraft == draft && env.vertexDrag == nil && env.undoStack.undoEntries.count == undoCount + 1)
        env.mode = .anchorPicking
        check("#80 Anchor 입력 중 꼭짓점 드래그 시작 차단", !env.allowsCanvasVertexDrag)
        _ = env.handlePriorityCanvasClick(at: LocalPoint(2, 2), tolerance: 6)
        check("#80 Anchor 입력 후 일반 꼭짓점 이동 복구", env.pendingAnchorLocal == LocalPoint(2, 2) && env.allowsCanvasVertexDrag)
        env.showAnchorScreen = false

        var amenity = FeatureGroup(featureType: .amenity, serialNumber: "amenity-safe", memberIDs: [])
        amenity.drawnVertices = [LocalPoint(20, 20)]
        env.features.insert(amenity)
        env.setDisplayPoint(LocalPoint(21, 20), for: amenity.id)
        check("#80 점 Feature의 가까운 표시점 허용", env.features.feature(amenity.id)?.displayPoint == LocalPoint(21, 20))
        env.beginDisplayPointPicking(amenity.id)
        let beforePoint = env.snapshot
        let undoPoint = env.undoStack.undoEntries
        env.setDisplayPoint(LocalPoint(90, 90), for: amenity.id)
        check("#80 점 Feature 범위 밖 거부·기존 상태 보존", env.snapshot == beforePoint
            && env.undoStack.undoEntries == undoPoint && env.mode == .displayPointPicking(amenity.id))
        let object = env.document!.objects[0]
        let grouped = FeatureGroup(featureType: .amenity, serialNumber: "amenity-grouped", memberIDs: [object.id])
        env.features.insert(grouped)
        let box = VertexExtractor.boundingBox(of: grouped.memberIDs, document: env.document!)
        env.setDisplayPoint(LocalPoint(box.midX, box.midY), for: grouped.id)
        let inside = env.features.feature(grouped.id)?.displayPoint
        env.setDisplayPoint(LocalPoint(box.maxX + 100, box.maxY + 100), for: grouped.id)
        check("#80 개체 기반 점 Feature의 기존 범위 검사", inside != nil && env.features.feature(grouped.id)?.displayPoint == inside)
        var opening = FeatureGroup(featureType: .opening, serialNumber: "opening-safe", memberIDs: [])
        opening.drawnVertices = [LocalPoint(0, 0), LocalPoint(100, 0)]
        env.features.insert(opening)
        env.setDisplayPoint(LocalPoint(30, 50), for: opening.id)
        check("#80 선형 표시점 투영은 유지", env.features.feature(opening.id)?.displayPoint == LocalPoint(30, 0))

        // Test import idempotence through the production command, including explicit conflict resolution.
        let source = ProjectLevel(info: ProjectLevelInfo(name: "반복 가져오기", ordinal: 0))
        let target = env.addProjectLevel()
        await env.waitForLevelDrawing()
        env.buildingProject.manifest = .object(["language": .string("ko")])
        var incoming = BuildingProject(levels: [source])
        incoming.manifest = .object(["language": .string("en")])
        check("#80 첫 Manifest 충돌 보관", env.importLevel(source, into: target, metadata: incoming)
            && env.buildingProject.legacyManifests?.count == 1 && env.buildingProject.manifestConflictsResolved == false)
        _ = env.importLevel(source, into: target, metadata: incoming)
        check("#80 미해결 동일 충돌 재등록 없음", env.buildingProject.legacyManifests?.count == 1 && env.buildingProject.manifestConflictsResolved == false)
        env.perform("검증용 현재 Manifest 유지") { env.buildingProject.manifestConflictsResolved = true }
        _ = env.importLevel(source, into: target, metadata: incoming)
        check("#80 해결한 동일 충돌은 다시 차단하지 않음", env.buildingProject.legacyManifests?.count == 1
            && env.buildingProject.manifestConflictsResolved == true && env.buildingProject.manifest["language"]?.string == "ko")
        incoming.manifest["language"] = .string("ja")
        _ = env.importLevel(source, into: target, metadata: incoming)
        check("#80 새로운 Manifest 충돌은 다시 확인", env.buildingProject.legacyManifests?.count == 2 && env.buildingProject.manifestConflictsResolved == false)
        env.undo()
        check("#80 새 충돌 가져오기 Undo는 해결 상태 복원", env.buildingProject.legacyManifests?.count == 1 && env.buildingProject.manifestConflictsResolved == true)
        env.redo()
        check("#80 새 충돌 가져오기 Redo", env.buildingProject.legacyManifests?.count == 2 && env.buildingProject.manifestConflictsResolved == false)
        let restored = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded()).commonProject()
        check("#80 충돌 사본·해결 상태 저장 왕복", restored.legacyManifests == env.buildingProject.legacyManifests
            && restored.manifestConflictsResolved == env.buildingProject.manifestConflictsResolved)
    }
}
