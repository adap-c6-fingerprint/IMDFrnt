import SwiftUI

/// 폴리곤 type 레이어의 상단바(신기능 5-4).
///
/// **선택이 없어도 항상 뜬다.** 이 모드에서는 *무엇을 더 해야 하는지*가 곧 안내다 —
/// 비활성 버튼만 있고 이유가 없으면 고장으로 읽힌다(문 닫기 창 3-4와 같은 이유).
struct PolygonToolbar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        HStack(spacing: 10) {
            LayerEditModePicker()
            if env.isComputingDerivedGeometry {
                ProgressView().controlSize(.mini)
                Text("다각형 계산 중").font(.caption2).foregroundStyle(.secondary)
            }
            Picker("", selection: Binding(
                get: { env.polygonWorkMode },
                set: { env.setPolygonWorkMode($0) }
            )) {
                ForEach(PolygonWorkMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(env.polygonWorkMode.help)

            ToolbarDivider().frame(height: 16)

            Text("\(env.faceSelection.count) / \(env.selectableFaceCount)개 선택")
                .font(.caption.monospacedDigit())
                .foregroundStyle(env.faceSelection.isEmpty ? .secondary : .primary)
                .fixedSize()
            // 신기능 5-4 1·2번: 상단바에 선택된 다각형 수 카운트.
            // 분모를 함께 보여주는 것은 제외 모드 때문이다 — 전부 고른 상태에서 빼 나가는데
            // 남은 개수만 보이면 얼마나 뺐는지 알 수 없다.

            Button {
                env.saveSelectedFaces()
            } label: {
                Label("선택한 다각형 모두 저장", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(env.faceSelection.isEmpty)
            .help("고른 면을 \(env.layers.activePropertyType?.displayName ?? "현재 type")의 Feature로 저장합니다")

            ToolbarDivider().frame(height: 16)

            Button("전체 선택") { env.selectAllFaces() }
                .disabled(env.closedPolygonFaces.isEmpty)
            Button("선택 해제") { env.clearFaceSelection() }
                .disabled(env.faceSelection.isEmpty)
        }
        .buttonStyle(.toolbarIcon)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .toolbarCard(cornerRadius: 10)
    }
}
