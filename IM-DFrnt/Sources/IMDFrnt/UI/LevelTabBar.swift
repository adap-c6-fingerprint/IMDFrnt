import SwiftUI

/// Level metadata is available before any drawing is parsed or rendered.
///
/// 신기능 12항: 층은 끌어서 화면 순서를 바꾼다(층 번호는 그대로다). 좌측 type이 모두 Complete인 층에는 초록 체크가 붙는다.
/// 층에 귀속되지 않는 정보 type(address·building·manifest·occupant)도 이 바의 오른쪽에 둔다.
struct LevelTabBar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(env.displayedLevels) { level in
                    Button { env.selectProjectLevel(level.id) } label: {
                        HStack(spacing: 7) {
                            if env.loadingLevelID == level.id {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: level.info.svg.isEmpty ? "square.dashed" : "map")
                            }
                            Text(level.info.name).lineLimit(1)
                            if env.isLevelComplete(level) {
                                WorkStatusIcon(status: .complete)
                                    .help("이 층의 모든 feature type이 Complete입니다")
                            }
                            if let short = level.info.shortName, !short.isEmpty, short != level.info.name {
                                Text(short).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(env.routingFloorID == level.id ? Color.accentColor.opacity(0.16) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(level.info.name) · 층 번호 \(level.info.ordinal)\n\(level.info.sourceName)")
                    .accessibilityIdentifier("level-tab-\(level.id.uuidString)")
                    .accessibilityValue(env.routingFloorID == level.id ? "선택됨" : "")
                    .draggable(level.id.uuidString) { Text(level.info.name).padding(6) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                        env.moveLevel(id, to: level.id)
                        return true
                    }
                }
                Divider().frame(height: 18).padding(.horizontal, 6)
                ForEach(AppEnvironment.metadataFeatureTypes) { type in
                    metadataChip(type)
                }
            }.padding(.horizontal, 12).padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .disabled(env.isProjectBusy)
        .accessibilityLabel("층 도면 탭")
    }

    /// 정보 type 하나. 상태 아이콘과 정보 입력 버튼이다(예전에는 좌측 type 목록에 있었다).
    private func metadataChip(_ type: IMDFFeatureType) -> some View {
        HStack(spacing: 5) {
            WorkStatusMenu(status: env.workStatus(type)) { env.setWorkStatus($0, for: type) }
            Button(type.displayName) { env.openMetadataEditor(type) }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(env.document == nil)
                .help("\(type.displayName) 정보 입력 — 층과 무관한 정보라 상단바에 둡니다")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}
