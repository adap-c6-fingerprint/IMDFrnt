import SwiftUI

struct RoutingNodeGroupAssignment: View {
    @EnvironmentObject var env: AppEnvironment
    let node: RoutingNode

    var body: some View {
        let graph = env.routing
        VStack(alignment: .leading, spacing: 8) {
            Picker("시설 노드 그룹", selection: Binding(
                get: { env.routing.node(node.id)?.verticalGroupID },
                set: { env.assignRoutingNodeGroup(node.id, to: $0) })) {
                Text("미배정").tag(nil as UUID?)
                ForEach(graph.nodeGroups ?? []) { group in
                    if graph.acceptsNode(node, in: group.id) || node.verticalGroupID == group.id {
                        Text("\(group.name) · \(group.id.uuidString.prefix(8))").tag(Optional(group.id))
                    }
                }
            }
            RoutingNodeGroupCreator(nodeID: node.id)
            Text(node.category == "escalator"
                 ? "에스컬레이터는 그룹만 배정합니다. 상·하행 방향과 층간 자동 연결은 지원하지 않습니다."
                 : "같은 종류·층마다 노드 하나를 배정합니다. 이웃한 층만 자동 연결하며, 미배정으로 바꾸면 그룹의 자동 연결만 해제합니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct RoutingNodeGroupsPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedGroup: UUID?

    var body: some View {
        let graph = env.routing
        let members = graph.nodes.filter {
            $0.verticalGroupID == selectedGroup && RoutingNodeCategory(rawValue: $0.category)?.isVertical == true
        }.sorted {
            let a = graph.floor($0.floorID)?.ordinal ?? 0, b = graph.floor($1.floorID)?.ordinal ?? 0
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("시설 노드 그룹").font(.headline)
            RoutingNodeGroupCreator()
            Picker("그룹별 노드 목록", selection: $selectedGroup) {
                Text("미배정").tag(nil as UUID?)
                ForEach(graph.nodeGroups ?? []) { group in
                    Text("\(group.name) · \(group.id.uuidString.prefix(8))").tag(Optional(group.id))
                }
            }
            if let group = graph.nodeGroup(selectedGroup) {
                TextField("그룹 이름", text: Binding(
                    get: { env.routing.nodeGroup(group.id)?.name ?? "" },
                    set: { env.renameRoutingNodeGroup(group.id, name: $0) }))
                Text(group.id.uuidString.lowercased()).font(.caption2.monospaced()).textSelection(.enabled)
                HStack {
                    Button("인접 층 연결 갱신") { env.reconnectRoutingNodeGroup(group.id) }
                    Button(role: .destructive) {
                        env.requestDeletion(title: "‘\(group.name)’ 노드 그룹을 삭제할까요?",
                            message: "노드와 기존 수동 연결은 유지하고, 이 그룹의 배정과 자동 연결만 해제합니다.") {
                            $0.removeRoutingNodeGroup(group.id)
                        }
                    } label: { Image(systemName: "trash") }
                    .help("노드 그룹 삭제")
                }
                Text("연결 갱신: 엘리베이터·계단만 지원. 에스컬레이터와 서로 다른 종류가 섞인 기존 그룹은 자동 연결하지 않습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("전체 층의 노드 \(members.count)개") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(members) { member in
                            Button {
                                env.selectRoutingFloor(member.floorID)
                                env.selectRoutingNode(member.id)
                            } label: {
                                Text("\(graph.floor(member.floorID)?.name ?? "") · \(member.label)")
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 160)
            }
        }
        .onChange(of: graph.nodeGroups) { _, _ in
            if graph.nodeGroup(selectedGroup) == nil { selectedGroup = nil }
        }
    }
}

private struct RoutingNodeGroupCreator: View {
    @EnvironmentObject var env: AppEnvironment
    var nodeID: UUID?
    @State private var name = ""

    var body: some View {
        HStack {
            TextField("새 노드 그룹 이름", text: $name).onSubmit { create() }
            Button(nodeID == nil ? "생성" : "생성·배정") { create() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func create() {
        if env.addRoutingNodeGroup(name: name, assigning: nodeID) != nil { name = "" }
    }
}
