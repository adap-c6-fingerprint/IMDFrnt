import AppKit
import SwiftUI

/// 드래그 거리를 사이드바 폭으로 옮기는 계산.
/// 뷰에서 떼어낸 이유는 검증 때문이다 — 리사이즈는 실제 마우스 드래그가 얽혀
/// `--selftest`가 조작 자체를 재현할 수 없으므로, 최소한 방향과 한계값만은
/// GUI 없이 확인할 수 있는 형태로 남긴다(디버깅 1번이 완료 보고 후 재발한 전례).
enum SidebarResizeMath {

    static func width(base: CGFloat,
                      translation: CGFloat,
                      edge: HorizontalEdge,
                      range: ClosedRange<CGFloat>) -> CGFloat {
        let delta = edge == .leading ? translation : -translation
        // 오른쪽 사이드바는 핸들이 왼편에 있어 같은 드래그가 반대 결과를 낸다.
        return min(range.upperBound, max(range.lowerBound, base + delta))
    }
}

/// 사이드바 + 드래그 구분선을 한 덩어리로 묶은 컨테이너.
/// `NavigationSplitView` 대신 `HStack`으로 3분할을 짰기 때문에 리사이즈를 직접 만든다.
///
/// **드래그 중에는 폭을 로컬 `@State`(`dragWidth`)에만 쓴다.** 이것이 이 파일의 핵심이다 —
/// 폭을 `AppEnvironment`의 `@Published`에 매 프레임 쓰면 그 객체를 구독하는 뷰가 전부
/// (캔버스·양쪽 사이드바 포함) 매 프레임 `body`를 다시 계산한다. 캔버스는 도면 전체를 그리는
/// 무거운 `Canvas`라 프레임이 밀리고, 그 결과가 "드래그하면 원위치에서 깜빡이다가
/// 손을 떼야 옮겨지는" 증상이었다(디버깅 1·13번).
/// 로컬 상태로 바꾸면 드래그 중 다시 계산되는 것은 이 컨테이너의 레이아웃뿐이다.
struct ResizableSidebar<Content: View>: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let edge: HorizontalEdge
    // .leading = 왼쪽 사이드바(핸들이 오른쪽에), .trailing = 오른쪽 사이드바(핸들이 왼쪽에)
    @ViewBuilder var content: () -> Content

    @State private var dragWidth: CGFloat?
    @State private var dragBase: CGFloat?
    @State private var hovering = false
    @State private var cursorPushed = false

    private var current: CGFloat { dragWidth ?? width }
    private var isDragging: Bool { dragWidth != nil }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .trailing { handle }
            content()
                .frame(width: current)
                .clipped()
                // 폭이 줄어드는 도중 내용이 넘쳐 이웃 뷰 위로 삐져나오는 것을 막는다.
            if edge == .leading { handle }
        }
        .animation(nil, value: current)
        // 사이드바 접기에 걸린 `withAnimation`이 드래그 폭까지 보간하면 커서보다 뒤처진다.
    }

    private var handle: some View {
        Rectangle()
            .fill(hovering || isDragging ? Color.accentColor.opacity(0.55) : Color.clear)
            .frame(width: 8)
            // 보이는 선은 가운데 `Divider` 1px이고, 8px은 잡는 영역이다.
            // 5px일 때는 겨냥이 자주 빗나가 "잘 안 잡힌다"는 체감으로 이어졌다.
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                syncCursor()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    // 0으로 둬야 누르는 즉시 반응한다. 1이면 첫 1px이 씹혀 뻑뻑하게 느껴진다.
                    // 전역 좌표계를 쓰는 이유는 드래그로 이 뷰의 폭이 바뀌기 때문이다 —
                    // 로컬 좌표계는 뷰가 움직이면 translation이 그만큼 어긋나 값이 발진한다.
                    .onChanged { value in
                        let base = dragBase ?? width
                        if dragBase == nil { dragBase = base }
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            dragWidth = SidebarResizeMath.width(
                                base: base,
                                translation: value.translation.width,
                                edge: edge,
                                range: range)
                        }
                        syncCursor()
                    }
                    .onEnded { _ in
                        if let w = dragWidth { width = w }
                        // 확정된 폭만 환경에 쓴다. 드래그가 끝난 시점의 한 번뿐이다.
                        dragWidth = nil
                        dragBase = nil
                        syncCursor()
                    }
            )
    }

    /// 커서를 좌우 화살표로 바꿔 드래그 가능하다는 것을 알린다.
    /// `push`/`pop` 횟수가 어긋나면 커서 스택이 쌓여 다른 화면에서도 화살표가 남으므로,
    /// 상태를 하나 두고 실제로 바뀔 때만 호출한다.
    private func syncCursor() {
        let wanted = hovering || isDragging
        // 드래그 중에는 커서가 핸들 밖으로 나가도 화살표를 유지한다 — 실제로 리사이즈 중이기 때문이다.
        guard wanted != cursorPushed else { return }
        cursorPushed = wanted
        if wanted { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
    }
}
