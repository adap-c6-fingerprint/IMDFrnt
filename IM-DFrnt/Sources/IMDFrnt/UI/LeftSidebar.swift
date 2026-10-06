import SwiftUI

/// 명세 3~4항의 좌측 사이드바.
struct LeftSidebar: View {
    @EnvironmentObject var env: AppEnvironment

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
                                   badge: "\(env.anchors.pairs.count)쌍") { anchorEntry }
                    Divider()
                    SidebarSection(id: .leftGate, title: "Opening 게이트") { openingGateBar }
                    // property type 목록 **바로 위**에 둔다. 잠긴 이유를 목록 옆에서 즉시 읽어야
                    // "왜 안 눌리지"로 헤매지 않는다(명세 10-1-2).
                    SidebarSection(id: .leftTypes, title: "PROPERTY TYPE") { typeSection }
                    SidebarSection(id: .leftLayers, title: "레이어",
                                   badge: "\(env.layers.layers.count)") { layerSection }
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
            Button { env.enterRoutingScreen() } label: {
                Label("길찾기 노드 편집", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.small)
            .disabled(env.document == nil)
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

    /// 신기능 5-5-2) 다각형 기준 진행률.
    /// 분모는 **보조 개체로 만들어지는 면까지 포함한** 전체 면 수이고(도면을 열 때 한 번 센다),
    /// 분자는 '제외로 사라진 면'과 '태깅한 면' 둘로 나뉜다.
    private var polygonProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    HStack(spacing: 0) {
                        Capsule().fill(ClosedPolygonAppearance.faceFill)
                            .frame(width: geo.size.width * env.taggedPolygonFraction)
                        Capsule().fill(env.canvasBackground.excludedStroke)
                            .frame(width: geo.size.width * env.vanishedPolygonFraction)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(env.polygonProgressText).font(.caption.monospacedDigit())
                Spacer()
                Text(String(format: "%.1f%%", env.polygonProgressFraction * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                progressLegend(ClosedPolygonAppearance.faceFill, "태깅한 다각형")
                progressLegend(env.canvasBackground.excludedStroke, "제외로 사라진 다각형")
            }
            Text("처리된 다각형 수 / 전체 다각형 수")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .hoverNote("보조선으로 만들어지는 다각형을 포함하여, 도면의 모든 다각형 수 대비 처리된 다각형 수를 진행률로 표시합니다.")
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
            Button {
                env.enterAnchorScreen()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope").frame(width: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Anchor 지정").font(.callout.weight(.medium))
                        Text("\(env.anchors.pairs.count) / \(AnchorStore.minimumPairs)쌍")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(env.anchors.isConfigured
                        ? Color.green.opacity(0.14) : Color.orange.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6))
            .disabled(env.document == nil)

            Text(env.anchors.isConfigured
                 ? "좌표 변환이 가능합니다."
                 : "3쌍 이상 지정해야 위경도 좌표와 내보내기가 열립니다.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: property type (명세 3항, 4항)

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(IMDFFeatureType.allCases) { type in
                typeRow(type)
            }
            // 사이드바는 260pt까지 좁아진다. `fixedSize`가 없으면 줄바꿈 대신 뒤가 잘려
            // 문장이 끊긴 채로 보인다(뷰 디버깅 16번).
            Text("type 이름은 표시 전용입니다. 오른쪽 버튼으로 레이어를 만들거나 엽니다.\n배지는 저장된 feature 개수입니다. type별 진행률은 분모를 정의할 수 없어 두지 않습니다.")
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
        let exists = env.layers.layer(for: type) != nil
        let count = env.features.count(ofType: type)

        HStack(spacing: 8) {
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
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .help(type.note)
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

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(env.layers.layers) { layer in
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
