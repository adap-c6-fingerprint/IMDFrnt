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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
