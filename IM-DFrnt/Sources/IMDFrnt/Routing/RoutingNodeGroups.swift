import Foundation

struct RoutingNodeGroup: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
}

extension RoutingGraph {
    func nodeGroup(_ id: UUID?) -> RoutingNodeGroup? { nodeGroups?.first { $0.id == id } }

    /// Legacy IDs have no names. Preserve IDs and do not guess ownership of old edges.
    mutating func migrateNodeGroups() {
        guard nodeGroups == nil else { return }
        let ids = Set(nodes.compactMap(\.verticalGroupID)).sorted { $0.uuidString < $1.uuidString }
        if !ids.isEmpty {
            nodeGroups = ids.map { RoutingNodeGroup(id: $0, name: "기존 시설 · \($0.uuidString.prefix(8))") }
        }
    }

    func validateNodeGroups() throws {
        // Nil is the legacy format; names are materialized at the project boundary.
        let groups = nodeGroups ?? [], ids = Set(groups.map(\.id))
        guard ids.count == groups.count, groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              nodeGroups == nil || nodes.allSatisfy({ $0.verticalGroupID == nil || ids.contains($0.verticalGroupID!) }) else {
            throw IMDFImporter.Failure(message: "노드 그룹 이름·UUID 또는 노드의 그룹 참조가 올바르지 않습니다.")
        }
        let lookup = nodesByID
        for edge in edges {
            guard let group = edge.autoVerticalGroupID else { continue }
            guard ids.contains(group), let a = lookup[edge.from], let b = lookup[edge.to],
                  a.verticalGroupID == group, b.verticalGroupID == group,
                  a.category == b.category, ["elevator", "stairs"].contains(a.category),
                  edge.category.rawValue == a.category,
                  let x = floor(a.floorID)?.ordinal, let y = floor(b.floorID)?.ordinal,
                  min(x, y) < Int.max, max(x, y) == min(x, y) + 1 else {
                throw IMDFImporter.Failure(message: "노드 그룹의 자동 연결은 같은 시설의 이웃한 층 사이여야 합니다.")
            }
        }
    }

    func acceptsNode(_ node: RoutingNode, in groupID: UUID) -> Bool {
        nodeGroup(groupID) != nil && RoutingNodeCategory(rawValue: node.category)?.isVertical == true
            && nodes.filter { $0.verticalGroupID == groupID && $0.id != node.id }.allSatisfy {
                $0.category == node.category && $0.floorID != node.floorID
                    && floor($0.floorID)?.ordinal != floor(node.floorID)?.ordinal
            }
    }

    mutating func assignNodeGroup(_ id: UUID, to groupID: UUID?) throws {
        migrateNodeGroups()
        guard let index = nodes.firstIndex(where: { $0.id == id }) else {
            throw IMDFImporter.Failure(message: "배정할 노드가 없습니다.")
        }
        if let groupID, !acceptsNode(nodes[index], in: groupID) {
            throw IMDFImporter.Failure(message: "같은 종류의 시설만 묶을 수 있으며, 한 그룹에는 층마다 노드 하나만 배정할 수 있습니다.")
        }
        let previous = nodes[index].verticalGroupID
        nodes[index].verticalGroupID = groupID
        if let previous, previous != groupID { _ = reconcileNodeGroup(previous) }
        if let groupID { _ = reconcileNodeGroup(groupID) }
    }

    /// Never bridge missing ordinals or relabel/delete a pre-existing manual connection.
    @discardableResult
    mutating func reconcileNodeGroup(_ groupID: UUID) -> Int {
        let members = verticalGroup(groupID)
        let categories = Set(members.map(\.category))
        var pairs: [(UUID, UUID)] = []
        if nodeGroup(groupID) != nil, categories.count == 1,
           let category = categories.first, ["elevator", "stairs"].contains(category),
           Set(members.map(\.floorID)).count == members.count,
           Set(members.compactMap { floor($0.floorID)?.ordinal }).count == members.count {
            for (a,b) in zip(members, members.dropFirst()) {
                if let x = floor(a.floorID)?.ordinal, let y = floor(b.floorID)?.ordinal,
                   x < Int.max, y == x + 1 { pairs.append((a.id,b.id)) }
            }
        }
        func key(_ a: UUID, _ b: UUID) -> String { [a.uuidString,b.uuidString].sorted().joined(separator: ":") }
        let wanted = Set(pairs.map { key($0.0,$0.1) })
        edges.removeAll { $0.autoVerticalGroupID == groupID && !wanted.contains(key($0.from,$0.to)) }
        var added = 0
        for (a,b) in pairs {
            guard !edges.contains(where: { key($0.from,$0.to) == key(a,b) }), let id = connect(a,b),
                  let index = edges.firstIndex(where: { $0.id == id }) else { continue }
            edges[index].autoVerticalGroupID = groupID
            added += 1
        }
        return added
    }

    mutating func removeNodeGroup(_ id: UUID) {
        edges.removeAll { $0.autoVerticalGroupID == id }
        for i in nodes.indices where nodes[i].verticalGroupID == id { nodes[i].verticalGroupID = nil }
        nodeGroups?.removeAll { $0.id == id }
        if nodeGroups?.isEmpty == true { nodeGroups = nil }
    }
}

extension BuildingProject {
    mutating func migrateNodeGroups() {
        var graph = routingGraph
        graph.migrateNodeGroups()
        nodeGroups = graph.nodeGroups
    }
}

@MainActor
extension AppEnvironment {
    @discardableResult
    func addRoutingNodeGroup(name: String, assigning nodeID: UUID? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var graph = routing
        graph.migrateNodeGroups()
        let group = RoutingNodeGroup(name: name)
        graph.nodeGroups = (graph.nodeGroups ?? []) + [group]
        do { if let nodeID { try graph.assignNodeGroup(nodeID, to: group.id) } }
        catch { notify(error.localizedDescription, isError: true); return nil }
        perform("노드 그룹 생성·배정") { routing = graph }
        return group.id
    }

    func assignRoutingNodeGroup(_ nodeID: UUID, to groupID: UUID?) {
        var graph = routing
        do { try graph.assignNodeGroup(nodeID, to: groupID) }
        catch { notify(error.localizedDescription, isError: true); return }
        guard graph != routing else { return }
        perform("노드 그룹 배정·연결") { routing = graph; normalizeRoutingEdgeState() }
    }

    func renameRoutingNodeGroup(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = routing.nodeGroups?.firstIndex(where: { $0.id == id }),
              routing.nodeGroups?[index].name != name else { return }
        perform("노드 그룹 이름 편집", coalescingKey: "node-group:\(id)") {
            var graph = routing
            graph.nodeGroups?[index].name = name
            routing = graph
        }
    }

    func removeRoutingNodeGroup(_ id: UUID) {
        guard routing.nodeGroup(id) != nil else { return }
        perform("노드 그룹 삭제·자동 연결 해제") {
            var graph = routing
            graph.removeNodeGroup(id)
            routing = graph
            normalizeRoutingEdgeState()
        }
    }

    func reconnectRoutingNodeGroup(_ id: UUID) {
        var graph = routing
        _ = graph.reconcileNodeGroup(id)
        guard graph != routing else { return }
        perform("노드 그룹 인접 층 연결 갱신") { routing = graph; normalizeRoutingEdgeState() }
    }
}
