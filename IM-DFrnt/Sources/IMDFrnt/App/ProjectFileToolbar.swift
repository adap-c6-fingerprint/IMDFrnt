import SwiftUI

struct ProjectFileToolbar: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var showDrawingLayers = false

    var body: some View {
        HStack(spacing: 14) {
            Menu("파일") {
                Button("새 프로젝트") { env.newProject() }
                Button("프로젝트 선택…") { env.showProjectPickerIfIdle() }
                Divider()
                Button("IMDF 불러오기…") { env.importIMDF() }
                Button(".imdfrnt 불러오기…") { env.openProject() }
                Button("도면 열기…") { env.openFile() }
                Divider()
                Button("노드/엣지 내보내기…") { env.exportNavigationDataset() }
                    .disabled(env.buildingProject.levels.isEmpty)
                Button("IMDF 아카이브 내보내기… (모든 층)") { env.exportIMDFArchive() }
                    .disabled(env.buildingProject.levels.isEmpty)
                Button("Sandbox 검사용 내보내기… (Opening 경계 오류만 우회)") { env.exportIMDFForSandbox() }
                    .disabled(env.buildingProject.levels.isEmpty)
                    .help("Opening–Unit 경계 불일치만 허용한 검사용 ZIP입니다. 다른 오류와 일반 내보내기의 검증은 유지합니다.")
                Button("클라이언트용 묶음 내보내기… (지도+길찾기)") { env.exportClientDataset() }
                    .disabled(env.buildingProject.levels.isEmpty)
            }
            .fixedSize()
            .disabled(env.isProjectBusy)
            Button { env.showProjectPickerIfIdle() } label: {
                Label(env.hasSomethingToPersist ? env.projectDisplayName : "IM-DFrnt", systemImage: "building.2")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(env.isProjectBusy)
            .help((env.projectURL?.path ?? "아직 자동 저장 전입니다.") + "\n눌러서 다른 프로젝트를 선택합니다.")
            // 지금 어떤 프로젝트가 열려 있는지 보이는 자리에서 바로 전환할 수 있게 한다.
            Text(env.projectSaveStatus)
                .font(.caption)
                .foregroundStyle(env.hasUnsavedChanges ? Color.orange : Color.secondary)
                .accessibilityIdentifier("project-save-status")
            Spacer()
            if !env.buildingProject.levels.isEmpty {
                Picker("층", selection: Binding(get: { env.routingFloorID }, set: { id in
                    if let id { env.selectProjectLevel(id) }
                })) {
                    ForEach(env.buildingProject.levels.sorted { $0.info.ordinal < $1.info.ordinal }) {
                        Text($0.info.name).tag(Optional($0.id))
                    }
                }.frame(width: 170)
            }
            if env.activeLevel != nil {
                Button { showDrawingLayers.toggle() } label: { Label("도면 레이어", systemImage: "square.3.layers.3d") }
                    .popover(isPresented: $showDrawingLayers) { DrawingLayersPanel().padding(16).frame(width: 310) }
                    .disabled(env.isProjectBusy)
            }
            Button("건물·층 관리") {
                if !env.hasCreatedProject { env.newProject() }
                if env.hasCreatedProject { env.showBuildingManager = true }
            }.disabled(env.isProjectBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
