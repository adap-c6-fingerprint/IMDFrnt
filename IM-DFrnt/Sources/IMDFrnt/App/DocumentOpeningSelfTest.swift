import AppKit
import Foundation

@MainActor
enum DocumentOpeningSelfTest {
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--document-open-selftest") else { return }
        await run()
    }

    private static func run() async {
        var count = 0, failures = 0
        func check(_ title: String, _ value: Bool) {
            count += 1; if !value { failures += 1 }
            print("[\(value ? "PASS" : "FAIL")] \(title)")
        }
        check("문서 검사는 NSApplication 초기화 없이 실행", NSApp == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntDocumentOpen-\(UUID())")
        let suite = "IMDFrntDocumentOpen.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        func environment(_ name: String) -> AppEnvironment {
            AppEnvironment(autosaveFolder: directory.appendingPathComponent(name, isDirectory: true), projectDefaults: defaults)
        }
        func wait(_ coordinator: DocumentOpenCoordinator) async {
            for _ in 0..<100 where coordinator.hasPendingRequests { try? await Task.sleep(for: .milliseconds(10)) }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
            check("빌드된 앱이 프로젝트 Editor/Owner 문서 연결을 선언", documents.contains {
                ($0["LSItemContentTypes"] as? [String])?.contains("com.imdfrnt.project") == true &&
                $0["CFBundleTypeRole"] as? String == "Editor" && $0["LSHandlerRank"] as? String == "Owner"
            })
            check("기존 SVG·PNG·JPEG 문서 타입 유지", documents.contains {
                Set($0["LSItemContentTypes"] as? [String] ?? []) == ["public.svg-image", "public.png", "public.jpeg"]
            })
            let declarations = Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]] ?? []
            let extensions = (declarations.first { $0["UTTypeIdentifier"] as? String == "com.imdfrnt.project" }?["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String] ?? []
            check("현재·이전 프로젝트 확장자를 같은 UTI에 등록", extensions.contains("imdfrnt") && extensions.contains("imdfproj"))

            let source = environment("source")
            source.openSample()
            source.enterRoutingScreen()
            source.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 1, modifiers: .command)
            let nodeID = source.routingSelectedNodeID!
            let first = source.makeProjectFile()!
            let second = ProjectFile.empty()
            let firstURL = directory.appendingPathComponent("first.imdfrnt")
            let secondURL = directory.appendingPathComponent("second.imdfrnt")
            let legacyURL = directory.appendingPathComponent("legacy.imdfproj")
            try first.encoded().write(to: firstURL)
            try second.encoded().write(to: secondURL)
            try first.encoded().write(to: legacyURL)

            let env = environment("direct")
            check("외부 프로젝트 열기로 ID·데이터·저장 위치 복원", env.openDocument(at: firstURL) == .opened && env.projectID == first.projectID && env.routing.node(nodeID) != nil && env.projectURL == firstURL && !env.hasUnsavedChanges)
            let reopenedFile = try ProjectFile.decoded(from: Data(contentsOf: firstURL))
            check("외부 열기한 파일 자체가 이 프로젝트의 자동 저장 파일", reopenedFile.hasSameContents(as: env.makeProjectFile()!))
            env.updateRoutingNode(nodeID, field: "name") { $0.name = "미저장 편집" }
            let unsaved = env.makeProjectFile()!
            var asked = false
            check("현재 프로젝트 재열기는 미저장 수정 보존·중복 질문 없음", env.openDocument(at: firstURL, confirmingChanges: { asked = true; return false }) == .opened && !asked && env.hasUnsavedChanges && env.makeProjectFile()!.hasSameContents(as: unsaved))
            let beforeRecovery = try Data(contentsOf: firstURL)
            check("다른 프로젝트 열기 취소는 현재 작업·파일 위치 유지", env.openDocument(at: secondURL, confirmingChanges: { false }) == .cancelled && env.projectURL == firstURL && env.makeProjectFile()!.hasSameContents(as: unsaved))
            check("취소는 프로젝트 파일도 바꾸지 않음", try Data(contentsOf: firstURL) == beforeRecovery)
            let brokenURL = directory.appendingPathComponent("broken.imdfrnt")
            try Data("broken".utf8).write(to: brokenURL)
            asked = false
            check("손상 파일은 작업 교체 질문 없이 거절", env.openDocument(at: brokenURL, confirmingChanges: { asked = true; return true }) == .failed && !asked && env.makeProjectFile()!.hasSameContents(as: unsaved))
            check("없는 파일은 현재 작업 보존", env.openDocument(at: directory.appendingPathComponent("missing.imdfrnt")) == .failed && env.makeProjectFile()!.hasSameContents(as: unsaved))
            check("지원하지 않는 파일/URL 거절", env.openDocument(at: directory.appendingPathComponent("file.txt")) == .failed && env.openDocument(at: URL(string: "https://example.com/file.imdfrnt")!) == .failed)
            check("편집 중에는 외부 파일 열기를 즉시 적용하지 않음", {
                env.isImportingIMDF = true; defer { env.isImportingIMDF = false }
                return env.openDocument(at: secondURL) == .failed && env.makeProjectFile()!.hasSameContents(as: unsaved)
            }())
            check("기존 작업 자동 저장 후 다른 프로젝트와 파일 위치 적용", env.openDocument(at: secondURL) == .opened && env.projectID == second.projectID && env.document == nil && env.projectURL == secondURL && !env.hasUnsavedChanges &&
                  (try? ProjectFile.decoded(from: Data(contentsOf: firstURL)))?.commonProject().routingGraph.node(nodeID)?.name == "미저장 편집")
            check("이전 .imdfproj 파일도 같은 경로로 열기", env.openDocument(at: legacyURL) == .opened && env.projectID == first.projectID && env.routing.node(nodeID) != nil)

            let queued = DocumentOpenCoordinator()
            var result: DocumentOpenResult?
            queued.enqueue([firstURL]) { result = $0 }
            check("시작 전 파일 요청은 환경이 생길 때까지 보존", result == nil && queued.hasPendingRequests)
            let fresh = environment("queued")
            queued.attach(fresh)
            await wait(queued)
            check("환경 연결 후 대기한 프로젝트를 한 번 열기", result == .opened && fresh.projectID == first.projectID && fresh.projectURL == firstURL && !queued.hasPendingRequests)
            result = nil
            queued.enqueue([secondURL]) { result = $0 }
            await wait(queued)
            check("실행 중 파일 전달도 새 프로젝트 열기", result == .opened && fresh.projectID == second.projectID)
            result = nil
            fresh.isImportingIMDF = true
            queued.enqueue([firstURL]) { result = $0 }
            try? await Task.sleep(for: .milliseconds(30))
            check("가져오기 중에는 요청 대기·현재 프로젝트 보존", result == nil && fresh.projectID == second.projectID && queued.hasPendingRequests)
            fresh.isImportingIMDF = false
            await wait(queued)
            check("가져오기 종료 후 요청 처리", result == .opened && fresh.projectID == first.projectID)
            result = nil
            queued.enqueue([firstURL, secondURL]) { result = $0 }
            await wait(queued)
            check("여러 파일 요청은 부분 교체 없이 거절", result == .failed && fresh.projectID == first.projectID)

            let delegate = AppDelegate()
            delegate.openDocuments([firstURL])
            let connected = environment("delegate")
            delegate.connectEnvironment(connected)
            for _ in 0..<100 where connected.projectURL == nil { try? await Task.sleep(for: .milliseconds(10)) }
            check("AppDelegate 공통 파일 요청을 실제 프로젝트 열기에 연결", connected.projectID == first.projectID && connected.projectURL == firstURL)
            delegate.connectEnvironment(connected)
            check("화면 재등장은 요청 프로젝트를 복구본으로 덮어쓰지 않음", connected.projectID == first.projectID)

            if let i = CommandLine.arguments.firstIndex(of: "--document-open-fixtures"), CommandLine.arguments.indices.contains(i + 1) {
                let output = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try first.encoded().write(to: output.appendingPathComponent("first.imdfrnt"))
                try second.encoded().write(to: output.appendingPathComponent("second.imdfrnt"))
                let expected = ["first": first.projectID.uuidString.lowercased(), "second": second.projectID.uuidString.lowercased()]
                try JSONEncoder().encode(expected).write(to: output.appendingPathComponent("expected.json"))
            }
        } catch { check("문서 연결·열기 통합 검사", false); print(error) }
        print("== Document open: \(count - failures)/\(count) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
