import Foundation

/// IMDF/그래프와 분리된 명시적 장소 매핑. iOS 소비자는 두 인덱스를 함께 읽는다.
enum NavigationFeatureLinks {
    static let fileName = "navigation-feature-links.json"

    static func records(project: BuildingProject, ids: [UUID: IDAssigner]) throws -> [ProjectJSON] {
        try RoutingFeatureLinks.validateUnique(in: project)
        var records: [ProjectJSON] = []
        for level in project.levels {
            for node in level.nodes {
                for ref in node.featureLinks ?? [] {
                    guard ref.isAvailable(in: project, levelID: level.id) else {
                        throw ClientDataset.Blocked(messages: ["\(level.info.name) · \(node.label): 연결한 \(ref.kind.title)이 없거나 휴지통에 있습니다. 장소 연결을 해제하거나 도형을 복원하세요."])
                    }
                    let id: UUID
                    if let authored = ref.authored(in: level) {
                        guard let exported = (ids[level.id] ?? level.editing.ids).peek(authored.id) else {
                            throw ClientDataset.Blocked(messages: ["\(node.label): 장소의 실제 IMDF UUID를 확인할 수 없습니다."])
                        }
                        id = exported
                    } else { id = ref.featureID }
                    records.append(.object([
                        "feature_type": .string(ref.kind.rawValue), "feature_id": .string(id.uuidString.lowercased()),
                        "level_id": .string(level.id.uuidString.lowercased()), "node_id": .string(node.id.uuidString.lowercased())
                    ]))
                }
            }
        }
        records.sort { $0.text < $1.text }
        return records
    }

    static func build(project: BuildingProject, ids: [UUID: IDAssigner], files: [String: Data]) throws -> Data {
        let records = try records(project: project, ids: ids)
        let data = try encoded(records: records, layoutVersion: project.layoutVersion)
        var finalFiles = files; finalFiles[fileName] = data
        let errors = problems(files: finalFiles, project: project, ids: ids)
        guard errors.isEmpty else { throw ClientDataset.Blocked(messages: errors) }
        return data
    }

    /// Shared wire format; routing-only export has no IMDF files to cross-check.
    static func encoded(records: [ProjectJSON], layoutVersion: String) throws -> Data {
        let nodeIDs = Set(records.compactMap { $0["node_id"]?.string })
        let nodes: [ProjectJSON] = nodeIDs.sorted().map { nodeID in
            .object(["node_id": .string(nodeID), "features": .array(records.filter { $0["node_id"]?.string == nodeID }.map { record in
                var ref = record; ref["node_id"] = nil; return ref
            })])
        }
        return try ProjectJSON.object([
            "schema_version": .number(1), "layout_version": .string(layoutVersion),
            "features": .array(records), "nodes": .array(nodes)
        ]).data()
    }

    /// 최종 IMDF/그래프 바이트와 대조해 층·UUID·1:N 제한·양방향 인덱스 일치를 검사한다.
    static func problems(files: [String: Data], project: BuildingProject, ids: [UUID: IDAssigner] = [:]) -> [String] {
        let hasLinks = project.levels.contains { $0.nodes.contains { $0.featureLinks?.isEmpty == false } }
        guard let data = files[fileName] else { return hasLinks ? ["장소 연결 파일이 없습니다."] : [] }
        do {
            let root = try ProjectJSON.parse(data)
            guard root["schema_version"] == .number(1), root["layout_version"]?.string == project.layoutVersion,
                  root["features"]?.isArray == true, root["nodes"]?.isArray == true else { return ["장소 연결 파일의 형식/도면 버전이 올바르지 않습니다."] }
            let routing = try ProjectJSON.parse(files[ClientDataset.routingFile] ?? Data())
            var nodeLevels: [UUID: UUID] = [:]
            for node in routing["features"]?.array ?? [] where node["properties"]?["role"]?.string == "node" {
                if let id = node["id"]?.uuid, let level = node["properties"]?["level_id"]?.uuid { nodeLevels[id] = level }
            }
            var maps: [String: [ProjectJSON]] = [:]
            for kind in RoutingFeatureKind.allCases {
                let path = ClientDataset.imdfDirectory + "/" + kind.rawValue + ".geojson"
                maps[kind.rawValue] = try ProjectJSON.parse(files[path] ?? Data())["features"]?.array ?? []
            }
            let records = root["features"]!.array
            var identities = Set<String>()
            for record in records {
                guard let type = record["feature_type"]?.string, let kind = RoutingFeatureKind(rawValue: type),
                      let id = record["feature_id"]?.uuid, let node = record["node_id"]?.uuid, let level = record["level_id"]?.uuid,
                      nodeLevels[node] == level,
                      let feature = maps[kind.rawValue]?.first(where: { $0["id"]?.uuid == id }),
                      BuildingProject.levelReferences(feature).contains(level),
                      identities.insert(type + ":" + id.uuidString).inserted else {
                    return ["장소 연결의 IMDF UUID·층·노드 참조가 없거나 장소 하나에 노드가 중복 배정되었습니다."]
                }
            }
            var reverse: [ProjectJSON] = [], seenNodes = Set<UUID>()
            for entry in root["nodes"]!.array {
                guard let node = entry["node_id"]?.uuid, seenNodes.insert(node).inserted,
                      entry["features"]?.isArray == true, !entry["features"]!.array.isEmpty else { return ["노드별 장소 목록 형식이 올바르지 않습니다."] }
                reverse += entry["features"]!.array.map { ref in var value = ref; value["node_id"] = entry["node_id"]; return value }
            }
            guard reverse.count == records.count, Set(reverse) == Set(records),
                  Set(records) == Set(try self.records(project: project, ids: ids)) else {
                return ["장소→노드와 노드→장소 인덱스가 일치하지 않습니다."]
            }
            return []
        } catch { return ["장소 연결 JSON을 읽을 수 없습니다: \(error.localizedDescription)"] }
    }
}
