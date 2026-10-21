import Foundation

/// Keeps arbitrary IMDF properties, foreign members, nulls and nested coordinates.
/// Decimal avoids rounding integer metadata through a Double during import/save.
enum ProjectJSON: Equatable, Codable, Sendable {
    case object([String: ProjectJSON]), array([ProjectJSON]), string(String), number(Decimal), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode([ProjectJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: ProjectJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(_ key: String) -> ProjectJSON? {
        get { if case .object(let v) = self { return v[key] }; return nil }
        set {
            guard case .object(var v) = self else { return }
            v[key] = newValue; self = .object(v)
        }
    }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var array: [ProjectJSON] { if case .array(let v) = self { return v }; return [] }
    var object: [String: ProjectJSON] { if case .object(let v) = self { return v }; return [:] }
    var featureID: String { self["id"]?.string ?? text }
    var uuid: UUID? { string.flatMap(UUID.init(uuidString:)) }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    var text: String { (try? String(decoding: data(), as: UTF8.self)) ?? "{}" }
    static func parse(_ data: Data) throws -> ProjectJSON { try JSONDecoder().decode(Self.self, from: data) }
}

/// Existing SVG tagging state is retained per Level while DraftShape is added in #21.
struct LevelEditingState: Equatable, Codable {
    var features = FeatureStore()
    var ownership = OwnershipRegistry()
    var segmentation = SegmentationStore()
    var auxiliary = AuxiliaryStore()
    var openingGate = OpeningGateStore()
    var borrow = BorrowRegistry()
    var doorClosures = DoorClosureStore()
    var serials = SerialNumberAllocator()
    var ids = IDAssigner()
}

struct ProjectLevel: Identifiable, Equatable, Codable {
    var info: ProjectLevelInfo
    var id: UUID { info.id }
    var editing = LevelEditingState()
    /// Original geographic Features; SVG is a derived display for IMDF input.
    var geoJSON: [String: [ProjectJSON]] = [:]
    var nodes: [RoutingNode] = []
    var edges: [RoutingEdge] = []
    /// Optional additions keep existing v5 projects readable without migration.
    var svgPresentation: DrawingLayerPresentation?
    var referenceDrawing: LevelReferenceDrawing?
    /// 이 층의 feature type별 작업 상태(신기능 12항). 키는 type 이름이다. 없으면 Todo다.
    var workStatus: [String: LayerWorkStatus]?
    /// 이 층에서 type별로 사용자가 마지막으로 feature를 고친 시각. 최근 작업 순 정렬에 쓴다.
    var lastEdited: [String: Date]?
}

/// Common building and Levels are authoritative. RoutingGraph is a compatibility
/// view for the existing node editor/exporter, never a second persisted owner.
struct BuildingProject: Equatable, Codable {
    var levels: [ProjectLevel] = []
    var globalGeoJSON: [String: [ProjectJSON]] = [:]
    /// Collection headers exclude features. Shared/multi-Level Features stay global.
    var collectionHeaders: [String: ProjectJSON] = [:]
    var manifest: ProjectJSON = .object([:])
    var extraFiles: [String: ProjectJSON] = [:]
    var crossLevelEdges: [RoutingEdge] = []
    var layoutVersion = "layout-1"
    var hardSearchRadiusMeters = 25.0
    var imdfSourceName: String?
    var footprintPresentation: DrawingLayerPresentation?
    /// 층에 귀속되지 않는 정보 type(address·building·manifest·occupant)의 작업 상태(신기능 12항).
    var metadataWorkStatus: [String: LayerWorkStatus]?
    /// 상단바의 층 표시 순서. 화면 순서일 뿐이고 층 번호(ordinal)는 바꾸지 않는다. 없으면 층 번호 순이다.
    var levelDisplayOrder: [UUID]?
    /// 좌측 Feature Type 목록의 사용자 지정 순서(type 이름). 없으면 기본 순서다.
    var featureTypeOrder: [String]?

    func validate() throws {
        guard Set(levels.map(\.id)).count == levels.count,
              Set(levels.map { $0.info.ordinal }).count == levels.count else {
            throw IMDFImporter.Failure(message: "프로젝트의 층 ID 또는 층 번호가 중복됩니다.")
        }
        let nodes = levels.flatMap(\.nodes)
        guard Set(nodes.map(\.id)).count == nodes.count,
              levels.allSatisfy({ level in level.nodes.allSatisfy { $0.floorID == level.id } }) else {
            throw IMDFImporter.Failure(message: "프로젝트의 노드 ID 또는 소속 층이 올바르지 않습니다.")
        }
        let nodeIDs = Set(nodes.map(\.id)), edges = levels.flatMap(\.edges) + crossLevelEdges
        guard Set(edges.map(\.id)).count == edges.count,
              edges.allSatisfy({ nodeIDs.contains($0.from) && nodeIDs.contains($0.to) }) else {
            throw IMDFImporter.Failure(message: "프로젝트에 중복되거나 노드가 없는 연결이 있습니다.")
        }
    }

    var routingGraph: RoutingGraph {
        RoutingGraph(floors: levels.map(\.info), nodes: levels.flatMap(\.nodes),
                     edges: levels.flatMap(\.edges) + crossLevelEdges,
                     layoutVersion: layoutVersion, hardSearchRadiusMeters: hardSearchRadiusMeters,
                     imdfSourceName: imdfSourceName)
    }

    mutating func applyRouting(_ graph: RoutingGraph) {
        let previous = Dictionary(uniqueKeysWithValues: levels.map { ($0.id, $0) })
        levels = graph.floors.map { info in
            var level = previous[info.id] ?? ProjectLevel(info: info)
            level.info = info
            level.nodes = graph.nodes(on: info.id)
            let nodeIDs = Set(level.nodes.map(\.id))
            level.edges = graph.edges.filter { nodeIDs.contains($0.from) && nodeIDs.contains($0.to) }
            return level
        }
        let nodeFloors = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.floorID) })
        crossLevelEdges = graph.edges.filter {
            nodeFloors[$0.from] != nil && nodeFloors[$0.to] != nil && nodeFloors[$0.from] != nodeFloors[$0.to]
        }
        layoutVersion = graph.layoutVersion
        hardSearchRadiusMeters = graph.hardSearchRadiusMeters
        imdfSourceName = graph.imdfSourceName
    }

    /// Reconstruct type-based files without changing original IDs or properties.
    func imdfFiles() -> [String: ProjectJSON] {
        var files = extraFiles
        files["manifest.json"] = manifest
        let types = Set(collectionHeaders.keys).union(globalGeoJSON.keys).union(levels.flatMap { $0.geoJSON.keys })
        for type in types {
            var header = collectionHeaders[type] ?? .object(["type": .string("FeatureCollection")])
            header["features"] = .array((globalGeoJSON[type] ?? []) + levels.flatMap { $0.geoJSON[type] ?? [] })
            files[type] = header
        }
        return files
    }

    /// IMDF SVG is a display cache. Rebuild it from saved geographic Features,
    /// retaining the projection so existing routing node coordinates stay stable.
    mutating func refreshIMDFDisplays() throws {
        var unitLevels: [String: UUID] = [:]
        for level in levels {
            for unit in level.geoJSON["unit.geojson"] ?? [] {
                if let id = unit["id"]?.string { unitLevels[id.lowercased()] = level.id }
            }
        }
        for i in levels.indices {
            guard let coordinates = levels[i].info.imdfCoordinates, !levels[i].geoJSON.isEmpty else { continue }
            let doc = try SVGParser.parse(data: Data(levels[i].info.svg.utf8), sourceName: levels[i].info.sourceName)
            var elements: [String] = []
            for type in ["level", "unit", "section", "fixture", "detail", "opening", "amenity"] {
                let name = type + ".geojson"
                let shared = (globalGeoJSON[name] ?? []).filter { Self.levelReferences($0, unitLevels: unitLevels).contains(levels[i].id) }
                for feature in (levels[i].geoJSON[name] ?? []) + shared {
                    guard let geometry = feature["geometry"], geometry != .null else { continue }
                    guard let object = try JSONSerialization.jsonObject(with: geometry.data()) as? [String: Any] else {
                        throw IMDFImporter.Failure(message: "\(name): geometry 형식이 올바르지 않습니다.")
                    }
                    elements.append(try IMDFImporter.svgElement(object, type: type,
                        category: feature["properties"]?["category"]?.string ?? "", coordinates: coordinates))
                }
            }
            guard !elements.isEmpty else { continue }
            func number(_ value: Double) -> String { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value) }
            levels[i].info.svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(doc.canvasSize.width))\" height=\"\(number(doc.canvasSize.height))\">\n"
                + elements.joined(separator: "\n") + "\n</svg>"
        }
    }

    /// Derived SVG and its formatting are not a second geometry authority.
    var semanticContents: BuildingProject {
        var result = self
        for i in result.levels.indices where result.levels[i].info.imdfCoordinates != nil && !result.levels[i].geoJSON.isEmpty {
            result.levels[i].info.svg = ""
        }
        return result
    }

    static func importing(_ imported: ImportedIMDF) throws -> BuildingProject {
        var project = BuildingProject()
        project.imdfSourceName = imported.sourceName
        project.layoutVersion = imported.layoutVersion
        project.levels = imported.floors.map {
            ProjectLevel(info: ProjectLevelInfo(id: $0.id, name: $0.name, ordinal: $0.ordinal,
                sourceName: imported.sourceName, svg: $0.svg, imdfCoordinates: imported.coordinates))
        }
        var unitLevels: [String: UUID] = [:]
        for feature in imported.files["unit.geojson"]?["features"]?.array ?? [] {
            guard let id = feature["id"]?.string, let level = feature["properties"]?["level_id"]?.uuid else { continue }
            guard unitLevels[id.lowercased()] == nil else {
                throw IMDFImporter.Failure(message: "unit.geojson의 Feature ID가 중복됩니다.")
            }
            unitLevels[id.lowercased()] = level
        }
        for (name, value) in imported.files {
            if name == "manifest.json" { project.manifest = value; continue }
            guard name.hasSuffix(".geojson"), value["type"]?.string == "FeatureCollection" else {
                project.extraFiles[name] = value; continue
            }
            var header = value; header["features"] = nil
            project.collectionHeaders[name] = header
            for feature in value["features"]?.array ?? [] {
                let refs: Set<UUID> = name == "level.geojson" ? Set([feature["id"]?.uuid].compactMap { $0 }) : levelReferences(feature, unitLevels: unitLevels)
                if refs.count == 1, let id = refs.first, let index = project.levels.firstIndex(where: { $0.id == id }) {
                    project.levels[index].geoJSON[name, default: []].append(feature)
                } else {
                    project.globalGeoJSON[name, default: []].append(feature)
                }
            }
        }
        for i in project.levels.indices {
            if let feature = project.levels[i].geoJSON["level.geojson"]?.first,
               let short = feature["properties"]?["short_name"] {
                project.levels[i].info.shortName = short["ko"]?.string ?? short["en"]?.string ?? short.string ?? ""
            }
        }
        let buildings = project.globalGeoJSON["building.geojson"] ?? []
        guard buildings.count <= 1 else { throw IMDFImporter.Failure(message: "한 프로젝트에는 건물 하나만 불러올 수 있습니다.") }
        return project
    }

    static func levelReferences(_ feature: ProjectJSON, unitLevels: [String: UUID] = [:]) -> Set<UUID> {
        if feature["feature_type"]?.string == "level", let id = feature["id"]?.uuid { return [id] }
        let props = feature["properties"]
        var ids = Set(props?["level_ids"]?.array.compactMap(\.uuid) ?? [])
        if let id = props?["level_id"]?.uuid { ids.insert(id) }
        for unit in (props?["unit_ids"]?.array ?? []) + [props?["unit_id"] ?? .null] {
            if let name = unit.string, let level = unitLevels[name.lowercased()] { ids.insert(level) }
        }
        return ids
    }
}
