import AppKit
import SwiftUI

/// 프로젝트 선택 창에 보이는 `.imdfrnt` 한 개.
struct SavedProject: Identifiable, Equatable {
    let url: URL
    let modified: Date
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// 층 이름만 읽는 가벼운 디코딩. 도면 SVG·편집 상태는 무시해 목록이 빨리 뜬다.
private struct ProjectLevelPeek: Decodable {
    struct Building: Decodable { var levels: [Level] }
    struct Level: Decodable { var info: Info }
    struct Info: Decodable { var name: String; var ordinal: Int }
    var buildingProject: Building?

    static func levelNames(at url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let peek = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return peek.buildingProject?.levels.map(\.info).sorted { $0.ordinal < $1.ordinal }.map(\.name)
        // 버전 2~4 파일은 buildingProject가 없어 nil이다. 목록에서는 층 정보만 비워 둔다.
    }
}

@MainActor
extension AppEnvironment {
    /// 지금 화면에 실제 프로젝트가 열려 있는가. 빈 새 프로젝트는 저장할 것이 없어 묻지 않는다.
    var hasOpenProject: Bool { hasSomethingToPersist && !isUnwrittenEmptyProject }

    /// 자동 저장 폴더의 프로젝트를 최근 수정 순으로. 폴더 밖에서 연 현재·지난 작업도 함께 보인다.
    func savedProjects() -> [SavedProject] {
        let fm = FileManager.default
        let extensions = [ProjectFile.fileExtension, ProjectFile.interimFileExtension]
        var urls = ((try? fm.contentsOfDirectory(at: autosaveFolder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
        let lastPath = projectDefaults.string(forKey: Self.lastProjectPathKey).map { URL(fileURLWithPath: $0) }
        for extra in [projectURL, lastPath].compactMap({ $0 }) where fm.fileExists(atPath: extra.path) {
            if !urls.contains(where: { Self.isSameFile($0, extra) }) { urls.append(extra) }
        }
        return urls.map { url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SavedProject(url: url, modified: modified)
        }.sorted { $0.modified > $1.modified }
    }

    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL == b.resolvingSymlinksInPath().standardizedFileURL
    }

    var lastWorkedProjectPath: String? { projectDefaults.string(forKey: Self.lastProjectPathKey) }

    func showProjectPickerIfIdle() {
        guard !isProjectBusy else { return }
        showProjectPicker = true
    }

    /// 앱을 켜면 지난 작업을 바로 열지 않고 프로젝트 선택 창을 띄운다.
    /// 예전 공용 복구본(`autosave.imdfrnt`)이 남아 있으면 새 이름 파일로 옮긴 뒤 목록에 보인다.
    func presentProjectPickerAtLaunch() {
        guard !hasSomethingToPersist, !Self.isRunningSelfTests else { return }
        do { _ = try lastWorkedProjectURL() }
        catch { notify("지난 작업을 옮기지 못했습니다: \(error.localizedDescription)", isError: true) }
        guard !savedProjects().isEmpty else { return }
        showProjectPicker = true
        // 저장된 프로젝트가 하나도 없으면 빈 캔버스의 시작 안내가 그대로 첫 화면이다.
    }

    /// 다른 프로젝트로 넘어가기 전에 지금 프로젝트를 저장하고 넘어갈지 묻는다.
    /// 두 프로젝트가 합쳐지는 것이 아니라 하나가 닫히고 다른 하나가 열린다는 것을 분명히 한다.
    func confirmProjectSwitch(_ question: String, confirmTitle: String = "저장하고 전환") -> Bool {
        guard hasOpenProject, !Self.isRunningSelfTests else {
            return autosaveBeforeLeaving(action: "프로젝트 전환")
        }
        // 검사는 실제 대화상자를 띄울 수 없다. 저장 동작만 같은 경로로 확인한다.
        let alert = NSAlert()
        alert.messageText = "‘\(projectDisplayName)’ 프로젝트를 저장하고 \(question)"
        alert.informativeText = "지금 프로젝트는 자기 파일에 저장된 채 닫힙니다. 두 프로젝트는 서로 합쳐지지 않으며, 프로젝트 선택에서 언제든 다시 열 수 있습니다."
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return autosaveBeforeLeaving(action: "프로젝트 전환")
    }

    /// 프로젝트 선택 창에서 고른 파일로 바꾼다. 검증·저장 질문은 `.imdfrnt` 불러오기와 같은 경로다.
    func switchProject(to url: URL) {
        showProjectPicker = false
        if let projectURL, Self.isSameFile(projectURL, url) { return }
        Task {
            if await openDocumentAsync(at: url) == .cancelled { showProjectPicker = true }
            // 저장 질문에서 취소하면 고르던 목록으로 돌아간다.
        }
    }
}

struct ProjectPicker: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var projects: [SavedProject] = []
    @State private var levelNames: [URL: [String]] = [:]
    @State private var selection: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if projects.isEmpty {
                ContentUnavailableView("저장된 프로젝트가 없습니다", systemImage: "folder",
                                       description: Text("새 프로젝트를 만들거나 다른 위치의 .imdfrnt를 여세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(projects, selection: $selection) { project in
                    row(project)
                        .tag(project.url)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { env.switchProject(to: project.url) }
                        .simultaneousGesture(TapGesture().onEnded { selection = project.url })
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("프로젝트 선택").font(.title2.weight(.semibold))
            Text(env.hasOpenProject
                 ? "지금 열린 프로젝트: ‘\(env.projectDisplayName)’ — 다른 프로젝트를 열면 지금 프로젝트는 저장된 뒤 닫힙니다."
                 : "작업할 프로젝트를 고르세요. .imdfrnt 하나가 건물 하나(모든 층 포함)입니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func row(_ project: SavedProject) -> some View {
        let isCurrent = env.projectURL.map { AppEnvironment.isSameFile($0, project.url) } ?? false
        let isLast = env.lastWorkedProjectPath.map { AppEnvironment.isSameFile(URL(fileURLWithPath: $0), project.url) } ?? false
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "building.2")
                .font(.title3)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                    if isCurrent { badge("현재 열림", .accentColor) }
                    else if isLast { badge("지난 작업", .secondary) }
                }
                Text(levelSummary(project.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(project.modified.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .help(project.url.path)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func levelSummary(_ url: URL) -> String {
        guard let names = levelNames[url] else { return "층 정보를 읽는 중…" }
        if names.isEmpty { return "층 없음" }
        return "\(names.count)개 층 · " + names.joined(separator: ", ")
    }

    private var footer: some View {
        HStack {
            Button("새 프로젝트") {
                env.showProjectPicker = false
                env.newProject()
            }
            Button("다른 위치에서 열기…") {
                env.showProjectPicker = false
                env.openProject()
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([selection ?? env.autosaveFolder])
            } label: { Image(systemName: "folder") }
                .help("Finder에서 자동 저장 폴더 보기")
            Spacer()
            Button(env.hasOpenProject ? "닫기" : "나중에") { env.showProjectPicker = false }
                .keyboardShortcut(.cancelAction)
            Button("열기") { if let selection { env.switchProject(to: selection) } }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
        }
        .padding(16)
    }

    private func reload() {
        projects = env.savedProjects()
        selection = projects.first { project in
            !(env.projectURL.map { AppEnvironment.isSameFile($0, project.url) } ?? false)
        }?.url ?? projects.first?.url
        // 이미 열린 프로젝트보다 '다른' 최근 프로젝트를 먼저 골라 두어 엔터 한 번으로 전환한다.
        let urls = projects.map(\.url)
        Task {
            let names = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: urls.map { ($0, ProjectLevelPeek.levelNames(at: $0) ?? []) })
            }.value
            levelNames = names
        }
    }
}
