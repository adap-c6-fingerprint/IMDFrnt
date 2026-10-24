import AppKit
import Foundation

@MainActor
extension AppEnvironment {
    var isProjectBusy: Bool { isImportingIMDF || isProjectActionInProgress }
    var canFillEmptyProject: Bool { hasCreatedProject && projectContents == BuildingProject() }

    var projectDisplayName: String {
        if let projectURL { return projectURL.deletingPathExtension().lastPathComponent }
        return document.map { ($0.sourceName as NSString).deletingPathExtension } ?? "새 프로젝트"
    }

    /// 자동 저장 파일 이름. 2026-10-17 15:30 → `새 도면_261017_1530`.
    static func defaultProjectFileName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyMMdd_HHmm"
        return "새 도면_" + formatter.string(from: date)
        // 사용자 지역 설정이 불기 달력·12시간제여도 숫자 자리가 흔들리지 않게 고정한다.
    }

    /// 마지막 자동 저장 뒤에 바뀐 내용이 있는가.
    var hasUnsavedChanges: Bool {
        guard let current = makeProjectFile() else { return false }
        guard let saved = lastRecoveryProject else { return !isUnwrittenEmptyProject }
        return !current.hasSameContents(as: saved)
    }

    /// 아직 파일이 없는 빈 프로젝트. 내용이 생기기 전에는 자동 저장 폴더에 파일을 만들지 않는다.
    var isUnwrittenEmptyProject: Bool { projectURL == nil && projectContents == BuildingProject() }

    var projectSaveStatus: String {
        if !hasSomethingToPersist { return "프로젝트 없음" }
        if isUnwrittenEmptyProject { return "빈 프로젝트" }
        return hasUnsavedChanges ? "자동 저장 대기" : "자동 저장됨"
    }

    static var isRunningSelfTests: Bool {
        ["--selftest", "--routing-selftest", "--project-selftest", "--document-open-selftest", "--building-selftest", "--drawing-loading-selftest", "--footprint-selftest"].contains {
            CommandLine.arguments.contains($0)
        }
    }

    func newProject() {
        guard !isProjectBusy else { return }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
        guard confirmProjectSwitch("새 프로젝트를 만들까요?", confirmTitle: "저장하고 새로 만들기") else { return }
        do {
            try createNewProject()
            notify("새 프로젝트를 만들었습니다. 도면 또는 IMDF를 불러와 작업을 시작하세요.")
        } catch { notify("새 프로젝트 생성 실패: \(error.localizedDescription)", isError: true) }
    }

    /// 새 프로젝트는 내용이 생긴 뒤 첫 자동 저장에서 자기 파일을 받는다.
    func createNewProject() throws {
        try adopt(ProjectFile.empty(), from: nil)
    }

    /// 다른 작업으로 넘어가기 전에 지금 프로젝트를 자기 파일에 마지막으로 저장한다.
    /// 저장에 실패했을 때만 묻는다 — 계속하면 마지막 자동 저장 이후 변경이 사라진다.
    func autosaveBeforeLeaving(action: String) -> Bool {
        guard hasUnsavedChanges else { return true }
        if persist(showingBanner: false) { return true }
        let alert = NSAlert()
        alert.messageText = "\(projectDisplayName)을 자동 저장하지 못했습니다."
        alert.informativeText = "\(action)를 계속하면 마지막 자동 저장 이후의 변경사항이 사라집니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "계속")
        return alert.runModal() == .alertSecondButtonReturn
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
