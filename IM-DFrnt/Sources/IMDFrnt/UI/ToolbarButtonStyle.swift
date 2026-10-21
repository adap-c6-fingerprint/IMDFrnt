import SwiftUI

/// 상단바가 지금 어느 캔버스 배경 위에 떠 있는지. `ButtonStyle`은 `@EnvironmentObject`를
/// 받을 수 없어서, 색을 정하는 데 필요한 이 값만 따로 environment로 흘려보낸다.
private struct CanvasBackgroundKey: EnvironmentKey {
    static let defaultValue: CanvasBackground = .light
}

extension EnvironmentValues {
    var canvasBackground: CanvasBackground {
        get { self[CanvasBackgroundKey.self] }
        set { self[CanvasBackgroundKey.self] = newValue }
    }
}

/// 상단바 버튼의 색·배경을 정하는 순수 규칙.
/// 뷰에서 떼어낸 이유는 `--selftest`가 GUI 없이 이 수치를 검증할 수 있게 하려는 것이다 —
/// 상단바 가시성 문제(디버깅 10번)는 눈으로만 잡히던 종류라 재발을 수치로 못박아 둔다.
enum ToolbarButtonAppearance {

    static let enabledOpacity: Double = 1.0
    /// 누를 수 있는 버튼은 절대 흐려지지 않는다.
    /// `.borderless` 기본 스타일이 활성 버튼을 흐리게 그려서 "비활성인 줄 알았는데 눌리는" 문제가 났다.

    static let disabledOpacity: Double = 0.3
    /// 진짜 비활성만 흐리다. 활성과 확실히 갈라져야 눌러도 되는지 한눈에 판단된다.

    static let idleBackground: Double = 0.0
    static let borderedIdleBackground: Double = 0.10
    static let hoverBackground: Double = 0.20
    static let pressedBackground: Double = 0.32

    static func opacity(isEnabled: Bool) -> Double {
        isEnabled ? enabledOpacity : disabledOpacity
    }

    static func background(isEnabled: Bool, isHovering: Bool, isPressed: Bool,
                           bordered: Bool = false) -> Double {
        let base = bordered ? borderedIdleBackground : idleBackground
        guard isEnabled else { return base }
        // 비활성 버튼에 hover 배경이 뜨면 눌릴 것처럼 보여 오히려 혼란스럽다.
        if isPressed { return pressedBackground }
        if isHovering { return hoverBackground }
        return base
    }
}

/// 상단바 전용 버튼 스타일.
///
/// 색을 `CanvasBackground`에서 뽑는 것이 핵심이다. 상단바는 도면 위에 떠 있는 요소라
/// **캔버스 배경**이 실질적인 바탕이고, 시스템 외관(`.primary`)은 그것과 무관하게 움직인다.
/// 둘이 어긋나는 순간(시스템 다크 + 캔버스 밝게) 흰 글씨가 흰 카드에 묻힌다 — 디버깅 10번.
struct ToolbarButtonStyle: ButtonStyle {

    /// 아이콘만 있는 버튼용. 글자가 없어 눌릴 곳을 못 찾으므로 평상시에도 옅은 바탕을 깐다.
    var bordered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(configuration: configuration, bordered: bordered)
    }

    private struct ToolbarButtonBody: View {
        let configuration: Configuration
        let bordered: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.canvasBackground) private var bg
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(bg.toolbarForeground)
                .opacity(ToolbarButtonAppearance.opacity(isEnabled: isEnabled))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bg.toolbarForeground.opacity(
                            ToolbarButtonAppearance.background(
                                isEnabled: isEnabled,
                                isHovering: hovering,
                                isPressed: configuration.isPressed,
                                bordered: bordered)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { ToolbarButtonStyle() }
    static var toolbarIcon: ToolbarButtonStyle { ToolbarButtonStyle(bordered: true) }
}

/// 상단바 카드 자체(바탕·테두리·그림자). 카드가 여러 화면에 흩어져 있어
/// 한 곳에서 정하지 않으면 이번처럼 한쪽만 고쳐져 다시 어긋난다.
struct ToolbarCard: ViewModifier {
    @Environment(\.canvasBackground) private var bg
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .foregroundStyle(bg.toolbarForeground)
            .background(bg.toolbarFill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(bg.toolbarStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
    }
}

/// 캡슐형 카드(모드 표시·범례). 모서리만 다르고 규칙은 `ToolbarCard`와 같다.
struct ToolbarCapsuleCard: ViewModifier {
    @Environment(\.canvasBackground) private var bg

    func body(content: Content) -> some View {
        content
            .foregroundStyle(bg.toolbarForeground)
            .background(bg.toolbarFill, in: Capsule())
            .overlay(Capsule().stroke(bg.toolbarStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }
}

extension View {
    func toolbarCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(ToolbarCard(cornerRadius: cornerRadius))
    }

    func toolbarCapsuleCard() -> some View {
        modifier(ToolbarCapsuleCard())
    }

    /// 상단바 안의 `Menu`에도 같은 색 규칙을 적용하기 위한 도우미.
    /// `Menu`는 `ButtonStyle`을 받지 않아 라벨 쪽에서 직접 색을 지정해야 한다.
    func toolbarMenuLabel(isEnabled: Bool) -> some View {
        modifier(ToolbarMenuLabel(isEnabled: isEnabled))
    }
}

struct ToolbarMenuLabel: ViewModifier {
    let isEnabled: Bool
    @Environment(\.canvasBackground) private var bg

    func body(content: Content) -> some View {
        content
            .foregroundStyle(bg.toolbarForeground)
            .opacity(ToolbarButtonAppearance.opacity(isEnabled: isEnabled))
    }
}

/// 캔버스 위에 뜨는 막대를 캔버스 폭 안에 담는다.
///
/// 들어가면 제 크기 그대로 두고, 넘치면 가로로 스크롤한다. 스크롤 막대를 보여 옆에 더 있다는 것을 알린다
/// (숨기면 오른쪽 버튼이 잘린 것처럼만 보였다). **막대를 억지로 줄이지 않는 이유:**
/// 줄이면 버튼 글자가 한 글자씩 줄바꿈돼 버튼이 세로로 길쭉한 빈 상자가 되고, 그래도 넘친 폭이
/// 캔버스 칸을 밀어 오른쪽 사이드바를 덮는다.
struct CanvasBarFit<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content.fixedSize()
            ScrollView(.horizontal, showsIndicators: true) {
                content.fixedSize().padding(.vertical, 10).padding(.horizontal, 4)
                // 카드 그림자가 스크롤 영역 가장자리에서 잘리지 않게 여백을 둔다.
            }
        }
        .padding(.horizontal, 12)
    }
}

/// 상단바 안 구분선. `.quaternary`는 시스템 외관을 따라가 카드 바탕과 어긋나므로 쓰지 않는다.
struct ToolbarDivider: View {
    @Environment(\.canvasBackground) private var bg

    var body: some View {
        Rectangle()
            .fill(bg.toolbarForeground.opacity(0.22))
            .frame(width: 1, height: 22)
    }
}
