import Foundation

/// A reversible, uniform-scale transform from a level's native drawing to the
/// building Footprint plane. It never changes the source drawing or its nodes.
struct LevelFootprintTransform: Codable, Equatable {
    var x = 0.0
    var y = 0.0
    var scale = 1.0
    var rotation = 0.0

    /// Map a native drawing point into the shared Footprint plane.
    func apply(_ p: LocalPoint) -> LocalPoint {
        let r = rotation * .pi / 180
        return LocalPoint(x + scale * (cos(r) * p.x - sin(r) * p.y),
                          y + scale * (sin(r) * p.x + cos(r) * p.y))
    }
    /// Recover a native drawing point without modifying the source geometry.
    func inverse(_ p: LocalPoint) -> LocalPoint {
        let r = rotation * .pi / 180
        let dx = (p.x - x) / scale, dy = (p.y - y) / scale
        return LocalPoint(cos(r) * dx + sin(r) * dy, -sin(r) * dx + cos(r) * dy)
    }
    var isValid: Bool { [x, y, scale, rotation].allSatisfy(\.isFinite) && scale > 1e-9 }

    /// Fit a uniform similarity transform; reject coincident or collapsed pairs.
    static func fit(_ pairs: [LevelFootprintPair]) throws -> Self {
        guard pairs.count >= 2 else { throw IMDFImporter.Failure(message: "서로 떨어진 대응점이 최소 2쌍 필요합니다.") }
        let n = Double(pairs.count)
        let a = LocalPoint(pairs.reduce(0) { $0 + $1.level.x } / n, pairs.reduce(0) { $0 + $1.level.y } / n)
        let b = LocalPoint(pairs.reduce(0) { $0 + $1.footprint.x } / n, pairs.reduce(0) { $0 + $1.footprint.y } / n)
        var dot = 0.0, cross = 0.0, length = 0.0
        for pair in pairs {
            let dx = pair.level.x - a.x, dy = pair.level.y - a.y
            let ex = pair.footprint.x - b.x, ey = pair.footprint.y - b.y
            dot += dx * ex + dy * ey; cross += dx * ey - dy * ex; length += dx * dx + dy * dy
        }
        guard length > 1e-12 else { throw IMDFImporter.Failure(message: "같은 위치의 대응점으로 정렬할 수 없습니다.") }
        var result = Self(scale: hypot(dot, cross) / length, rotation: atan2(cross, dot) * 180 / .pi)
        let translated = result.apply(a)
        result.x = b.x - translated.x; result.y = b.y - translated.y
        guard result.isValid else { throw IMDFImporter.Failure(message: "대응점의 크기 또는 위치가 올바르지 않습니다.") }
        return result
    }
}

struct LevelFootprintPair: Identifiable, Codable, Equatable {
    var id = UUID()
    var level: LocalPoint
    var footprint: LocalPoint
}

struct LevelFootprintRegistration: Codable, Equatable {
    var transform = LevelFootprintTransform()
    var pairs: [LevelFootprintPair] = []
    var isVisible = true
    var opacity = 0.6
    /// Display preferences and unfinished pairs must not opt a floor into GPS registration.
    var isAligned = false

    enum CodingKeys: String, CodingKey { case transform, pairs, isVisible, opacity, isAligned }

    /// Start with display defaults and no geographic alignment commitment.
    init() {}

    /// Read pre-v6 registrations conservatively; the source floor is handled separately.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        transform = try values.decodeIfPresent(LevelFootprintTransform.self, forKey: .transform) ?? LevelFootprintTransform()
        pairs = try values.decodeIfPresent([LevelFootprintPair].self, forKey: .pairs) ?? []
        isVisible = try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.6
        if let explicit = try values.decodeIfPresent(Bool.self, forKey: .isAligned) {
            isAligned = explicit
        } else if transform != LevelFootprintTransform() {
            isAligned = true
        } else if let fitted = try? LevelFootprintTransform.fit(pairs) {
            // Old files have no explicit flag. Retain a genuinely fitted identity
            // registration, not a display-only record or unfinished nonidentity fit.
            isAligned = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)].allSatisfy {
                fitted.apply($0).distance(to: transform.apply($0)) < 1e-7
            }
        }
    }
}

/// Local geometry exists before any GPS calibration. Original imported features
/// are retained verbatim so migration does not discard foreign properties.
struct SharedFootprint: Codable, Equatable {
    var features: [FeatureGroup] = []
    var originals: [String: ProjectJSON] = [:]
    var anchors = AnchorStore()
    var sourceLevelID: UUID?
    var seedCoordinates: IMDFCoordinateSpace?
    /// Unconvertible legacy features remain owned by their original levels until calibration is possible.
    var pendingMigrationFeatureIDs: [UUID]?

    /// Build one reusable local-to-GPS converter for a batch of points.
    var geographicConverter: (LocalPoint) -> GeoPoint? {
        if !anchors.pairs.isEmpty {
            let georeferencer = Georeferencer(pairs: anchors.pairs)
            return georeferencer.geoPoint
        }
        guard let space = seedCoordinates, space.isValid else { return { _ in nil } }
        return space.geoPoint
    }

    /// Convert a shared point; batch callers should reuse geographicConverter.
    func geoPoint(_ p: LocalPoint) -> GeoPoint? {
        geographicConverter(p)
    }
    var isGeoreferenced: Bool { geoPoint(LocalPoint(0, 0)) != nil }

    /// Project a copy between native and shared planes, retaining Feature identity and properties.
    func projected(_ feature: FeatureGroup, transform: LevelFootprintTransform, toLevel: Bool) -> FeatureGroup {
        var copy = feature
        copy.polygonRings = feature.polygonRings.map { ring in ring.map { toLevel ? transform.inverse($0) : transform.apply($0) } }
        if let point = feature.displayPoint { copy.displayPoint = toLevel ? transform.inverse(point) : transform.apply(point) }
        return copy
    }

    /// Export live Features, retaining imported metadata and exact unchanged coordinates.
    func geographicFeatures() -> [ProjectJSON] {
        let convert = geographicConverter
        return features.filter { !$0.isInTrash }.compactMap { feature in
            var result = originals[feature.id.uuidString] ?? .object([
                "type": .string("Feature"), "feature_type": .string("footprint"), "id": .string(feature.id.uuidString.lowercased())
            ])
            var unchangedGeometry: ProjectJSON?
            // Retain exact imported coordinates when only properties changed.
            if anchors.pairs.isEmpty, let original = originals[feature.id.uuidString], seedCoordinates != nil,
               let rings = try? FootprintGeometry.rings(original["geometry"] ?? .null) {
                let locals = rings.map { $0.dropLast().map { seedCoordinates!.localPoint(longitude: $0[0], latitude: $0[1]) } }
                if locals == feature.polygonRings { unchangedGeometry = original["geometry"] }
            }
            var converted: [ProjectJSON] = []
            for ring in feature.polygonRings {
                let points = ring.compactMap(convert)
                guard points.count == ring.count, points.count >= 3,
                      points.allSatisfy({ $0.longitude.isFinite && $0.latitude.isFinite && abs($0.longitude) <= 180 && abs($0.latitude) <= 90 }) else { return nil }
                let coords = points.map { ProjectJSON.array([.number(Decimal($0.longitude)), .number(Decimal($0.latitude))]) }
                converted.append(.array(coords + [coords[0]]))
            }
            let polygons = RingNesting.polygons(feature.polygonRings)
            let multiple = feature.multiPolygon == true || polygons.count > 1
            let coordinates: ProjectJSON = multiple
                ? .array(polygons.map { .array([converted[$0.outer]] + $0.holes.map { converted[$0] }) })
                : .array(converted)
            result["geometry"] = .object(["type": .string(multiple ? "MultiPolygon" : "Polygon"), "coordinates": coordinates])
            if let unchangedGeometry { result["geometry"] = unchangedGeometry }
            var properties = result["properties"] ?? .object([:])
            for (key, value) in feature.properties {
                if let data = try? JSONSerialization.data(withJSONObject: value.jsonValue, options: [.fragmentsAllowed]),
                   let json = try? ProjectJSON.parse(data) { properties[key] = json }
            }
            if properties["category"] == nil || properties["category"] == .null { properties["category"] = .string("ground") }
            result["properties"] = properties
            return result
        }
    }

    /// Insert/update geographic geometry through the same authoritative model used by canvas edits.
    /// Existing draft geometry is never implicitly recalibrated to accommodate an external GPS edit.
    mutating func upsertGeographicFeature(_ original: ProjectJSON) throws {
        guard let exportID = original["id"]?.uuid else { throw IMDFImporter.Failure(message: "Footprint ID가 올바르지 않습니다.") }
        let rings = try FootprintGeometry.rings(original["geometry"] ?? .null)
        if !isGeoreferenced, features.isEmpty, anchors.pairs.isEmpty, let first = rings.first?.first {
            seedCoordinates = IMDFCoordinateSpace(west: first[0], north: first[1], unitsPerLongitudeDegree: 100_000,
                unitsPerLatitudeDegree: 100_000, padding: 0)
        }
        guard isGeoreferenced else { throw IMDFImporter.Failure(message: "전역 Footprint의 GPS Anchor를 먼저 설정하세요.") }
        let inverse = Georeferencer(pairs: anchors.pairs)
        let converted = rings.map { ring in ring.dropLast().compactMap { coordinate -> LocalPoint? in
            let geo = GeoPoint(longitude: coordinate[0], latitude: coordinate[1])
            if !anchors.pairs.isEmpty { return inverse.localPoint(for: geo) }
            guard let space = seedCoordinates, space.isValid else { return nil }
            return space.localPoint(longitude: geo.longitude, latitude: geo.latitude)
        } }
        guard zip(converted, rings).allSatisfy({ $0.count == $1.count - 1 }),
              converted.flatMap({ $0 }).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw IMDFImporter.Failure(message: "Footprint 좌표를 공유 평면으로 변환할 수 없습니다.")
        }
        let index = features.firstIndex { $0.id == exportID || originals[$0.id.uuidString]?["id"]?.uuid == exportID }
        var feature = index.map { features[$0] } ?? FeatureGroup(id: exportID, featureType: .footprint,
            serialNumber: "footprint-\(features.count + 1)", memberIDs: [])
        feature.polygonRings = converted
        feature.memberIDs = []; feature.polygonFaceIDs = []
        feature.multiPolygon = original["geometry"]?["type"]?.string == "MultiPolygon"
        for (key, value) in original["properties"]?.object ?? [:] {
            if let string = value.string { feature.properties[key] = .string(string) }
            else if value == .null { feature.properties[key] = .null }
            else if case .array(let list) = value, list.allSatisfy({ $0.string != nil }) {
                feature.properties[key] = .stringArray(list.compactMap(\.string))
            }
        }
        originals[feature.id.uuidString] = original
        if let index { features[index] = feature } else { features.append(feature) }
    }
}

extension BuildingProject {
    /// Incrementally move legacy Footprints into one plane. Failed conversions stay in their source level.
    mutating func migrateSharedFootprint() {
        var shared = sharedFootprint ?? SharedFootprint()
        var pending: [UUID] = []
        // First prefer existing locally-authored Footprints, including pre-GPS projects.
        for i in levels.indices {
            let old = levels[i].editing.features.features.filter { $0.featureType == .footprint }
            guard !old.isEmpty else { continue }
            if shared.sourceLevelID == nil {
                shared.sourceLevelID = levels[i].id
                shared.anchors = levels[i].info.anchors
                shared.seedCoordinates = levels[i].info.imdfCoordinates
            }
            let needsDrawing = old.contains { $0.polygonRings.isEmpty }
            let doc = needsDrawing ? try? SVGParser.parse(data: Data(levels[i].info.svg.utf8), sourceName: levels[i].info.sourceName) : nil
            for var feature in old {
                let originalFeature = feature
                if feature.polygonRings.isEmpty, let doc {
                    let points = VertexExtractor.vertices(for: feature, document: doc, segmentation: levels[i].editing.segmentation,
                        kind: .polygon, borrowed: levels[i].editing.borrow.objects(borrowedBy: feature.id))
                    feature.polygonRings = [points]
                }
                guard feature.polygonRings.allSatisfy({ $0.count >= 3 }), !feature.polygonRings.isEmpty else {
                    pending.append(feature.id); continue
                }
                if levels[i].id != shared.sourceLevelID {
                    // Local points from different drawings cannot be concatenated.
                    // Round-trip through each floor's native GPS, never an existing override.
                    var native = levels[i].info; native.footprintGeoAnchors = nil
                    let fromNative = Georeferencer(pairs: native.anchors.pairs)
                    let toShared = Georeferencer(pairs: shared.anchors.pairs)
                    /// Cross native GPS into the selected shared frame, rejecting unusable calibration.
                    func convert(_ point: LocalPoint) -> LocalPoint? {
                        let geo: GeoPoint?
                        if let space = native.imdfCoordinates { geo = space.isValid ? space.geoPoint(for: point) : nil }
                        else { geo = fromNative.geoPoint(for: point) }
                        guard let geo else { return nil }
                        let local: LocalPoint?
                        if !shared.anchors.pairs.isEmpty { local = toShared.localPoint(for: geo) }
                        else if let space = shared.seedCoordinates, space.isValid {
                            local = space.localPoint(longitude: geo.longitude, latitude: geo.latitude)
                        } else { local = nil }
                        guard let local, local.x.isFinite, local.y.isFinite else { return nil }
                        return local
                    }
                    let converted = feature.polygonRings.map { $0.compactMap(convert) }
                    guard zip(converted, feature.polygonRings).allSatisfy({ $0.count == $1.count }) else {
                        pending.append(feature.id); continue
                    }
                    feature.polygonRings = converted
                    if let point = originalFeature.displayPoint {
                        guard let converted = convert(point) else { pending.append(feature.id); continue }
                        feature.displayPoint = converted
                    }
                }
                if !shared.features.contains(where: { $0.id == feature.id }) {
                    feature.memberIDs = []; feature.polygonFaceIDs = []
                    shared.features.append(feature)
                    // Retain the lifetime export UUID allocated by older versions.
                    let exportID = levels[i].editing.ids.id(for: feature.id)
                    shared.originals[feature.id.uuidString] = .object(["type": .string("Feature"),
                        "feature_type": .string("footprint"), "id": .string(exportID.uuidString.lowercased())])
                }
                levels[i].editing.features.remove(feature.id)
                levels[i].editing.ownership.releaseAll(of: feature.id)
            }
        }
        // Imported WGS84 Features need a reversible drawing plane, not GPS guessing.
        let imported = globalGeoJSON["footprint.geojson"] ?? []
        if !imported.isEmpty {
            if shared.sourceLevelID == nil, let first = levels.first {
                shared.sourceLevelID = first.id; shared.seedCoordinates = first.info.imdfCoordinates
                shared.anchors = first.info.anchors
            }
            let all = imported.compactMap { try? FootprintGeometry.rings($0["geometry"] ?? .null) }.flatMap { $0 }.flatMap { $0 }
            if shared.seedCoordinates == nil, shared.anchors.pairs.isEmpty, let p = all.first, p.count >= 2 {
                shared.seedCoordinates = IMDFCoordinateSpace(west: p[0], north: p[1], unitsPerLongitudeDegree: 100_000,
                    unitsPerLatitudeDegree: 100_000, padding: 0)
            }
            let migratedIDs = Set(shared.originals.values.compactMap { $0["id"]?.uuid })
            for original in imported {
                guard let id = original["id"]?.uuid, let rings = try? FootprintGeometry.rings(original["geometry"] ?? .null) else { continue }
                // Retained raw JSON is provenance, not a second owner. Do not
                // resurrect a deleted shared Feature when retrying migration.
                if migratedIDs.contains(id) || shared.features.contains(where: { $0.id == id }) { continue }
                let inverse = Georeferencer(pairs: shared.anchors.pairs)
                /// Recover a shared point without preferring a stale seed over edited GPS anchors.
                func local(_ coordinate: [Double]) -> LocalPoint? {
                    guard coordinate.count >= 2 else { return nil }
                    if !shared.anchors.pairs.isEmpty { return inverse.localPoint(for: GeoPoint(longitude: coordinate[0], latitude: coordinate[1])) }
                    if let space = shared.seedCoordinates, space.isValid { return space.localPoint(longitude: coordinate[0], latitude: coordinate[1]) }
                    return nil
                }
                let converted = rings.map { $0.dropLast().compactMap(local) }
                guard zip(converted, rings).allSatisfy({ $0.count == $1.count - 1 }) else { continue }
                var feature = FeatureGroup(id: id, featureType: .footprint, serialNumber: "footprint-\(shared.features.count + 1)", memberIDs: [])
                feature.polygonRings = converted
                feature.multiPolygon = original["geometry"]?["type"]?.string == "MultiPolygon"
                for (key, value) in original["properties"]?.object ?? [:] {
                    if let string = value.string { feature.properties[key] = .string(string) }
                    else if case .null = value { feature.properties[key] = .null }
                    else if case .array(let list) = value, list.allSatisfy({ $0.string != nil }) { feature.properties[key] = .stringArray(list.compactMap(\.string)) }
                }
                shared.features.append(feature); shared.originals[id.uuidString] = original
            }
        }
        guard !shared.features.isEmpty || !pending.isEmpty else { return }
        shared.pendingMigrationFeatureIDs = pending.isEmpty ? nil : pending
        sharedFootprint = shared
        if let source = shared.sourceLevelID, let i = levels.firstIndex(where: { $0.id == source }) {
            if levels[i].info.footprintRegistration == nil { levels[i].info.footprintRegistration = LevelFootprintRegistration() }
        }
        synchronizeFootprintCoordinates()
    }

    /// Only explicitly aligned floors use shared GPS. An aligned floor with invalid GPS stays blocked.
    mutating func synchronizeFootprintCoordinates() {
        guard let shared = sharedFootprint else { return }
        let convert = shared.geographicConverter
        for i in levels.indices {
            guard let registration = levels[i].info.footprintRegistration,
                  levels[i].id == shared.sourceLevelID || registration.isAligned else {
                levels[i].info.footprintGeoAnchors = nil
                continue
            }
            let basis = [LocalPoint(0, 0), LocalPoint(100, 0), LocalPoint(0, 100)]
            let pairs = basis.compactMap { local -> AnchorPair? in
                guard let geo = convert(registration.transform.apply(local)) else { return nil }
                return AnchorPair(id: levels[i].id, local: local, geo: geo, label: "Footprint 기준")
            }
            levels[i].info.footprintGeoAnchors = pairs.count == 3 ? pairs : []
        }
    }
}

extension ProjectLevel {
    /// Reproject imported WGS84 data through native drawing coordinates. The
    /// original GeoJSON and SVG stay intact, so repeated adjustments do not drift.
    func registeredFeatureForExport(_ feature: ProjectJSON) -> ProjectJSON {
        guard info.footprintRegistration != nil, info.footprintGeoAnchors?.count == 3 else { return feature }
        var native = info; native.footprintGeoAnchors = nil
        let registered = Georeferencer(pairs: info.footprintGeoAnchors ?? [])
        let nativeGeoreferencer = Georeferencer(pairs: native.anchors.pairs)
        /// Retain native coordinate-space validity and finite-point checks while reusing fitted transforms.
        func nativeLocal(_ geo: GeoPoint) -> LocalPoint? {
            if let space = native.imdfCoordinates {
                guard space.isValid else { return nil }
                let point = space.localPoint(longitude: geo.longitude, latitude: geo.latitude)
                return point.x.isFinite && point.y.isFinite ? point : nil
            }
            return nativeGeoreferencer.localPoint(for: geo)
        }
        /// Walk nested coordinate arrays, preserving optional altitude values.
        func coordinates(_ value: ProjectJSON) -> ProjectJSON {
            let array = value.array
            if array.count >= 2, case .number(let lon) = array[0], case .number(let lat) = array[1],
               let local = nativeLocal(GeoPoint(longitude: NSDecimalNumber(decimal: lon).doubleValue, latitude: NSDecimalNumber(decimal: lat).doubleValue)),
               let geo = registered.geoPoint(for: local) {
                return .array([.number(Decimal(geo.longitude)), .number(Decimal(geo.latitude))] + array.dropFirst(2))
            }
            if case .array = value { return .array(array.map(coordinates)) }
            return value
        }
        /// Reproject coordinates and GeometryCollection children without changing foreign members.
        func geometry(_ value: ProjectJSON) -> ProjectJSON {
            var result = value
            if let raw = value["coordinates"] { result["coordinates"] = coordinates(raw) }
            if let geometries = value["geometries"] { result["geometries"] = .array(geometries.array.map(geometry)) }
            return result
        }
        var result = feature
        if let raw = feature["geometry"], raw != .null { result["geometry"] = geometry(raw) }
        if let raw = feature["properties"]?["display_point"], raw != .null { result["properties"]?["display_point"] = geometry(raw) }
        return result
    }
}
