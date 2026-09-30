import SwiftUI

/// 명세 6~7항의 우측 사이드바.
struct RightSidebar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let type = env.layers.activePropertyType {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let live = env.features.features(ofType: type)
                        featureListHeader(count: live.count)
                        // **카드 전부를 감싸는 접기 트리를 두지 않는다**(2026-08-26 요청).
                        // 상위 토글 하나로 통째로 접히면 카드마다 따로 접고 펴는 뜻이 사라진다.
                        // 여기서는 개수만 알려주고, 접고 펴는 것은 카드 각자의 몫이다.

                        if live.isEmpty {
                            Text("아직 저장된 feature가 없습니다.\n캔버스에서 개체를 선택하고 'Feature로 저장'을 누르세요.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 20)
                        }
                        ForEach(live) { f in featureCard(f) }

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
    private func featureListHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("FEATURES").font(.caption.weight(.semibold))
            Text("\(count)").font(.caption2.monospacedDigit())
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
                Label("Anchor \(env.anchors.pairs.count)", systemImage: "scope")
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
                        Text("개체 \(f.memberIDs.count)").font(.caption).foregroundStyle(.secondary)
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

            Button { env.trash(f.id) } label: { Image(systemName: "trash") }
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

        VStack(alignment: .leading, spacing: 6) {
            ForEach(PropertySchema.fields(for: f.featureType)) { field in
                PropertySlotRow(feature: f, field: field)
            }
        }

        if f.featureType.hasDisplayPoint {
            Divider()
            HStack {
                Text("display point").font(.caption.weight(.semibold))
                Spacer()
                if let dp = f.displayPoint {
                    Text(String(format: "%.1f, %.1f", dp.x, dp.y))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(f.displayPoint == nil ? "찍기" : "다시 찍기") {
                    env.beginDisplayPointPicking(f.id)
                }
                .controlSize(.small)
            }
        }

        Divider()
        coordinateTable(f)
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

            control
        }
    }

    @ViewBuilder
    private var control: some View {
        let value = feature.value(field.key)

        if field.key == "id" {
            Text(env.ids.peek(feature.id)?.uuidString.lowercased() ?? "내보내기 시 자동 생성")
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.type == .alwaysNull {
            Text("null").font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.type == .point {
            Text(feature.displayPoint == nil ? "null" : "Point")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.key == "category",
                  !PropertySchema.categoryOptions(for: feature.featureType).isEmpty {
            Picker("", selection: Binding(
                get: { if case .string(let s) = value { return s }; return "" },
                set: { env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0),
                                          in: feature.id) }
            )) {
                Text("null").tag("")
                ForEach(PropertySchema.categoryOptions(for: feature.featureType), id: \.self) {
                    Text($0).tag($0)
                }
            }
            .labelsHidden().controlSize(.small)
        } else if field.type == .boolean {
            Toggle("", isOn: Binding(
                get: { if case .boolean(let b) = value { return b }; return false },
                set: { env.updateProperty(field.key, value: .boolean($0), in: feature.id) }
            ))
            .labelsHidden().toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if field.type == .localizedName {
            VStack(spacing: 3) {
                textField("en", get: { if case .localized(let en, _) = value { return en }; return "" },
                          set: { en in
                    let ko = { if case .localized(_, let k) = value { return k }; return "" }()
                    env.updateProperty(field.key,
                                       value: en.isEmpty && ko.isEmpty ? .null : .localized(en: en, ko: ko),
                                       in: feature.id)
                })
                textField("ko", get: { if case .localized(_, let ko) = value { return ko }; return "" },
                          set: { ko in
                    let en = { if case .localized(let e, _) = value { return e }; return "" }()
                    env.updateProperty(field.key,
                                       value: en.isEmpty && ko.isEmpty ? .null : .localized(en: en, ko: ko),
                                       in: feature.id)
                })
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
        } else if case .reference(let refType) = field.type {
            Picker("", selection: Binding(
                get: { if case .string(let s) = value { return s }; return "" },
                set: { env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0),
                                          in: feature.id) }
            )) {
                Text("null").tag("")
                ForEach(env.features.features(ofType: refType)) { f in
                    Text(f.serialNumber).tag(f.serialNumber)
                }
            }
            .labelsHidden().controlSize(.small)
            .help("일련번호로 고르면 내보내기 때 해당 feature의 UUID로 치환됩니다.")
        } else {
            textField("null", get: { if case .string(let s) = value { return s }; return "" },
                      set: { env.updateProperty(field.key, value: $0.isEmpty ? .null : .string($0),
                                                in: feature.id) })
        }
    }

    private func textField(_ placeholder: String,
                           get: @escaping () -> String,
                           set: @escaping (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: get, set: set))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(.caption)
    }
}
