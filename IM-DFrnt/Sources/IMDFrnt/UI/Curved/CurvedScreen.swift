import SwiftUI

/// '곡선 개체만 따로 보기' 전용 창(명세 3-3).
/// Anchor·보조 개체·문 닫기 창과 같은 이유로 전체 화면 전환이다.
struct CurvedScreen: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    CurvedDrawingPane()
                    actionBar.padding(.top, 12)
                    // 상단바는 선택이 없어도 항상 뜬다 — 이 창에서는 무엇을 더 해야 하는지가 곧 안내다.
                }
                ResizableSidebar(width: $env.auxiliarySidebarWidth,
                                 range: 240...520,
                                 edge: .trailing) { sidebar }
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "scribble")
            Text("곡선 개체만 따로 보기").font(.headline).fixedSize()
            Text("곡선을 골라 선분화합니다. 선분화해야 좌표를 뽑을 수 있습니다")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
            Spacer(minLength: 8)
            Text("선분화 \(env.segmentedCount) / 곡선 \(env.curvedObjectCount)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button("작업 화면으로 돌아가기") { env.exitCurvedScreen() }
                .keyboardShortcut(.escape, modifiers: [])
                .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Label("\(env.curvedSelectionCount)개 선택", systemImage: "hand.tap")
                .font(.caption.monospacedDigit())
                .foregroundStyle(env.curvedSelectionCount > 0 ? .primary : .secondary)

            ToolbarDivider().frame(height: 16)

            Button { env.segmentizeSelection() } label: {
                Label("선택 선분화", systemImage: "scissors")
            }
            .disabled(env.selection.isEmpty)

            Button { env.desegmentize(env.selection.selected) } label: {
                Label("선분화 해제", systemImage: "arrow.uturn.backward")
            }
            .disabled(env.selection.isEmpty)

            Button { env.segmentize(env.document?.curvedObjectIDs ?? []) } label: {
                Label("곡선 전체 선분화", systemImage: "wand.and.stars")
            }
            .disabled(env.curvedObjectCount == 0)

            ToolbarDivider().frame(height: 16)

            // ✅ 2026-08-30 신설 — 드래그 사각형의 방향 토글(요청 1-2).
            Button {
                env.marqueeSubtracts.toggle()
            } label: {
                Label(env.marqueeSubtracts ? "드래그: 해제" : "드래그: 선택",
                      systemImage: env.marqueeSubtracts
                        ? "minus.rectangle" : "plus.rectangle")
            }
            .help("켜면 드래그한 사각형에 걸린 개체가 선택에서 빠집니다. 꺼져 있으면 선택에 더해집니다. 클릭은 모드와 상관없이 뒤집기입니다.")

            ToolbarDivider().frame(height: 16)

            Toggle("선분화된 것만 보기", isOn: Binding(
                get: { env.curvedShowsSegmentedOnly },
                set: { env.setCurvedShowsSegmentedOnly($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("모든 곡선을 50%로 두고 선분화된 곡선만 100%로 보여줍니다(명세 3-3-3)")
        }
        .buttonStyle(.toolbarIcon)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .toolbarCard(cornerRadius: 10)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("곡선 개체").font(.headline)
                Spacer()
                Text("\(env.curvedObjectCount)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()

            HStack(spacing: 6) {
                Text("tolerance").font(.caption2)
                Slider(value: $env.segmentationTolerance, in: 0.1...4)
                Text(String(format: "%.1f", env.segmentationTolerance))
                    .font(.caption2.monospacedDigit()).frame(width: 26)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Text("값이 작을수록 곡선을 더 잘게 나눕니다. 꼭짓점이 늘어나는 만큼 파일도 커집니다.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            Divider().padding(.top, 8)

            if let doc = env.document {
                let curved = doc.objects.filter(\.isCurved)
                if curved.isEmpty {
                    Text("이 도면에는 곡선 개체가 없습니다.")
                        .font(.caption).foregroundStyle(.secondary).padding(12)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(curved, id: \.id) { o in row(o) }
                        }
                        .padding(8)
                    }
                }
            }
        }
    }

    private func row(_ o: VectorObject) -> some View {
        let picked = env.selection.selected.contains(o.id)
        let segmented = env.segmentation.isSegmented(o.id)
        return Button {
            env.selection.toggle(o.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: picked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                Circle()
                    .fill(segmented ? CurvedAppearance.segmented : CurvedAppearance.curved)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(o.sourceElement) #\(o.ordinal)")
                        .font(.caption.monospaced())
                    Text(segmented
                         ? "선분 \(env.segmentation.segmentation(for: o.id)?.segments.count ?? 0)개"
                         : "선분화 전")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3).padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .background(picked ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }
}
