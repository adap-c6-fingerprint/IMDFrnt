import SwiftUI

struct ProjectFileToolbar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        HStack(spacing: 14) {
            Menu("파일") {
                Button("새 프로젝트") { env.newProject() }
                Divider()
                Button("IMDF 불러오기…") { env.importIMDF() }
                Button("도면 열기…") { env.openFile() }
                Button("작업 열기…") { env.openProject() }
                Divider()
                Button("작업 저장") { env.saveProject() }
                    .disabled(!env.hasSomethingToPersist)
                Button("다른 이름으로 저장…") { env.saveProject(as: true) }
                    .disabled(!env.hasSomethingToPersist)
            }
            .fixedSize()
            .disabled(env.isProjectBusy)
            Label(env.hasSomethingToPersist ? env.projectDisplayName : "IM-DFrnt", systemImage: "doc")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .help(env.projectURL?.path ?? "저장 위치를 선택하지 않았습니다.")
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
            Button("건물·층 관리") {
                if !env.hasCreatedProject { env.newProject() }
                if env.hasCreatedProject { env.showBuildingManager = true }
            }.disabled(env.isProjectBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
