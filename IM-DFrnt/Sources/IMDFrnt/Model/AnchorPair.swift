import Foundation

typealias AnchorID = UUID

/// 명세 9-1)의 Anchor 한 쌍.
/// IMDF의 `Anchor` Feature와 이름이 겹쳐 "Anchor"를 쓰지 않는다(0.1절 5번).
struct AnchorPair: Identifiable, Hashable, Codable, Sendable {
    let id: AnchorID
    var local: LocalPoint
    // from point — 도면 위 좌표
    var geo: GeoPoint
    // to point — 실제 위경도
    var label: String
    var residual: Double?
    // 변환식 계산 후 채워지는 잔차(m)
    var fromAlignment: Bool?
    // 지도 정렬 화면(신기능 11항)에서 정렬된 도면을 찍어 만든 쌍인가. 참이면 정렬을 고칠 때 위경도를 다시 계산한다.
    // 손으로 짝지은 쌍은 건드리지 않는다. 선택적이라 이전 파일도 그대로 읽힌다.

    init(id: AnchorID = UUID(), local: LocalPoint, geo: GeoPoint, label: String) {
        self.id = id
        self.local = local
        self.geo = geo
        self.label = label
        self.residual = nil
    }
}
