import Foundation

/// Every metadata entry point edits project-wide records, independent of the active floor.
@MainActor
extension AppEnvironment {
    func openMetadataEditor(_ type: IMDFFeatureType) {
        guard type.isMetadataOnly else { return }
        if let layer = layers.layer(for: type) { perform("정보 레이어 닫기") { layers.close(layer.id) } }
        metadataEditorType = type
    }

    var manifestEditorID: UUID { projectID }

    func metadataFeatures(_ type: IMDFFeatureType, trashed: Bool = false) -> [FeatureGroup] {
        if type == .manifest {
            var f = FeatureGroup(id: manifestEditorID, featureType: .manifest, serialNumber: "manifest", memberIDs: [])
            f.properties = buildingProject.manifest.object.mapValues(PropertyValue.from)
            return trashed ? [] : [f]
        }
        let values = trashed ? buildingProject.metadataTrash?[type.rawValue + ".geojson"] ?? [] : globalFeatures(type.rawValue)
        return values.compactMap { value in
            guard let id = value["id"]?.uuid else { return nil }
            var f = FeatureGroup(id: id, featureType: type,
                                 serialNumber: "\(type.rawValue)-\(id.uuidString.prefix(8).lowercased())", memberIDs: [])
            f.properties = (value["properties"]?.object ?? [:]).mapValues(PropertyValue.from)
            f.isInTrash = trashed
            return f
        }
    }

    func metadataAllowsMore(_ type: IMDFFeatureType) -> Bool { type != .manifest }

    @discardableResult
    func addMetadataFeature(_ type: IMDFFeatureType) -> FeatureGroupID? {
        guard type.isMetadataOnly, type != .manifest else { return nil }
        let id = UUID()
        let properties = Dictionary(uniqueKeysWithValues: PropertySchema.fields(for: type)
            .filter { $0.key != "id" }.map { ($0.key, ProjectJSON.null) })
        let feature: ProjectJSON = .object(["type": .string("Feature"), "feature_type": .string(type.rawValue),
            "id": .string(id.uuidString.lowercased()), "geometry": .null, "properties": .object(properties)])
        perform("\(type.rawValue) 추가") { buildingProject.globalGeoJSON[type.rawValue + ".geojson", default: []].append(feature) }
        hasCreatedProject = true
        return id
    }

    func isGlobalMetadata(_ id: UUID) -> Bool {
        id == manifestEditorID || IMDFFeatureType.globalMetadataTypes.contains { type in
            globalFeatures(type.rawValue).contains { $0["id"]?.uuid == id }
        }
    }

    @discardableResult
    func updateGlobalProperty(_ key: String, value: PropertyValue, in id: UUID) -> Bool {
        guard isGlobalMetadata(id) else { return false }
        perform("\(key) 입력", coalescingKey: "metadata:\(id):\(key)") {
            if id == manifestEditorID { buildingProject.manifest[key] = value.projectJSON }
            else {
                for type in IMDFFeatureType.globalMetadataTypes {
                    let name = type.rawValue + ".geojson"
                    guard let index = buildingProject.globalGeoJSON[name]?.firstIndex(where: { $0["id"]?.uuid == id }) else { continue }
                    var properties = buildingProject.globalGeoJSON[name]![index]["properties"] ?? .object([:])
                    properties[key] = value.projectJSON
                    buildingProject.globalGeoJSON[name]![index]["properties"] = properties
                }
            }
        }
        hasCreatedProject = true
        return true
    }

    @discardableResult
    func moveGlobalMetadata(_ id: UUID, restoring: Bool = false) -> Bool {
        for type in IMDFFeatureType.globalMetadataTypes {
            let name = type.rawValue + ".geojson"
            let source = restoring ? buildingProject.metadataTrash?[name] : buildingProject.globalGeoJSON[name]
            guard let feature = source?.first(where: { $0["id"]?.uuid == id }) else { continue }
            perform(restoring ? "정보 복원" : "정보 휴지통") {
                var trash = buildingProject.metadataTrash ?? [:]
                if restoring {
                    trash[name]?.removeAll { $0["id"]?.uuid == id }
                    buildingProject.globalGeoJSON[name, default: []].append(feature)
                } else {
                    buildingProject.globalGeoJSON[name]?.removeAll { $0["id"]?.uuid == id }
                    trash[name, default: []].append(feature)
                }
                buildingProject.metadataTrash = trash
            }
            return true
        }
        return false
    }

    /// Values are UUIDs, labels include floor/name; unit-001 is not a globally unique identifier.
    func referenceChoices(_ type: IMDFFeatureType) -> [(id: String, label: String)] {
        if let cached = referenceChoiceCache[type] { return cached }
        let project = projectContents
        var choices: [String: String] = [:]
        let key = type.rawValue + ".geojson"
        let originals = (project.globalGeoJSON[key] ?? []) + project.levels.flatMap { $0.geoJSON[key] ?? [] }
        for raw in originals {
            guard let id = raw["id"]?.string else { continue }
            let labels = raw["properties"]?["name"]?.object ?? [:]
            let name = labels["ko"]?.string ?? labels["en"]?.string ?? labels.values.compactMap(\.string).first ?? type.rawValue
            choices[id.lowercased()] = "\(name) · \(id.prefix(8))"
        }
        for level in project.levels {
            if type == .level { choices[level.id.uuidString.lowercased()] = level.info.name }
            for feature in level.editing.features.features(ofType: type) where !feature.isInTrash {
                let id = type == .level ? level.id : level.editing.ids.peek(feature.id) ?? feature.id
                choices[id.uuidString.lowercased()] = "\(feature.serialNumber) · \(level.info.name)"
            }
        }
        let result = choices.map { (id: $0.key, label: $0.value) }.sorted { $0.label < $1.label }
        referenceChoiceCache[type] = result
        return result
    }

    func updateLocalizedProperty(_ key: String, language: String, text: String, in feature: FeatureGroup) {
        var labels = feature.value(key).projectJSON.object
        labels[language] = text.isEmpty ? nil : .string(text)
        updateProperty(key, value: labels.isEmpty ? .null : .json(.object(labels)), in: feature.id)
    }

    /// Advanced geometry/foreign-member editing retains identity; final delivery validation remains common.
    func replaceGlobalRecord(_ text: String, type: IMDFFeatureType, id: UUID) throws {
        let value = try ProjectJSON.parse(Data(text.utf8))
        let key = type.rawValue + ".geojson"
        guard value["type"]?.string == "Feature", value["feature_type"]?.string == type.rawValue,
              value["id"]?.uuid == id, value["properties"]?.isObject == true, value["geometry"] != nil,
              let index = buildingProject.globalGeoJSON[key]?.firstIndex(where: { $0["id"]?.uuid == id }) else {
            throw IMDFImporter.Failure(message: "Feature 타입과 UUID를 유지하고 properties·geometry를 포함하세요.")
        }
        perform("공통 Feature JSON 편집") { buildingProject.globalGeoJSON[key]![index] = value }
    }
}
