import AppKit
import SwiftUI

struct RoutingScreen: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var keyMonitor: RoutingKeyMonitor?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { env.showRoutingScreen = false } label: {
                    Label("도면 편집으로", systemImage: "chevron.left")
                }
                Text("길찾기 노드").font(.headline)
                Button("IMDF 불러오기…") { env.importIMDF() }
                Button(".imdfrnt 불러오기…") { env.openProject() }
                Spacer()
                Picker("편집 도구", selection: Binding(get: { env.routingTool }, set: { env.setRoutingTool($0) })) {
                    ForEach(RoutingTool.allCases.filter { $0 != .calibrate || env.currentRoutingFloor?.imdfCoordinates == nil }, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented).frame(maxWidth: 550)
                Button("출입구 노드 자동 배치") { env.placeEntranceNodes() }
                    .disabled(!env.hasOpeningFeatures || env.isImportingIMDF)
                    .help("IMDF opening 중앙에 출입구(entrance) 노드를 놓습니다. 다시 실행해도 중복되지 않습니다.")
                Button("노드/엣지 내보내기…") { env.exportNavigationDataset() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                floors.frame(width: 250)
                Divider()
                CanvasView().frame(minWidth: 360)
                Divider()
                inspector.frame(width: 300)
            }
        }
        .onAppear {
            let monitor = RoutingKeyMonitor(env: env)
            monitor.start()
            keyMonitor = monitor
        }
        .onDisappear {
            keyMonitor?.stop(); keyMonitor = nil
            env.routingConnectionDrag = nil
            env.clearRoutingFeatureSelection()
            env.routingContextMenuIsOpen = false
        }
        .alert("길찾기 파일을 내보낼 수 없습니다", isPresented: Binding(
            get: { env.routingExportError != nil }, set: { if !$0 { env.routingExportError = nil } }
        )) {
            Button("확인", role: .cancel) { env.routingExportError = nil }
        } message: { Text(env.routingExportError ?? "") }
        .alert("기존 장소 연결을 교체할까요?", isPresented: Binding(
            get: { env.routingFeatureReplacement != nil }, set: { if !$0 { env.routingFeatureReplacement = nil } }
        ), presenting: env.routingFeatureReplacement) { request in
            Button("취소", role: .cancel) { env.routingFeatureReplacement = nil }
            Button("노드 연결 교체") { env.confirmRoutingFeatureReplacement(request) }
        } message: { _ in Text("이 장소에 이미 연결된 노드를 해제하고 방금 선택한 노드로 교체합니다. 도형·노드·엣지는 삭제하지 않습니다.") }
    }

    private var floors: some View {
        let graph = env.routing
        let isolatedCount = graph.isolatedNodes.count, componentCount = graph.componentCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("층별 도면").font(.headline)
                Spacer()
                Button { env.addRoutingFloor() } label: { Image(systemName: "plus") }
                    .help("새 층 추가")
            }
            if let source = graph.imdfSourceName {
                Label(source, systemImage: "map").font(.caption).lineLimit(2)
                Text("IMDF의 층 ID·좌표를 사용합니다.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("클라이언트 층 목록 가져오기…") { env.importRoutingLevels() }
                    .controlSize(.small)
            }
            Text("층 번호 0 = 지상 1층 · 지하는 음수")
                .font(.caption2).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(graph.floors.sorted { $0.ordinal < $1.ordinal }) { floor in
                        RoutingFloorCell(floor: floor, nodeCount: graph.nodes(on: floor.id).count,
                                         isSelected: env.currentRoutingFloor?.id == floor.id,
                                         onSelect: { env.selectRoutingFloor(floor.id) },
                                         onDelete: { env.requestRoutingFloorDeletion(floor.id) },
                                         onMenuTracking: { env.routingContextMenuIsOpen = $0 })
                            .frame(height: 53)
                    }
                }
            }
            if let start = graph.node(env.routingConnectStart) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("연결 시작: \(start.label)", systemImage: "link")
                    Text("\(graph.floor(start.floorID)?.name ?? "")에서 선택한 핀입니다. 도착 핀을 클릭하세요.")
                    Button("연결 취소") { env.routingConnectStart = nil }
                }
                .font(.caption).padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Text("전체 노드 \(graph.nodes.count)개 · 연결 \(graph.edges.count)개")
                .font(.caption)
            if isolatedCount > 0 {
                Label("연결 없는 노드 \(isolatedCount)개", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if componentCount > 1 {
                Text("경로가 \(componentCount)개 그룹으로 나뉘어 있습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoutingEdgeGroupsPanel()
                Divider()
                RoutingFeatureLinksPanel()
                Divider()
                if let floor = env.currentRoutingFloor {
                    RoutingFloorEditor(floor: floor).id(floor.id)
                    Divider()
                }
                if env.routingTool == .calibrate {
                    RoutingCalibrationEditor()
                } else if let node = env.selectedRoutingNode {
                    RoutingNodeEditor(node: node).id(node.id)
                } else if let edge = env.selectedRoutingEdge {
                    RoutingEdgeEditor(edge: edge).id(edge.id)
                } else {
                    Label("핀을 선택하면 정보를 편집할 수 있습니다.", systemImage: "mappin.and.ellipse")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let result = env.lastEntrancePlacement { EntrancePlacementSummary(plan: result) }
                Divider()
                DisclosureGroup("내보내기 설정") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("도면 버전", text: Binding(
                            get: { env.routing.layoutVersion }, set: { value in
                                env.perform("도면 버전 편집", coalescingKey: "routing-layout") { env.routing.layoutVersion = value }
                            }))
                        HStack {
                            Text("탐색 반경 (m)").font(.caption)
                            TextField("25", value: Binding(
                                get: { env.routing.hardSearchRadiusMeters }, set: { value in
                                    env.perform("탐색 반경 편집", coalescingKey: "routing-radius") { env.routing.hardSearchRadiusMeters = value }
                                }), format: .number)
                        }
                        Text("GeoJSON으로 전체 층의 노드와 연결을 함께 내보냅니다. IMDF를 불러오면 기존 위경도를 바로 사용합니다. 이미지·SVG 도면은 좌표 기준점이 필요합니다.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(14)
        }
    }
}

struct RoutingFloorEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let floor: RoutingFloor
    @State private var levelID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("현재 층").font(.headline)
            TextField("층 이름", text: Binding(get: { env.routing.floor(floor.id)?.name ?? "" }, set: { value in
                env.updateRoutingFloor(floor.id, field: "name") { $0.name = value }
            }))
            TextField("층 짧은 이름", text: Binding(get: { env.routing.floor(floor.id)?.shortName ?? "" }, set: { value in
                env.updateRoutingFloor(floor.id, field: "shortName") { $0.shortName = value }
            }))
            HStack {
                Text("층 번호").font(.caption)
                TextField("0", value: Binding(get: { env.routing.floor(floor.id)?.ordinal ?? 0 }, set: { value in
                    env.updateRoutingFloor(floor.id, field: "ordinal") { $0.ordinal = value }
                }), format: .number)
            }
            Button(floor.imdfCoordinates == nil ? "이 층 도면 불러오기…" : "참고 도면 불러오기…") { env.importRoutingDrawing() }
            Text(floor.sourceName.isEmpty ? "SVG·PNG·JPG 도면을 불러오세요." : floor.sourceName)
                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            let configured = floor.hasGeographicCoordinates
            Label(floor.imdfCoordinates != nil ? "IMDF 위경도 사용 · 바로 편집 가능" :
                  (configured ? "실제 좌표 변환 준비됨" : "좌표 기준점 \(floor.anchors.pairs.count)개 / 최소 3개"),
                  systemImage: configured ? "checkmark.circle" : "location.slash")
                .font(.caption).foregroundStyle(configured ? Color.green : Color.orange)
            if floor.imdfCoordinates == nil {
                Button("좌표 기준점 설정") { env.setRoutingTool(.calibrate) }
                    .controlSize(.small)
            }
            DisclosureGroup("Level ID") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("level UUID", text: $levelID).font(.caption.monospaced())
                    Button("층 ID 적용") {
                        guard let id = UUID(uuidString: levelID) else {
                            env.notify("올바른 UUID를 입력하세요.", isError: true); return
                        }
                        env.assignRoutingLevelID(floor.id, newID: id)
                    }
                    Text(floor.imdfCoordinates != nil
                         ? "IMDF의 원본 층 ID입니다. 변경하면 도형·노드의 참조도 함께 갱신됩니다."
                         : "클라이언트 level.geojson의 ID와 일치시켜야 해당 층에 연결됩니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
        }
        .onAppear { levelID = floor.id.uuidString.lowercased() }
    }
}

private struct RoutingNodeEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let node: RoutingNode
    @State private var metadata = "{}"
    @State private var metadataError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("노드 정보").font(.headline)
            Text(node.id.uuidString.lowercased()).font(.caption2.monospaced()).textSelection(.enabled)
            TextField("노드 이름", text: Binding(get: { env.routing.node(node.id)?.name ?? "" }, set: { value in
                env.updateRoutingNode(node.id, field: "name") { $0.name = value }
            }))
            Picker("카테고리", selection: Binding(get: { env.routing.node(node.id)?.category ?? "waypoint" }, set: { value in
                env.updateRoutingNode(node.id, field: "category") { $0.category = value }
            })) {
                ForEach(RoutingNodeCategory.allCases, id: \.self) { category in
                    Label {
                        Text(category.title)
                    } icon: {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                    }
                    .tag(category.rawValue)
                }
            }
            Text(String(format: "도면 좌표: %.1f, %.1f", node.point.x, node.point.y))
                .font(.caption.monospacedDigit())
            if let floor = env.routing.floor(node.floorID),
               let geo = floor.geoPoint(for: node.point) {
                Text(String(format: "경도 %.7f · 위도 %.7f", geo.longitude, geo.latitude))
                    .font(.caption2.monospacedDigit()).textSelection(.enabled)
            }
            if RoutingNodeCategory(rawValue: node.category)?.isVertical == true {
                VerticalReplicationSection(node: node)
            }
            Text("메타데이터 (JSON)").font(.subheadline.weight(.semibold))
            TextEditor(text: $metadata).font(.system(.caption, design: .monospaced))
                .frame(height: 110).border(Color.secondary.opacity(0.25))
            Text("예: {\"unit_id\": \"…\", \"description\": \"정문\"}")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                if metadata != node.metadataJSON { Text("미적용").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button("메타데이터 적용") {
                    do {
                        _ = try RoutingExporter.metadata(metadata)
                        env.updateRoutingNode(node.id, field: "metadata") { $0.metadataJSON = metadata }
                        metadataError = nil
                    } catch { metadataError = error.localizedDescription }
                }
            }
            if let metadataError { Text(metadataError).font(.caption).foregroundStyle(.red) }
            Divider()
            Text("연결 \(env.routing.connections(of: node.id).count)개").font(.subheadline.weight(.semibold))
            ForEach(env.routing.connections(of: node.id)) { edge in
                let other = env.routing.node(edge.from == node.id ? edge.to : edge.from)
                Button { env.selectRoutingEdge(edge.id) } label: {
                    Label("\(env.routing.floor(other?.floorID)?.name ?? "") · \(other?.label ?? "")", systemImage: "link")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("이 노드에서 연결 시작") {
                env.setRoutingTool(.connect)
                env.routingConnectStart = node.id
            }
            Button(role: .destructive) { env.requestRoutingNodeDeletion(node.id) } label: {
                Text("노드 삭제").foregroundStyle(.red)
            }
            Text("핀 선택 후 Delete → 삭제 확인 · ⌘Z로 복구")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { metadata = node.metadataJSON }
        .onChange(of: node.metadataJSON) { _, value in metadata = value }
    }
}

/// 기준 층에서 찍은 계단·엘리베이터·에스컬레이터를 다른 층에 같은 실제 좌표로 복제한다(신기능 13항).
private struct VerticalReplicationSection: View {
    @EnvironmentObject var env: AppEnvironment
    let node: RoutingNode
    @State private var excluded = Set<UUID>()

    var body: some View {
        let others = env.routing.floors.filter { $0.id != node.floorID }.sorted { $0.ordinal > $1.ordinal }
        let isElevator = node.category == RoutingNodeCategory.elevator.rawValue
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("층별 복제").font(.subheadline.weight(.semibold))
            if let group = node.verticalGroupID {
                Text("같은 시설 노드 \(env.routing.verticalGroup(group).count)개 (\(group.uuidString.prefix(8)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(others) { floor in
                Toggle(floor.name, isOn: Binding(get: { !excluded.contains(floor.id) }, set: { on in
                    if on { excluded.remove(floor.id) } else { excluded.insert(floor.id) }
                })).font(.caption)
            }
            Button("선택한 층에 같은 좌표로 복제") {
                env.replicateVerticalNode(node.id, to: others.map(\.id).filter { !excluded.contains($0) })
            }
            .disabled(others.allSatisfy { excluded.contains($0.id) })
            Text(isElevator ? "같은 시설의 이웃한 층 엘리베이터 노드는 자동으로 연결합니다. 이미 있는 노드는 옮기지 않습니다."
                 : "노드만 복제하고 층간 연결은 만들지 않습니다. 이미 있는 노드는 옮기지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct RoutingEdgeEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let edge: RoutingEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("연결 정보").font(.headline)
            let a = env.routing.node(edge.from), b = env.routing.node(edge.to)
            Text("\(env.routing.floor(a?.floorID)?.name ?? "") · \(a?.label ?? "")\n↕\n\(env.routing.floor(b?.floorID)?.name ?? "") · \(b?.label ?? "")")
                .font(.callout)
            Text("양방향 통행").font(.caption).foregroundStyle(.secondary)
            Picker("연결 종류", selection: Binding(get: { env.routing.edge(edge.id)?.category ?? .walkway }, set: { value in
                env.updateRoutingEdge(edge.id) { $0.category = value }
            })) {
                ForEach(RoutingEdgeCategory.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("휠체어 접근 가능", isOn: Binding(get: { env.routing.edge(edge.id)?.accessible ?? false }, set: { value in
                env.updateRoutingEdge(edge.id) { $0.accessible = value }
            }))
            .disabled(edge.category == .stairs)
            Button(role: .destructive) { env.requestRoutingEdgeDeletion(edge.id) } label: {
                Text("연결 삭제").foregroundStyle(.red)
            }
            Text("연결 선택 후 Delete → 삭제 확인. 양 끝 노드는 남습니다.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct RoutingCalibrationEditor: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var longitude = ""
    @State private var latitude = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("좌표 기준점").font(.headline)
            Text("도면에서 위치를 클릭하고 지도에서 확인한 경도·위도를 입력하세요. 서로 떨어진 3점 이상이 필요합니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let point = env.routingPendingAnchor {
                Text(String(format: "찍은 점: %.1f, %.1f", point.x, point.y)).font(.caption.monospacedDigit())
                TextField("경도 (예: 129.0)", text: $longitude)
                TextField("위도 (예: 36.0)", text: $latitude)
                Button("기준점 추가") {
                    guard let lon = Double(longitude), let lat = Double(latitude) else {
                        env.notify("경도·위도를 숫자로 입력하세요.", isError: true); return
                    }
                    env.addRoutingAnchor(longitude: lon, latitude: lat)
                }
            }
            if let floor = env.currentRoutingFloor {
                ForEach(floor.anchors.pairs) { pair in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pair.label)
                            Text(String(format: "%.7f, %.7f", pair.geo.longitude, pair.geo.latitude))
                                .font(.caption2.monospacedDigit())
                        }
                        Spacer()
                        Button(role: .destructive) {
                            env.requestDeletion(title: "\(pair.label)을 삭제할까요?",
                                                message: "이 층의 좌표 기준점 하나를 삭제합니다. 좌표 변환과 내보내기에 영향을 줄 수 있습니다. 실행 취소로 복구할 수 있습니다.") {
                                $0.updateRoutingFloor(floor.id) { $0.anchors.remove(pair.id) }
                            }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }.buttonStyle(.borderless)
                            .help("좌표 기준점 삭제")
                    }.font(.caption)
                }
            }
            Button("노드 찍기로 돌아가기") { env.setRoutingTool(.place) }
        }
    }
}

/// A text field owns Delete while typing. Only canvas selection consumes it.
@MainActor
final class RoutingKeyMonitor {
    weak var env: AppEnvironment?
    private var token: Any?
    init(env: AppEnvironment) { self.env = env }

    func start() {
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handle(keyCode: event.keyCode, modifiers: event.modifierFlags,
                             textIsEditing: NSApp.keyWindow?.firstResponder is NSTextView,
                             hasModal: NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil) ?? false
            }
            return handled ? nil : event
        }
    }

    func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], textIsEditing: Bool = false,
                hasModal: Bool = false) -> Bool {
        guard let env, env.showRoutingScreen, !env.routingContextMenuIsOpen,
              env.pendingDeletion == nil, env.routingFeatureReplacement == nil, !hasModal, !textIsEditing,
              modifiers.intersection([.command, .control]).isEmpty else { return false }
        if keyCode == 53 {
            env.routingConnectionDrag = nil
            env.routingConnectStart = nil
            env.routingPendingAnchor = nil
            env.selectRoutingNode(nil)
            env.clearRoutingFeatureSelection()
            return true
        }
        guard !modifiers.contains(.option) else { return false }
        if [51, 117].contains(keyCode), env.routingSelectedNodeID != nil || !env.routingSelectedEdgeIDs.isEmpty {
            env.requestRoutingSelectionDeletion(); return env.pendingDeletion != nil
        }
        return false
    }

    func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
}

struct EntrancePlacementSummary: View {
    let plan: EntrancePlacementPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("출입구 자동 배치 결과", systemImage: "door.left.hand.open").font(.headline)
            Text("opening \(plan.openingCount)곳 · 새 노드 \(plan.nodes.count) · 이미 배치 \(plan.alreadyPlaced) · 기존 노드와 겹침 \(plan.coveredByExisting) · 제외 \(plan.skipped.count)")
                .font(.caption)
            if !plan.skipped.isEmpty {
                DisclosureGroup("제외된 opening \(plan.skipped.count)곳") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, skip in
                            Text("\(skip.floorName) · \(skip.openingID.prefix(8)) — \(skip.reason)")
                                .font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
                        }
                    }.padding(.top, 4)
                }.font(.caption)
            }
        }
    }
}
