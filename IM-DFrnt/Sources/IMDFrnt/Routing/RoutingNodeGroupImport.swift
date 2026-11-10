import Foundation

enum RoutingNodeGroupImport {
    static func prepare(_ original: ProjectLevel, source: BuildingProject?, target: BuildingProject) throws
        -> (level: ProjectLevel, groups: [RoutingNodeGroup]?) {
        var incomingGraph = (source ?? target).routingGraph, targetGraph = target.routingGraph
        incomingGraph.migrateNodeGroups(); targetGraph.migrateNodeGroups()
        try incomingGraph.validateNodeGroups(); try targetGraph.validateNodeGroups()
        var groups = targetGraph.nodeGroups ?? [], level = original
        let referenced = Set(original.nodes.compactMap(\.verticalGroupID))
        var reserved = Set(groups.map(\.id)).union(incomingGraph.nodeGroups?.map(\.id) ?? [])
        var replacements: [UUID:UUID] = [:]
        for id in referenced.sorted(by: { $0.uuidString < $1.uuidString }) {
            // Metadata-less imports can still carry the legacy unnamed group IDs.
            guard var incoming = incomingGraph.nodeGroup(id) ?? (source == nil
                ? RoutingNodeGroup(id: id, name: "기존 시설 · \(id.uuidString.prefix(8))") : nil) else {
                throw IMDFImporter.Failure(message: "가져올 노드의 그룹 정보가 없습니다.")
            }
            if let existing = groups.first(where: { $0.id == id }) {
                if existing == incoming { continue }
                repeat { incoming.id = UUID() } while reserved.contains(incoming.id)
                reserved.insert(incoming.id)
                replacements[id] = incoming.id
            }
            groups.append(incoming)
        }
        for i in level.nodes.indices {
            if let id = level.nodes[i].verticalGroupID, let replacement = replacements[id] {
                level.nodes[i].verticalGroupID = replacement
            }
        }
        for i in level.edges.indices {
            if let id = level.edges[i].autoVerticalGroupID, let replacement = replacements[id] {
                level.edges[i].autoVerticalGroupID = replacement
            }
        }
        return (level, groups.isEmpty ? nil : groups)
    }
}
