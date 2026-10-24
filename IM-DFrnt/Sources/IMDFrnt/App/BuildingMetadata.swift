import Foundation

@MainActor
extension AppEnvironment {
    func globalFeatures(_ type: String) -> [ProjectJSON] { buildingProject.globalGeoJSON[type + ".geojson"] ?? [] }

    func setManifest(_ text: String) throws {
        let value = try ProjectJSON.parse(Data(text.utf8))
        guard case .object = value else { throw IMDFImporter.Failure(message: "manifest는 JSON 객체여야 합니다.") }
        perform("Manifest 편집") { buildingProject.manifest = value }
        hasCreatedProject = true
    }

    /// Metadata is edited without rebuilding the Feature, retaining foreign
    /// members, feature UUID, geometry, references and other localized names.
    func setGlobalMetadata(type: String, id: UUID, text: String) throws {
        let value = try ProjectJSON.parse(Data(text.utf8))
        guard case .object = value, let index = globalFeatures(type).firstIndex(where: { $0["id"]?.uuid == id }) else {
            throw IMDFImporter.Failure(message: "유효한 Feature와 properties JSON 객체가 필요합니다.")
        }
        perform("\(type) 정보 편집") { buildingProject.globalGeoJSON[type + ".geojson"]?[index]["properties"] = value }
    }

    func createBuilding() {
        guard globalFeatures("building").isEmpty else { return }
        let feature: ProjectJSON = .object(["type": .string("Feature"), "feature_type": .string("building"),
            "id": .string(UUID().uuidString.lowercased()), "geometry": .null,
            "properties": .object(["category": .string("unspecified"), "name": .null, "alt_name": .null,
                "restriction": .null, "display_point": .null, "address_id": .null])])
        perform("건물 생성") { buildingProject.globalGeoJSON["building.geojson"] = [feature] }
        hasCreatedProject = true
    }


    /// Save a Footprint geometry while retaining the Feature identity and
    /// properties. Canvas authoring and map re-picking both use this path.
    @discardableResult
    func saveFootprint(id: UUID?, geometryText: String, category: String) throws -> UUID {
        let geometry = try ProjectJSON.parse(Data(geometryText.utf8))
        try FootprintGeometry.validate(geometry)
        guard ["ground", "aerial", "subterranean"].contains(category) else {
            throw IMDFImporter.Failure(message: "Footprint 카테고리가 올바르지 않습니다.")
        }
        let resultID = id ?? UUID()
        var features = globalFeatures("footprint")
        let index = features.firstIndex(where: { $0["id"]?.uuid == resultID })
        if id != nil && index == nil { throw IMDFImporter.Failure(message: "삭제된 Footprint입니다. 다시 선택하세요.") }
        var feature = index.map { features[$0] } ?? .object(["type": .string("Feature"),
            "feature_type": .string("footprint"), "id": .string(resultID.uuidString.lowercased())])
        var props = feature["properties"] ?? .object(["name": .null,
            "building_ids": .array(globalFeatures("building").compactMap { $0["id"] })])
        props["category"] = .string(category)
        feature["properties"] = props; feature["geometry"] = geometry
        if let index { features[index] = feature } else { features.append(feature) }
        perform(id == nil ? "Footprint 생성" : "Footprint 좌표 편집") { buildingProject.globalGeoJSON["footprint.geojson"] = features }
        hasCreatedProject = true
        return resultID
    }

    func requestFootprintDeletion(_ id: UUID) {
        guard globalFeatures("footprint").contains(where: { $0["id"]?.uuid == id }) else { return }
        requestDeletion(title: "Footprint를 삭제할까요?", message: "건물 외곽 도형을 삭제합니다. 실행 취소로 복구할 수 있습니다.") { env in
            env.perform("Footprint 삭제") { env.buildingProject.globalGeoJSON["footprint.geojson"]?.removeAll { $0["id"]?.uuid == id } }
        }
    }
}

enum FootprintGeometry {
    static func rings(_ value: ProjectJSON) throws -> [[[Double]]] {
        let object = try JSONSerialization.jsonObject(with: value.data()) as? [String: Any]
        if value["type"]?.string == "Polygon", let rings = object?["coordinates"] as? [[[Double]]] { return rings }
        if value["type"]?.string == "MultiPolygon", let polygons = object?["coordinates"] as? [[[[Double]]]], !polygons.isEmpty,
           polygons.allSatisfy({ !$0.isEmpty }) { return polygons.flatMap { $0 } }
        throw IMDFImporter.Failure(message: "Footprint는 Polygon 또는 MultiPolygon geometry여야 합니다.")
    }

    static func validate(_ value: ProjectJSON) throws {
        let rings = try rings(value)
        guard !rings.isEmpty else { throw IMDFImporter.Failure(message: "Footprint 좌표가 비어 있습니다.") }
        for ring in rings {
            guard ring.count >= 4, ring.first == ring.last,
                  ring.allSatisfy({ $0.count >= 2 && $0.allSatisfy(\.isFinite) && abs($0[0]) <= 180 && abs($0[1]) <= 90 }),
                  Set(ring.dropLast().map { LocalPoint($0[0], $0[1]) }).count >= 3 else {
                throw IMDFImporter.Failure(message: "경도·위도 범위와 닫힌 링(서로 다른 점 최소 3개)을 확인하세요.")
            }
            let points = ring.map { LocalPoint($0[0], $0[1]) }
            guard abs(ClosedPolygonFinder.signedArea(points)) > 1e-14 else {
                throw IMDFImporter.Failure(message: "Footprint는 면적이 있는 다각형이어야 합니다.")
            }
        }
    }
}
