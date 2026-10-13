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
        let backup = folder.appendingPathComponent("recovery.imdfrnt")
        let destination = folder.appendingPathComponent("building.imdfrnt")
        func environment() -> AppEnvironment { AppEnvironment(recoveryURL: backup, projectDefaults: defaults) }

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
            check("새 빈 프로젝트는 저장 가능하고 아직 수정사항 없음", env.hasSomethingToPersist && !env.hasUnsavedChanges && env.projectSaveStatus == "저장되지 않음")
            let blankID = env.projectID
            check("도면 없는 프로젝트 저장", env.saveProject(to: destination))
            let blank = try ProjectFile.decoded(from: Data(contentsOf: destination))
            let reopened = environment()
            try reopened.adopt(blank, from: destination)
            check("빈 프로젝트 재열기와 ID·이름·저장 상태 유지", reopened.document == nil && reopened.projectID == blankID &&
                  reopened.projectDisplayName == "building" && reopened.projectSaveStatus == "저장됨" && !reopened.hasUnsavedChanges)
            env.openSample()
            check("새 빈 프로젝트에 도면 추가 시 ID·저장 위치 유지", env.projectID == blankID && env.projectURL == destination && env.hasUnsavedChanges)
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
            check("전체 작업 파일 저장", env.saveProject(to: destination))
            let originalBytes = try Data(contentsOf: destination)
            let file = try ProjectFile.decoded(from: originalBytes)
            try reopened.adopt(file, from: destination)
            check("도면·feature·Anchor·노드·엣지·메타데이터 완전 재열기", !file.buildingProject!.levels[0].editing.features.features.isEmpty && file.commonProject().routingGraph.nodes.count == 2 &&
                  file.commonProject().routingGraph.edges.count == 1 && reopened.makeProjectFile()!.hasSameContents(as: file) &&
                  reopened.routing.node(first)?.metadataJSON == "{\"kind\":\"entry\"}")
            env.selectRoutingNode(first)
            env.selectRoutingFloor(env.routing.floors[0].id)
            env.showAnchorScreen = true
            env.selection.selected = []
            check("선택·화면 변경은 저장할 수정사항으로 판단하지 않음", !env.hasUnsavedChanges)
            env.updateRoutingNode(first, field: "name") { $0.name = "변경" }
            check("노드 데이터 수정은 저장 상태에 반영", env.hasUnsavedChanges && env.projectSaveStatus == "수정사항 있음")
            env.undo()
            check("저장 시점으로 Undo하면 수정 상태 해제", !env.hasUnsavedChanges)
            env.redo()
            env.autosaveTick()
            check("자동 저장은 복구본만 갱신하고 원본·미저장 상태 보존", try Data(contentsOf: destination) == originalBytes &&
                  ProjectFile.decoded(from: Data(contentsOf: backup)).commonProject().routingGraph.node(first)?.name == "변경" && env.hasUnsavedChanges)
            try reopened.restoreRecovery(from: backup)
            check("복구 시 원본 저장 위치와 미저장 변경 구분", reopened.projectURL == destination && reopened.hasUnsavedChanges && reopened.routing.node(first)?.name == "변경")
            let beforeCancel = env.makeProjectFile()!
            var saveCalled = false
            check("취소는 저장을 부르지 않고 작업 보존", !env.resolveUnsavedChanges(.cancel, saving: { saveCalled = true; return true }) &&
                  !saveCalled && env.makeProjectFile()!.hasSameContents(as: beforeCancel))
            check("저장 창 취소는 후속 작업을 막음", !env.resolveUnsavedChanges(.save, saving: { false }))
            let blocker = folder.appendingPathComponent("not-a-folder")
            try Data("block".utf8).write(to: blocker)
            check("저장 실패는 파일 위치·dirty·내용을 유지하고 후속 작업을 막음", !env.resolveUnsavedChanges(.save, saving: {
                env.saveProject(to: blocker.appendingPathComponent("invalid.imdfrnt"))
            }) && env.projectURL == destination && env.hasUnsavedChanges && env.makeProjectFile()!.hasSameContents(as: beforeCancel))
            try env.discardRecoveryChanges()
            try reopened.restoreRecovery(from: backup)
            let bytesAfterDiscard = try Data(contentsOf: destination)
            check("저장하지 않고 종료할 변경이 복구에서 부활하지 않음", !reopened.hasUnsavedChanges && reopened.routing.node(first)?.name != "변경" &&
                  bytesAfterDiscard == originalBytes)
            let broken = AppEnvironment(recoveryURL: blocker.appendingPathComponent("recovery.imdfrnt"), projectDefaults: defaults)
            broken.openSample()
            let brokenID = broken.projectID
            do { try broken.createNewProject(); check("복구본 쓰기 실패 시 새 프로젝트로 교체하지 않음", false) }
            catch { check("복구본 쓰기 실패 시 새 프로젝트로 교체하지 않음", broken.document != nil && broken.projectID == brokenID) }
            var invalid = file
            invalid.buildingProject!.levels[0].info.svg = "broken"
            do { try env.adopt(invalid, from: nil); check("잘못된 프로젝트를 열어도 현재 데이터 보존", false) }
            catch { check("잘못된 프로젝트를 열어도 현재 데이터 보존", env.makeProjectFile()!.hasSameContents(as: beforeCancel)) }
            var legacyJSON = try JSONSerialization.jsonObject(with: file.legacyEditorView().encoded()) as! [String: Any]
            legacyJSON.removeValue(forKey: "hasDrawing")
            legacyJSON["version"] = 3
            let legacy = try ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: legacyJSON))
            try reopened.adopt(legacy, from: destination)
            check("기존 hasDrawing 없는 파일과 버전 3 호환", reopened.document != nil && reopened.routing == env.lastExplicitSavedProject!.commonProject().routingGraph && !reopened.hasUnsavedChanges)
            try env.createNewProject()
            let bytesAfterNew = try Data(contentsOf: destination)
            check("새 프로젝트 생성은 이전 파일을 덮어쓰지 않음", env.projectID != blankID && bytesAfterNew == originalBytes)
            let unsaved = environment()
            unsaved.openSample()
            unsaved.autosaveTick()
            try unsaved.discardRecoveryChanges()
            check("한 번도 저장하지 않은 변경 폐기 시 복구본 제거", !FileManager.default.fileExists(atPath: backup.path))
        } catch { check("프로젝트 저장·전환 통합 검사", false); print(error) }
        print("== Project: \(count - failures)/\(count) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
