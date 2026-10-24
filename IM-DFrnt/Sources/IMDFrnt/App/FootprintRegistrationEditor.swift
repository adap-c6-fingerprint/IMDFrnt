import Foundation

@MainActor
extension AppEnvironment {
    var sharedFootprint: SharedFootprint { projectContents.sharedFootprint ?? SharedFootprint() }

    func reloadSharedFootprintFeatures() {
        for feature in features.features where feature.featureType == .footprint { features.remove(feature.id) }
        guard let shared = buildingProject.sharedFootprint else { return }
        let transform = activeLevel?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
        for feature in shared.features {
            features.insert(shared.projected(feature, transform: transform, toLevel: true))
            serials.reserve(feature.serialNumber)
            ids.adopt(feature.id, id: shared.originals[feature.id.uuidString]?["id"]?.uuid ?? feature.id)
        }
        if !shared.features.isEmpty, layers.layer(for: .footprint) == nil { _ = layers.addPropertyTypeLayer(.footprint) }
        refreshCanvasReferences()
    }

    func editFootprintAnchors(_ name: String, _ change: (inout AnchorStore) -> Void) {
        storeActiveLevel()
        perform(name) {
            guard var shared = buildingProject.sharedFootprint else { return }
            change(&shared.anchors)
            buildingProject.sharedFootprint = shared
            buildingProject.synchronizeFootprintCoordinates()
        }
    }

    func enterLevelFootprintScreen() {
        storeActiveLevel()
        guard buildingProject.sharedFootprint?.features.contains(where: { !$0.isInTrash }) == true else {
            notify("먼저 footprint 레이어에서 건물 외곽을 그리세요.", isError: true)
            return
        }
        selection.clear(); cancelPointDraft()
        showRoutingScreen = false; showAnchorScreen = false; showMapAlignScreen = false
        showLevelFootprintScreen = true
    }

    func editLevelRegistration(_ levelID: UUID, name: String, _ change: (inout LevelFootprintRegistration) -> Void) {
        storeActiveLevel()
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == levelID }) else { return }
        var next = buildingProject.levels[i].info.footprintRegistration ?? LevelFootprintRegistration()
        let oldTransform = next.transform
        change(&next)
        guard next.transform.isValid else { notify("크기·회전·이동 값은 유효한 숫자여야 합니다.", isError: true); return }
        if next.transform != oldTransform {
            // Manual fine adjustment moves the target positions of saved pairs too.
            for j in next.pairs.indices { next.pairs[j].footprint = next.transform.apply(next.pairs[j].level) }
        }
        perform(name) {
            buildingProject.levels[i].info.footprintRegistration = next
            buildingProject.synchronizeFootprintCoordinates()
            reloadSharedFootprintFeatures()
        }
    }

    func fitLevelToFootprint(_ levelID: UUID) {
        guard let registration = projectContents.levels.first(where: { $0.id == levelID })?.info.footprintRegistration else { return }
        do {
            let result = try LevelFootprintTransform.fit(registration.pairs)
            // Retain measured targets when fitting; only manual adjustments move them.
            storeActiveLevel()
            guard let index = buildingProject.levels.firstIndex(where: { $0.id == levelID }) else { return }
            perform("층 대응점 정렬") {
                buildingProject.levels[index].info.footprintRegistration?.transform = result
                buildingProject.synchronizeFootprintCoordinates()
                reloadSharedFootprintFeatures()
            }
        } catch { notify(error.localizedDescription, isError: true) }
    }
}

enum RegistrationGeometry {
    static func levelRings(_ level: ProjectLevel) -> [[LocalPoint]] {
        var result = level.editing.features.features(ofType: .level).flatMap(\.polygonRings)
        for feature in level.geoJSON["level.geojson"] ?? [] {
            guard let geometry = feature["geometry"], let rings = try? FootprintGeometry.rings(geometry) else { continue }
            result += rings.map { ring in ring.dropLast().compactMap { coordinate in
                // Imported geometry belongs to the immutable native drawing space.
                if let space = level.info.imdfCoordinates { return space.localPoint(longitude: coordinate[0], latitude: coordinate[1]) }
                return Georeferencer(pairs: level.info.anchors.pairs).localPoint(for: GeoPoint(longitude: coordinate[0], latitude: coordinate[1]))
            } }
        }
        if result.isEmpty, let doc = try? SVGParser.parse(data: Data(level.info.svg.utf8), sourceName: level.info.sourceName) {
            for feature in level.editing.features.features(ofType: .level) where feature.polygonRings.isEmpty {
                let ring = VertexExtractor.vertices(for: feature, document: doc, segmentation: level.editing.segmentation,
                    kind: .polygon, borrowed: level.editing.borrow.objects(borrowedBy: feature.id))
                if ring.count >= 3 { result.append(ring) }
            }
        }
        return result
    }

    /// The existing endpoint/vertex/intersection extractor is also used here;
    /// edge projection is added after vertex candidates, preserving magnet priority.
    static func snapped(_ p: LocalPoint, rings: [[LocalPoint]], tolerance: Double) -> LocalPoint? {
        let objects = rings.enumerated().map { index, ring in
            VectorObject(id: UUID(), geometry: PathGeometry(subpaths: [Subpath(start: ring.first ?? p,
                segments: ring.dropFirst().map { .line(to: $0) }, isClosed: true)]), style: .default, sourceElement: "polygon", ordinal: index)
        }
        let candidates = SnapPointExtractor.points(in: objects, segmentation: SegmentationStore())
        if let best = candidates.min(by: { $0.point.distance(to: p) < $1.point.distance(to: p) }), best.point.distance(to: p) <= tolerance {
            return best.point
        }
        var best: (point: LocalPoint, distance: Double)?
        for ring in rings where ring.count >= 2 {
            for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
                let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
                guard denominator > 1e-12 else { continue }
                let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator))
                let q = LocalPoint(a.x + t * dx, a.y + t * dy), distance = q.distance(to: p)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (q, distance) }
            }
        }
        return best?.point
    }
}
