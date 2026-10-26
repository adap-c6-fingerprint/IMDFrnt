import Foundation

extension PropertyValue {
    /// Arbitrary JSON keeps imported languages, nested door objects and extension properties lossless.
    static func from(_ json: ProjectJSON) -> PropertyValue {
        switch json {
        case .null: return .null
        case .string(let s): return .string(s)
        case .bool(let b): return .boolean(b)
        case .number(let n):
            if let i = Int(json.text) { return .integer(i) }
            return .json(.number(n))
        case .array(let a) where a.allSatisfy({ $0.string != nil }): return .stringArray(a.compactMap(\.string))
        default: return .json(json)
        }
    }

    var projectJSON: ProjectJSON {
        switch self {
        case .null: return .null
        case .string(let s): return .string(s)
        case .integer(let i): return .number(Decimal(i))
        case .boolean(let b): return .bool(b)
        case .localized(let en, let ko):
            var labels: [String: ProjectJSON] = [:]
            if !en.isEmpty { labels["en"] = .string(en) }
            if !ko.isEmpty { labels["ko"] = .string(ko) }
            return labels.isEmpty ? .null : .object(labels)
        case .stringArray(let a): return .array(a.map(ProjectJSON.string))
        case .json(let value): return value
        }
    }
}

extension IMDFFeatureType {
    static let globalMetadataTypes: Set<IMDFFeatureType> = [.address, .building, .occupant, .relationship]
}

extension ProjectLevelInfo {
    /// Imported IMDF drawings already have an invertible WGS84 projection, without manual GPS pairs.
    var exportGeoreferencer: Georeferencer {
        if let footprintGeoAnchors { return Georeferencer(pairs: footprintGeoAnchors) }
        if let coordinates = imdfCoordinates, coordinates.isValid {
            let basis = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)]
            return Georeferencer(pairs: basis.map {
                AnchorPair(local: $0, geo: coordinates.geoPoint(for: $0), label: "IMDF projection")
            })
        }
        return Georeferencer(pairs: anchors.pairs)
    }
}

extension BuildingProject {
    /// Promote old floor-owned unlocated records once. Export UUIDs and each floor's serial references
    /// are resolved before removal; equal IDs with unequal contents are retained for explicit repair.
    mutating func migrateGlobalMetadata() {
        let types = IMDFFeatureType.globalMetadataTypes
        let needsMigration = levels.contains { level in
            level.editing.features.features.contains { types.contains($0.featureType) || $0.featureType == .manifest }
                || level.geoJSON.keys.contains { ["address.geojson", "building.geojson", "occupant.geojson"].contains($0) }
        }
        guard needsMigration else { return }
        var allSerials: [String: [UUID]] = [:]
        var localSerials: [[String: UUID]] = []
        for i in levels.indices {
            var serials: [String: UUID] = [:]
            for f in levels[i].editing.features.features {
                let id = f.featureType == .level ? levels[i].id : levels[i].editing.ids.id(for: f.id)
                serials[f.serialNumber] = id
                if !f.isInTrash { allSerials[f.serialNumber, default: []].append(id) }
            }
            localSerials.append(serials)
        }
        let unique = allSerials.compactMapValues { $0.count == 1 ? $0[0] : nil }
        let emptyDrawing = DrawingDocument(objects: [], canvasSize: .zero, sourceName: "metadata migration")
        for i in levels.indices {
            let mapping = unique.merging(localSerials[i]) { _, local in local }
            // Resolve references on spatial records too, so moving Address never invalidates their links.
            for f in levels[i].editing.features.features {
                levels[i].editing.features.update(f.id) { feature in
                    for field in PropertySchema.fields(for: f.featureType) {
                        if case .reference = field.type, case .string(let s) = feature.value(field.key), let id = mapping[s] {
                            feature.properties[field.key] = .string(id.uuidString.lowercased())
                        } else if field.type == .stringArray, case .stringArray(let values) = feature.value(field.key) {
                            feature.properties[field.key] = .stringArray(values.map { mapping[$0]?.uuidString.lowercased() ?? $0 })
                        }
                    }
                }
            }
            let metadata = levels[i].editing.features.features.filter { types.contains($0.featureType) || $0.featureType == .manifest }
            let exporter = GeoJSONExporter(document: emptyDrawing, segmentation: SegmentationStore(),
                                          georeferencer: levels[i].info.exportGeoreferencer)
            var ids = levels[i].editing.ids
            for f in metadata {
                let recoveryKey = "\(levels[i].id.uuidString)/\(f.id.uuidString)"
                if legacyMetadataGroups?[recoveryKey] == nil {
                    var copies = legacyMetadataGroups ?? [:]; copies[recoveryKey] = f; legacyMetadataGroups = copies
                }
                if f.featureType == .manifest {
                    var candidate: [String: ProjectJSON] = [:]
                    for (key, value) in f.properties where key != "id" && !value.isNull {
                        candidate[key] = value.projectJSON
                    }
                    if !candidate.isEmpty && !f.isInTrash {
                        var conflicts = false
                        for (key, value) in candidate {
                            if let old = manifest[key], old != .null, old != value { conflicts = true }
                            else { manifest[key] = value }
                        }
                        if conflicts {
                            var copy = ProjectJSON.object(candidate)
                            copy["imdfrnt_source_level"] = .string(levels[i].info.name)
                            if !(legacyManifests ?? []).contains(copy) {
                                legacyManifests = (legacyManifests ?? []) + [copy]
                                manifestConflictsResolved = false
                            }
                        }
                    }
                } else {
                    let object = exporter.serialize(f, ids: &ids, serialToUUID: mapping)
                    guard let data = try? JSONSerialization.data(withJSONObject: object), var value = try? ProjectJSON.parse(data) else {
                        // A failed conversion stays on its source floor; never delete data after a failed migration.
                        continue
                    }
                    // Retain the original local display point when GPS has not been configured yet.
                    if let point = f.displayPoint, !levels[i].info.exportGeoreferencer.isConfigured {
                        value["imdfrnt_local_display_point"] = .object([
                            "level_id": .string(levels[i].id.uuidString.lowercased()),
                            "x": .number(Decimal(point.x)), "y": .number(Decimal(point.y))])
                    }
                    let name = f.featureType.rawValue + ".geojson"
                    if f.isInTrash {
                        var trash = metadataTrash ?? [:]
                        if !(trash[name] ?? []).contains(value) { trash[name, default: []].append(value) }
                        metadataTrash = trash
                    } else if !(globalGeoJSON[name] ?? []).contains(value) {
                        globalGeoJSON[name, default: []].append(value)
                    }
                }
                levels[i].editing.features.remove(f.id)
                levels[i].editing.ownership.releaseAll(of: f.id)
                levels[i].editing.borrow.giveBackAll(of: f.id)
            }
            levels[i].editing.ids = ids
            for name in ["address.geojson", "building.geojson", "occupant.geojson"] {
                for feature in levels[i].geoJSON.removeValue(forKey: name) ?? [] where !(globalGeoJSON[name] ?? []).contains(feature) {
                    globalGeoJSON[name, default: []].append(feature)
                }
            }
        }
    }
}
