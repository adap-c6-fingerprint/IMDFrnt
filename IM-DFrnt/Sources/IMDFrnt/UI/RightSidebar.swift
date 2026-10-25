import SwiftUI

/// 명세 6~7항의 우측 사이드바.
struct RightSidebar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let type = env.layers.activePropertyType {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let all = env.features.features(ofType: type)
                        let live = all.filter { env.passesCategoryFilter($0) }
                        featureListHeader(count: live.count, total: all.count)
                        // **카드 전부를 감싸는 접기 트리를 두지 않는다**(2026-08-26 요청).
                        // 상위 토글 하나로 통째로 접히면 카드마다 따로 접고 펴는 뜻이 사라진다.
                        // 여기서는 개수만 알려주고, 접고 펴는 것은 카드 각자의 몫이다.
                        if !all.isEmpty { CategoryFilterBar(type: type, features: all) }

                        if all.isEmpty {
                            Text("아직 저장된 feature가 없습니다.\n캔버스에서 개체를 선택하고 'Feature로 저장'을 누르세요.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 20)
                        } else if live.isEmpty {
                            Text("고른 category에 해당하는 feature가 없습니다.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 20)
                        }
                        ForEach(live) { f in featureCard(f).id(f.id) }

                        let trashed = env.features.features(ofType: type, includingTrashed: true)
                            .filter(\.isInTrash)
                        if !trashed.isEmpty {
                            SidebarSection(id: .rightTrash, title: "휴지통",
                                           badge: "\(trashed.count)") {
                                ForEach(trashed) { f in trashedRow(f) }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: env.focusedFeature) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id) }
                }
                // 캔버스 이름표로 고른 카드가 목록 아래에 있으면 고른 것이 안 보인다. 그 카드로 내린다.
                // 위치를 정하지 않아 이미 보이는 카드(패널에서 직접 누른 카드)는 움직이지 않는다.
                }
            } else {
                Spacer()
                Text("좌측에서 property type을 선택하세요")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            exportBar
        }
        .frame(maxWidth: .infinity)
    }

    /// 카드 목록의 머리글. 접히지 않는 표시 전용 줄이다.
    private func featureListHeader(count: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text("FEATURES").font(.caption.weight(.semibold))
            Text(count == total ? "\(count)" : "\(count) / \(total)").font(.caption2.monospacedDigit())
            // category 필터가 걸려 있으면 보이는 수 / 전체 수다(#52).
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(env.layers.activePropertyType?.displayName ?? "—")
                    .font(.headline)
                Text("FEATURES").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { env.enterAnchorScreen() } label: {
                Label("Footprint GPS \(env.sharedFootprint.anchors.pairs.count)", systemImage: "scope")
            }
            .controlSize(.small)
            Button {
                withAnimation(.easeOut(duration: 0.18)) { env.showRightSidebar = false }
            } label: { Image(systemName: "sidebar.trailing") }
                .buttonStyle(.borderless)
                .help("사이드바 접기")
            SidebarCollapseAllButton(owner: .right)
            // 우측은 펼쳐 놓은 feature 카드가 자리를 가장 많이 차지한다. 그것까지 함께 접힌다.
        }
        .padding(12)
    }

    // MARK: feature 카드

    private func featureCard(_ f: FeatureGroup) -> some View {
        let expanded = env.isFeatureExpanded(f.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { env.toggleFeatureExpansion(f.id) }
                    // 카드마다 독립된 토글이다. 여러 개를 동시에 펼쳐 둘 수 있고,
                    // 머리글의 '모두 접기/펼치기'가 이 토글들을 한꺼번에 움직인다.
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(f.serialNumber).font(.callout.weight(.medium).monospaced())
                            .lineLimit(1).truncationMode(.middle)
                        Text(f.isPointDrawn
                             ? "꼭짓점 \((f.drawnVertices?.count ?? 0) + f.polygonRings.reduce(0) { $0 + $1.count })"
                             : "개체 \(f.memberIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                        // #21: 점으로 그린 도형은 원본 개체가 없다. '개체 0'은 비어 있는 것처럼 읽힌다.
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                collapsedActions(f)
                    .fixedSize()
                // 좁힐 때 줄어드는 쪽은 일련번호다. 오른쪽 동작 버튼이 잘리면 못 누른다.
                // 일련번호는 가운데를 잘라(`.middle`) 앞뒤를 남긴다 — "unit-…-012"처럼
                // 종류와 번호가 함께 보여야 어느 feature인지 알아본다(뷰 디버깅 16번).
            }

            if expanded { expandedBody(f) }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(expanded ? Color.accentColor.opacity(0.4) : .clear))
    }

    /// 명세 7-2) 접힌 feature에 대한 액션
    private func collapsedActions(_ f: FeatureGroup) -> some View {
        HStack(spacing: 4) {
            Button {
                env.layers.isolatedFeature = env.layers.isolatedFeature == f.id ? nil : f.id
                env.layers.excludedFeature = nil
            } label: {
                Image(systemName: env.layers.isolatedFeature == f.id ? "eye.fill" : "eye")
            }
            .help("이 feature만 보이게 하기")

            Button {
                env.layers.excludedFeature = env.layers.excludedFeature == f.id ? nil : f.id
                env.layers.isolatedFeature = nil
            } label: {
                Image(systemName: env.layers.excludedFeature == f.id ? "eye.slash.fill" : "eye.slash")
            }
            .help("이 feature 빼고 다 보이게 하기")

            Button(role: .destructive) {
                env.requestDeletion(title: "\(f.serialNumber)를 삭제할까요?",
                                    message: "이 feature를 휴지통으로 보냅니다. 다른 폴리곤에서 빌려 쓰는 opening이면 해당 폴리곤이 열릴 수 있습니다. 휴지통에서 복원하거나 실행 취소로 되돌릴 수 있습니다.") {
                    $0.trash(f.id)
                }
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
                .help("휴지통으로 보내기")

            Button { env.ungroup(f.id) } label: { Image(systemName: "rectangle.on.rectangle.slash") }
                .help("그룹 해제")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func trashedRow(_ f: FeatureGroup) -> some View {
        HStack {
            Text(f.serialNumber).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Button("복원") { env.restore(f.id) }.controlSize(.mini)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 펼친 feature (명세 7-3)

    @ViewBuilder
    private func expandedBody(_ f: FeatureGroup) -> some View {
        Divider()

        // 명세 10-4-3: 링이 닫혔는지 인스펙터에서 상시 보여준다.
        // 저장 순간의 배너는 곧 사라지므로, 나중에 돌아왔을 때 상태를 다시 확인할 곳이 필요하다.
        if let closure = env.ringClosure(of: f), !closure.isClosed {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(env.canvasBackground.marker(.outlier))
                VStack(alignment: .leading, spacing: 2) {
                    Text("폴리곤이 닫히지 않았습니다 (\(closure.gaps.count)곳)")
                        .font(.caption.weight(.semibold))
                    Text("벌어진 자리를 캔버스에 점선 원으로 표시했습니다.")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(7)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        }

        // 명세 10-3-4: 빌려온 opening은 구성원이 아니므로 별도 섹션으로 보여준다.
        // 구성원 목록에 섞으면 "이 unit이 문을 소유한다"로 읽혀 소유·대여 구분이 무너진다.
        let lent = env.borrow.objects(borrowedBy: f.id)
        if !lent.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.left.arrow.right.square")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("빌려온 opening (\(lent.count))")
                        .font(.caption.weight(.semibold))
                    Text(borrowedSerials(lent))
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text("좌표만 빌려 폴리곤을 닫습니다. 소유권은 opening에 있습니다.")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(7)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        }

        if let doc = env.document, let warn = GeometryClassifier.mismatchWarning(f, document: doc) {
            Label(warn, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }

        if env.canDesignateMultiPolygon(f) { multiPolygonSection(f) }
        if f.featureType == .fixture { fixtureTwinSection(f) }
        if f.featureType == .footprint {
            VStack(alignment: .leading, spacing: 6) {
                Button("복제") { _ = env.duplicateFootprint(f.id) }
                Button("Footprint를 기준층 Level 외곽에 맞추기") { env.matchFootprintToGroundLevel(f.id) }
                    .disabled(env.groundFootprintUnavailableReason != nil)
                if let reason = env.groundFootprintUnavailableReason {
                    Text(reason)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("외곽을 교체하고 category를 ground로 설정합니다. 실행 취소로 되돌릴 수 있습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            ForEach(PropertySchema.fields(for: f.featureType)) { field in
                PropertySlotRow(feature: f, field: field)
            }
        }

        if f.featureType.hasDisplayPoint {
            Divider()
            DisplayPointControls(feature: f)
        }

        Divider()
        coordinateTable(f)
    }

    /// 저장한 다각형을 MultiPolygon으로 지정하고 다각형·구멍을 더한다. 스펙상 POLYGONAL인 모든 type이 대상이다.
    private func multiPolygonSection(_ f: FeatureGroup) -> some View {
        let isTarget = env.multiPolygonTargetID == f.id
        let summary = env.multiPolygonSummary(f)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(f.isMultiPolygon ? "MultiPolygon · 다각형 \(summary.polygons) · 구멍 \(summary.holes)" : "Polygon")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !f.isMultiPolygon {
                    Button("MultiPolygon으로 지정") { env.designateMultiPolygon(f.id) }
                        .controlSize(.small)
                } else {
                    if f.multiPolygon == true, f.polygonRings.count == 1 {
                        Button("Polygon으로") { env.releaseMultiPolygon(f.id) }
                            .controlSize(.small)
                    }
                    Button(isTarget ? "추가 끝내기" : "다각형 추가") {
                        if isTarget { env.finishMultiPolygonAdding() } else { env.startMultiPolygonAdding(f.id) }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(isTarget ? .orange : .accentColor)
                }
            }
            if isTarget || !f.isMultiPolygon {
                Text(isTarget
                     ? "다각형을 닫거나 면을 저장하면 이 feature에 더해집니다. 기존 다각형을 감싸면 기존 것이 구멍이 되고, 기존 다각형 안쪽이면 새 것이 구멍이 됩니다."
                     : "MultiPolygon으로 지정한 뒤 '다각형 추가'를 누른 동안에만 새 다각형이 이 feature에 더해집니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(7)
        .background((isTarget ? Color.orange : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
    }

    /// fixture와 똑같이 생긴 자리마다 같은 태깅의 fixture를 둔다(2026-10-18 요청). 자리는 캔버스에 보라 점선으로 보인다.
    private func fixtureTwinSection(_ f: FeatureGroup) -> some View {
        let count = f.polygonRings.isEmpty && !f.memberIDs.isEmpty
            ? env.fixtureMemberTwins(of: f.memberIDs).count
            : env.fixtureTwinPlacements(of: f).count
        // 선 단위로 저장한 fixture는 도면 개체로 자리를 찾는다.
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(count > 0 ? "똑같이 생긴 개체 \(count)곳" : "똑같이 생긴 개체 없음")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("같은 태깅으로 저장") { env.applyTaggingToFixtureTwins(f.id) }
                    .controlSize(.small)
                    .disabled(count == 0)
            }
            Text("자리마다 이 카드의 속성을 그대로 가진 fixture를 개별 Polygon으로 저장합니다. 이미 저장된 자리는 속성만 이 카드와 같게 맞춥니다. 회전·반전된 모양은 찾지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(env.canvasBackground.twinStroke.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
    }

    /// 명세 7-3-5·6) 좌표 표
    private func coordinateTable(_ f: FeatureGroup) -> some View {
        let rows = env.vertexRows(for: f.id)
        let configured = env.georeferencer.isConfigured
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("좌표 (\(rows.count))").font(.caption.weight(.semibold))
                Spacer()
                Text(f.featureType.requiredGeometry.rawValue)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text("좌표 변환 대상 꼭짓점이 없습니다.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // 폭 고정(110pt) 대신 `Grid`를 쓴다(뷰 디버깅 16번).
            // 사이드바는 260~620pt로 넓이가 변하는데 열 폭을 못 박아 두면
            // 좁힐 때 두 열이 서로 밀려 머리글과 값의 세로줄이 어긋난다.
            // `Grid`는 **내용에 맞춰 열 폭을 스스로 정하고**, 그 폭을 모든 행에 똑같이 적용한다.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("도면 좌표").font(.caption2).foregroundStyle(.secondary)
                    Text("위경도").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(String(format: "%.1f, %.1f", row.0.x, row.0.y))
                            .font(.caption2.monospacedDigit())
                            .fixedSize()
                        if let g = row.1 {
                            Text(String(format: "%.6f, %.6f", g.longitude, g.latitude))
                                .font(.caption2.monospacedDigit())
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            // 위경도는 자릿수가 길다. 좁을 때 줄바꿈으로 행 높이가 달라지면
                            // 표의 가로줄이 어긋나므로, 줄이 늘지 않게 하고 뒤를 자른다.
                        } else {
                            Text("Anchor 미지정")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .opacity(configured ? 1 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 내보내기 (명세 7-4)

    private var exportBar: some View {
        VStack(spacing: 6) {
            if !env.georeferencer.isConfigured {
                Label("Anchor \(env.anchors.pairs.count)/\(AnchorStore.minimumPairs)쌍 — 위경도 변환 불가",
                      systemImage: "exclamationmark.circle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                env.export()
            } label: {
                Label("geojson 파일로 반환", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(env.layers.activePropertyType == nil)
        }
        .padding(12)
    }

    /// 빌려온 opening을 소유 feature의 일련번호로 적는다 — 개체 UUID는 사용자에게 의미가 없다.
    private func borrowedSerials(_ ids: Set<VectorObjectID>) -> String {
        let serials = Set(ids.compactMap { id -> String? in
            guard let owner = env.ownership.ownerOf(id) else { return nil }
            return env.features.feature(owner)?.serialNumber
        })
        return serials.sorted().joined(separator: ", ")
    }
}

/// 슬롯 한 줄. 타입 변경 불가(명세 7-3-1)이므로 필드 타입에 따라 컨트롤이 고정된다.
struct PropertySlotRow: View {
    @EnvironmentObject var env: AppEnvironment
    let feature: FeatureGroup
    let field: PropertyField

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(field.key).font(.caption.monospaced())
                if field.isNonStandard {
                    Text("비표준").font(.system(size: 8))
                        .padding(.horizontal, 3)
                        .background(Color.orange.opacity(0.25), in: Capsule())
                        .help(field.note)
                }
            }
            .frame(minWidth: 84, idealWidth: 108, maxWidth: 132, alignment: .leading)
            // 폭을 못 박으면 좁은 사이드바에서 라벨이 값 칸을 밀어낸다(뷰 디버깅 16번).
            // 범위로 두면 넓을 때는 종전과 같고, 좁을 때는 라벨이 먼저 양보한다.

            VStack(alignment: .leading, spacing: 2) {
                control
                if let guide = PropertyRules.guide(feature.featureType, field.key) {
                    Text(guide).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem = PropertyRules.problem(feature.featureType, field.key, in: feature) {
                    Label(problem.message, systemImage: problem.severity == .violation ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(problem.severity == .violation ? Color.red : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 정보 type은 칸 아래에 입력 가이드를, 스펙을 어기면 고치는 방법을 빨간 글씨로 붙인다(2026-10-20).
            // Apple 검증의 경고(Warning)만 해당하면 주황이다. 가이드가 없는 type은 종전과 같다.
        }
    }

    @ViewBuilder
    private var control: some View {
        let value = feature.value(field.key)

        if field.key == "id" {
            Text(env.exportID(for: feature)?.uuidString.lowercased() ?? "내보내기 시 자동 생성")
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if feature.featureType == .venue, field.key == "hours" {
            OpeningHoursEditor(value: Binding(get: {
                if case .string(let text) = feature.value("hours") { return text }; return ""
            }, set: { env.updateProperty("hours", value: $0.isEmpty ? .null : .string($0), in: feature.id) }))
        } else if !field.isEditable, field.type == .string {
            Text(feature.featureType == .manifest && field.key == "version" ? "1.0.0"
                 : feature.featureType == .manifest && field.key == "created" ? "내보낼 때 자동 기록" : value.displayText)
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let choices = PropertyRules.choices(feature.featureType, field.key, in: feature) {
            let labels = Dictionary(choices.map { ($0.value, $0.label) }, uniquingKeysWith: { a, _ in a })
            SearchablePicker(selection: { if case .string(let s) = value { return s }; return "" }(),
                             options: choices.map(\.value),
                             onSelect: { env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0), in: feature.id) },
                             label: { labels[$0] ?? $0 })
        } else if field.type == .alwaysNull {
            Text("null").font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.type == .point {
            if env.isGlobalMetadata(feature.id) {
                JSONPropertyEditor(feature: feature, key: field.key)
            } else {
                Text(feature.displayPoint == nil ? "null" : "Point")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if field.type == .json {
            JSONPropertyEditor(feature: feature, key: field.key)
        } else if field.key == "category",
                  !PropertySchema.categoryOptions(for: feature.featureType).isEmpty {
            let type = feature.featureType
            let ordered = env.categoryOptionsOrdered(for: type)
            SearchablePicker(selection: { if case .string(let s) = value { return s }; return "" }(),
                             options: ordered.options,
                             onSelect: {
                env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0), in: feature.id)
                env.recordRecentCategory($0, type: type)
            }, label: { CategoryLabel.display($0, type: type) }, recent: ordered.recent)
            // unit은 최근 고른 category가 맨 위에 최근 순으로 온다(2026-10-19 요청).
            // 드롭다운 대신 검색해서 고른다. 모든 레이어의 category 칸이 이 한 곳을 지난다.
            // 보이는 이름은 `한국어(영어)`, 저장되는 값은 영어 원문이다(#52).
        } else if field.type == .boolean {
            Toggle("", isOn: Binding(
                get: { if case .boolean(let b) = value { return b }; return false },
                set: { env.updateProperty(field.key, value: .boolean($0), in: feature.id) }
            ))
            .labelsHidden().toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.type == .localizedName {
            VStack(spacing: 3) {
                ForEach(["ko", "en"], id: \.self) { language in
                    textField(language, get: { value.projectJSON[language]?.string ?? "" }, set: {
                        env.updateLocalizedProperty(field.key, language: language, text: $0, in: feature)
                    })
                }
                DisclosureGroup("모든 언어 JSON") { JSONPropertyEditor(feature: feature, key: field.key) }
            }
        } else if field.type == .integer {
            textField("null", get: { if case .integer(let i) = value { return String(i) }; return "" },
                      set: { s in
                env.updateProperty(field.key, value: Int(s).map { .integer($0) } ?? .null, in: feature.id)
            })
        } else if field.type == .stringArray {
            textField("쉼표로 구분",
                      get: { if case .stringArray(let a) = value { return a.joined(separator: ", ") }; return "" },
                      set: { s in
                let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                env.updateProperty(field.key, value: parts.isEmpty ? .null : .stringArray(parts),
                                   in: feature.id)
            })
        } else if field.key == "level_id", let level = env.activeLevel {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(level.info.name) · ordinal \(level.info.ordinal)")
                    .font(.caption)
                Text(level.id.uuidString.lowercased())
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("건물·층 관리에서 정한 지금 층으로 자동 지정됩니다. 내보내기 때 이 UUID가 level_id로 들어갑니다.")
            // 직접 고르지 않는다. 예전에는 이 층에 그린 level feature의 일련번호를 골랐는데,
            // 내보내기는 level feature의 id를 층 UUID로 바꾸므로 고른 값과 실제 level id가 어긋날 수 있었다.
        } else if case .reference(let refType) = field.type {
            let choices = env.referenceChoices(refType)
            let labels = Dictionary(choices.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
            SearchablePicker(selection: { if case .string(let s) = value { return s }; return "" }(),
                             options: choices.map(\.id), onSelect: {
                env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0), in: feature.id)
            }, label: { labels[$0] ?? $0 })
            .help("공통 정보와 모든 층의 Feature에서 고릅니다. 값은 UUID로 저장됩니다.")
            // 참조 칸(unit_id·anchor_id 등)도 드롭다운이었다. 일련번호가 수백 개면 찾을 수 없어 같은 검색 칸을 쓴다.
        } else {
            textField("null", get: { if case .string(let s) = value { return s }; return "" },
                      set: { env.updateProperty(field.key, value: Self.text($0, key: field.key), in: feature.id) })
        }
    }

    /// 글자칸 값. 앞뒤 공백을 떼고, 남는 것이 없으면 null이다 — 공백만 든 값은 Apple 검증의 '빈 값' 위반이다.
    /// phone은 사람이 흔히 넣는 공백·하이픈·괄호를 떼어 E.164 모양에 가깝게 둔다.
    static func text(_ raw: String, key: String) -> PropertyValue {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key == "phone" { s.removeAll { " -()".contains($0) } }
        return s.isEmpty ? .null : .string(s)
    }

    static func label(en: String, ko: String) -> PropertyValue {
        let en = en.trimmingCharacters(in: .whitespacesAndNewlines), ko = ko.trimmingCharacters(in: .whitespacesAndNewlines)
        return en.isEmpty && ko.isEmpty ? .null : .localized(en: en, ko: ko)
    }

    /// 글자칸. 입력 중에는 칸만 바뀌고, 잠깐 멈추거나 확정할 때 저장한다(`DraftTextField`).
    private func textField(_ placeholder: String,
                           get: @escaping @MainActor @Sendable () -> String,
                           set: @escaping @MainActor @Sendable (String) -> Void) -> some View {
        DraftTextField(placeholder: placeholder, saved: get(), commit: set)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(.caption)
    }
}
