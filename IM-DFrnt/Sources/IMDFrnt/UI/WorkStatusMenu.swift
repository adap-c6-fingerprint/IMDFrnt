import SwiftUI

/// 상태 아이콘. 누르면 네 상태 중 하나를 고른다(신기능 12항).
struct WorkStatusMenu: View {
    let status: LayerWorkStatus
    let onSelect: (LayerWorkStatus) -> Void

    var body: some View {
        Menu {
            ForEach(LayerWorkStatus.allCases) { s in
                Button { onSelect(s) } label: {
                    Label(s.title, systemImage: s == status ? "checkmark" : s.systemImage)
                }
            }
        } label: {
            WorkStatusIcon(status: status)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("상태: \(status.title) — 눌러서 바꿉니다")
    }
}

struct WorkStatusIcon: View {
    let status: LayerWorkStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 15)
    }
}
