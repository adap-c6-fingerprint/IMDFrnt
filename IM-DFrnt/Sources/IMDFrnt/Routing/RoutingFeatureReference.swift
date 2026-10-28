import Foundation

enum RoutingFeatureKind: String, Codable, CaseIterable {
    case unit, fixture
    var title: String { self == .unit ? "Unit" : "Fixture" }
    var imdfType: IMDFFeatureType { self == .unit ? .unit : .fixture }
    var layer: RoutingMapLayer { self == .unit ? .unit : .fixture }
}

/// 원본 GeoJSON은 수정하지 않는다. 직접 그린 면은 내부 ID를 저장하고 내보낼 때 실제 IMDF UUID로 바꾼다.
struct RoutingFeatureReference: Hashable, Codable, Identifiable {
    enum Source: String, Codable { case authored, imported }
    var kind: RoutingFeatureKind
    var featureID: UUID
    var source: Source
    var id: String { "\(source.rawValue):\(kind.rawValue):\(featureID.uuidString)" }

    func authored(in level: ProjectLevel) -> FeatureGroup? {
        level.editing.features.features.first {
            $0.featureType == kind.imdfType && (source == .authored ? $0.id == featureID : (level.editing.ids.peek($0.id) ?? $0.id) == featureID)
        }
    }

    /// 편집본이 원본을 덮어쓰는 경우도 같은 장소로 취급해 노드를 중복 배정하지 않는다.
    func identity(in level: ProjectLevel, ids: IDAssigner? = nil) -> String {
        let value = authored(in: level).map { (ids ?? level.editing.ids).peek($0.id) ?? $0.id } ?? featureID
        return "\(kind.rawValue):\(value.uuidString.lowercased())"
    }

    func imported(in project: BuildingProject, levelID: UUID) -> ProjectJSON? {
        guard source == .imported, let level = project.levels.first(where: { $0.id == levelID }) else { return nil }
        let name = kind.rawValue + ".geojson"
        if let local = level.geoJSON[name]?.first(where: { $0["id"]?.uuid == featureID }) { return local }
        let shared = (project.globalGeoJSON[name] ?? []).filter { $0["id"]?.uuid == featureID }
        if let direct = shared.first(where: { BuildingProject.levelReferences($0).contains(levelID) }) { return direct }
        guard !shared.isEmpty else { return nil }
        // Only indirect shared references need the Unit index; ordinary lookups stay cheap.
        let unitLevels = project.unitLevelReferences
        return shared.first {
            BuildingProject.levelReferences($0, unitLevels: unitLevels).contains(levelID)
        }
    }

    func isAvailable(in project: BuildingProject, levelID: UUID) -> Bool {
        guard let level = project.levels.first(where: { $0.id == levelID }) else { return false }
        if let feature = authored(in: level) { return !feature.isInTrash }
        return imported(in: project, levelID: levelID) != nil
    }

    func label(in project: BuildingProject, levelID: UUID) -> String {
        let level = project.levels.first { $0.id == levelID }
        let feature = level.flatMap { authored(in: $0) }
        let name = feature?.value("name").projectJSON ?? imported(in: project, levelID: levelID)?["properties"]?["name"]
        let text = name?.string ?? name?["ko"]?.string ?? name?["en"]?.string ?? feature?.serialNumber ?? ""
        return "\(kind.title) \(text) · \(featureID.uuidString.prefix(8))"
    }
}

enum RoutingFeatureLinks {
    /// 한 층만 복사할 때 연결된 공통 도형도 그 층의 사본으로 가져와 ID 재발급에 참여시킨다.
    static func preparingImport(_ source: ProjectLevel, metadata: BuildingProject?) -> ProjectLevel {
        guard let metadata else { return source }
        var result = source
        for ref in source.nodes.flatMap({ $0.featureLinks ?? [] }) where ref.source == .imported {
            let name = ref.kind.rawValue + ".geojson"
            guard result.geoJSON[name]?.contains(where: { $0["id"]?.uuid == ref.featureID }) != true,
                  var record = ref.imported(in: metadata, levelID: source.id) else { continue }
            if var props = record["properties"] {
                if props["level_ids"] != nil { props["level_ids"] = .array([.string(source.id.uuidString.lowercased())]) }
                if props["level_id"] != nil { props["level_id"] = .string(source.id.uuidString.lowercased()) }
                record["properties"] = props
            }
            result.geoJSON[name, default: []].append(record)
        }
        return result
    }

    /// 같은 장소(공통 Fixture 포함)는 프로젝트 전체에서 노드 하나만 대표한다.
    static func validateUnique(in project: BuildingProject) throws {
        var seen = Set<String>()
        for level in project.levels {
            for node in level.nodes {
                for ref in node.featureLinks ?? [] {
                    guard seen.insert(ref.identity(in: level)).inserted else {
                        throw IMDFImporter.Failure(message: "\(ref.kind.title) · \(ref.featureID.uuidString.prefix(8)): 장소 하나에는 노드 하나만 연결할 수 있습니다.")
                    }
                }
            }
        }
    }

    static func owner(of ref: RoutingFeatureReference, on levelID: UUID, in project: BuildingProject) -> RoutingNode? {
        guard let target = project.levels.first(where: { $0.id == levelID }) else { return nil }
        let identity = ref.identity(in: target)
        return project.levels.lazy.compactMap { level in
            level.nodes.first { node in (node.featureLinks ?? []).contains { $0.identity(in: level) == identity } }
        }.first
    }
}
