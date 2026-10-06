import AppKit
import SwiftUI

@main
struct IMDFrntApp: App {
    @StateObject private var env = AppEnvironment()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("IM-DFrnt") {
            RootView()
                .environmentObject(env)
                .environmentObject(env.moves)
                .frame(minWidth: 1180, minHeight: 720)
                .onAppear {
                    delegate.env = env
                    // 종료 확인 팝업이 이 환경을 저장해야 하므로 델리게이트에 건네준다.
                    // `@NSApplicationDelegateAdaptor`는 SwiftUI 환경을 못 받는다.
                    env.restoreAutosaveIfAvailable()
                    env.startAutosaveLoop()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("도면 열기…") { env.openFile() }
                    .keyboardShortcut("o")
                Divider()
                Button("작업 열기…") { env.openProject() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("작업 저장") { env.saveProject() }
                    .keyboardShortcut("s")
                    .disabled(!env.hasSomethingToPersist)
                Button("다른 이름으로 저장…") { env.saveProject(as: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!env.hasSomethingToPersist)
                Divider()
                Button("작업 몫 나눠주기…") { env.shareSelectionAsAssignment() }
                    .disabled(!env.canShareAssignment)
                Button("배정본 합치기…") { env.mergeAssignments() }
                    .disabled(env.document == nil || env.assignment != nil)
                // 신기능 1-2. 좌측 사이드바에도 같은 두 항목이 있다 —
                // 메뉴는 발견성이 낮아 사이드바가 정식 입구이고, 여기는 단축 경로다.
                // 명세 7-3-2·9-7. 저장이 없으면 앱을 닫는 순간 UUID 대장이 사라져
                // 다시 내보낼 때 새 id가 발급된다 — IMDF 스펙 위반이다.
            }
            CommandGroup(replacing: .undoRedo) {
                Button(env.undoMenuTitle) { env.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!env.canUndo)
                Button(env.redoMenuTitle) { env.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!env.canRedo)
                // 시스템 기본 실행취소 항목을 대체한다. 남겨두면 `UndoManager`를 보는 빈 메뉴가
                // 같은 단축키를 두고 다투게 된다(명세 디버깅 8번).
            }
            CommandMenu("도구") {
                Button("길찾기 노드 편집") { env.enterRoutingScreen() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(env.document == nil)
                Button("길찾기 GeoJSON 내보내기…") { env.exportRoutingGraph() }
                    .disabled(env.routing.nodes.isEmpty)
                Divider()
                Button("Anchor 지정 화면") { env.enterAnchorScreen() }
                    .keyboardShortcut("k")
                    .disabled(env.showRoutingScreen)
                Button("전체 선택 해제") { env.requestClearSelection(.main) }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(env.selection.isEmpty)
                // 상단바 버튼과 같은 확인 팝업을 태운다(명세 디버깅 7번).
                // 손으로 고른 선택이 한 번에 날아가는 것은 어느 경로로 눌러도 똑같이 위험하다.
                Toggle("겹치는 곳 윤곽 표시", isOn: $env.showOverlapHighlight)
                Button("모든 개체 원위치") { env.resetPositions() }
                    .disabled(!env.hasAnyOffset)
                Divider()
                Button(env.showRoutingScreen ? "길찾기 GeoJSON 내보내기" : "geojson 내보내기") { env.export() }
                    .keyboardShortcut("e")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @MainActor weak var env: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RoutingSelfTest.runIfRequested()
        _ = SelfTest.runIfRequested()
        // --selftest 인자가 있으면 여기서 점검 결과를 출력하고 종료한다.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // 번들 없이 `swift run`으로 띄울 때도 창이 앞으로 나오게 한다.

        DispatchQueue.main.async { NSApp.windows.first?.delegate = self }
        // 창 닫기 버튼도 종료 확인을 거쳐야 한다(신기능 1-1-2). 창은 지금 시점에 아직 없다.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 창 닫기 버튼(신기능 1-1-2). **닫지 않고 종료 경로로 넘긴다.**
    /// 여기서 그냥 닫아 버리면 `applicationShouldTerminate`가 뒤늦게 팝업을 띄우게 되는데,
    /// '아니오'를 눌러도 창은 이미 닫힌 뒤라 돌아갈 화면이 없다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    /// cmd+Q · 메뉴 종료 · 창 닫기가 **모두 이 한 곳**을 지난다.
    /// 명세는 "앱 창 닫기"만 말하지만, cmd+Q가 확인 없이 빠져나가면
    /// "종료해도 작업이 모두 저장돼요"라는 약속이 그 경로에서만 깨진다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let env else { return .terminateNow }
        guard MainActor.assumeIsolated({ env.confirmTermination() }) else {
            return .terminateCancel
        }
        // 저장은 끝났고, 배너("작업이 모두 저장되었어요!")를 읽을 시간만 남겨 둔다.
        // 시스템 알림을 쓰지 않는 이유는 알림 권한을 요구하기 때문이다 —
        // 종료 한 번 알리려고 권한을 묻는 것은 과하다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
