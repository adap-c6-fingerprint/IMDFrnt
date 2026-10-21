import AppKit
import Foundation

enum ProjectOpeningPreparation {
    /// Validate before replacing existing work; expensive parsing stays off UI.
    static func validate(_ data: Data, reporter: LongTaskReporter? = nil) throws -> Data {
        reporter?.report(0.02, "프로젝트 파일 읽는 중")
        var file = try ProjectFile.decoded(from: data)
        try file.validateLegacyRouting()
        var project = file.commonProject()
        try project.validate()
        try project.refreshIMDFDisplays()
        reporter?.report(0.15, "층 도면 확인 중")
        let drawn = project.levels.filter { !$0.info.svg.isEmpty }
        for (i, level) in drawn.enumerated() {
            try Task.checkCancellation()
            _ = try SVGParser.parse(data: Data(level.info.svg.utf8), sourceName: level.info.sourceName)
            reporter?.report(0.15 + 0.8 * Double(i + 1) / Double(max(1, drawn.count)),
                             "\(level.info.name) 도면 확인 (\(i + 1)/\(drawn.count))")
            // 층 도면 파싱이 대부분의 시간이다. 층마다 진행률을 올린다.
        }
        for level in project.levels {
            if let reference = level.referenceDrawing {
                _ = try SVGParser.parse(data: Data(reference.svg.utf8), sourceName: reference.sourceName)
            }
        }
        file.buildingProject = project
        return try file.encoded()
    }
}

@MainActor
extension AppEnvironment {
    func adoptPreparedProject(_ data: Data, from url: URL?) throws {
        let file = try ProjectFile.decoded(from: data)
        let project = file.commonProject()
        resetProjectState(id: file.projectID)
        buildingProject = project
        assignment = file.assignment
        beginLevelDrawingLoad(file.assignment?.levelID ?? project.levels.first?.id)
        showRoutingScreen = project.imdfSourceName != nil
        projectURL = url
        lastRecoveryProject = makeProjectFile()
    }

    func adoptProjectAsync(_ file: ProjectFile, from url: URL?, reporter: LongTaskReporter? = nil) async throws {
        let data = try file.encoded()
        let validated = try await Task.detached(priority: .userInitiated) {
            try ProjectOpeningPreparation.validate(data, reporter: reporter)
        }.value
        try adoptPreparedProject(validated, from: url)
    }

    @discardableResult
    func openDocumentAsync(at url: URL, confirmingChanges: (() -> Bool)? = nil) async -> DocumentOpenResult {
        guard !isProjectBusy, url.isFileURL else { return .failed }
        let ext = url.pathExtension.lowercased()
        let project = [ProjectFile.fileExtension, ProjectFile.interimFileExtension].contains(ext)
        guard project || ["svg", "png", "jpg", "jpeg"].contains(ext) else { return .failed }
        if project, projectURL?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL { return .opened }
        if !project {
            return await importDrawingAsync(at: url, confirmingChanges: {
                confirmingChanges?() ?? self.autosaveBeforeLeaving(action: "다른 도면 열기")
            })
        }
        isProjectActionInProgress = true
        let task = beginLongTask("프로젝트 여는 중", detail: url.deletingPathExtension().lastPathComponent)
        let reporter = longTaskReporter(task)
        defer { isProjectActionInProgress = false; endLongTask(task) }
        do {
            let validated = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try ProjectOpeningPreparation.validate(Data(contentsOf: url), reporter: reporter)
            }.value
            endLongTask(task)
            // 저장 후 전환 질문이 진행률 팝업에 가리지 않게 먼저 닫는다.
            let target = url.deletingPathExtension().lastPathComponent
            let previous = hasOpenProject ? projectDisplayName : nil
            guard confirmingChanges?() ?? confirmProjectSwitch("‘\(target)’ 프로젝트로 전환할까요?") else { return .cancelled }
            try adoptPreparedProject(validated, from: url)
            persist(showingBanner: false)
            notify(previous.map { "‘\(target)’ 프로젝트로 전환했습니다. 이전 ‘\($0)’ 프로젝트는 따로 저장되어 있습니다." }
                   ?? "‘\(target)’ 프로젝트를 열었습니다.")
            return .opened
        } catch {
            notify("열기 실패: \(error.localizedDescription)", isError: true)
            return .failed
        }
    }

    @discardableResult
    func importDrawingAsync(at url: URL, confirmingChanges: (() -> Bool)? = nil) async -> DocumentOpenResult {
        guard !isProjectBusy else { return .failed }
        isProjectActionInProgress = true
        let task = beginLongTask("도면 불러오는 중", detail: url.lastPathComponent, fraction: nil)
        defer { isProjectActionInProgress = false; endLongTask(task) }
        let id = routingFloorID ?? buildingProject.levels.first?.id ?? UUID()
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let image = ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
                let svg = try image ? DrawingImageImporter.embeddedSVG(from: data)
                    : DrawingImageImporter.embedLocalImages(in: data, relativeTo: url)
                return try PreparedLevelDrawing.make(LevelDrawingInput(levelID: id, svg: String(decoding: svg, as: UTF8.self), sourceName: url.lastPathComponent))
            }.value
            endLongTask(task)
            // Finder's unsaved-work decision follows validation and precedes
            // every mutation, including clearing an anchor-only editor.
            guard confirmingChanges?() ?? true else { return .cancelled }
            if buildingProject.levels.isEmpty {
                if !hasCreatedProject { resetProjectState() }
                perform("첫 층 도면 불러오기") {
                    let info = ProjectLevelInfo(id: id, name: "1층", ordinal: 0, sourceName: prepared.input.sourceName, svg: prepared.input.svg)
                    buildingProject.levels.append(ProjectLevel(info: info))
                    levelDrawingCache.insert(prepared)
                    beginLevelDrawingLoad(id)
                }
            } else {
                let result = try applyRoutingDrawing(prepared)
                guard result == .opened else { return result }
            }
            persist(showingBanner: false)
            return .opened
        } catch {
            notify("도면을 불러오지 못했습니다: \(error.localizedDescription)", isError: true)
            return .failed
        }
    }
}
