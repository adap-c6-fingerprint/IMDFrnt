import Foundation

@MainActor
extension AppEnvironment {
    /// Read live Footprint edits without constructing or synchronizing every project level.
    var sharedFootprint: SharedFootprint {
        var shared = buildingProject.sharedFootprint ?? SharedFootprint(sourceLevelID: routingFloorID)
        guard routingFloorID != nil else { return shared }
        let pending = Set(shared.pendingMigrationFeatureIDs ?? [])
        let transform = activeLevel?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
        let originals = Dictionary(uniqueKeysWithValues: shared.features.map { ($0.id, $0) })
        shared.features = features.features.filter { $0.featureType == .footprint && !pending.contains($0.id) }.map { local in
            if let original = originals[local.id], shared.projected(original, transform: transform, toLevel: true) == local { return original }
            return shared.projected(local, transform: transform, toLevel: false)
        }
        return shared
    }

    /// Refresh global projections without removing unconverted legacy features from their source level.
    func reloadSharedFootprintFeatures() {
        let pending = Set(buildingProject.sharedFootprint?.pendingMigrationFeatureIDs ?? [])
        for feature in features.features where feature.featureType == .footprint && !pending.contains(feature.id) { features.remove(feature.id) }
        guard let shared = buildingProject.sharedFootprint else { return }
        let transform = activeLevel?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
        for feature in shared.features {
            features.insert(shared.projected(feature, transform: transform, toLevel: true))
        }
        if !shared.features.isEmpty, layers.layer(for: .footprint) == nil { _ = layers.addPropertyTypeLayer(.footprint) }
        refreshCanvasReferences()
    }

    /// Reserve global serials only when creating a Feature; viewing another floor must stay read-only.
    func nextFeatureSerial(for type: IMDFFeatureType) -> String {
        if type == .footprint {
            for feature in sharedFootprint.features { serials.reserve(feature.serialNumber) }
        }
        return serials.next(for: type)
    }

    /// Shared Footprints own their export identity globally rather than in every floor's ID allocator.
    func exportID(for feature: FeatureGroup) -> UUID? {
        if isGlobalMetadata(feature.id) { return feature.id }
        if feature.featureType == .footprint {
            return buildingProject.sharedFootprint?.originals[feature.id.uuidString]?["id"]?.uuid ?? feature.id
        }
        return ids.peek(feature.id)
    }

    /// Update GPS calibration and retry deferred migration as a single undoable operation.
    func editFootprintAnchors(_ name: String, _ change: (inout AnchorStore) -> Void) {
        storeActiveLevel()
        perform(name) {
            guard var shared = buildingProject.sharedFootprint else { return }
            change(&shared.anchors)
            buildingProject.sharedFootprint = shared
            buildingProject.migrateSharedFootprint()
            reloadSharedFootprintFeatures()
        }
    }

    /// Enter alignment exclusively, clearing the previous Anchor input mode.
    func enterLevelFootprintScreen() {
        storeActiveLevel()
        guard buildingProject.sharedFootprint?.features.contains(where: { !$0.isInTrash }) == true else {
            notify("먼저 footprint 레이어에서 건물 외곽을 그리세요.", isError: true)
            return
        }
        selection.clear(); cancelPointDraft()
        exitAnchorScreen()
        showRoutingScreen = false; showMapAlignScreen = false
        showLevelFootprintScreen = true
    }

    /// Preferences and unfinished pairs do not activate alignment; explicit transform edits do.
    func editLevelRegistration(_ levelID: UUID, name: String, coalescingKey: String? = nil,
                               _ change: (inout LevelFootprintRegistration) -> Void) {
        storeActiveLevel()
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == levelID }) else { return }
        var next = buildingProject.levels[i].info.footprintRegistration ?? LevelFootprintRegistration()
        let oldTransform = next.transform
        change(&next)
        guard next.transform.isValid else { notify("크기·회전·이동 값은 유효한 숫자여야 합니다.", isError: true); return }
        if next.transform != oldTransform {
            next.isAligned = true
            // Manual fine adjustment moves the target positions of saved pairs too.
            for j in next.pairs.indices { next.pairs[j].footprint = next.transform.apply(next.pairs[j].level) }
        }
        guard next != buildingProject.levels[i].info.footprintRegistration else { return }
        let transformChanged = next.transform != oldTransform
        perform(name, coalescingKey: coalescingKey) {
            buildingProject.levels[i].info.footprintRegistration = next
            buildingProject.synchronizeFootprintCoordinates()
            if transformChanged { reloadSharedFootprintFeatures() }
        }
    }

    /// Apply measured correspondences only when the user requests alignment.
    func fitLevelToFootprint(_ levelID: UUID) {
        guard let registration = buildingProject.levels.first(where: { $0.id == levelID })?.info.footprintRegistration else { return }
        do {
            let result = try LevelFootprintTransform.fit(registration.pairs)
            // Retain measured targets when fitting; only manual adjustments move them.
            storeActiveLevel()
            guard let index = buildingProject.levels.firstIndex(where: { $0.id == levelID }) else { return }
            perform("층 대응점 정렬") {
                buildingProject.levels[index].info.footprintRegistration?.transform = result
                buildingProject.levels[index].info.footprintRegistration?.isAligned = true
                buildingProject.synchronizeFootprintCoordinates()
                reloadSharedFootprintFeatures()
            }
        } catch { notify(error.localizedDescription, isError: true) }
    }
}

enum RegistrationGeometry {
    /// Read native outlines and parse SVG only when an actual legacy Level needs extraction.
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
        let legacy = level.editing.features.features(ofType: .level).filter { $0.polygonRings.isEmpty }
        if !legacy.isEmpty, let doc = try? SVGParser.parse(data: Data(level.info.svg.utf8), sourceName: level.info.sourceName) {
            for feature in legacy {
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
        RegistrationSnapData(rings: rings).snapped(p, tolerance: tolerance)
    }
}

/// Geometry-dependent snap preparation, reusable by every hover/click at any zoom.
struct RegistrationSnapData {
    private let candidates: [SnapPointExtractor.SnapPoint]
    private let segments: [LineSegment]

    /// Extract candidates, crossings and segment bounds only when the source rings change.
    init(rings: [[LocalPoint]]) {
        let objects = rings.enumerated().map { index, ring in
            VectorObject(id: UUID(), geometry: PathGeometry(subpaths: [Subpath(start: ring.first ?? LocalPoint(0, 0),
                segments: ring.dropFirst().map { .line(to: $0) }, isClosed: true)]), style: .default, sourceElement: "polygon", ordinal: index)
        }
        candidates = SnapPointExtractor.points(in: objects, segmentation: SegmentationStore())
        segments = objects.flatMap { $0.geometry.lineSegments() }
    }

    /// Prefer vertex/intersection candidates, then project onto nearby edges using the current tolerance.
    func snapped(_ p: LocalPoint, tolerance: Double) -> LocalPoint? {
        if let best = candidates.min(by: { $0.point.distance(to: p) < $1.point.distance(to: p) }), best.point.distance(to: p) <= tolerance {
            return best.point
        }
        var best: (point: LocalPoint, distance: Double)?
        let query = CGRect(x: p.x - tolerance, y: p.y - tolerance, width: tolerance * 2, height: tolerance * 2)
        for segment in segments where segment.boundingBox.intersects(query) {
            let a = segment.start, b = segment.end
            let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
            guard denominator > 1e-12 else { continue }
            let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator))
            let q = LocalPoint(a.x + t * dx, a.y + t * dy), distance = q.distance(to: p)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (q, distance) }
        }
        return best?.point
    }
}

/// Screen-local cache whose key excludes opacity, visibility and registration transforms.
@MainActor
final class RegistrationGeometryCache: ObservableObject {
    private struct Entry {
        var editing: LevelEditingState
        var geometry: [ProjectJSON]
        var svg: String
        var coordinates: IMDFCoordinateSpace?
        var anchors: AnchorStore
        var rings: [[LocalPoint]]
    }
    private var entries: [UUID: Entry] = [:]
    private(set) var buildCount = 0

    /// Reuse native rings across slider updates; editing or native georeferencing invalidates the entry.
    func rings(for level: ProjectLevel) -> [[LocalPoint]] {
        let geometry = level.geoJSON["level.geojson"] ?? []
        if let entry = entries[level.id], entry.editing == level.editing, entry.geometry == geometry,
           entry.svg == level.info.svg, entry.coordinates == level.info.imdfCoordinates, entry.anchors == level.info.anchors {
            return entry.rings
        }
        let rings = RegistrationGeometry.levelRings(level)
        entries[level.id] = Entry(editing: level.editing, geometry: geometry, svg: level.info.svg,
            coordinates: level.info.imdfCoordinates, anchors: level.info.anchors, rings: rings)
        buildCount += 1
        return rings
    }
}
