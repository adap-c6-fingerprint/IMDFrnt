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

    /// 이미 저장된 면. 고를 수 없다는 뜻을 회색으로 알린다.
    static let savedFill = Color(red: 0.55, green: 0.55, blue: 0.6)
    static let savedFillOpacity: Double = 0.35

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
