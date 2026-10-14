import SwiftUI

/// Level metadata is available before any drawing is parsed or rendered.
struct LevelTabBar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(env.buildingProject.levels.sorted { $0.info.ordinal < $1.info.ordinal }) { level in
                    Button { env.selectProjectLevel(level.id) } label: {
                        HStack(spacing: 7) {
                            if env.loadingLevelID == level.id {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: level.info.svg.isEmpty ? "square.dashed" : "map")
                            }
                            Text(level.info.name).lineLimit(1)
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
                }
            }.padding(.horizontal, 12).padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .disabled(env.isProjectBusy)
        .accessibilityLabel("층 도면 탭")
    }
}
