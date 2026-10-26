import SwiftUI

/// 명세 3~4항의 좌측 사이드바.
struct LeftSidebar: View {
    @EnvironmentObject var env: AppEnvironment
    @AppStorage("featureTypeSort") private var sortRaw = FeatureTypeSort.custom.rawValue
    // 정렬 기준은 보는 사람의 취향이라 프로젝트 파일이 아니라 이 Mac에 둔다. 드래그로 정한 순서는 프로젝트에 둔다.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SidebarSection(id: .leftShare, title: "다른 사람과 작업 공유") { shareSection }
                    // 신기능 1-2-1: '사이드바 펼치기 버튼 바로 하단'. 헤더 아래 첫 항목이 그 자리다.
                    Divider()
                    SidebarSection(id: .leftProgress, title: "진행률",
                                   badge: env.progressText) { progressSection }
                    SidebarSection(id: .leftMode, title: "보기 모드") { modeSection }
                    Divider()
                    SidebarSection(id: .leftAnchor, title: "Anchor 지정",
                                   badge: "\(env.sharedFootprint.anchors.pairs.count)쌍") { anchorEntry }
                    Divider()
                    SidebarSection(id: .leftGate, title: "Opening 게이트") { openingGateBar }
                    // property type 목록 **바로 위**에 둔다. 잠긴 이유를 목록 옆에서 즉시 읽어야
                    // "왜 안 눌리지"로 헤매지 않는다(명세 10-1-2).
                    SidebarSection(id: .leftTypes, title: "FEATURE TYPE") { typeSection }
                    SidebarSection(id: .leftLayers, title: "기본·필터 레이어",
                                   badge: "\(otherLayers.count)") { layerSection }
                    // feature type 레이어의 표시·투명도는 각 type 줄에서 바꾼다(신기능 12항). 여기에는 그 밖의 레이어만 남는다.
                    // 접힌 항목에도 **개수·진행률을 배지로 남긴다.** 접는 목적은 자리를 줄이는 것이지
                    // 상태를 감추는 것이 아니다 — 접어 두면 아무것도 모르게 되면 결국 다시 펴게 된다.
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("IM-DFrnt").font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { env.showLeftSidebar = false }
                } label: { Image(systemName: "sidebar.leading") }
                    .buttonStyle(.borderless)
                    .help("사이드바 접기")
            }
            Text(env.document?.sourceName ?? "도면 없음")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Button("열기…") { env.openFile() }
                    .controlSize(.small)
                Spacer()
                SidebarCollapseAllButton(owner: .left)
            }
            Button("IMDF 불러오기…") { env.importIMDF() }
                .controlSize(.small).disabled(env.isImportingIMDF)
            Button(".imdfrnt 불러오기…") { env.openProject() }
                .controlSize(.small).disabled(env.isProjectBusy)
            Button { env.enterRoutingScreen() } label: {
                Label("길찾기 노드 편집", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: 다른 사람과 작업 공유 (신기능 1-2)

    /// 지금 배정본을 열고 있으면 **공유 버튼 대신 담당 구역 안내**를 보여준다.
    /// 받은 사람에게 필요한 정보는 "내가 다시 나눠줄 수 있는가"가 아니라
    /// "내 몫이 어디까지인가"다. 같은 자리에 다른 것을 놓는 편이 항목을 늘리는 것보다 낫다.
    @ViewBuilder
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = env.assignment {
                assignmentBadge(a)
            } else {
                Button {
                    env.shareSelectionAsAssignment()
                } label: {
                    Label("작업 몫 나눠주기…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.small)
                .disabled(!env.canShareAssignment)
                .help(env.selection.isEmpty
                      ? "먼저 넘길 개체를 고르세요. 고른 개체가 한 사람 몫이 됩니다."
                      : "고른 개체 \(env.selection.selected.count)개를 .imdfrnt 파일로 내보냅니다.")

                Button {
                    env.mergeAssignments()
                } label: {
                    Label("배정본 합치기…", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.small)
                .disabled(env.document == nil)
                .help("나눠 준 몫들이 돌아오면 여기서 하나로 모읍니다. 여러 개를 한 번에 고를 수 있습니다.")
            }
        }
    }

    /// 배정본을 열었을 때의 상태 표시.
    private func assignmentBadge(_ a: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                Text("받은 작업 몫").font(.caption.weight(.semibold))
            }
            Text(a.summary).font(.caption2).foregroundStyle(.secondary)
            Text("담당 밖 개체는 회색으로 보이고 고를 수 없습니다. 도면 전체가 보이는 것은 주변을 보기 위해서입니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 진행률 (명세 3-1)

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 제외된 보조 개체도 '완료'로 세지만 색을 나눈다(명세 디버깅 6번).
            // `ProgressView`는 구간을 색으로 나눌 수 없어 막대를 직접 그린다.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    HStack(spacing: 0) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * env.claimedFraction)
                        Capsule().fill(env.canvasBackground.excludedStroke)
                            .frame(width: geo.size.width * env.excludedFraction)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(env.progressText).font(.caption.monospacedDigit())
                Spacer()
                Text(String(format: "%.1f%%", env.progressFraction * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if env.excludedCount > 0 {
                HStack(spacing: 10) {
                    progressLegend(Color.accentColor, "feature로 저장")
                    progressLegend(env.canvasBackground.excludedStroke, "보조 개체 제외")
                }
            }
            Text("완료 및 제외 개체 수 / 전체 개체 수")
                .font(.caption2).foregroundStyle(.tertiary)
                // 디버깅 14번(2026-08-25) — 문구를 이 형태로 확정. "제외해도 분모는 줄지
                // 않습니다"라는 부연은 위 범례(저장/제외 색 구분)로 이미 드러나므로 뺐다.

            Divider().padding(.vertical, 2)
            polygonProgressSection
        }
        .hoverNote("서로 다른 property type 또는 feature가 동일한 벡터 개체를 공유할 수 있으므로, 진행률을 다 채운 것이 최종 작업 완료를 의미하는 것은 아닙니다.")
        // 신기능 5-5-1. **이 막대의 한계를 그 자리에서 밝히는 장치다** —
        // 숫자만 보면 100%가 곧 완료로 읽히는데, 공유가 정상인 구조에서는 그렇지 않다.
    }

    /// 점 기준 진행률(#21). 신기능 5-5-2의 다각형 막대를 점 기준으로 바꿨다.
    /// 분모는 **보조 개체까지 포함한** 전체 점(꼭짓점·끝점·교차점) 수이고,
    /// 분자는 '태깅된 점'과 '보조 개체 제외로 사라진 점' 둘로 나뉜다. 면 단위로 저장해도 점 기준이다.
    private var polygonProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    HStack(spacing: 0) {
                        Capsule().fill(ClosedPolygonAppearance.savedFill)
                            .frame(width: geo.size.width * env.taggedPointFraction)
                        // 캔버스의 태깅 색과 같은 색이다. 막대와 도면이 같은 것을 같은 색으로 말해야 대조된다.
                        Capsule().fill(env.canvasBackground.excludedStroke)
                            .frame(width: geo.size.width * env.excludedPointFraction)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(env.pointProgressText).font(.caption.monospacedDigit())
                if env.isComputingDerivedGeometry { ProgressView().controlSize(.mini) }
                Spacer()
                Text(String(format: "%.1f%%", env.pointProgressFraction * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                progressLegend(ClosedPolygonAppearance.savedFill, "태깅된 점")
                progressLegend(env.canvasBackground.excludedStroke, "제외된 점")
            }
            Text("처리된 점 수 / 전체 점(꼭짓점·교점) 수")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .hoverNote("보조선의 점을 포함하여, 도면의 모든 꼭짓점·교점 수 대비 태깅되거나 제외된 점 수를 진행률로 표시합니다. 면 단위로 저장해도 그 면의 꼭짓점이 태깅된 점으로 셈해집니다.")
    }

    private func progressLegend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 5)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 보기 모드 (명세 3-2, 3-3)

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            modeButton(title: env.isPolygonWorkMode
                       ? "저장되지 않은 다각형만 보기"
                       : "그룹화되지 않은 개체 보기",
                       systemImage: "square.dashed",
                       isOn: isUngroupedOnly) {
                env.setMode(isUngroupedOnly ? .idle : .ungroupedOnly)
            }
            .help(env.isPolygonWorkMode
                  ? "이미 feature로 저장한 다각형을 옅게 눌러 아직 남은 것만 눈에 띄게 합니다."
                  : "이미 그룹화된 개체를 75%로 옅게 표시합니다.")
            // 신기능 5-4 4번(사노): '미그룹만 보기'는 **선분 단위와 면 단위 모두** 제공한다.
            // 남은 일감을 눈에 띄게 하는 목적은 같고, 무엇이 일감인지가 모드마다 다를 뿐이다.

            // 명세 3-3의 원문대로 **전용 창**이다(2026-08-27). 메인 캔버스의 모드로 두었을 때는
            // 눌렀을 때의 변화가 '곡선 아닌 개체 75%'뿐이라 아무 일도 안 일어난 것처럼 보였고,
            // 폴리곤 type 레이어에서는 클릭이 면을 고르므로 곡선을 고를 수조차 없었다.
            modeButton(title: "곡선 개체만 따로 보기 (선분화 \(env.segmentedCount)/\(env.curvedObjectCount))",
                       systemImage: "scribble",
                       isOn: false) {
                env.enterCurvedScreen()
            }
            .disabled(!env.canEnterCurvedScreen)
            .help(env.canEnterCurvedScreen
                  ? "곡선 개체만 따로 보며 선분화합니다. 선분화해야 좌표를 뽑을 수 있습니다."
                  : "이 도면에는 곡선 개체가 없습니다.")

            // 보조 개체 제외는 '보기 모드'가 아니라 전용 창이다 — 진입점만 여기 둔다.
            modeButton(title: env.excludedCount > 0
                       ? "보조 개체 제외 (\(env.excludedCount)개 제외됨)" : "보조 개체 제외",
                       systemImage: "square.dashed.inset.filled",
                       isOn: false) {
                env.enterAuxiliaryScreen()
            }
            if env.excludedCount > 0 {
                HStack(spacing: 6) {
                    Text("제외된 개체 진하기").font(.caption).foregroundStyle(.secondary).fixedSize()
                    Slider(value: $env.excludedAuxiliaryOpacity, in: 0...1)
                        .controlSize(.mini)
                    Text(env.excludedAuxiliaryOpacity < 0.005 ? "숨김"
                         : String(format: "%.0f%%", env.excludedAuxiliaryOpacity * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.leading, 32).padding(.trailing, 8)
                .help("메인 도면에서 보조 개체로 제외한 개체를 얼마나 진하게 보일지 정합니다. 0이면 숨깁니다. 이 Mac에 기억됩니다.")
                // 제외한 개체만 대상이라 하나라도 제외했을 때만 보인다. 실행취소 대상이 아니다 — 보기 설정이다.
            }

            // 신기능 3항. **Openings 레이어일 때만 보인다** — 다른 type에서 열어 주면
            // 사용자가 만든 opening이 엉뚱한 레이어에 쌓인다. 안 보이는 이유를 알 수 있도록
            // 버튼을 숨기지 않고 비활성으로 두고 도움말로 조건을 밝힌다.
            modeButton(title: env.doorClosures.isEmpty
                       ? "문 임시로 닫기"
                       : "문 임시로 닫기 (임시 문 \(env.doorClosures.count)개)",
                       systemImage: "door.left.hand.open",
                       isOn: false) {
                env.enterDoorClosureScreen()
            }
            .disabled(!env.canEnterDoorClosure)
            .help(env.canEnterDoorClosure
                  ? "열린 상태로 그려진 문 자리를 두 점으로 닫아 Openings 개체를 만듭니다."
                  : "Openings 레이어를 연 상태에서만 쓸 수 있습니다.")

            // 신기능 5-4: '닫힌 다각형 보기'는 별도 창이 아니라 **폴리곤 type 레이어의 기본 화면**이
            // 됐다. 진입 버튼을 따로 두지 않는다 — 레이어를 여는 것이 곧 진입이다.
        }
    }

    private var isUngroupedOnly: Bool { if case .ungroupedOnly = env.mode { return true }; return false }
    private var isCurvedOnly: Bool { if case .curvedOnly = env.mode { return true }; return false }

    private func modeButton(title: String, systemImage: String,
                            isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage).frame(width: 16)
                Text(title).font(.callout).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if isOn { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                // 제목에 개수가 붙어 길어질 수 있다("보조 개체 제외 (12개 제외됨)").
                // 줄을 늘리면 행 높이가 제각각이 되어 목록의 세로 리듬이 깨진다(뷰 디버깅 16번).
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    // 곡선 패널은 전용 창(`UI/Curved/`)으로 옮겼다(2026-08-27).
    // 사이드바 안에 두면 tolerance 슬라이더·버튼 넷이 좁은 폭에 눌려 들어가고,
    // 정작 곡선을 고르는 캔버스는 다른 화면에 있어 눈이 두 곳을 오간다.

    // MARK: Anchor 지정 진입점 (명세 9항)

    private var anchorEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Level · Footprint 정렬") { env.enterLevelFootprintScreen() }
                .buttonStyle(.bordered)
            Button {
                env.enterAnchorScreen()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope").frame(width: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Anchor 지정").font(.callout.weight(.medium))
                        Text("Footprint GPS · \(env.sharedFootprint.anchors.pairs.count) / \(AnchorStore.minimumPairs)쌍")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(env.sharedFootprint.isGeoreferenced
                        ? Color.green.opacity(0.14) : Color.orange.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6))
            .disabled(env.document == nil)

            Button {
                env.enterMapAlignScreen()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map").frame(width: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("지도 정렬").font(.callout.weight(.medium))
                        Text("\(env.mapAlignProgress.done) / \(env.mapAlignProgress.total)층 정렬됨")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .disabled(env.mapAlignLevels.isEmpty)
            .help("도면을 위성사진 위에 직접 맞추고, 맞춘 도면에서 Anchor를 찍습니다(신기능 11항). ⌘⇧K")
            // 기존 'Anchor 지정'(1:1 찍기)은 그대로 둔다(사용자 결정, 2026-10-15).

            Text(env.sharedFootprint.isGeoreferenced
                 ? "Footprint의 GPS가 설정되었습니다. 층별 정렬을 진행하세요."
                 : "Footprint를 그린 뒤 Anchor 3쌍 이상으로 GPS를 설정하세요.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: feature type (명세 3항, 4항, 신기능 12항)

    private var sort: FeatureTypeSort { FeatureTypeSort(rawValue: sortRaw) ?? .custom }

    private var typeSection: some View {
        let shown = env.sortedFeatureTypes(sort)
        return VStack(alignment: .leading, spacing: 6) {
            Picker("정렬", selection: $sortRaw) {
                ForEach(FeatureTypeSort.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .padding(.bottom, 2)
            ForEach(shown) { type in
                typeRow(type)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let dragged = IMDFFeatureType(rawValue: raw) else { return false }
                        env.moveFeatureType(dragged, to: type, shown: shown)
                        sortRaw = FeatureTypeSort.custom.rawValue
                        return true
                        // 다른 기준으로 정렬된 채 끌었으면 보이는 순서에서 옮긴 결과를 사용자 지정 순서로 삼는다.
                    }
            }
            // 사이드바는 260pt까지 좁아진다. `fixedSize`가 없으면 줄바꿈 대신 뒤가 잘려
            // 문장이 끊긴 채로 보인다(뷰 디버깅 16번).
            Text("왼쪽 아이콘으로 이 층의 상태를 정하고, ≡를 끌어 순서를 바꿉니다. 모든 type이 Complete이면 층이 Complete가 됩니다.\n배지는 저장된 feature 개수입니다. 정보만 입력하는 type은 상단바에 있습니다.")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 명세 4항 — type 이름 클릭으로는 레이어가 만들어지지 않는다.
    /// 레이어 생성은 되돌리기 어려운 작업이라(개체 소유권이 걸린다) 명시적 버튼으로만 실행한다.
    @ViewBuilder
    private func typeRow(_ type: IMDFFeatureType) -> some View {
        let isActive = env.layers.activePropertyType == type
        let layer = env.layers.layer(for: type)
        let exists = layer != nil
        let count = env.features.count(ofType: type)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 10)
                    .draggable(type.rawValue) {
                        Label(type.displayName, systemImage: icon(for: type)).padding(6)
                    }
                    .help("끌어서 순서 바꾸기")
                // 손잡이만 끌린다. 줄 전체를 끌리게 하면 투명도 슬라이더를 움직일 때 줄이 딸려 온다.
                WorkStatusMenu(status: env.workStatus(type)) { env.setWorkStatus($0, for: type) }
                    .disabled(env.activeLevel == nil)
                Image(systemName: icon(for: type)).frame(width: 15)
                    .foregroundStyle(.secondary)

                Text(type.displayName)
                    .font(.callout)
                    .fontWeight(isActive ? .semibold : .regular)
                    .textSelection(.enabled)
                    .lineLimit(1).truncationMode(.tail)
                // 좁힐 때 줄어드는 쪽은 type 이름이다. 오른쪽 버튼 글자가 잘리면
                // "레이어 생…"이 되어 무엇을 하는 버튼인지 알 수 없다(뷰 디버깅 16번).

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                }

                Spacer(minLength: 6)

                layerButton(type: type, isActive: isActive, exists: exists)
                    .fixedSize()
            }
            if let layer {
                HStack(spacing: 6) {
                    Button {
                        env.layers.setHidden(!layer.isHidden, for: layer.id)
                    } label: {
                        Image(systemName: layer.isHidden ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(layer.isHidden ? "레이어 보이기" : "레이어 숨기기")
                    opacityRow(layer)
                    if layer.isClosable {
                        Button { env.layers.close(layer.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).controlSize(.mini)
                            .help("레이어 닫기")
                    }
                }
                .padding(.leading, 33)
                // 예전 '레이어' 섹션의 표시·투명도·닫기를 type 줄 바로 아래로 옮겼다(신기능 12항).
                ImageOverlayRow(type: type)
                    .padding(.leading, 33)
                // 이미지는 그 type 레이어에 딸린다(신기능 15항). 레이어가 열려 있어야 얹을 수 있다.
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6))
        .help(type.note)
        // 줄마다 옅은 바탕을 깔고 위아래 여백을 넓혔다(2026-10-20 요청). 표시·투명도 줄이 붙은 type은
        // 두 줄짜리가 되어, 여백이 좁으면 어느 줄이 어느 type 것인지 경계가 흐려졌다.
    }

    @ViewBuilder
    private func layerButton(type: IMDFFeatureType, isActive: Bool, exists: Bool) -> some View {
        if isActive {
            Text("사용 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Button(exists ? "레이어 열기" : "레이어 생성하기") {
                env.selectPropertyType(type)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(env.document == nil)
            .help(exists
                  ? "이미 만들어진 \(type.displayName) 레이어로 전환합니다."
                  : "\(type.displayName) 레이어를 새로 만듭니다. 도면의 모든 개체가 포함되며, 다른 type이 이미 저장한 개체는 비활성으로 표시됩니다.")
        }
    }

    private func icon(for t: IMDFFeatureType) -> String {
        switch t {
        case .address: return "mappin.and.ellipse"
        case .amenity: return "figure.walk"
        case .anchor: return "pin"
        case .building: return "building.2"
        case .detail: return "line.diagonal"
        case .kiosk: return "storefront"
        case .relationship: return "point.3.connected.trianglepath.dotted"
        case .fixture: return "chair"
        case .footprint: return "square.dashed"
        case .level: return "square.stack.3d.up"
        case .manifest: return "doc.text"
        case .occupant: return "person.crop.square"
        case .opening: return "door.left.hand.open"
        case .section: return "square.on.square.dashed"
        case .geofence: return "dot.circle.and.hand.point.up.left.fill"
        case .unit: return "rectangle.split.3x1"
        case .venue: return "map"
        }
    }

    // MARK: opening 선행 태깅 게이트 (명세 10-1)

    @ViewBuilder
    private var openingGateBar: some View {
        if env.document != nil {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: env.openingGate.allowsOtherTypes
                          ? "lock.open" : "lock")
                    Text(env.openingGate.allowsOtherTypes
                         ? "opening 태깅 완료됨" : "opening을 먼저 태깅하세요")
                        .font(.caption.weight(.semibold))
                }
                Text(env.openingGate.allowsOtherTypes
                     ? "빠뜨린 문이 있으면 다시 열어 추가할 수 있습니다. 저장한 feature는 유지됩니다."
                     : "문을 먼저 확정해야 방 폴리곤을 닫을 수 있습니다. 그때까지 다른 type은 잠깁니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("opening \(env.features.features(ofType: .opening).count)개")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if env.openingGate.allowsOtherTypes {
                        Button("opening 다시 편집") { env.reopenOpeningTagging() }
                            .controlSize(.small)
                    } else {
                        Button("opening 태깅 완료") { env.declareOpeningComplete() }
                            .controlSize(.small)
                    }
                }
            }
            .padding(8)
            .background(env.openingGate.allowsOtherTypes
                        ? Color.secondary.opacity(0.08) : Color.orange.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6))
            // 잠긴 동안에는 눈에 띄어야 한다 — 다른 메뉴가 왜 안 눌리는지 여기서만 알 수 있다.
        }
    }

    // MARK: 레이어 (명세 2항)

    /// 레이어별 투명도 조절(2026-08-27 요청).
    ///
    /// **슬라이더를 레이어 줄 바로 아래 붙인다.** 별도 창이나 팝오버로 빼면 값을 바꾸는 동안
    /// 도면이 가려져, 정작 얼마나 옅어졌는지 보면서 맞출 수가 없다. 조절의 목적이
    /// "이 레이어를 얼마나 비쳐 보이게 할까"라 **결과를 보면서 움직여야** 한다.
    @ViewBuilder
    private func opacityRow(_ layer: EditorLayer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption2).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { layer.opacity },
                set: { env.layers.setOpacity($0, for: layer.id) }
            ), in: EditorLayer.minimumOpacity...1.0)
            .controlSize(.mini)
            .disabled(layer.isHidden)
            // 숨긴 레이어의 투명도를 만지면 아무 변화가 없다 — 고장으로 읽히므로 잠근다.

            Text("\(Int(layer.opacity * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            if layer.hasCustomOpacity {
                Button {
                    env.layers.setOpacity(nil, for: layer.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("기본값으로 되돌리기 (\(Int(layer.baseOpacity * 100))%)")
                // 하위 기본 레이어의 기본값 50%는 명세가 정한 수치라(명세 2-3),
                // 만진 뒤에 되돌릴 길이 있어야 한다.
            }
        }
        .opacity(layer.isHidden ? 0.4 : 1)
    }

    /// feature type 레이어를 뺀 나머지(상위·하위 기본 레이어, 속성 필터 레이어).
    private var otherLayers: [EditorLayer] {
        env.layers.layers.filter { if case .propertyType = $0.kind { return false }; return true }
    }

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(otherLayers) { layer in
                HStack(spacing: 6) {
                    Button {
                        env.layers.setHidden(!layer.isHidden, for: layer.id)
                    } label: {
                        Image(systemName: layer.isHidden ? "eye.slash" : "eye")
                            .foregroundStyle(layer.isHidable ? Color.primary : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!layer.isHidable)

                    Text(layer.title).font(.caption).lineLimit(1)
                    Spacer()
                    if layer.isClosable {
                        Button { env.layers.close(layer.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).controlSize(.mini)
                    }
                }
                .padding(.top, 3).padding(.horizontal, 6)

                opacityRow(layer)
                    .padding(.horizontal, 6).padding(.bottom, 3)
                .background(env.layers.activeLayerID == layer.id
                            ? Color.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    guard layer.allowsObjectActions else {
                        env.notify("하위 기본 레이어는 원위치 확인용이라 작업할 수 없습니다.", isError: true)
                        // 명세 2-3. 아무 반응이 없으면 클릭이 씹힌 것으로 오해한다.
                        return
                    }
                    env.perform("\(layer.title) 열기") { env.layers.activate(layer.id) }
                }
            }

            if !env.selection.isEmpty, let doc = env.document,
               let first = env.selection.selected.first, let o = doc.object(first) {
                Button("같은 속성의 벡터만 모아보기") {
                    env.perform("속성 필터 레이어") {
                        env.layers.addAttributeFilterLayer(key: o.style.attributeKey,
                                                           label: o.style.humanDescription)
                    }
                    // 레이어 생성도 되돌릴 수 있어야 한다. 만들면 화면에 보이는 개체가 바뀌므로
                    // cmd+z로 직전 화면으로 돌아가지 못하면 손으로 레이어를 닫아야 한다.
                    env.notify("속성 필터 레이어를 만들었습니다: \(o.style.humanDescription) — 개체 \(env.objectsMatchingAttribute(o.style.attributeKey).count)개")
                    // 개수는 색인(`objectIDsByAttributeKey`)에서 즉시 나온다(제안 6).
                    // 몇 개가 걸렸는지 알려주지 않으면 레이어를 열어 보고서야 헛수고인지 안다.
                }
                .controlSize(.small)
                .padding(.top, 4)

                if env.isAttributeFilterActive {
                    Button("선택한 개체를 이 레이어에 추가") {
                        env.addSelectionToActiveFilterLayer()
                    }
                    .controlSize(.small)
                    .help("속성이 달라 필터에 걸리지 않은 개체도 이 레이어에서 함께 다룰 수 있습니다(명세 2항)")
                    // 필터 레이어를 연 상태에서만 뜬다 — 다른 레이어에서는 누를 대상이 없다.
                }
            }

            Toggle("겹치는 곳 윤곽 표시", isOn: $env.showOverlapHighlight)
                .controlSize(.small)
                .help("선택한 개체가 다른 벡터와 겹치는 지점을 표시합니다. 개체 위치는 옮길 수 없습니다.")
        }
    }
}
