import AppKit
import Foundation

enum UnsavedProjectChoice { case save, discard, cancel }

@MainActor
extension AppEnvironment {
    var isProjectBusy: Bool { isImportingIMDF || isProjectActionInProgress }
    var recoveryURL: URL { recoveryURLOverride ?? Self.autosaveURL }
    var canFillEmptyProject: Bool { hasCreatedProject && projectContents == BuildingProject() }

    var projectDisplayName: String {
        if let projectURL { return projectURL.deletingPathExtension().lastPathComponent }
        return document.map { ($0.sourceName as NSString).deletingPathExtension } ?? "새 프로젝트"
    }

    var hasUnsavedChanges: Bool {
        guard let current = makeProjectFile() else { return false }
        guard let saved = lastExplicitSavedProject else { return true }
        return !current.hasSameContents(as: saved)
    }

    var projectSaveStatus: String {
        if !hasSomethingToPersist { return "프로젝트 없음" }
        if projectURL == nil { return "저장되지 않음" }
        return hasUnsavedChanges ? "수정사항 있음" : "저장됨"
    }

    static var isRunningSelfTests: Bool {
        ["--selftest", "--routing-selftest", "--project-selftest", "--document-open-selftest", "--building-selftest", "--drawing-loading-selftest"].contains {
            CommandLine.arguments.contains($0)
        }
    }

    func newProject() {
        guard !isProjectBusy else { return }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
        guard confirmUnsavedChanges(action: "새 프로젝트 만들기") else { return }
        do {
            try createNewProject()
            notify("새 프로젝트를 만들었습니다. 도면 또는 IMDF를 불러와 작업을 시작하세요.")
        } catch { notify("새 프로젝트 생성 실패: \(error.localizedDescription)", isError: true) }
    }

    /// 복구본 교체가 실패하면 현재 작업을 초기화하지 않는다.
    func createNewProject() throws {
        let file = ProjectFile.empty()
        try writeRecovery(file, projectURL: nil)
        try adopt(file, from: nil)
    }

    func confirmUnsavedChanges(action: String, discardRecovery: Bool = false) -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "\(projectDisplayName)의 변경사항을 저장할까요?"
        alert.informativeText = "\(action)를 하면 저장하지 않은 변경사항이 사라집니다."
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장하지 않음")
        alert.addButton(withTitle: "취소")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        let choice: UnsavedProjectChoice = response == .alertFirstButtonReturn ? .save
            : response == .alertSecondButtonReturn ? .discard : .cancel
        if choice == .discard && discardRecovery {
            do { try discardRecoveryChanges() }
            catch { notify("변경사항을 정리하지 못했습니다: \(error.localizedDescription)", isError: true); return false }
        }
        return resolveUnsavedChanges(choice, saving: { self.saveProject() })
    }

    /// 저장 창 취소 또는 저장 실패는 화면을 유지하는 결과로 전달한다.
    func resolveUnsavedChanges(_ choice: UnsavedProjectChoice, saving: () -> Bool) -> Bool {
        switch choice {
        case .save: return saving()
        case .discard: return true
        case .cancel: return false
        }
    }

    @discardableResult
    func saveProject(to url: URL) -> Bool {
        guard let file = makeProjectFile() else { return false }
        do {
            try file.encoded().write(to: url, options: .atomic)
            // 쓰기가 성공한 뒤에만 저장 위치와 완료 상태를 갱신한다.
            projectURL = url
            lastExplicitSavedProject = file
            do { try writeRecovery(file, projectURL: url) }
            catch { notify("프로젝트는 저장했지만 복구본 저장에 실패했습니다: \(error.localizedDescription)", isError: true); return true }
            notify("작업을 저장했습니다: \(url.lastPathComponent)")
            return true
        } catch {
            notify("저장 실패: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func writeRecovery(_ file: ProjectFile, projectURL: URL?) throws {
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.encoded().write(to: recoveryURL, options: .atomic)
        projectDefaults.set(projectURL?.path, forKey: Self.lastProjectPathKey)
        lastRecoveryProject = file
    }

    /// 저장하지 않음을 택하고 종료한 수정사항이 다음 실행에서 부활하지 않게 한다.
    func discardRecoveryChanges() throws {
        if let saved = lastExplicitSavedProject {
            try writeRecovery(saved, projectURL: projectURL)
        } else {
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                try FileManager.default.removeItem(at: recoveryURL)
            }
            if recoveryURLOverride == nil, FileManager.default.fileExists(atPath: Self.interimAutosaveURL.path) {
                try FileManager.default.removeItem(at: Self.interimAutosaveURL)
            }
            projectDefaults.removeObject(forKey: Self.lastProjectPathKey)
            lastRecoveryProject = nil
        }
    }
}

extension ProjectFile {
    static func empty() -> ProjectFile {
        var file = ProjectFile(sourceName: "새 프로젝트", svg: "",
            features: FeatureStore(), ownership: OwnershipRegistry(), segmentation: SegmentationStore(),
            auxiliary: AuxiliaryStore(), anchors: AnchorStore(), serials: SerialNumberAllocator(),
            ids: IDAssigner(), openingGate: OpeningGateStore(), borrow: BorrowRegistry())
        file.hasDrawing = false
        file.buildingProject = BuildingProject()
        return file
    }
}
