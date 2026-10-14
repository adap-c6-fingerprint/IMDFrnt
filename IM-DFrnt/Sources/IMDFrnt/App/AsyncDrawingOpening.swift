import AppKit
import Foundation

enum ProjectOpeningPreparation {
    /// Validate before replacing existing work; expensive parsing stays off UI.
    static func validate(_ data: Data) throws -> Data {
        var file = try ProjectFile.decoded(from: data)
        try file.validateLegacyRouting()
        var project = file.commonProject()
        try project.validate()
        try project.refreshIMDFDisplays()
        for level in project.levels where !level.info.svg.isEmpty {
            try Task.checkCancellation()
            _ = try SVGParser.parse(data: Data(level.info.svg.utf8), sourceName: level.info.sourceName)
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
        lastExplicitSavedProject = makeProjectFile()
        lastRecoveryProject = makeProjectFile()
    }

    func adoptProjectAsync(_ file: ProjectFile, from url: URL?) async throws {
        let data = try file.encoded()
        let validated = try await Task.detached(priority: .userInitiated) {
            try ProjectOpeningPreparation.validate(data)
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
        if !project { return await importDrawingAsync(at: url) }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
        do {
            let validated = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try ProjectOpeningPreparation.validate(Data(contentsOf: url))
            }.value
            guard confirmingChanges?() ?? confirmUnsavedChanges(action: "다른 프로젝트 열기") else { return .cancelled }
            try adoptPreparedProject(validated, from: url)
            persist(showingBanner: false)
            notify("\(url.lastPathComponent)을 불러왔습니다.")
            return .opened
        } catch {
            notify("열기 실패: \(error.localizedDescription)", isError: true)
            return .failed
        }
    }

    @discardableResult
    func importDrawingAsync(at url: URL) async -> DocumentOpenResult {
        guard !isProjectBusy else { return .failed }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
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
