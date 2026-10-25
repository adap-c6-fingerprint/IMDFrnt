import Foundation

/// AIMP 제출 편집 명령. 원본 feature ID와 실행취소 경계를 보존한다(#79).
@MainActor
extension AppEnvironment {
    @discardableResult
    func duplicateFootprint(_ id: FeatureGroupID) -> FeatureGroupID? {
        guard let source = features.feature(id), source.featureType == .footprint, !source.isInTrash else { return nil }
        var copy = FeatureGroup(featureType: .footprint, serialNumber: nextFeatureSerial(for: .footprint), memberIDs: [])
        copy.properties = source.properties
        copy.polygonRings = source.polygonRings
        copy.multiPolygon = source.multiPolygon
        perform("Footprint 복제") {
            if var original = buildingProject.sharedFootprint?.originals[id.uuidString] {
                original["id"] = .string(copy.id.uuidString.lowercased())
                buildingProject.sharedFootprint?.originals[copy.id.uuidString] = original
            }
            features.insert(copy)
        }
        return copy.id
    }

    /// 버튼 표시에는 SVG를 파싱하지 않는다. 실제 geometry 검증은 명령 실행 시 한다.
    var groundFootprintUnavailableReason: String? {
        // 활성 층의 아직 저장하지 않은 Level 속성도 내보내기와 같은 기준으로 읽는다.
        let ground = buildingProject.levels.compactMap { stored -> ProjectLevel? in
            var level = stored
            if level.id == routingFloorID { level.editing.features = features }
            return level.exportsLevelOrdinal(0) ? level : nil
        }
        if ground.count > 1 { return "IMDF ordinal이 0인 층이 여러 개입니다. 기준층 하나를 정하세요." }
        guard ground.count == 1, let level = ground.first else { return "ordinal 0인 Level이 하나 있어야 합니다." }
        let editor = level.id == routingFloorID ? features : level.editing.features
        let localLevels = editor.features(ofType: .level)
        let importedLevels = level.geoJSON["level.geojson"] ?? []
        guard !localLevels.isEmpty || !importedLevels.isEmpty else {
            return "ordinal 0 층에 Level 외곽선을 먼저 그리세요."
        }
        guard localLevels.count + importedLevels.count == 1 else { return "기준층의 Level 외곽선이 여러 개입니다. 하나로 정리하세요." }
        guard let shared = buildingProject.sharedFootprint else { return "전역 Footprint를 먼저 만드세요." }
        if level.id != shared.sourceLevelID && level.info.footprintRegistration?.isAligned != true
            && (!shared.isGeoreferenced || !level.info.hasGeographicCoordinates) {
            return "기준층을 Footprint에 정렬하거나 양쪽 GPS를 먼저 설정하세요."
        }
        return nil
    }

    /// 클릭 시 최신 편집 상태를 사용한다. 원점이 다른 층은 GPS 또는 확정된 정렬을 거쳐 변환한다.
    func groundFootprintRings() throws -> [[LocalPoint]] {
        if let reason = groundFootprintUnavailableReason { throw IMDFImporter.Failure(message: reason) }
        let project = projectContents
        let candidates = project.levels.filter { $0.exportsLevelOrdinal(0) }
        guard candidates.count == 1, let level = candidates.first else {
            throw IMDFImporter.Failure(message: "ordinal 0인 Level이 하나 있어야 합니다. 건물·층 관리에서 확인하세요.")
        }
        let rings = RegistrationGeometry.levelRings(level)
        guard !rings.isEmpty, rings.allSatisfy({ $0.count >= 3 }), RingNesting.isValid(rings) else {
            throw IMDFImporter.Failure(message: "ordinal 0 층에 유효한 Level 외곽선을 먼저 그리세요.")
        }
        guard let shared = project.sharedFootprint else {
            throw IMDFImporter.Failure(message: "전역 Footprint를 먼저 만드세요.")
        }
        let inShared: [[LocalPoint]]
        if level.id == shared.sourceLevelID || level.info.footprintRegistration?.isAligned == true {
            let transform = level.info.footprintRegistration?.transform ?? LevelFootprintTransform()
            inShared = rings.map { $0.map(transform.apply) }
        } else {
            let inverse = Georeferencer(pairs: shared.anchors.pairs)
            inShared = rings.map { ring in ring.compactMap { p in
                guard let geo = level.info.geoPoint(for: p) else { return nil }
                if !shared.anchors.pairs.isEmpty { return inverse.localPoint(for: geo) }
                return shared.seedCoordinates?.localPoint(longitude: geo.longitude, latitude: geo.latitude)
            } }
            guard zip(rings, inShared).allSatisfy({ $0.count == $1.count }) else {
                throw IMDFImporter.Failure(message: "기준층을 Footprint에 정렬하거나 양쪽 GPS를 먼저 설정하세요.")
            }
        }
        let active = activeLevel?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
        return inShared.map { $0.map(active.inverse) }
    }

    func matchFootprintToGroundLevel(_ id: FeatureGroupID) {
        guard let feature = features.feature(id), feature.featureType == .footprint else { return }
        do {
            let rings = try groundFootprintRings()
            perform("Footprint를 기준층 외곽에 맞추기") {
                ownership.releaseAll(of: id)
                features.update(id) {
                    $0.memberIDs = []; $0.polygonFaceIDs = []; $0.drawnVertices = nil
                    $0.polygonRings = rings
                    $0.multiPolygon = RingNesting.polygons(rings).count > 1
                    $0.properties["category"] = .string("ground")
                }
            }
        } catch { notify(error.localizedDescription, isError: true) }
    }

    func clearDisplayPoint(_ id: FeatureGroupID) {
        if !updateGlobalProperty("display_point", value: .null, in: id) {
            perform("display point 삭제") { features.update(id) { $0.displayPoint = nil } }
        }
        if mode == .displayPointPicking(id) { mode = .idle }
    }

    /// 원본 개체 방식도 실제 닫힌 외곽으로 검사하며, 구멍은 선택할 수 없다.
    func displayPointRings(for feature: FeatureGroup) -> [[LocalPoint]] {
        if !feature.polygonRings.isEmpty { return feature.polygonRings }
        guard let doc = document else { return [] }
        let ring = VertexExtractor.vertices(for: feature, document: doc, segmentation: segmentation,
            kind: .polygon, borrowed: borrow.objects(borrowedBy: feature.id))
        return ring.count >= 3 ? [ring] : []
    }

    func permitsDisplayPoint(_ p: LocalPoint, for feature: FeatureGroup) -> Bool {
        if feature.featureType == .building {
            // ground/aerial가 겹쳐도 서로 상쇄되지 않는다. 각 Footprint의 구멍만 제외한다.
            return features.features(ofType: .footprint).contains {
                SubmissionGeometry.contains(p, rings: $0.polygonRings)
            }
        }
        if feature.featureType.requiredGeometry == .point {
            if let vertices = feature.drawnVertices, let point = vertices.first { return point.distance(to: p) <= 2 }
            guard let document else { return false }
            return VertexExtractor.boundingBox(of: feature.memberIDs, document: document).insetBy(dx: -2, dy: -2).contains(p.cg)
        }
        return SubmissionGeometry.contains(p, rings: displayPointRings(for: feature))
    }

    func beginGlobalDisplayPointPicking(_ id: UUID) {
        showBuildingManager = false
        metadataEditorType = nil
        showRoutingScreen = false; showAnchorScreen = false; showMapAlignScreen = false; showLevelFootprintScreen = false
        selection.clear(); cancelPointDraft()
        mode = .displayPointPicking(id)
        notify("건물 또는 Venue 외곽 안에서 대표 표시점을 클릭하세요.")
    }

    /// Imported global metadata stores WGS84 directly, unlike locally drawn feature points.
    func setGlobalDisplayPoint(_ p: LocalPoint, for id: UUID) -> Bool {
        for type in ["building", "venue"] {
            guard let index = globalFeatures(type).firstIndex(where: { $0["id"]?.uuid == id }) else { continue }
            guard let info = projectContents.levels.first(where: { $0.id == routingFloorID })?.info,
                  let geo = info.geoPoint(for: p) else {
                notify("현재 층의 GPS를 먼저 설정하세요.", isError: true); return true
            }
            let geometries = type == "building" ? globalFeatures("footprint").compactMap { $0["geometry"] }
                : [globalFeatures(type)[index]["geometry"] ?? .null]
            let point = LocalPoint(geo.longitude, geo.latitude)
            let inside = geometries.contains { value in
                guard let rings = try? FootprintGeometry.rings(value) else { return false }
                return SubmissionGeometry.contains(point, rings: rings.map { $0.map { LocalPoint($0[0], $0[1]) } })
            }
            guard inside else { notify("건물 또는 Venue 외곽 안을 선택하세요.", isError: true); return true }
            perform("display point 지정") {
                var props = buildingProject.globalGeoJSON[type + ".geojson"]![index]["properties"] ?? .object([:])
                props["display_point"] = .object(["type": .string("Point"), "coordinates": .array([
                    .number(Decimal(geo.longitude)), .number(Decimal(geo.latitude))])])
                buildingProject.globalGeoJSON[type + ".geojson"]![index]["properties"] = props
                buildingProject.globalGeoJSON[type + ".geojson"]![index]["imdfrnt_local_display_point"] = nil
            }
            mode = .idle
            return true
        }
        return false
    }
}

enum SubmissionGeometry {
    static func contains(_ p: LocalPoint, rings: [[LocalPoint]]) -> Bool {
        rings.filter { $0.count >= 3 && RingNesting.contains($0, p) }.count % 2 == 1
    }
}
