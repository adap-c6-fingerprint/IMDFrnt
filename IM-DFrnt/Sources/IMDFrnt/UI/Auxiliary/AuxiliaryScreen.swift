import SwiftUI

/// '똑같이 생긴 개체 모두 표시' 버튼의 글자(엔진 디버깅 1-2번, 2026-08-25).
///
/// **뷰에서 떼어낸 이유는 `AuxiliaryOpacity`와 같다 — 검증이다.** 복수 선택을 허용하면
/// 100%로 뜨는 개체가 여러 쌍둥이 그룹의 합집합이 되는데, 그 사실을 화면이 말해 주는 것이
/// 이번 완화의 전제 조건이다. 라벨이 뷰 안에 문자열 보간으로 박혀 있으면 `--selftest`가
/// "그룹 수를 정말 보여주는가"를 확인할 방법이 없다.
enum TwinToggleText {

    /// 버튼 라벨. 켜져 있을 때는 **그룹 수와 총 개수를 함께** 보여준다.
    /// 그룹이 하나뿐이면 "N그룹"은 군더더기라 개수만 쓴다 — 뜻이 없는 숫자는 읽는 데 방해만 된다.
    static func label(isOn: Bool, groupCount: Int, objectCount: Int) -> String {
        guard isOn else { return "똑같이 생긴 개체 모두 표시" }
        if groupCount <= 1 { return "쌍둥이 \(objectCount)개 표시 중" }
        return "쌍둥이 \(groupCount)그룹 · \(objectCount)개 표시 중"
    }

    /// 비활성 이유·동작 설명. 이유 없이 흐린 버튼은 고장으로 읽힌다(뷰 디버깅 10번의 오해와 같은 종류).
    static func help(selectionCount: Int, groupCount: Int) -> String {
        if selectionCount == 0 { return "개체를 하나 이상 선택하면 쓸 수 있습니다" }
        if groupCount > 1 {
            return "선택한 \(selectionCount)개가 걸친 쌍둥이 \(groupCount)그룹 전체를 100%로, 나머지를 75%로 표시합니다"
        }
        return "선택한 개체와 모든 값이 똑같은 쌍둥이 개체를 100%로, 나머지를 75%로 표시합니다"
    }
}

/// '보조 개체 제외' 전용 창(명세 디버깅 6번).
/// 도면에 섞여 들어온 치수 숫자·보조선처럼 어떤 property type에도 속하지 않는 개체를
/// 태깅 대상에서 빼둔다. Anchor 화면과 같은 이유로 시트가 아니라 전체 화면 전환이다 —
/// 도면 전체를 훑으며 수십 개를 골라내는 작업이라 화면이 넓어야 한다.
struct AuxiliaryScreen: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    AuxiliaryDrawingPane()
                    if !env.auxiliarySelection.isEmpty {
                        selectionBar
                            .padding(.top, 12)
                    }
                }
                ResizableSidebar(width: $env.auxiliarySidebarWidth,
                                 range: 260...560,
                                 edge: .trailing) { sidebar }
                // 320 고정이던 것을 메인 화면과 같은 방식으로 바꿨다(명세 디버깅 13번,
                // "모든 작업 화면에 대해 수정할 것"). 쌍둥이 그룹 이름이 길어 좁으면 잘린다.
            }
        }
    }

    // MARK: 제목 줄

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed.inset.filled")
            Text("보조 개체 제외").font(.headline).fixedSize()
            Text("도면의 숫자·보조선처럼 property type 태깅 대상이 아닌 개체를 골라 뺍니다")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
            // 창을 좁히면 **이 설명이 가장 먼저 줄어야 한다**(뷰 디버깅 16번).
            // 우선순위를 안 주면 SwiftUI가 모든 텍스트를 고르게 줄여, 개수와 버튼 글자까지 잘린다.
            Spacer(minLength: 8)
            Text("제외 \(env.excludedCount) / 전체 \(env.totalObjectCount)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button("작업 화면으로 돌아가기") { env.exitAuxiliaryScreen() }
                .keyboardShortcut(.escape, modifiers: [])
                .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: 개체 선택 상단 바 (명세 디버깅 6번)

    private var selectionBar: some View {
        HStack(spacing: 0) {
            Text("\(env.auxiliarySelection.count)개 선택")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)

            divider

            Button { env.markSelectedAsAuxiliary() } label: {
                Label("보조 개체로 지정", systemImage: "nosign")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)

            divider

            Button { env.showTwinsOnly.toggle() } label: {
                Label(twinToggleLabel, systemImage: "square.on.square.intersection.dashed")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .disabled(!env.canShowTwins)
            .help(twinToggleHelp)

            if env.showTwinsOnly {
                divider
                Button { env.markTwinsAsAuxiliary() } label: {
                    Label("똑같이 생긴 개체 모두 지정", systemImage: "square.stack.3d.down.forward")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
            }

            if selectionHasExcluded {
                divider
                Button { env.unmarkSelectedAsAuxiliary() } label: {
                    Label("지정 풀기", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
            }

            divider

            // ✅ 2026-08-30 신설 — 드래그 사각형의 방향 토글(요청 1-2).
            // 이 창은 ⌥드래그가 이미 화면 이동이라, 수식키로 빼기를 표현할 자리가 없다.
            Button {
                env.marqueeSubtracts.toggle()
            } label: {
                Label(env.marqueeSubtracts ? "드래그: 해제" : "드래그: 선택",
                      systemImage: env.marqueeSubtracts
                        ? "minus.rectangle" : "plus.rectangle")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .help("켜면 드래그한 사각형에 걸린 개체가 선택에서 빠집니다. 꺼져 있으면 선택에 더해집니다. 클릭은 모드와 상관없이 뒤집기입니다.")

            divider

            // 메인 상단바와 같은 규칙(명세 디버깅 7번). 여기서도 손으로 고른 선택이 한 번에 날아간다.
            Button {
                env.requestClearSelection(.auxiliary)
            } label: {
                Label("전체 선택 해제", systemImage: "xmark.circle")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
        }
        .frame(height: 38)
        .toolbarCard()
    }

    private var twinToggleHelp: String {
        TwinToggleText.help(selectionCount: env.auxiliarySelection.count,
                            groupCount: env.selectedTwinGroupCount)
    }

    private var twinToggleLabel: String {
        TwinToggleText.label(isOn: env.showTwinsOnly,
                             groupCount: env.selectedTwinGroupCount,
                             objectCount: env.twins(of: env.auxiliarySelection).count)
    }

    private var selectionHasExcluded: Bool {
        env.auxiliarySelection.contains { env.auxiliary.isExcluded($0) }
    }

    private var divider: some View { ToolbarDivider() }

    // MARK: 창 전용 우측 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // 세그먼트 전환을 고른 이유는 `AppEnvironment.auxiliarySidebarGroups(_:)` 주석에 적었다.
                // 요약하면 개별 개체 목록이 길어 두 섹션을 쌓으면 그룹 목록을 밀어내기 때문이다.
                Picker("", selection: $env.auxiliarySidebarTab) {
                    ForEach(AppEnvironment.AuxiliarySidebarTab.allCases) { tab in
                        Text("\(tab.title) \(env.auxiliarySidebarGroups(tab).count)").tag(tab)
                        // 탭 이름에 개수를 붙인다 — 보고 있지 않은 쪽의 규모를 알아야
                        // "여기 없으면 저기 있겠구나"가 성립한다.
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(alignment: .top) {
                    Text(sidebarCaption)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    SidebarCollapseAllButton(owner: .auxiliary)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    SidebarSection(id: .auxGroups, title: env.auxiliarySidebarTab.title,
                                   badge: "\(env.auxiliarySidebarGroups(env.auxiliarySidebarTab).count)") {
                        ForEach(env.auxiliarySidebarGroups(env.auxiliarySidebarTab)) { group in
                            groupRow(group)
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    env.excludeAllAuxiliary()
                } label: {
                    Label("모든 보조 개체 제외", systemImage: "nosign")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(env.markedTwinGroups.isEmpty)
                .help("지정된 보조 개체가 속한 쌍둥이 그룹 전체를 태깅 대상에서 뺍니다")

                Text("지정된 그룹 \(env.markedTwinGroups.count)개 · 제외 개체 \(env.excludedCount)개")
                    .font(.caption2).foregroundStyle(.secondary)

                Button("모든 제외 해제") { env.clearAuxiliary() }
                    .controlSize(.small)
                    .disabled(env.excludedCount == 0)
            }
            .padding(12)
        }
    }

    private var sidebarCaption: String {
        switch env.auxiliarySidebarTab {
        case .twinGroups:
            return "모양·색·두께가 완전히 같은 개체끼리 묶었습니다. 위치는 보지 않습니다."
        case .soloObjects:
            return "도면에 하나뿐이라 어느 그룹에도 안 묶인 개체입니다. 방위표·범례처럼 반복되지 않는 보조 개체가 여기 있습니다."
        }
    }

    private func excludedCount(in group: AppEnvironment.TwinGroup) -> Int {
        group.memberIDs.filter { env.auxiliary.isExcluded($0) }.count
    }

    private func groupRow(_ group: AppEnvironment.TwinGroup) -> some View {
        let excluded = excludedCount(in: group)
        let isFocused = env.focusedTwinKey == group.key
        return HStack(spacing: 8) {
            Image(systemName: excluded == group.count ? "nosign"
                  : (excluded > 0 ? "circle.lefthalf.filled" : "square.on.square"))
                .foregroundStyle(excluded > 0 ? Color.orange : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.count > 1 ? group.label : group.sample.shapeSummary).font(.caption)
                // 개별 개체에 `× 1`을 붙이면 뜻 없는 숫자가 늘어난다. 하나뿐인 게 이 탭의 전제다.
                Text(group.sample.style.humanDescription)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if excluded > 0 {
                Text(group.count > 1 ? "\(excluded)/\(group.count) 제외" : "제외됨")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isFocused ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .onTapGesture {
            // 목록에서 고르면 그 모양만 100%, 나머지는 75%로 표시된다(명세 디버깅 6번).
            // **개별 개체 탭도 같은 코드를 쓴다.** 크기 1짜리 그룹의 키는 그 개체 하나만 가리키므로
            // `focusedTwinKey` 하나로 두 탭이 다 된다 — 개별 개체용 상태를 따로 두면 강조 대상이
            // 두 군데서 정해져 `auxiliaryHighlightedIDs`가 둘 중 뭘 먼저 볼지 규칙을 또 만들어야 한다.
            env.focusedTwinKey = isFocused ? nil : group.key
            env.auxiliarySelection = isFocused ? [] : Set(group.memberIDs)
        }
    }
}
