import Foundation

struct DeletionRequest: Identifiable {
    let id = UUID()
    let projectID: UUID
    let title: String
    let message: String
    let action: @MainActor (AppEnvironment) -> Void
}

@MainActor
extension AppEnvironment {
    func requestDeletion(title: String, message: String,
                         action: @escaping @MainActor (AppEnvironment) -> Void) {
        guard pendingDeletion == nil else { return }
        pendingDeletion = DeletionRequest(projectID: projectID, title: title, message: message, action: action)
    }

    func cancelDeletion() { pendingDeletion = nil }

    func confirmDeletion(_ requestID: UUID) {
        guard let request = pendingDeletion, request.id == requestID else { return }
        pendingDeletion = nil
        guard request.projectID == projectID else { return }
        request.action(self)
    }

    func requestRoutingSelectionDeletion() {
        if let id = routingSelectedNodeID { requestRoutingNodeDeletion(id) }
        else if let id = routingSelectedEdgeID { requestRoutingEdgeDeletion(id) }
    }

    func requestRoutingNodeDeletion(_ id: UUID) {
        guard let node = routing.node(id) else { return }
        requestDeletion(title: "\(node.label)을 삭제할까요?",
                        message: "이 노드와 연결선 \(routing.connections(of: id).count)개를 삭제합니다. 실행 취소로 복구할 수 있습니다.") {
            $0.deleteRoutingNode(id)
        }
    }

    func requestRoutingEdgeDeletion(_ id: UUID) {
        guard let edge = routing.edge(id), let from = routing.node(edge.from), let to = routing.node(edge.to) else { return }
        requestDeletion(title: "연결을 삭제할까요?",
                        message: "\(from.label) ↔ \(to.label)의 연결을 삭제합니다. 양 끝 노드는 남습니다. 실행 취소로 복구할 수 있습니다.") {
            $0.deleteRoutingEdge(id)
        }
    }

    func requestRoutingFloorDeletion(_ id: UUID) {
        guard let floor = routing.floor(id) else { return }
        requestDeletion(title: "\(floor.name)을 삭제할까요?",
                        message: "\(floor.name)의 도면과 노드 \(routing.nodes(on: id).count)개를 삭제합니다. 다른 층으로 이어지는 연결선도 함께 삭제됩니다. 실행 취소로 복구할 수 있습니다.") {
            guard $0.routing.floor(id) != nil else { return }
            $0.removeRoutingFloor(id)
        }
    }
}
