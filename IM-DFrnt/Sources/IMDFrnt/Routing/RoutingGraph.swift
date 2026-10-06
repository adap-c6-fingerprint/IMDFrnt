import Foundation

/// Editor coordinates and drawings stay in the project. Client export uses WGS 84.
struct RoutingFloor: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var ordinal: Int
    var sourceName: String = ""
    var svg: String = ""
    var anchors = AnchorStore()
    /// IMDF already contains WGS 84 geometry; no manual calibration is needed.
    var imdfCoordinates: IMDFCoordinateSpace?

    var hasGeographicCoordinates: Bool {
        imdfCoordinates?.isValid == true || Georeferencer(pairs: anchors.pairs).isConfigured
    }

    func geoPoint(for point: LocalPoint) -> GeoPoint? {
        if let coordinates = imdfCoordinates {
            return coordinates.isValid ? coordinates.geoPoint(for: point) : nil
        }
        return Georeferencer(pairs: anchors.pairs).geoPoint(for: point)
    }
}

struct RoutingNode: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var floorID: UUID
    var point: LocalPoint
    var name: String = ""
    var category: String = "waypoint"
    var metadataJSON: String = "{}"

    var shortID: String { String(id.uuidString.prefix(8)) }
    var label: String { name.isEmpty ? "노드 \(shortID)" : name }
}

enum RoutingEdgeCategory: String, CaseIterable, Codable {
    case walkway, stairs, elevator
    var title: String {
        switch self { case .walkway: "통로"; case .stairs: "계단"; case .elevator: "엘리베이터" }
    }
}

struct RoutingEdge: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var from: UUID
    var to: UUID
    var accessible = true
    var category: RoutingEdgeCategory = .walkway
}

struct RoutingGraph: Equatable, Codable {
    var floors: [RoutingFloor] = []
    var nodes: [RoutingNode] = []
    var edges: [RoutingEdge] = []
    var layoutVersion = "layout-1"
    var hardSearchRadiusMeters = 25.0
    var imdfSourceName: String?

    func floor(_ id: UUID?) -> RoutingFloor? { floors.first { $0.id == id } }
    func node(_ id: UUID?) -> RoutingNode? { nodes.first { $0.id == id } }
    func edge(_ id: UUID?) -> RoutingEdge? { edges.first { $0.id == id } }
    func nodes(on floorID: UUID?) -> [RoutingNode] { nodes.filter { $0.floorID == floorID } }
    func connections(of id: UUID) -> [RoutingEdge] { edges.filter { $0.from == id || $0.to == id } }

    /// Extend only colliding prefixes so every canvas label distinguishes its node.
    var nodeDisplayIDs: [UUID: String] {
        var result: [UUID: String] = [:]
        for group in Dictionary(grouping: nodes, by: \.shortID).values {
            for node in group {
                let uuid = node.id.uuidString
                var length = 8
                while length < uuid.count && group.contains(where: {
                    $0.id != node.id && $0.id.uuidString.prefix(length) == uuid.prefix(length)
                }) { length += 1 }
                result[node.id] = String(uuid.prefix(length))
            }
        }
        return result
    }

    mutating func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.from == id || $0.to == id }
    }

    mutating func removeFloor(_ id: UUID) {
        for node in nodes(on: id) { removeNode(node.id) }
        floors.removeAll { $0.id == id }
    }

    /// Return an existing connection rather than creating duplicate undirected edges.
    mutating func connect(_ from: UUID, _ to: UUID) -> UUID? {
        guard from != to, let a = node(from), let b = node(to) else { return nil }
        if let existing = edges.first(where: {
            ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from)
        }) { return existing.id }
        let category: RoutingEdgeCategory
        if a.floorID == b.floorID { category = .walkway }
        else if a.category == "stairs", b.category == "stairs" { category = .stairs }
        else if a.category == "elevator", b.category == "elevator" { category = .elevator }
        else { return nil }
        let edge = RoutingEdge(from: from, to: to, accessible: category != .stairs, category: category)
        edges.append(edge)
        return edge.id
    }

    var isolatedNodes: [RoutingNode] {
        let connected = Set(edges.flatMap { [$0.from, $0.to] })
        return nodes.filter { !connected.contains($0.id) }
    }

    var componentCount: Int {
        var unseen = Set(nodes.map(\.id)), count = 0
        var adjacency: [UUID: [UUID]] = [:]
        for e in edges {
            adjacency[e.from, default: []].append(e.to)
            adjacency[e.to, default: []].append(e.from)
        }
        while let first = unseen.first {
            count += 1
            var stack = [first]
            unseen.remove(first)
            while let id = stack.popLast() {
                for neighbor in adjacency[id] ?? [] where unseen.remove(neighbor) != nil {
                    stack.append(neighbor)
                }
            }
        }
        return count
    }
}

enum RoutingTool: String, CaseIterable {
    case place, select, connect, calibrate
    var title: String {
        switch self {
        case .place: "노드 찍기"
        case .select: "선택·이동"
        case .connect: "노드 연결"
        case .calibrate: "좌표 기준점"
        }
    }
    var hint: String {
        switch self {
        case .place: "빈 곳 클릭으로 노드 추가 · 핀 드래그로 이동 · ⌥ Option + 핀 드래그로 연결"
        case .select: "핀·연결선 선택 · Delete로 삭제 · ⌥ Option + 핀 드래그로 연결"
        case .connect: "핀에서 다른 핀으로 드래그해 연결 · 층간 연결은 두 핀을 차례로 클릭"
        case .calibrate: "도면에서 기준점을 클릭하고 오른쪽에 실제 경도·위도 입력 (최소 3점)"
        }
    }
}

/// Transient pointer interaction; excluded from project files and undo snapshots.
struct RoutingConnectionDrag: Equatable {
    var from: UUID
    var floorID: UUID
    var pointer: LocalPoint
    var target: UUID?
}
