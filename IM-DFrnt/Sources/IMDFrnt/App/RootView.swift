import SwiftUI

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var monitor: SelectModifierMonitor?

    var body: some View {
        VStack(spacing: 0) {
            ProjectFileToolbar()
            if !env.buildingProject.levels.isEmpty {
                Divider()
                LevelTabBar()
            }
            Divider()
            editorContent
        }
        .sheet(isPresented: $env.showBuildingManager) { BuildingManager().environmentObject(env) }
        .sheet(isPresented: $env.showProjectPicker) { ProjectPicker().environmentObject(env) }
        .navigationTitle(env.projectDisplayName)
        .navigationSubtitle(env.projectSaveStatus)
    }

    private var editorContent: some View {
        Group {
            if env.showRoutingScreen {
                RoutingScreen()
            } else if env.showMapAlignScreen {
                MapAlignScreen()
                // 신기능 11항(#31). 지도를 넓게 써야 하는 작업이라 Anchor 화면처럼 전체 화면 전환이다.
            } else if env.showAnchorScreen {
                AnchorScreen()
                // 명세 9항: Anchor 지정은 시트가 아니라 전체 화면 전환이다.
            } else if env.showDoorClosureScreen {
                DoorClosureScreen()
                // 신기능 3항. Anchor·보조 개체 창과 같은 이유로 전체 화면 전환이다.
            } else if env.showCurvedScreen {
                CurvedScreen()
                // 명세 3-3의 "창이 열림"을 그대로 따른다. 모드로 두었을 때는 변화가
                // 옅기 25% 차이뿐이라 눌러도 아무 일이 없는 것처럼 보였다(2026-08-27).
            } else if env.showAuxiliaryScreen {
                AuxiliaryScreen()
                // 보조 개체 제외도 같은 이유로 전체 화면이다(명세 디버깅 6번).
            } else {
                HStack(spacing: 0) {
                    if env.showLeftSidebar {
                        ResizableSidebar(width: $env.leftSidebarWidth,
                                         range: 200...460,
                                         edge: .leading) { LeftSidebar() }
                    }

                    CanvasView()
                        .frame(minWidth: 360)

                    if env.showRightSidebar {
                        ResizableSidebar(width: $env.rightSidebarWidth,
                                         range: 260...620,
                                         edge: .trailing) { RightSidebar() }
                    }
                }
                .overlay(alignment: .topLeading) { sidebarToggle(.leading) }
                .overlay(alignment: .topTrailing) { sidebarToggle(.trailing) }
            }
        }
        .disabled(env.isProjectBusy)
        .overlay {
            if let task = env.longTask, task.isVisible { LongTaskOverlay(task: task) }
            // IMDF 불러오기도 이 팝업으로 진행률을 보인다. 끝나면 `longTask`가 비워져 저절로 닫힌다.
        }
        .animation(.easeOut(duration: 0.15), value: env.longTask?.isVisible)
        .environment(\.canvasBackground, env.canvasBackground)
        // 상단바 색은 시스템 외관이 아니라 캔버스 배경을 따라야 한다(디버깅 10번).
        // `ButtonStyle`은 `@EnvironmentObject`를 못 받으므로 여기서 한 번 흘려보낸다.
        .overlay(alignment: .top) { bannerView }
        .overlay { if env.closedPolygonNotice != nil { polygonNotice } }
        .onAppear { startMonitor() }
        .onDisappear { monitor?.stop() }
        .alert(env.pendingDeletion?.title ?? "삭제할까요?", isPresented: Binding(
            get: { env.pendingDeletion != nil && !env.showBuildingManager },
            set: { if !$0 { env.cancelDeletion() } }
        ), presenting: env.pendingDeletion) { request in
            Button("취소", role: .cancel) { env.cancelDeletion() }
                .keyboardShortcut(.defaultAction)
            Button(role: .destructive) { env.confirmDeletion(request.id) } label: {
                Text("삭제").foregroundStyle(.red)
            }
        } message: { request in
            Text(request.message)
        }
        .alert("이미 저장된 개체입니다", isPresented: Binding(
            get: { env.conflict != nil },
            set: { if !$0 { env.conflict = nil } }
        ), presenting: env.conflict) { info in
            Button("\(info.ownerType.displayName) 레이어로 이동") {
                env.selectPropertyType(info.ownerType)
                env.expandedFeature = info.ownerFeature
                if let f = env.features.feature(info.ownerFeature) {
                    env.selection.selected = f.memberIDs
                }
                env.conflict = nil
            }
            Button("현재 레이어에 남기", role: .cancel) { env.conflict = nil }
        } message: { info in
            Text("이미 \(info.ownerType.displayName) 레이어에서 \(info.ownerSerial)으로 저장된 개체입니다. 이 개체를 \(env.layers.activePropertyType?.displayName ?? "현재 type")으로 바꾸려면, \(info.ownerType.displayName)에서 저장을 해제하세요.")
        }
        // 신기능 1-2-5. 합치기는 남의 작업을 내 작업에 섞는 일이라, 무엇이 들어오고
        // 무엇이 막혔는지 반드시 보여준다. 조용히 건너뛰면 내보내기 단계에서야 드러난다.
        .alert("배정본 합치기 결과", isPresented: Binding(
            get: { env.mergeReportMessage != nil },
            set: { if !$0 { env.mergeReportMessage = nil } }
        )) {
            Button("확인", role: .cancel) { env.mergeReportMessage = nil }
        } message: {
            Text(env.mergeReportMessage ?? "")
        }
        .alert("파일로 변환할 수 없습니다", isPresented: Binding(
            get: { !env.exportBlockers.isEmpty },
            set: { if !$0 { env.exportBlockers = [] } }
        )) {
            Button("확인", role: .cancel) { env.exportBlockers = [] }
        } message: {
            Text(env.exportBlockers.map(\.message).joined(separator: "\n\n"))
        }
        .alert("IMDF 아카이브를 만들 수 없습니다", isPresented: Binding(
            get: { !env.archiveExportBlockers.isEmpty },
            set: { if !$0 { env.archiveExportBlockers = [] } }
        )) {
            Button("확인", role: .cancel) { env.archiveExportBlockers = [] }
        } message: {
            Text(env.archiveExportBlockers.joined(separator: "\n\n"))
        }
        // 명세 디버깅 7번. 보조 개체 창에서도 떠야 하므로 화면 분기 **바깥**의 최상위에 붙인다.
        .alert("전체 선택 해제", isPresented: Binding(
            get: { env.pendingClearSelection != nil },
            set: { if !$0 { env.cancelClearSelection() } }
        ), presenting: env.pendingClearSelection) { _ in
            Button("예") { env.confirmClearSelection() }
            Button("아니오", role: .cancel) { env.cancelClearSelection() }
        } message: { target in
            Text("현재 선택중인 모든 개체(\(env.selectionCount(target))개)를 선택 해제하시겠습니까?")
        }
    }

    /// 폴리곤 type 레이어를 열었을 때 한 번 뜨는 안내(신기능 5-2).
    private var polygonNotice: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Label("모든 닫힌 다각형을 표시했습니다.", systemImage: "checkmark.seal")
                    .font(.headline)
                Text(env.closedPolygonNotice ?? "")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("보조 개체 제외 창 열기") {
                        env.closedPolygonNotice = nil
                        env.enterAuxiliaryScreen()
                    }
                    // 안내가 가리키는 처방을 **그 자리에서 실행할 수 있게** 둔다.
                    // 문장으로만 알려주면 메뉴를 다시 찾아야 한다.
                    Button("확인") { env.closedPolygonNotice = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    /// 사이드바가 닫혀 있을 때만 보이는 펼치기 버튼.
    /// 열려 있을 때의 접기 버튼은 각 사이드바 헤더 안에 있다.
    @ViewBuilder
    private func sidebarToggle(_ edge: HorizontalEdge) -> some View {
        let isOpen = edge == .leading ? env.showLeftSidebar : env.showRightSidebar
        if !isOpen {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if edge == .leading { env.showLeftSidebar = true }
                    else { env.showRightSidebar = true }
                }
            } label: {
                Image(systemName: edge == .leading
                      ? "sidebar.leading" : "sidebar.trailing")
            }
            .buttonStyle(.bordered)
            .padding(8)
            .help(edge == .leading ? "왼쪽 사이드바 펼치기" : "오른쪽 사이드바 펼치기")
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let b = env.banner {
            Text(b.text)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(b.isError ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.85),
                            in: Capsule())
                .foregroundStyle(.white)
                .shadow(radius: 6, y: 2)
                .padding(.top, 8)
                .allowsHitTesting(false)
                // 배너는 알림일 뿐이다. 클릭을 받으면 그 아래 '작업 화면으로 돌아가기' 같은 버튼이 눌리지 않는다.
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(b.id)
                .task(id: b.id) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if env.banner?.id == b.id { env.banner = nil }
                }
        }
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        let m = SelectModifierMonitor { down in
            Task { @MainActor in env.selectModifierDown = down }
        }
        m.start()
        monitor = m
    }
}
