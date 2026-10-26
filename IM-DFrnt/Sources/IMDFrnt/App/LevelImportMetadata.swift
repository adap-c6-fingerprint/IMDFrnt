import Foundation

/// Select before conflict checking: another floor's unrelated metadata must not block this import.
enum LevelImportMetadata {
    static func records(in project: BuildingProject, source: ProjectLevel, targetID: UUID,
                        includingVenue: Bool, includingFootprint: Bool) -> [String: [ProjectJSON]] {
        // Old single-floor documents can contain unlinked common records. Preserve that recovery path.
        guard project.levels.count > 1 else { return project.globalGeoJSON }
        var selected = project.globalGeoJSON
        var importedIDs = Set(source.geoJSON.values.flatMap { $0 }.compactMap { $0["id"]?.string?.lowercased() })
        for feature in source.editing.features.features {
            importedIDs.insert((feature.featureType == .level ? targetID : source.editing.ids.peek(feature.id) ?? feature.id).uuidString.lowercased())
        }
        selected["occupant.geojson"] = (selected["occupant.geojson"] ?? []).filter {
            importedIDs.contains($0["properties"]?["anchor_id"]?.string?.lowercased() ?? "")
        }
        selected["relationship.geojson"] = (selected["relationship.geojson"] ?? []).filter { record in
            let props = record["properties"]
            let refs = [props?["origin"], props?["destination"]].compactMap { $0 }
                + (props?["intermediary"]?.array ?? [])
            return refs.allSatisfy { $0 == .null || importedIDs.contains($0["id"]?.string?.lowercased() ?? "") }
        }

        let authored = source.editing.features.features
        var roots = source.geoJSON.values.flatMap { $0 }.compactMap { $0["properties"] }
            + authored.map { .object($0.properties.mapValues(\.projectJSON)) }
        for name in ["occupant.geojson", "relationship.geojson"] {
            roots += (selected[name] ?? []).compactMap { $0["properties"] }
        }
        if includingVenue { roots += (project.globalGeoJSON["venue.geojson"] ?? []).compactMap { $0["properties"] } }
        var footprintProperties: [ProjectJSON] = []
        if includingFootprint, let shared = project.sharedFootprint {
            // The shared geometry is copied as a whole by mergeLevelMetadata; keep all of its dependencies.
            // Use effective properties, not stale references in originals overridden by current edits.
            footprintProperties = shared.features.map { feature in
                var props = shared.originals[feature.id.uuidString]?["properties"] ?? .object([:])
                for (key, value) in feature.properties { props[key] = value.projectJSON }
                return props
            }
            let known = Set(shared.originals.values.compactMap { $0["id"]?.uuid })
            footprintProperties += (project.globalGeoJSON["footprint.geojson"] ?? []).filter {
                $0["id"]?.uuid.map { !known.contains($0) } ?? true
            }.compactMap { $0["properties"] }
            roots += footprintProperties
        }
        func references(_ props: ProjectJSON) -> Set<UUID> {
            var ids = Set((props["building_ids"]?.array ?? []).compactMap(\.uuid))
            if let id = props["address_id"]?.uuid { ids.insert(id) }
            for endpoint in [props["origin"], props["destination"]].compactMap({ $0 }) + (props["intermediary"]?.array ?? []) {
                if let id = endpoint["id"]?.uuid { ids.insert(id) }
            }
            return ids
        }
        var reachable = Set(roots.flatMap { references($0) })
        let buildings = project.globalGeoJSON["building.geojson"] ?? []
        let addresses = project.globalGeoJSON["address.geojson"] ?? []
        func missing(_ value: ProjectJSON?) -> Bool { value == nil || value == .null }
        func emptyBuildings(_ value: ProjectJSON?) -> Bool {
            missing(value) || (value?.isArray == true && value?.array.isEmpty == true)
        }
        // Match the existing export defaults for an authored feature / copied Footprint with one Building.
        let implicitBuilding = authored.contains { emptyBuildings($0.value("building_ids").projectJSON) }
            || footprintProperties.contains { emptyBuildings($0["building_ids"]) }
        if implicitBuilding, buildings.count == 1, let id = buildings[0]["id"]?.uuid { reachable.insert(id) }
        // A reachable Building can in turn reference an Address. Walk to a fixed point without UUID-keyed
        // dictionary construction, so duplicate/colliding incoming records still reach the merge validator.
        let common = buildings + addresses
        var previous: Set<UUID>
        repeat {
            previous = reachable
            for record in common where record["id"]?.uuid.map({ reachable.contains($0) }) == true {
                reachable.formUnion(references(record["properties"] ?? .object([:])))
            }
        } while previous != reachable
        let implicitAddress = authored.contains {
            [.venue, .building, .level].contains($0.featureType) && $0.value("address_id").isNull
        } || buildings.contains {
            $0["id"]?.uuid.map { reachable.contains($0) } == true && missing($0["properties"]?["address_id"])
        }
        if implicitAddress, addresses.count == 1, let id = addresses[0]["id"]?.uuid { reachable.insert(id) }
        for name in ["address.geojson", "building.geojson"] {
            selected[name] = (project.globalGeoJSON[name] ?? []).filter {
                $0["id"]?.uuid.map { reachable.contains($0) } == true
            }
        }
        return selected
    }
}
