import CoreGraphics
import Foundation

/// 확대·축소 규칙. **세 작업 화면(메인 캔버스 · 보조 개체 제외 · Anchor 지정)이 함께 쓴다.**
///
/// 한 곳에 모은 이유는 세 화면의 상한이 제각각이었기 때문이다 —
/// 메인 8배, 보조 20배, Anchor 20배. 정작 태깅을 하는 주 화면이 가장 덜 확대됐다.
/// 화면마다 따로 적으면 이런 어긋남을 알아챌 방법이 없다.
enum CanvasZoom {

    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 200
    /// 상한 200배. 도면 단위로 벽 두께나 문틈처럼 몇 단위짜리 간격을 눈으로 확인하려면
    /// 종전 8배로는 어림도 없다. 하한은 세 화면 중 가장 관대하던 0.1로 맞춘다.

    static func clamp(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    /// Node/edge inspector layout changes must not reset zoom/pan (#90).
    /// onAppear fits the first layout; this only retries an initially unusable viewport.
    static func routingResizeNeedsFit(from old: CGSize, to new: CGSize) -> Bool {
        let wasUsable = old.width.isFinite && old.height.isFinite && old.width > 1 && old.height > 1
        let isUsable = new.width.isFinite && new.height.isFinite && new.width > 1 && new.height > 1
        return !wasUsable && isUsable
    }

    // MARK: 선 두께 — 상한만 올리면 확대가 소용없어지는 이유

    /// 확대해도 선이 더 굵어지지 않는 시점(배율).
    static let strokeGrowthCap: CGFloat = 4

    /// 도면 좌표계에 그릴 선 두께.
    ///
    /// **이 함수가 이번 변경의 실질이다.** `Canvas`가 `scaleBy(s)`로 좌표를 늘리므로
    /// 선 두께도 s배로 함께 늘어난다. 8배까지는 티가 안 나지만 50배·200배에서는
    /// 벽선 하나가 화면을 덮어, 확대 상한만 올려 놓으면 **더 크게 볼 수는 있는데
    /// 아무것도 안 보이는** 상태가 된다.
    ///
    /// 그래서 `strokeGrowthCap`배 시점의 화면 두께에서 성장을 멈춘다.
    /// - 4배 이하에서는 계산 결과가 종전과 **완전히 같다.** 지금까지 보던 화면이 안 바뀐다.
    /// - 그 위에서는 화면상 두께가 고정되어, 확대할수록 도형 사이 간격이 실제로 벌어져 보인다.
    /// - 얇아지는 쪽(축소)은 건드리지 않았다. 이번 요청은 확대이고, 축소 쪽 규칙을 같이 바꾸면
    ///   지금 잘 보이는 화면까지 흔들린다.
    static func strokeWidth(_ raw: CGFloat, at scale: CGFloat, emphasis: CGFloat = 1) -> CGFloat {
        max(0.6, raw) * emphasis * min(scale, strokeGrowthCap) / max(scale, 0.0001)
    }

    /// 배율과 무관하게 **화면상 크기가 일정해야 하는** 것의 도면 좌표 길이.
    /// 선택 강조 테두리·마커·점선 간격처럼 "도면의 일부"가 아니라 "화면에 얹은 표시"가 여기 해당한다.
    /// 보정하지 않으면 200배에서 선택 테두리가 개체에서 화면 밖까지 멀어진다.
    static func screenLength(_ points: CGFloat, at scale: CGFloat) -> CGFloat {
        points / max(scale, 0.0001)
    }

    // MARK: 표시

    /// 줌 컨트롤에 쓰는 배율 문구.
    /// 200배를 `20000%`로 쓰면 자릿수가 넘쳐 칸을 벗어난다. 10배부터는 `×` 표기로 바꾼다 —
    /// 그 구간에서는 사람도 백분율보다 배수로 생각한다.
    static func label(_ scale: CGFloat) -> String {
        if scale >= 10 { return String(format: "%.0f×", scale) }
        return "\(Int((scale * 100).rounded()))%"
    }
}
