import Foundation

struct AmenityUnitChoice: Identifiable {
    let id: String
    let label: String
    let isCurrentLevel: Bool
    let distance: Double?

    /// Interior points have distance zero; holes and disconnected polygons retain their boundaries.
    static func distance(from point: LocalPoint?, to rings: [[LocalPoint]]) -> Double? {
        guard let point, point.x.isFinite, point.y.isFinite, !rings.isEmpty,
              rings.allSatisfy({ $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) else { return nil }
        if SubmissionGeometry.contains(point, rings: rings) { return 0 }
        return rings.flatMap { ring in
            ring.indices.map { LineSegment(start: ring[$0], end: ring[($0 + 1) % ring.count]).distance(to: point) }
        }.min()
    }
}

private struct AmenityUnitCandidate {
    let id: String
    let label: String
    let isCurrentLevel: Bool
    let rings: [[LocalPoint]]
}

@MainActor
extension AppEnvironment {
    /// Calculated when the picker opens, not for every Amenity card or canvas frame.
    func amenityUnitChoices(for amenity: FeatureGroup) -> [AmenityUnitChoice] {
        let point = amenity.drawnVertices?.first ?? document.flatMap {
            VertexExtractor.vertices(for: amenity, document: $0, segmentation: segmentation, kind: .point).first
        }
        return amenityUnitCandidates(currentLevelOnly: false).map { unit in
            let distance = unit.isCurrentLevel ? AmenityUnitChoice.distance(from: point, to: unit.rings) : nil
            return AmenityUnitChoice(id: unit.id, label: distance == 0 ? "포함 · " + unit.label : unit.label,
                                     isCurrentLevel: unit.isCurrentLevel, distance: distance)
        }.sorted {
            if $0.isCurrentLevel != $1.isCurrentLevel { return $0.isCurrentLevel }
            let a = $0.distance ?? .infinity, b = $1.distance ?? .infinity
            return a != b ? a < b : $0.label < $1.label
        }
    }

    private func amenityUnitCandidates(currentLevelOnly: Bool) -> [AmenityUnitCandidate] {
        let projection = activeLevel?.info.imdfCoordinates
        // Imported GeoJSON stays native; Footprint reprojection only happens at export.
        let nativeGeoreferencer = Georeferencer(pairs: anchors.pairs)
        func local(_ coordinate: [Double]) -> LocalPoint? {
            guard coordinate.count >= 2, coordinate[0].isFinite, coordinate[1].isFinite else { return nil }
            return projection?.localPoint(longitude: coordinate[0], latitude: coordinate[1])
                ?? nativeGeoreferencer.localPoint(for: GeoPoint(longitude: coordinate[0], latitude: coordinate[1]))
        }
        var choices: [String: AmenityUnitCandidate] = [:]
        var representedIDs = Set<UUID>()
        func add(_ id: UUID, feature: FeatureGroup, level: ProjectLevel?, rings: [[LocalPoint]]) {
            let current = level?.id == routingFloorID && routingFloorID != nil
            let name = Self.nameText(of: feature)
            let uuid = id.uuidString.lowercased()
            let label = [name, feature.serialNumber,
                         level?.info.name ?? "공통 Unit", uuid].filter { !$0.isEmpty }.joined(separator: " · ")
            choices[uuid] = AmenityUnitCandidate(id: uuid, label: label, isCurrentLevel: current, rings: rings)
        }
        func addOriginal(_ raw: ProjectJSON, id: UUID, level: ProjectLevel?) {
            var feature = FeatureGroup(id: id, featureType: .unit, serialNumber: "", memberIDs: [])
            feature.properties = (raw["properties"]?.object ?? [:]).mapValues(PropertyValue.from)
            var rings: [[LocalPoint]] = []
            if level?.id == routingFloorID {
                let rawRings = (try? FootprintGeometry.rings(raw["geometry"] ?? .null)) ?? []
                let converted = rawRings.map { $0.compactMap(local) }
                if zip(rawRings, converted).allSatisfy({ $0.count == $1.count }) { rings = converted }
            }
            add(id, feature: feature, level: level, rings: rings)
        }
        for level in buildingProject.levels {
            let current = level.id == routingFloorID
            if currentLevelOnly && !current { continue }
            let editing = current ? levelEditingState : level.editing
            let units = editing.features.features.filter { $0.featureType == .unit }
            // Originals represented by live edits or trash must not reappear as separate choices.
            let editedIDs = Set(units.map { editing.ids.peek($0.id) ?? $0.id })
            representedIDs.formUnion(editedIDs)
            for raw in level.geoJSON["unit.geojson"] ?? [] {
                guard let id = raw["id"]?.uuid, !editedIDs.contains(id) else { continue }
                addOriginal(raw, id: id, level: level)
            }
            for unit in units where !unit.isInTrash {
                var rings = unit.polygonRings
                if rings.isEmpty, current, let document {
                    let ring = VertexExtractor.vertices(for: unit, document: document, segmentation: segmentation,
                        kind: .polygon, borrowed: borrow.objects(borrowedBy: unit.id))
                    rings = [ring]
                }
                add(editing.ids.peek(unit.id) ?? unit.id, feature: unit, level: level, rings: rings)
            }
        }
        for raw in buildingProject.globalGeoJSON["unit.geojson"] ?? [] {
            guard let id = raw["id"]?.uuid, !representedIDs.contains(id), choices[id.uuidString.lowercased()] == nil else { continue }
            let level = buildingProject.levels.first { $0.id == raw["properties"]?["level_id"]?.uuid }
            if currentLevelOnly && level?.id != routingFloorID { continue }
            addOriginal(raw, id: id, level: level)
        }
        return Array(choices.values)
    }

    /// Only explicit, visible Amenity IDs are changed; geometry is prepared once for this floor.
    func connectAmenitiesToContainingUnits(_ amenityIDs: [UUID]) {
        guard routingFloorID != nil, !isProjectBusy, !amenityIDs.isEmpty else { return }
        let units = amenityUnitCandidates(currentLevelOnly: true)
        var updates: [UUID: [String]] = [:]
        var skipped = 0, unchanged = 0
        for id in Set(amenityIDs) {
            guard let amenity = features.feature(id), amenity.featureType == .amenity, !amenity.isInTrash else { continue }
            let point = amenity.drawnVertices?.first ?? document.flatMap {
                VertexExtractor.vertices(for: amenity, document: $0, segmentation: segmentation, kind: .point).first
            }
            let contained = units.filter { AmenityUnitChoice.distance(from: point, to: $0.rings) == 0 }.map(\.id).sorted()
            guard !contained.isEmpty else { skipped += 1; continue }
            let existing = amenity.value("unit_ids")
            // Malformed existing values need manual repair, not a lossy automatic rewrite.
            if existing != .null {
                guard case .array(let values) = existing.projectJSON, values.allSatisfy({ $0.string != nil }) else {
                    skipped += 1; continue
                }
            }
            var ids = existing.projectJSON.array.compactMap(\.string)
            let known = Set(ids.map { $0.lowercased() })
            let additions = contained.filter { !known.contains($0) }
            guard !additions.isEmpty else { unchanged += 1; continue }
            ids.append(contentsOf: additions)
            updates[id] = ids
        }
        if !updates.isEmpty {
            perform("Amenity 포함 Unit 일괄 연결") {
                for (id, ids) in updates { features.update(id) { $0.properties["unit_ids"] = .stringArray(ids) } }
            }
        }
        notify("포함 Unit 연결: \(updates.count)개 추가 · \(unchanged)개 이미 연결 · \(skipped)개 건너뜀(포함 Unit 없음·좌표/기존 값 확인 필요)")
    }

    func setAmenityUnit(_ id: String, selected: Bool, for featureID: UUID) {
        guard let feature = features.feature(featureID), feature.featureType == .amenity, !feature.isInTrash else { return }
        var values = feature.value("unit_ids").projectJSON.array.compactMap(\.string)
        if selected {
            guard !values.contains(where: { $0.lowercased() == id.lowercased() }) else { return }
            values.append(id)
        } else { values.removeAll { $0.lowercased() == id.lowercased() } }
        perform("Amenity Unit 연결 변경") {
            features.update(featureID) { $0.properties["unit_ids"] = values.isEmpty ? .null : .stringArray(values) }
        }
    }
}
