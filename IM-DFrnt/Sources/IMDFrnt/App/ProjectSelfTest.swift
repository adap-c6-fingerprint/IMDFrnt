import AppKit
import Foundation

@MainActor
enum ProjectSelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--project-selftest") else { return }
        var count = 0, failures = 0
        func check(_ name: String, _ valid: Bool) {
            count += 1
            if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntProjectTest-\(UUID())")
        let suite = "IMDFrntProjectTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let autosave = folder.appendingPathComponent("autosave", isDirectory: true)
        func environment(_ directory: URL? = nil) -> AppEnvironment {
            AppEnvironment(autosaveFolder: directory ?? autosave, projectDefaults: defaults)
        }
        func savedFiles(_ directory: URL = autosave) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == ProjectFile.fileExtension }
        }

        do {
            let env = environment()
            env.openSample()
            env.selectPropertyType(.opening)
            env.selection.selected = [env.document!.objects.first!.id]
            env.createFeature()
            env.anchors.add(local: LocalPoint(1, 2), geo: GeoPoint(longitude: 129, latitude: 36), label: "기준")
            env.enterRoutingScreen()
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 8, modifiers: .command)
            check("초기화 검사에 실제 feature·Anchor·노드 작업 포함", env.features.features.count == 1 &&
                  env.anchors.pairs.count == 1 && env.routing.nodes.count == 1)
            let oldID = env.projectID
            env.showAnchorScreen = true
            env.showAuxiliaryScreen = true
            env.showDoorClosureScreen = true
            env.doorDraftPoints = [LocalPoint(1, 2)]
            try env.createNewProject()
            check("새 ID·현재 schema version으로 빈 프로젝트 생성", env.projectID != oldID && env.makeProjectFile()?.version == ProjectFile.currentVersion)
            check("문서·태깅·Anchor·routing·임시 상태·Undo 초기화", env.document == nil && env.loadedSVG == nil &&
                  env.features.features.isEmpty && env.anchors.pairs.isEmpty && env.routing == RoutingGraph() &&
                  env.selection.isEmpty && env.assignment == nil && !env.canUndo && !env.canRedo &&
                  env.doorDraftPoints.isEmpty && !env.showRoutingScreen && !env.showAnchorScreen &&
                  !env.showAuxiliaryScreen && !env.showDoorClosureScreen && env.projectURL == nil)
            var nameParts = DateComponents()
            (nameParts.year, nameParts.month, nameParts.day, nameParts.hour, nameParts.minute) = (2026, 10, 17, 15, 30)
            let nameDate = Calendar(identifier: .gregorian).date(from: nameParts)!
            check("자동 저장 이름은 새 도면_YYMMDD_HHmm", AppEnvironment.defaultProjectFileName(at: nameDate) == "새 도면_261017_1530")
            check("새 빈 프로젝트는 수정사항 없음", env.hasSomethingToPersist && !env.hasUnsavedChanges && env.projectSaveStatus == "빈 프로젝트")
            check("빈 프로젝트는 자동 저장 폴더에 파일을 만들지 않음", env.persist(showingBanner: false) && env.projectURL == nil && savedFiles().isEmpty)
            let blankID = env.projectID
            env.openSample()
            check("새 빈 프로젝트에 도면 추가 시 ID 유지·자동 저장 대기", env.projectID == blankID && env.projectURL == nil &&
                  env.hasUnsavedChanges && env.projectSaveStatus == "자동 저장 대기")
            env.autosaveTick()
            guard let projectURL = env.projectURL else { throw CocoaError(.fileNoSuchFile) }
            check("첫 자동 저장은 자동 저장 폴더에 새 도면_ 이름 파일 하나를 만듦",
                  projectURL.deletingLastPathComponent().standardizedFileURL == autosave.standardizedFileURL &&
                  projectURL.lastPathComponent.hasPrefix("새 도면_") && projectURL.pathExtension == ProjectFile.fileExtension &&
                  savedFiles().count == 1 && !env.hasUnsavedChanges && env.projectSaveStatus == "자동 저장됨" &&
                  env.projectDisplayName == projectURL.deletingPathExtension().lastPathComponent)
            check("마지막 작업 파일 위치 기록", defaults.string(forKey: AppEnvironment.lastProjectPathKey) == projectURL.path)

            env.anchors.add(local: LocalPoint(1, 2), geo: GeoPoint(longitude: 129, latitude: 36), label: "기준")
            env.selectPropertyType(.opening)
            env.selection.selected = [env.document!.objects.first!.id]
            env.createFeature()
            env.enterRoutingScreen()
            env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 8, modifiers: .command)
            let first = env.routingSelectedNodeID!
            env.handleRoutingClick(at: LocalPoint(300, 100), tolerance: 8, modifiers: .command)
            _ = env.routing.connect(first, env.routingSelectedNodeID!)
            env.updateRoutingNode(first, field: "metadata") { $0.metadataJSON = "{\"kind\":\"entry\"}" }
            env.autosaveTick()
            check("이후 자동 저장은 같은 파일 하나에만 덮어씀", env.projectURL == projectURL && savedFiles().count == 1 && !env.hasUnsavedChanges)
            let originalBytes = try Data(contentsOf: projectURL)
            let file = try ProjectFile.decoded(from: originalBytes)
            let reopened = environment()
            try reopened.adopt(file, from: projectURL)
            check("도면·feature·Anchor·노드·엣지·메타데이터 완전 재열기", !file.buildingProject!.levels[0].editing.features.features.isEmpty && file.commonProject().routingGraph.nodes.count == 2 &&
                  file.commonProject().routingGraph.edges.count == 1 && reopened.makeProjectFile()!.hasSameContents(as: file) &&
                  reopened.routing.node(first)?.metadataJSON == "{\"kind\":\"entry\"}" && !reopened.hasUnsavedChanges)
            check("다음 실행은 마지막 작업 파일을 엶", try environment().lastWorkedProjectURL() == projectURL)
            env.selectRoutingNode(first)
            env.selectRoutingFloor(env.routing.floors[0].id)
            env.showAnchorScreen = true
            env.selection.selected = []
            check("선택·화면 변경은 저장할 수정사항으로 판단하지 않음", !env.hasUnsavedChanges)
            env.updateRoutingNode(first, field: "name") { $0.name = "변경" }
            check("노드 데이터 수정은 자동 저장 대기로 반영", env.hasUnsavedChanges && env.projectSaveStatus == "자동 저장 대기")
            env.undo()
            check("자동 저장 시점으로 Undo하면 대기 해제", !env.hasUnsavedChanges)
            env.redo()
            let leftCleanly = env.autosaveBeforeLeaving(action: "검사")
            let afterLeaving = try ProjectFile.decoded(from: Data(contentsOf: projectURL))
            check("다른 작업으로 넘어가기 전 자동 저장", leftCleanly && !env.hasUnsavedChanges &&
                  afterLeaving.commonProject().routingGraph.node(first)?.name == "변경")

            let blocker = folder.appendingPathComponent("not-a-folder")
            try Data("block".utf8).write(to: blocker)
            let failing = environment(blocker)
            failing.openSample()
            check("자동 저장 실패는 파일 위치·대기 상태를 유지", !failing.persist(showingBanner: false) && failing.projectURL == nil && failing.hasUnsavedChanges)

            let beforeInvalid = env.makeProjectFile()!
            var invalid = file
            invalid.buildingProject!.levels[0].info.svg = "broken"
            do { try env.adopt(invalid, from: nil); check("잘못된 프로젝트를 열어도 현재 데이터 보존", false) }
            catch { check("잘못된 프로젝트를 열어도 현재 데이터 보존", env.makeProjectFile()!.hasSameContents(as: beforeInvalid)) }
            var legacyJSON = try JSONSerialization.jsonObject(with: file.legacyEditorView().encoded()) as! [String: Any]
            legacyJSON.removeValue(forKey: "hasDrawing")
            legacyJSON["version"] = 3
            let legacy = try ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: legacyJSON))
            try reopened.adopt(legacy, from: projectURL)
            check("기존 hasDrawing 없는 파일과 버전 3 호환", reopened.document != nil && reopened.routing == file.commonProject().routingGraph && !reopened.hasUnsavedChanges)

            let bytesBeforeNew = try Data(contentsOf: projectURL)
            try env.createNewProject()
            env.openSample()
            env.autosaveTick()
            check("새 프로젝트는 이전 파일을 덮어쓰지 않고 자기 파일을 새로 만듦", env.projectID != blankID && env.projectURL != projectURL &&
                  savedFiles().count == 2 && (try? Data(contentsOf: projectURL)) == bytesBeforeNew)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: projectURL.path)
            let listed = env.savedProjects()
            check("프로젝트 선택 목록은 자동 저장 폴더의 프로젝트를 최근 순으로 보여 줌", listed.count == 2 &&
                  AppEnvironment.isSameFile(listed[0].url, env.projectURL!) && AppEnvironment.isSameFile(listed[1].url, projectURL))
            check("열린 프로젝트가 있으면 전환 시 저장 질문 대상", env.hasOpenProject && environment().hasOpenProject == false)
            let taken = environment().nextAutosaveURL(at: nameDate)
            try Data().write(to: taken)
            check("같은 분에 만든 프로젝트는 _2를 붙여 구분", environment().nextAutosaveURL(at: nameDate).lastPathComponent == "새 도면_261017_1530_2.imdfrnt")

            let legacyFolder = folder.appendingPathComponent("legacy", isDirectory: true)
            try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
            let legacyAutosave = legacyFolder.appendingPathComponent("autosave.imdfrnt")
            try originalBytes.write(to: legacyAutosave)
            let migrated = try environment(legacyFolder).lastWorkedProjectURL()
            check("예전 공용 복구본은 새 도면_ 이름 파일로 옮겨 엶", migrated.map { $0.lastPathComponent.hasPrefix("새 도면_") } == true &&
                  !FileManager.default.fileExists(atPath: legacyAutosave.path) && migrated.flatMap { try? Data(contentsOf: $0) } == originalBytes)
        } catch { check("프로젝트 저장·전환 통합 검사", false); print(error) }
        print("== Project: \(count - failures)/\(count) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
