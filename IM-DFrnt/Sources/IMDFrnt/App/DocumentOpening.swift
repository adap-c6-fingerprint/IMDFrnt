import AppKit
import Foundation

enum DocumentOpenResult: Equatable {
    case opened, cancelled, failed

    var applicationReply: NSApplication.DelegateReply {
        switch self { case .opened: .success; case .cancelled: .cancel; case .failed: .failure }
    }
}

@MainActor
extension AppEnvironment {
    /// Finder and the File menu use the same validation/confirmation/persistence.
    /// An injectable confirmation keeps cancellation/failure tests off real UI.
    @discardableResult
    func openDocument(at url: URL, confirmingChanges: (() -> Bool)? = nil) -> DocumentOpenResult {
        guard !isProjectBusy, url.isFileURL else { return .failed }
        let ext = url.pathExtension.lowercased()
        let project = [ProjectFile.fileExtension, ProjectFile.interimFileExtension].contains(ext)
        guard project || ["svg", "png", "jpg", "jpeg"].contains(ext) else {
            notify("지원하지 않는 파일입니다. .imdfrnt 또는 SVG·PNG·JPG 도면을 선택하세요.", isError: true)
            return .failed
        }
        if project, projectURL?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL {
            // Reopening the current project must not erase recovered/unsaved edits.
            return .opened
        }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            if project {
                let file = try ProjectFile.decoded(from: Data(contentsOf: url))
                guard confirmingChanges?() ?? confirmUnsavedChanges(action: "다른 프로젝트 열기") else { return .cancelled }
                try adopt(file, from: url)
            } else {
                let data = try Data(contentsOf: url)
                let svg = try ext == "svg" ? DrawingImageImporter.embedLocalImages(in: data, relativeTo: url)
                    : DrawingImageImporter.embeddedSVG(from: data)
                _ = try SVGParser.parse(data: svg, sourceName: url.lastPathComponent)
                guard confirmingChanges?() ?? confirmUnsavedChanges(action: "다른 도면 열기") else { return .cancelled }
                load(data: svg, name: url.lastPathComponent)
                guard loadedSVGText == String(decoding: svg, as: UTF8.self) else { return .failed }
            }
            persist(showingBanner: false)
            notify("\(url.lastPathComponent)을 불러왔습니다.")
            return .opened
        } catch {
            notify("열기 실패: \(error.localizedDescription)", isError: true)
            return .failed
        }
    }
}

/// Launch Services can deliver a file before SwiftUI connects its environment.
/// Queue requests until then; serialize them around imports and modal dialogs.
@MainActor
final class DocumentOpenCoordinator {
    private struct Request {
        var urls: [URL]
        var reply: (DocumentOpenResult) -> Void
    }
    private weak var environment: AppEnvironment?
    private var requests: [Request] = []
    private var task: Task<Void, Never>?

    var hasPendingRequests: Bool { !requests.isEmpty || task != nil }

    func attach(_ environment: AppEnvironment) {
        self.environment = environment
        startIfNeeded()
    }

    func enqueue(_ urls: [URL], reply: @escaping (DocumentOpenResult) -> Void = { _ in }) {
        requests.append(Request(urls: urls, reply: reply))
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard task == nil, environment != nil, !requests.isEmpty else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            while !requests.isEmpty {
                guard let environment else { return }
                if environment.isProjectBusy || NSApp?.modalWindow != nil {
                    try? await Task.sleep(for: .milliseconds(150))
                    continue
                }
                let request = requests.removeFirst()
                guard request.urls.count == 1, let url = request.urls.first else {
                    environment.notify("한 번에 파일 하나만 열 수 있습니다.", isError: true)
                    request.reply(.failed)
                    continue
                }
                request.reply(environment.openDocument(at: url))
            }
        }
    }
}
