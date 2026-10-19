import SwiftUI

/// fixture 선 단위의 상단바(2026-10-19 요청). 모드 전환과 안내는 늘 보이고, 개체를 고르면 그 아래에
/// 종전 개체 선택 상단바('Feature로 저장' 등)가 뜬다.
struct ObjectToolbar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                LayerEditModePicker()
                Text(env.selection.isEmpty
                     ? "도면 개체를 클릭하거나 드래그해 고르세요. 고른 개체가 fixture 하나가 됩니다."
                     : "\(env.selection.selected.count)개 골랐습니다. 'Feature로 저장'을 누르면 fixture 하나로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .toolbarCard(cornerRadius: 10)
            if !env.selection.isEmpty {
                SelectionToolbar()
            }
        }
    }
}
