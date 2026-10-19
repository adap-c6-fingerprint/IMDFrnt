import Foundation

/// 도형 없이 정보만 갖는 type(address·building·occupant·manifest)의 입력(2026-10-19 요청).
///
/// **레이어를 만들지 않는다.** 이 type들은 그릴 도형이 없어 레이어를 만들어도 캔버스에서 할 일이 없었고,
/// 빈 레이어만 쌓였다. 좌측 목록에서 누르면 정보 입력 창이 뜨고, 거기서 feature를 더하고 속성을 넣는다.
/// 저장 위치는 종전과 같은 지금 층의 feature 목록이다 — 내보내기가 모든 층에서 모아 쓰므로 바꿀 필요가 없다.
@MainActor
extension AppEnvironment {
    /// 정보 입력 창을 연다. 예전에 만든 이 type의 레이어가 있으면 닫는다(feature는 그대로 남는다).
    func openMetadataEditor(_ type: IMDFFeatureType) {
        guard type.isMetadataOnly else { return }
        if let old = layers.layer(for: type) {
            perform("\(type.displayName) 레이어 닫기") { layers.close(old.id) }
        }
        metadataEditorType = type
    }

    /// 한 개만 둘 수 있는 type인가. manifest는 세트 메타데이터라 하나뿐이다.
    func metadataAllowsMore(_ type: IMDFFeatureType) -> Bool {
        type != .manifest || features.features(ofType: .manifest).isEmpty
    }

    /// 빈 속성(모두 null)의 feature를 하나 더한다. 실행취소 한 칸.
    @discardableResult
    func addMetadataFeature(_ type: IMDFFeatureType) -> FeatureGroupID? {
        guard type.isMetadataOnly, metadataAllowsMore(type) else { return nil }
        let serial = serials.next(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        perform("\(serial) 추가") { features.insert(f) }
        return f.id
    }
}
