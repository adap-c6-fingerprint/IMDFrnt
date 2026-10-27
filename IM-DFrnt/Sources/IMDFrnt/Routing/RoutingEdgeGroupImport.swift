import Foundation

enum RoutingEdgeGroupImport {
    static func prepare(_ original: ProjectLevel, source: BuildingProject?, target: BuildingProject) throws
        -> (level: ProjectLevel, groups: [RoutingEdgeGroup]?) {
        try target.routingGraph.validateEdgeGroups()
        if let source { try source.routingGraph.validateEdgeGroups() }
        var groups = target.edgeGroups ?? [], level = original
        let referenced = Set(original.edges.compactMap(\.groupID))
        var replacements: [UUID: UUID] = [:]
        var reserved = Set(groups.map(\.id)).union(source?.edgeGroups?.map(\.id) ?? [])
        for id in referenced.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard var incoming = (source ?? target).routingGraph.edgeGroup(id) else {
                throw IMDFImporter.Failure(message: "가져올 연결의 엣지 그룹 정보가 없습니다.")
            }
            if let existing = groups.first(where: { $0.id == id }) {
                if existing == incoming { continue }
                // Same-project copies may have renamed a group; keep both meanings without overwriting either.
                repeat { incoming.id = UUID() } while reserved.contains(incoming.id)
                reserved.insert(incoming.id)
                replacements[id] = incoming.id
            }
            groups.append(incoming)
        }
        for i in level.edges.indices {
            if let id = level.edges[i].groupID, let replacement = replacements[id] { level.edges[i].groupID = replacement }
        }
        return (level, groups.isEmpty ? nil : groups)
    }
}
