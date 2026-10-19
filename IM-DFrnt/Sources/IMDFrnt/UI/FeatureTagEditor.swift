import SwiftUI

/// 이름표를 누르면 뜨는 작은 편집 창. 그 feature의 category와 name을 바로 정한다(2026-10-19 요청).
/// 우측 패널 카드까지 가지 않아도 되게 하려는 것이다. 칸은 우측 패널과 같은 `PropertySlotRow`를 쓴다.
struct FeatureTagEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let featureID: FeatureGroupID

    /// 이름표 창에 놓을 칸. category 목록이 있는 레이어의 category, 이름을 적을 수 있는 레이어의 name이다.
    static func fields(for type: IMDFFeatureType) -> [PropertyField] {
        PropertySchema.fields(for: type).filter { field in
            (field.key == "category" && !PropertySchema.categoryOptions(for: type).isEmpty)
                || (field.key == "name" && field.type == .localizedName)
        }
    }

    var body: some View {
        if let f = env.features.feature(featureID) {
            VStack(alignment: .leading, spacing: 8) {
                Text(f.serialNumber).font(.caption.monospaced().weight(.semibold))
                ForEach(Self.fields(for: f.featureType)) { field in
                    PropertySlotRow(feature: f, field: field)
                }
            }
            .padding(12)
            .frame(width: 300)
        }
    }
}
