import SwiftUI

/// 상태 아이콘. 누르면 네 상태 중 하나를 고른다(신기능 12항).
///
/// `Menu`를 쓰지 않는다. macOS는 메뉴 버튼의 아이콘과 펼친 메뉴 항목을 단색 템플릿으로 그려
/// 상태 색(초록·파랑·노랑·빨강)이 지워진다. 버튼과 팝오버는 SwiftUI가 직접 그려 색이 남는다.
struct WorkStatusMenu: View {
    let status: LayerWorkStatus
    let onSelect: (LayerWorkStatus) -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            WorkStatusIcon(status: status)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("상태: \(status.title) — 눌러서 바꿉니다")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(LayerWorkStatus.allCases) { s in
                    Button {
                        onSelect(s)
                        isOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            WorkStatusIcon(status: s)
                            Text(s.title)
                            Spacer(minLength: 12)
                            if s == status {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(s == status ? Color.secondary.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(minWidth: 150)
        }
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
