import SwiftUI

/// 지도 위 Anchor 마커. 도면 쪽(`AnchorDrawingPane.drawMarker`)과 **같은 십자 형태**다.
///
/// 원래는 지름 14pt의 원(블루닷)이었다. 원은 그 중심이 어디인지 눈으로 특정할 수 없어
/// 건물 모서리에 맞추는 정밀 조정에 쓸 수 없다 — 마커가 가린 자리가 곧 찍어야 할 자리다.
/// 십자는 선이 만나는 한 점이 곧 좌표이고, 그 점 주변이 가려지지 않는다.
/// 도면과 지도의 마커 모양을 같게 두는 것도 목적이다. 두 화면에서 같은 지점을 짝지어야 하는데
/// 모양이 다르면 무엇과 무엇을 맞추는 중인지 눈으로 대조하기 어렵다.
struct AnchorMapMarker: View {
    let index: Int
    let isOutlier: Bool

    private let radius: CGFloat = 11

    var body: some View {
        ZStack {
            crosshair(lineWidth: 3.6, color: .white.opacity(0.9))
            crosshair(lineWidth: 1.6, color: isOutlier ? .red : .cyan)
            // 위성 이미지 위에서는 한 가지 색만으로 어떤 지붕에서도 보이게 할 수 없다.
            // 흰 선을 굵게 깔고 그 위에 색을 얹어, 밝은 옥상과 어두운 그림자 양쪽에서 모두 보이게 한다.

            Text("\(index)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOutlier ? Color.red : .cyan)
                .shadow(color: .white, radius: 1.5)
                .offset(x: radius + 7, y: -radius - 1)
        }
        .frame(width: radius * 2 + 2, height: radius * 2 + 2)
        .allowsHitTesting(false)
        // 마커가 클릭을 먹으면 마커를 집는 드래그가 지도까지 닿지 않는다.
        // 집기 판정은 좌표 거리로 하므로(`nearestAnchor`) 마커 자체는 그림이기만 하면 된다.
    }

    private func crosshair(lineWidth: CGFloat, color: Color) -> some View {
        Path { p in
            let c = CGPoint(x: radius + 1, y: radius + 1)
            p.move(to: CGPoint(x: c.x - radius, y: c.y))
            p.addLine(to: CGPoint(x: c.x + radius, y: c.y))
            p.move(to: CGPoint(x: c.x, y: c.y - radius))
            p.addLine(to: CGPoint(x: c.x, y: c.y + radius))
            p.addEllipse(in: CGRect(x: c.x - radius / 2, y: c.y - radius / 2,
                                    width: radius, height: radius))
            // 가운데 작은 원은 도면 마커와 같은 구성이다. 십자만 있으면 선이 도면의 벽선과
            // 섞여 보이는데, 원이 있으면 '마커'라는 것이 한눈에 구분된다.
        }
        .stroke(color, lineWidth: lineWidth)
        .frame(width: radius * 2 + 2, height: radius * 2 + 2)
    }
}
