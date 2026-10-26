import Foundation

enum RoutingExporter {
    struct Failure: LocalizedError {
        var messages: [String]
        var errorDescription: String? { messages.joined(separator: "\n") }
    }

    static func metadata(_ json: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw Failure(messages: ["메타데이터는 JSON 객체여야 합니다. 예: {\"unit_id\": \"…\"}"])
        }
        return object
    }

    static func collection(_ graph: RoutingGraph) throws -> [String: Any] {
        var errors: [String] = []
        if graph.nodes.isEmpty { errors.append("먼저 노드를 찍어 주세요.") }
        if graph.layoutVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("도면 버전을 입력하세요.")
        }
        if !graph.hardSearchRadiusMeters.isFinite || graph.hardSearchRadiusMeters <= 0 {
            errors.append("탐색 반경은 0보다 큰 미터 값이어야 합니다.")
        }
        if Set(graph.floors.map(\.id)).count != graph.floors.count {
            errors.append("층 ID는 중복될 수 없습니다.")
        }
        let ids = graph.nodes.map(\.id) + graph.edges.map(\.id)
        if Set(ids).count != ids.count { errors.append("노드·연결 ID가 중복됩니다.") }
        var coordinates: [UUID: GeoPoint] = [:]
        for floor in graph.floors where !graph.nodes(on: floor.id).isEmpty {
            let configured = floor.hasGeographicCoordinates
            if !configured { errors.append("\(floor.name): IMDF 좌표 또는 서로 일직선이 아닌 좌표 기준점 3개 이상이 필요합니다.") }
            for node in graph.nodes(on: floor.id) {
                guard let geo = floor.geoPoint(for: node.point), geo.longitude.isFinite,
                      geo.latitude.isFinite, abs(geo.longitude) <= 180, abs(geo.latitude) <= 90 else {
                    if configured { errors.append("\(node.label): 실제 좌표가 유효하지 않습니다.") }
                    continue
                }
                coordinates[node.id] = geo
            }
        }
        for node in graph.nodes {
            if graph.floor(node.floorID) == nil { errors.append("\(node.label): 소속 층이 없습니다.") }
            if !node.point.x.isFinite || !node.point.y.isFinite { errors.append("\(node.label): 도면 좌표가 유효하지 않습니다.") }
            if (try? metadata(node.metadataJSON)) == nil { errors.append("\(node.label): 메타데이터가 유효한 JSON 객체가 아닙니다.") }
        }
        var pairs = Set<String>()
        for edge in graph.edges {
            guard let a = graph.node(edge.from), let b = graph.node(edge.to), a.id != b.id else {
                errors.append("연결 \(edge.id.uuidString.prefix(6)): 양 끝 노드가 유효하지 않습니다.")
                continue
            }
            let key = [a.id.uuidString, b.id.uuidString].sorted().joined(separator: ":")
            if !pairs.insert(key).inserted { errors.append("\(a.label) ↔ \(b.label): 중복 연결입니다.") }
            if a.floorID != b.floorID {
                if edge.category == .walkway || a.category != edge.category.rawValue || b.category != edge.category.rawValue {
                    errors.append("층간 연결 \(a.label) ↔ \(b.label): 같은 종류의 계단 또는 엘리베이터 노드를 연결하세요.")
                }
            }
            if edge.category == .stairs && edge.accessible {
                errors.append("계단 연결은 휠체어 접근 가능으로 표시할 수 없습니다.")
            }
        }
        guard errors.isEmpty else { throw Failure(messages: errors) }

        var features: [[String: Any]] = []
        for node in graph.nodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let geo = coordinates[node.id], let floor = graph.floor(node.floorID) else { continue }
            var properties: [String: Any] = ["role": "node", "level": floor.ordinal,
                               "level_id": floor.id.uuidString.lowercased(), "name": node.name,
                               "category": node.category, "metadata": try metadata(node.metadataJSON)]
            if let group = node.verticalGroupID { properties["vertical_group_id"] = group.uuidString.lowercased() }
            features.append([
                "type": "Feature", "id": node.id.uuidString.lowercased(),
                "properties": properties,
                "geometry": ["type": "Point", "coordinates": geo.geoJSONArray]
            ])
        }
        for edge in graph.edges.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let from = coordinates[edge.from], let to = coordinates[edge.to] else { continue }
            features.append([
                "type": "Feature", "id": edge.id.uuidString.lowercased(),
                "properties": ["role": "edge", "from": edge.from.uuidString.lowercased(),
                               "to": edge.to.uuidString.lowercased(), "accessible": edge.accessible,
                               "direction": "undirected", "category": edge.category.rawValue],
                "geometry": ["type": "LineString", "coordinates": [from.geoJSONArray, to.geoJSONArray]]
            ])
        }
        return ["type": "FeatureCollection", "schema_version": 1,
                "layout_version": graph.layoutVersion,
                "routing_config": ["hard_search_radius_meters": graph.hardSearchRadiusMeters],
                "features": features]
    }

    static func encoded(_ graph: RoutingGraph) throws -> Data {
        try JSONSerialization.data(withJSONObject: collection(graph), options: [.prettyPrinted, .sortedKeys])
    }
}
