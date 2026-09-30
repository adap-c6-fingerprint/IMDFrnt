import SwiftUI

/// 마우스를 올리면 뜨고 내리면 사라지는 반투명 검정 안내 창(신기능 5-5).
///
/// **왜 `.help`(시스템 툴팁)를 쓰지 않나:** 시스템 툴팁은 뜨기까지 1초 넘게 걸리고 폭이 좁아
/// 두 줄을 넘기는 문장이 잘린다. 여기 들어갈 문구는 **진행률 숫자를 어떻게 읽어야 하는지**를
/// 설명하는 두어 줄짜리라, 곧바로 뜨고 넓게 펼쳐지는 창이어야 한다.
struct HoverNote: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .topLeading) {
                if isHovering {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.black.opacity(0.82),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 300, alignment: .leading)
                        .offset(y: -6)
                        .allowsHitTesting(false)
                        // 창이 마우스를 가로채면 그 순간 hover가 풀려 창이 깜빡인다.
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    func hoverNote(_ text: String) -> some View { modifier(HoverNote(text: text)) }
}
