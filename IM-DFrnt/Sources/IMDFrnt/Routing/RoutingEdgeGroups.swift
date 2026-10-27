import Foundation

@MainActor
extension AppEnvironment {
    /// Shared by drawing, hit testing, the edge list and selection commands.
    var visibleRoutingEdges: [RoutingEdge] {
        let graph = routing, floorID = currentRoutingFloor?.id
        return graph.edges.filter {
            routingEdgeFilter.includes($0) &&
                (graph.node($0.from)?.floorID == floorID || graph.node($0.to)?.floorID == floorID)
        }
    }

    var selectedRoutingEdges: [RoutingEdge] {
        visibleRoutingEdges.filter { routingSelectedEdgeIDs.contains($0.id) }
    }

    func setRoutingEdgeFilter(_ filter: RoutingEdgeFilter) {
        routingEdgeFilter = filter
        normalizeRoutingEdgeState()
    }

    func normalizeRoutingEdgeState() {
        if case .group(let id) = routingEdgeFilter, routing.edgeGroup(id) == nil { routingEdgeFilter = .all }
        if routing.edgeGroup(routingNewEdgeGroupID) == nil { routingNewEdgeGroupID = nil }
        routingSelectedEdgeIDs.formIntersection(Set(visibleRoutingEdges.map(\.id)))
        routingSelectedEdgeID = routingSelectedEdgeIDs.count == 1 ? routingSelectedEdgeIDs.first : nil
    }

    @discardableResult
    func addRoutingEdgeGroup(name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let group = RoutingEdgeGroup(name: name)
        perform("엣지 그룹 추가") {
            var graph = routing
            graph.edgeGroups = (graph.edgeGroups ?? []) + [group]
            routing = graph
        }
        return group.id
    }

    func renameRoutingEdgeGroup(_ id: UUID, name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = routing.edgeGroups?.firstIndex(where: { $0.id == id }) else { return }
        perform("엣지 그룹 이름 편집", coalescingKey: "edge-group:\(id)") {
            var graph = routing
            graph.edgeGroups?[index].name = name
            routing = graph
        }
    }

    func removeRoutingEdgeGroup(_ id: UUID) {
        guard routing.edgeGroup(id) != nil else { return }
        perform("엣지 그룹 삭제·배정 해제") {
            var graph = routing
            graph.edgeGroups?.removeAll { $0.id == id }
            if graph.edgeGroups?.isEmpty == true { graph.edgeGroups = nil }
            for i in graph.edges.indices where graph.edges[i].groupID == id { graph.edges[i].groupID = nil }
            routing = graph
            normalizeRoutingEdgeState()
        }
    }

    func assignRoutingEdgeGroup(_ groupID: UUID?) {
        guard groupID == nil || routing.edgeGroup(groupID) != nil else { return }
        let selected = Set(selectedRoutingEdges.map(\.id))
        guard !selected.isEmpty else { return }
        perform("선택 엣지 그룹 배정") {
            var graph = routing
            for i in graph.edges.indices where selected.contains(graph.edges[i].id) { graph.edges[i].groupID = groupID }
            routing = graph
            normalizeRoutingEdgeState()
        }
    }

    /// Never relabel a pre-existing undirected connection just because it was selected again.
    func connectRoutingNodes(_ from: UUID, _ to: UUID) -> UUID? {
        var graph = routing
        let existing = Set(graph.edges.map(\.id))
        guard let id = graph.connect(from, to) else { return nil }
        if !existing.contains(id), graph.edgeGroup(routingNewEdgeGroupID) != nil,
           let index = graph.edges.firstIndex(where: { $0.id == id }) {
            graph.edges[index].groupID = routingNewEdgeGroupID
        }
        routing = graph
        return id
    }

    func selectRoutingEdge(_ id: UUID?, additive: Bool) {
        guard additive else { selectRoutingEdge(id); return }
        guard let id, visibleRoutingEdges.contains(where: { $0.id == id }) else { return }
        routingSelectedNodeID = nil
        if !routingSelectedEdgeIDs.insert(id).inserted { routingSelectedEdgeIDs.remove(id) }
        normalizeRoutingEdgeState()
    }

    /// Use screen coordinates, so zoom and rotation do not change the marquee's meaning.
    func selectRoutingEdges(in rect: CGRect, projecting: (LocalPoint) -> CGPoint, additive: Bool) {
        let graph = routing, floorID = currentRoutingFloor?.id
        let hits = visibleRoutingEdges.compactMap { edge -> UUID? in
            guard let a = graph.node(edge.from), let b = graph.node(edge.to),
                  a.floorID == floorID, b.floorID == floorID,
                  RoutingEdgeSelection.intersects(rect, from: projecting(a.point), to: projecting(b.point)) else { return nil }
            return edge.id
        }
        routingSelectedNodeID = nil
        routingSelectedEdgeIDs = additive ? routingSelectedEdgeIDs.union(hits) : Set(hits)
        normalizeRoutingEdgeState()
    }

    func deleteRoutingEdges(_ ids: Set<UUID>) {
        guard routing.edges.contains(where: { ids.contains($0.id) }) else { return }
        perform("선택 연결 삭제") {
            var graph = routing
            graph.edges.removeAll { ids.contains($0.id) }
            routing = graph
            normalizeRoutingEdgeState()
        }
    }
}

enum RoutingEdgeSelection {
    /// Segment/rectangle clipping includes a line crossing the box with both endpoints outside.
    static func intersects(_ rect: CGRect, from a: CGPoint, to b: CGPoint) -> Bool {
        guard !rect.isNull, [a.x, a.y, b.x, b.y, rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite) else { return false }
        var low = 0.0, high = 1.0
        for (origin, delta, minimum, maximum) in [
            (a.x, b.x - a.x, rect.minX, rect.maxX), (a.y, b.y - a.y, rect.minY, rect.maxY)
        ] {
            if delta == 0 {
                if origin < minimum || origin > maximum { return false }
            } else {
                let t1 = (minimum - origin) / delta, t2 = (maximum - origin) / delta
                low = max(low, min(t1, t2)); high = min(high, max(t1, t2))
                if low > high { return false }
            }
        }
        return true
    }
}
