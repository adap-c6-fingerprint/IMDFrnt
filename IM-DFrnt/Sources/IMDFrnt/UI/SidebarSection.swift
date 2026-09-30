import SwiftUI

/// 사이드바 안에서 접었다 펼 수 있는 항목 하나와, 그것들을 한 번에 접는 버튼.
///
/// **접는 상태를 뷰가 아니라 `AppEnvironment`에 두는 이유**는 '모두 접기' 때문이다.
/// 각 섹션이 자기 `@State`로 상태를 들고 있으면 바깥에서 한 번에 바꿀 방법이 없다.
/// 한 곳에 모아 두면 버튼은 그냥 키 목록을 넣고 빼기만 하면 된다.
enum SidebarSectionID: String, CaseIterable {

    // 좌측 사이드바
    case leftShare, leftProgress, leftMode, leftAnchor, leftGate, leftTypes, leftLayers
    // 우측 사이드바
    case rightTrash
    // `rightFeatures`(카드 전부를 감싸던 최상위 트리)는 2026-08-26에 없앴다 —
    // 상위 토글 하나로 통째로 접히면 카드별 토글이 뜻을 잃는다.
    // 보조 개체 제외 창
    case auxGroups
    // 문 임시로 닫기 창
    case doorList
    // Anchor 지정 화면
    case anchorPairs

    /// 어느 사이드바에 속하는가. '모두 접기'가 **자기 사이드바만** 건드리게 하려는 것이다 —
    /// 한 버튼이 다른 창의 항목까지 접으면, 그 창에 갔을 때 접힌 이유를 알 수 없다.
    enum Owner: CaseIterable {
        case left, right, auxiliary, door, anchor
    }

    var owner: Owner {
        switch self {
        case .leftShare, .leftProgress, .leftMode, .leftAnchor, .leftGate, .leftTypes, .leftLayers:
            return .left
        case .rightTrash: return .right
        case .auxGroups: return .auxiliary
        case .doorList: return .door
        case .anchorPairs: return .anchor
        }
    }

    static func all(in owner: Owner) -> [SidebarSectionID] {
        allCases.filter { $0.owner == owner }
    }
}

/// 접었다 펼 수 있는 사이드바 항목.
struct SidebarSection<Content: View>: View {
    @EnvironmentObject var env: AppEnvironment

    let id: SidebarSectionID
    let title: String
    var badge: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let collapsed = env.isSectionCollapsed(id)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { env.toggleSection(id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .frame(width: 10)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                // 제목 줄 전체가 눌려야 한다. 화살표만 눌리면 표적이 10pt짜리가 된다.
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if !collapsed { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// '모두 접기' 버튼.
///
/// 우측 사이드바에서 이 버튼은 **feature 카드마다 달린 개별 토글을 한꺼번에 움직인다**
/// (2026-08-26). 카드 전부를 감싸는 상위 트리를 접는 것이 아니다.
///
/// **접기만 있고 펴기가 없으면 되돌릴 방법이 항목을 하나씩 누르는 것뿐이다.**
/// 그래서 전부 접힌 상태에서는 같은 자리에서 '모두 펼치기'로 바뀐다 —
/// 버튼을 두 개 두지 않는 이유는, 둘 중 하나는 항상 아무 일도 안 하는 버튼이 되기 때문이다.
struct SidebarCollapseAllButton: View {
    @EnvironmentObject var env: AppEnvironment

    let owner: SidebarSectionID.Owner

    var body: some View {
        let ids = SidebarSectionID.all(in: owner)
        let allCollapsed = env.areAllSectionsCollapsed(in: owner)
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if allCollapsed { env.expandAllSections(in: owner) }
                else { env.collapseAllSections(in: owner) }
            }
        } label: {
            Label(allCollapsed ? "모두 펼치기" : "모두 접기",
                  systemImage: allCollapsed
                    ? "arrow.down.left.and.arrow.up.right"
                    : "arrow.up.right.and.arrow.down.left")
                .font(.caption2)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(allCollapsed
              ? "이 사이드바의 항목을 모두 펼칩니다."
              : "이 사이드바의 항목을 모두 접습니다. 목록이 길 때 원하는 항목까지 스크롤하는 수고를 줄입니다.")
        .disabled(ids.isEmpty && owner != .right)
        // 우측은 섹션이 하나도 없어도(휴지통이 비었을 때) 카드가 남아 있어 할 일이 있다.
    }
}
