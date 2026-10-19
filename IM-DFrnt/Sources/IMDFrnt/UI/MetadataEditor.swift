import SwiftUI

/// 메타데이터 type의 정보 입력 창(2026-10-19 요청). 우측 패널과 같은 속성 칸(`PropertySlotRow`)을 쓴다.
struct MetadataEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let type: IMDFFeatureType

    var body: some View {
        let items = env.features.features(ofType: type)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(type.displayName) 정보").font(.headline)
                Spacer()
                Button("\(type.displayName) 추가") { env.addMetadataFeature(type) }
                    .disabled(!env.metadataAllowsMore(type))
                    .help(type == .manifest ? "manifest는 하나만 둡니다." : "빈 \(type.displayName)를 하나 더합니다.")
            }
            Text("도형이 없는 type이라 레이어를 만들지 않고 여기서 값을 넣습니다. 지금 층(\(env.activeLevel?.info.name ?? "-"))에 저장되고, 내보낼 때 모든 층의 값을 모읍니다."
                 + (type.note.isEmpty ? "" : " \(type.note)"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if items.isEmpty {
                Text("아직 없습니다. '\(type.displayName) 추가'를 누르세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { f in card(f) }
                    }
                }
                .frame(maxHeight: 460)
            }
            HStack {
                Spacer()
                Button("닫기") { env.metadataEditorType = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func card(_ f: FeatureGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(f.serialNumber).font(.callout.weight(.semibold))
                Spacer()
                Button(role: .destructive) { env.trash(f.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("휴지통으로 보냅니다. 실행 취소로 되돌릴 수 있습니다.")
            }
            ForEach(PropertySchema.fields(for: f.featureType)) { field in
                PropertySlotRow(feature: f, field: field)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
