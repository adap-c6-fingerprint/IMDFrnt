import Foundation

/// A floor copied into a project owns new identities only where the existing project already uses them.
enum LevelImportIdentity {
    struct Prepared {
        var level: ProjectLevel
        var metadata: BuildingProject?
    }

    static func prepare(_ source: ProjectLevel, targetID: UUID, project: BuildingProject,
                        metadata: BuildingProject?) throws -> Prepared {
        let others = project.levels.filter { $0.id != targetID }
        let features = others.flatMap { $0.editing.features.features } + (project.sharedFootprint?.features ?? [])
        let internalIDs = Set(features.map(\.id))
        var occupied = Set(project.globalGeoJSON.values.flatMap { $0 }.compactMap { $0["id"]?.uuid })
        occupied.formUnion(project.sharedFootprint?.originals.values.compactMap { $0["id"]?.uuid } ?? [])
        occupied.formUnion(project.levels.flatMap { $0.editing.ids.retired })
        for level in others {
            occupied.insert(level.id)
            occupied.formUnion(level.geoJSON.values.flatMap { $0 }.compactMap { $0["id"]?.uuid })
            occupied.formUnion(level.editing.ids.assigned.values)
            occupied.formUnion(level.editing.ids.retired)
            occupied.formUnion(level.editing.features.features.map { level.editing.ids.peek($0.id) ?? $0.id })
        }
        occupied.formUnion(internalIDs)
        var reserved = occupied.union(source.editing.features.features.map(\.id))
        reserved.formUnion(source.editing.ids.assigned.values)
        reserved.formUnion(source.editing.ids.retired)
        reserved.formUnion(source.geoJSON.values.flatMap { $0 }.compactMap { $0["id"]?.uuid })
        reserved.formUnion(metadata?.globalGeoJSON.values.flatMap { $0 }.compactMap { $0["id"]?.uuid } ?? [])
        reserved.insert(targetID)
        func fresh() -> UUID {
            var id = UUID()
            while reserved.contains(id) { id = UUID() }
            reserved.insert(id)
            return id
        }
        var internals: [UUID: UUID] = [:]
        var exports: [UUID: UUID] = [source.id: targetID]
        for feature in source.editing.features.features {
            let exported = feature.featureType == .level ? source.id : source.editing.ids.peek(feature.id) ?? feature.id
            if occupied.contains(feature.id) || (feature.featureType != .level && occupied.contains(exported)) {
                let id = fresh()
                internals[feature.id] = id
                if feature.featureType != .level { exports[exported] = id }
            }
        }
        for record in source.geoJSON.values.flatMap({ $0 }) {
            guard let id = record["id"]?.uuid, id != source.id, occupied.contains(id) else { continue }
            if exports[id] == nil { exports[id] = fresh() }
        }
        // Cloned anchors require cloned Occupant/Relationship records, not changes to the existing records.
        var common = metadata
        for name in ["occupant.geojson", "relationship.geojson"] {
            for record in metadata?.globalGeoJSON[name] ?? [] {
                if references(record, ids: exports) != record, let id = record["id"]?.uuid, occupied.contains(id) {
                    exports[id] = fresh()
                }
            }
        }
        var level = source
        let copies = try source.editing.features.features.map { feature -> FeatureGroup in
            var copy = feature
            if let id = internals[feature.id] {
                var value = try ProjectJSON.parse(JSONEncoder().encode(feature))
                value["id"] = .string(id.uuidString.lowercased())
                copy = try JSONDecoder().decode(FeatureGroup.self, from: value.data())
            }
            let original = ProjectJSON.object(feature.properties.mapValues(\.projectJSON))
            for (key, value) in properties(original, ids: exports).object where original[key] != value {
                copy.properties[key] = PropertyValue.from(value)
            }
            return copy
        }
        level.editing.features.replaceImportedFeatures(copies)
        level.editing.ownership.remapImportedFeatures(internals)
        level.editing.borrow.remapImportedFeatures(internals)
        level.editing.ids.remapImportedFeatures(internals, exports: exports)
        for feature in source.editing.features.features where feature.featureType != .level {
            if let id = internals[feature.id] {
                level.editing.ids.adopt(id, id: exports[source.editing.ids.peek(feature.id) ?? feature.id] ?? id)
            }
        }
        level.geoJSON = level.geoJSON.mapValues { $0.map { record($0, ids: exports) } }
        for i in level.nodes.indices {
            level.nodes[i].featureLinks = level.nodes[i].featureLinks?.map { ref in
                var copy = ref
                copy.featureID = (ref.source == .authored ? internals[ref.featureID] : exports[ref.featureID]) ?? ref.featureID
                return copy
            }
            if let text = level.nodes[i].sourceOpeningID, let id = UUID(uuidString: text), let replacement = exports[id] {
                level.nodes[i].sourceOpeningID = replacement.uuidString.lowercased()
            }
        }
        if common != nil {
            common!.globalGeoJSON = common!.globalGeoJSON.mapValues { $0.map { record($0, ids: exports) } }
        }
        return Prepared(level: level, metadata: common)
    }

    static func properties(_ value: ProjectJSON, ids: [UUID: UUID]) -> ProjectJSON {
        var result = value
        func reference(_ value: ProjectJSON) -> ProjectJSON {
            if let id = value.uuid, let replacement = ids[id] { return .string(replacement.uuidString.lowercased()) }
            return value
        }
        for key in ["level_id", "unit_id", "anchor_id", "address_id"] {
            if let value = result[key] { result[key] = reference(value) }
        }
        for key in ["level_ids", "unit_ids", "building_ids", "parents"] {
            if let value = result[key], value.isArray { result[key] = .array(value.array.map(reference)) }
        }
        for key in ["origin", "destination"] {
            if var endpoint = result[key], let id = endpoint["id"] { endpoint["id"] = reference(id); result[key] = endpoint }
        }
        if let via = result["intermediary"], via.isArray {
            result["intermediary"] = .array(via.array.map { endpoint in
                var endpoint = endpoint
                if let id = endpoint["id"] { endpoint["id"] = reference(id) }
                return endpoint
            })
        }
        return result
    }

    private static func references(_ value: ProjectJSON, ids: [UUID: UUID]) -> ProjectJSON {
        var result = value
        if let props = value["properties"] { result["properties"] = properties(props, ids: ids) }
        return result
    }

    private static func record(_ value: ProjectJSON, ids: [UUID: UUID]) -> ProjectJSON {
        var result = references(value, ids: ids)
        if let id = value["id"]?.uuid, let replacement = ids[id] { result["id"] = .string(replacement.uuidString.lowercased()) }
        return result
    }
}
