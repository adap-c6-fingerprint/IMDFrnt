import AppKit
import SwiftUI

struct RoutingEdgeGroupsPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var newName = ""
    @State private var assignmentID: UUID?

    var body: some View {
        let graph = env.routing, nodes = graph.nodesByID
        let visible = graph.visibleEdges(on: env.currentRoutingFloor?.id, filter: env.routingEdgeFilter)
        let selectedCount = visible.filter { env.routingSelectedEdgeIDs.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 10) {
            Text("엣지 그룹").font(.headline)
            Picker("엣지 필터", selection: Binding(get: { env.routingEdgeFilter }, set: { env.setRoutingEdgeFilter($0) })) {
                Text("전체").tag(RoutingEdgeFilter.all)
                Text("미배정만").tag(RoutingEdgeFilter.unassigned)
                ForEach(graph.edgeGroups ?? []) { group in
                    Text(label(group)).tag(RoutingEdgeFilter.group(group.id))
                }
            }
            RoutingEdgeGroupPicker(title: "새 엣지 그룹", selection: $env.routingNewEdgeGroupID)
            Text("새로 연결할 엣지에만 적용합니다. 기존 연결은 바꾸지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                TextField("새 그룹 이름", text: $newName)
                    .onSubmit { addGroup() }
                Button("추가") { addGroup() }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            DisclosureGroup("그룹 이름·UUID 관리") {
                ForEach(graph.edgeGroups ?? []) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("그룹 이름", text: Binding(
                                get: { env.routing.edgeGroup(group.id)?.name ?? "" },
                                set: { env.renameRoutingEdgeGroup(group.id, name: $0) }))
                            Button(role: .destructive) {
                                env.requestDeletion(title: "‘\(group.name)’ 그룹을 삭제할까요?",
                                    message: "이 그룹의 연결은 남기고 그룹 배정만 해제합니다. 실행 취소로 복구할 수 있습니다.") {
                                    $0.removeRoutingEdgeGroup(group.id)
                                }
                            } label: { Image(systemName: "trash") }
                        }
                        Text(group.id.uuidString.lowercased()).font(.caption2.monospaced()).textSelection(.enabled)
                    }.padding(.top, 6)
                }
            }
            Divider()
            Text("선택 엣지 \(selectedCount)개").font(.subheadline.weight(.semibold))
            RoutingEdgeGroupPicker(title: "배정할 그룹", selection: $assignmentID)
            Button("선택 엣지에 적용") { env.assignRoutingEdgeGroup(assignmentID) }
                .disabled(selectedCount == 0)
            Text("미배정 선택 후 적용하면 그룹을 해제합니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("엣지 다중 선택 도구") { env.setRoutingTool(.edges) }
            Text("Shift 클릭: 추가/해제 · 드래그: 교차하는 엣지 선택 · Shift 드래그: 추가. 층간 엣지는 아래 목록에서도 선택할 수 있습니다.")
                .font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("현재 층 엣지 \(visible.count)개") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visible) { edge in
                            Button {
                                env.selectRoutingEdge(edge.id, additive: NSEvent.modifierFlags.contains(.shift))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(nodes[edge.from]?.label ?? "") ↔ \(nodes[edge.to]?.label ?? "")")
                                        .lineLimit(2)
                                    Text(graph.edgeGroup(edge.groupID).map(label) ?? "미배정")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(env.routingSelectedEdgeIDs.contains(edge.id) ? Color.orange.opacity(0.18) : Color.clear)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 180)
            }
        }
        .onChange(of: graph.edgeGroups) { _, groups in
            if let id = assignmentID, !(groups ?? []).contains(where: { $0.id == id }) { assignmentID = nil }
        }
    }

    private func label(_ group: RoutingEdgeGroup) -> String { "\(group.name) · \(group.id.uuidString.prefix(8))" }

    private func addGroup() {
        if let id = env.addRoutingEdgeGroup(name: newName) {
            assignmentID = id
            env.routingNewEdgeGroupID = id
            newName = ""
        }
    }
}

private struct RoutingEdgeGroupPicker: View {
    @EnvironmentObject var env: AppEnvironment
    let title: String
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("미배정").tag(nil as UUID?)
            ForEach(env.routing.edgeGroups ?? []) { group in
                Text("\(group.name) · \(group.id.uuidString.prefix(8))").tag(Optional(group.id))
            }
        }
    }
}
