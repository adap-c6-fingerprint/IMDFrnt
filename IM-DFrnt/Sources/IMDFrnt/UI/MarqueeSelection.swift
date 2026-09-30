import AppKit
import CoreGraphics
import SwiftUI

/// 드래그 사각형의 화면 좌표(명세 디버깅 9번).
///
/// 도면 좌표가 아니라 **화면** 좌표로 들고 있는 이유는, 그리기는 화면에 그대로 얹으면 되고
/// 판정할 때만 한 번 도면 좌표로 옮기면 되기 때문이다. 반대로 도면 좌표로 들고 있으면
/// 드래그 중에 확대·팬이 끼어들 때 사각형이 손에서 미끄러진다.
///
/// 세 작업 화면(메인 캔버스 · 보조 개체 제외 · Anchor)이 같은 것을 쓴다.
/// 화면마다 따로 만들면 이번처럼 한 곳만 고쳐지고 나머지는 그대로 남는다.
struct MarqueeRect {
    var start: CGPoint
    var current: CGPoint

    var rect: CGRect {
        CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
               width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    /// 오른쪽에서 왼쪽으로 끌면 '스치면 선택'. 도면 CAD의 관례와 같다.
    var isCrossing: Bool { current.x < start.x }

    var mode: HitTester.MarqueeMode { isCrossing ? .crossing : .enclose }

    /// 클릭과 드래그를 가르는 이동량(pt). 손이 떨려 몇 픽셀 움직인 것까지
    /// 사각형 선택으로 받으면 클릭이 사라진다.
    static let dragThreshold: CGFloat = 4
}

/// 드래그 중인 사각형 그림. 두 방식이 눈으로 구분돼야 결과를 예측할 수 있어
/// '완전히 감싸기'는 실선, '스치면 선택'은 점선으로 그린다.
struct MarqueeOverlay: View {
    let marquee: MarqueeRect?
    let background: CanvasBackground

    var body: some View {
        if let m = marquee {
            let color = background.selection
            Path { $0.addRect(m.rect) }
                .fill(color.opacity(0.14))
                .overlay(
                    Path { $0.addRect(m.rect) }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.2,
                                                          dash: m.isCrossing ? [5, 3] : []))
                )
                .allowsHitTesting(false)
        }
    }
}

extension NSEvent {
    /// 지금 option 키가 눌려 있는가. SwiftUI `DragGesture`는 수식키를 값으로 주지 않아
    /// (`.modifiers(_:)`는 제스처 자체를 갈라놔 드래그가 도중에 끊긴다) 직접 물어본다.
    static var optionHeld: Bool { modifierFlags.contains(.option) }
}
