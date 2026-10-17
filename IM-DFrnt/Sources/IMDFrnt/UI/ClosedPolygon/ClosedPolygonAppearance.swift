import SwiftUI

/// '닫힌 다각형 보기' 창의 색과 수치(신기능 5-2: "면/선/점은 서로 다른 색으로 표시한다").
///
/// **뷰에서 떼어낸 이유는 검증이다.** 세 가지가 서로 구분되는지는 이 기능이 성립하는 조건인데,
/// 색이 뷰 안에 박혀 있으면 `--selftest`가 "정말 다른 색인가"를 확인할 방법이 없다
/// (`AuxiliaryOpacity`·`DoorClosureAppearance`와 같은 규칙).
enum ClosedPolygonAppearance {

    /// 면 — 채움. 선·점보다 옅다. 면은 넓이를 차지하므로 같은 진하기로 칠하면
    /// 그 위에 그린 선과 점을 덮어 버린다.
    static let faceFill = Color(red: 0.25, green: 0.55, blue: 0.95)
    static let faceFillOpacity: Double = 0.22

    /// 고른 면. 채움 색을 바꾸지 않고 **진하기만** 올린다 — 색까지 바뀌면
    /// "고른 것"과 "다른 종류의 면"이 구분되지 않는다.
    static let selectedFillOpacity: Double = 0.55

    /// 지금 레이어에서 태깅(저장)한 선·면. 초록이다 — 회색이면 도면 선·비활성 개체와 구별되지 않아
    /// 어디까지 태깅했는지 한눈에 안 보인다(2026-10-17 요청). 파랑(선택·고를 수 있는 면)·청록(경계선)·
    /// 노랑(꼭짓점)·주황(강조·제외)·보라(임시 문)·빨강(이상치) 어느 것과도 겹치지 않는다.
    static let savedFill = Color(red: 0.16, green: 0.66, blue: 0.24)
    static let savedFillOpacity: Double = 0.35

    /// 다른 레이어(property type)에서 태깅한 면·선·점·개체. 지금 레이어의 태깅 초록보다 **옅은 초록**이다
    /// (2026-10-17 요청: 편집 중이 아닌 레이어의 태깅 결과도 지금 화면에서 보이게, 단 더 옅게).
    /// 회색이던 것을 바꿨다 — 회색은 도면 선·비활성 개체와 섞여 다른 레이어가 무엇을 가져갔는지 안 보였다.
    /// 지금 레이어에서는 여전히 고를 수 없다(비활성 그대로). 색만 "이미 태깅됨"을 알린다.
    static let otherLayerFill = Color(red: 0.62, green: 0.86, blue: 0.6)
    static let otherLayerFillOpacity: Double = 0.18
    // 채움. 지금 레이어(`savedFillOpacity` 0.35)의 절반쯤이라 겹쳐도 지금 레이어가 위에서 또렷하다.
    static let otherLayerStrokeOpacity: Double = 0.8
    // 선. 옅은 색이라 채움보다는 진하게 두어야 밝은 배경에서도 윤곽이 보인다.

    /// 지금 보고 있는 저장 개체 — 우측 사이드바에서 펼친 카드이거나 '이 feature만 보기'(눈)로 띄운 것.
    /// 초록 태깅 색과 확실히 갈라지는 주황이다. 파랑(고를 수 있는 면·선택)과 노랑(꼭짓점)과도 겹치지 않는다.
    static let highlightFill = Color(red: 1.0, green: 0.42, blue: 0.1)
    static let highlightFillOpacity: Double = 0.45

    /// 선 — 면의 경계. 면보다 진하고 점보다 어둡다.
    static let edgeStroke = Color(red: 0.15, green: 0.75, blue: 0.6)

    /// 점 — 꼭짓점·교차점.
    static let vertexFill = Color(red: 1.0, green: 0.72, blue: 0.15)

    /// 임시 문으로 닫힌 면의 표시색. 도면에 없는 선으로 닫힌 면이라는 것을
    /// 알고 고르는 편이 낫다.
    static let temporaryDoorAccent = Color(red: 0.85, green: 0.4, blue: 0.95)

    static let edgeWidth: CGFloat = 1.4
    static let vertexRadius: CGFloat = 2.6

    /// 세 가지가 서로 다른 색인가. `--selftest`가 확인한다.
    static var facesLinesPointsAreDistinct: Bool {
        Set([faceFill.description, edgeStroke.description, vertexFill.description]).count == 3
    }
}
