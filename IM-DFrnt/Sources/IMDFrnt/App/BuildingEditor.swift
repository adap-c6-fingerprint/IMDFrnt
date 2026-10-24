import AppKit
import Foundation

@MainActor
extension AppEnvironment {
    var activeLevel: ProjectLevel? { buildingProject.levels.first { $0.id == routingFloorID } }

    var levelEditingState: LevelEditingState {
        LevelEditingState(features: features, ownership: ownership, segmentation: segmentation,
            auxiliary: auxiliary, openingGate: openingGate, borrow: borrow, doorClosures: doorClosures,
            serials: serials, ids: ids)
    }

    /// Flush the active editor only into its Level. Reading a save snapshot does
    /// not publish mutations or alter UI selection/dirty state.
    var projectContents: BuildingProject {
        var project = buildingProject
        if let i = project.levels.firstIndex(where: { $0.id == routingFloorID }) {
            project.levels[i].editing = levelEditingState
            project.levels[i].info.anchors = anchors
            let transform = project.levels[i].info.footprintRegistration?.transform ?? LevelFootprintTransform()
            let localFootprints = features.features.filter { $0.featureType == .footprint }
            if project.sharedFootprint != nil || !localFootprints.isEmpty {
                var shared = project.sharedFootprint ?? SharedFootprint(sourceLevelID: routingFloorID)
                shared.features = localFootprints.map { local in
                    if let original = shared.features.first(where: { $0.id == local.id }),
                       shared.projected(original, transform: transform, toLevel: true) == local { return original }
                    return shared.projected(local, transform: transform, toLevel: false)
                }
                project.sharedFootprint = shared
                if project.levels[i].info.footprintRegistration == nil, shared.sourceLevelID == routingFloorID {
                    project.levels[i].info.footprintRegistration = LevelFootprintRegistration()
                }
                for feature in localFootprints { project.levels[i].editing.features.remove(feature.id) }
            }
        }
        project.synchronizeFootprintCoordinates()
        return project
    }

    func storeActiveLevel() { buildingProject = projectContents }

    func loadLevelEditor(_ id: UUID?) throws {
        let level = buildingProject.levels.first { $0.id == id }
        // Validate before replacing the current editor; corrupt input cannot
        // silently clear the user's active document.
        let prepared = try level.map { level in
            let input = LevelDrawingInput(level)
            return try levelDrawingCache.cached(input) ?? PreparedLevelDrawing.make(input)
        }
        cancelLevelDrawingLoads()
        installLevelMetadata(level)
        if let prepared { levelDrawingCache.insert(prepared); installLevelDrawing(prepared) }
    }

    /// Publish cheap editing/Level data first; no SVG parsing occurs here.
    func installLevelMetadata(_ level: ProjectLevel?) {
        isInstallingLevelDrawing = true
        defer { isInstallingLevelDrawing = false }
        clearLevelInteraction()
        routingFloorID = level?.id
        document = nil
        clearDocumentIndexesForLoading()
        renderCache.invalidateAll()
        derivedTask?.cancel(); derivedTask = nil
        applyDerivedGeometry(.empty, key: nil)
        pointDraft = PointDraft(); vertexDrag = nil; layerEditMode = .point
        loadedSVG = level?.info.svg.isEmpty == false ? level?.info.svg : nil
        let editing = level?.editing ?? LevelEditingState()
        features = editing.features; ownership = editing.ownership
        segmentation = editing.segmentation; auxiliary = editing.auxiliary
        openingGate = editing.openingGate; borrow = editing.borrow
        doorClosures = editing.doorClosures; serials = editing.serials; ids = editing.ids
        if let shared = buildingProject.sharedFootprint {
            let transform = level?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
            for feature in shared.features {
                features.insert(shared.projected(feature, transform: transform, toLevel: true))
                serials.reserve(feature.serialNumber)
                ids.adopt(feature.id, id: shared.originals[feature.id.uuidString]?["id"]?.uuid ?? feature.id)
            }
        }
        anchors = level?.info.anchors ?? AnchorStore()
        layers = LayerStore(); layers.bootstrap()
        categoryFilters = [:]
        // 층마다 저장된 category가 다르다. 앞 층에서 고른 필터가 남으면 새 층 카드가 까닭 없이 비어 보인다.
        for type in Set(features.features.map(\.featureType)).sorted(by: { $0.rawValue < $1.rawValue }) {
            _ = layers.addPropertyTypeLayer(type)
        }
    }

    func installLevelDrawing(_ prepared: PreparedLevelDrawing) {
        isInstallingLevelDrawing = true
        installPreparedIndexes(prepared)
        isInstallingLevelDrawing = false
        // Undo can restore expanded features while document is still nil.
        refreshOpenRingGaps()
        loadingLevelID = nil
        drawingLoadError = nil
        refreshCanvasReferences()
    }

    func cancelLevelDrawingLoads() {
        levelDrawingRequest = UUID()
        levelDrawingTask?.cancel(); levelDrawingTask = nil
        levelPrefetchTask?.cancel(); levelPrefetchTask = nil
        loadingLevelID = nil; drawingLoadError = nil
    }

    func beginLevelDrawingLoad(_ id: UUID?) {
        cancelLevelDrawingLoads()
        let level = buildingProject.levels.first { $0.id == id }
        installLevelMetadata(level)
        refreshCanvasReferences()
        guard let level else { return }
        let input = LevelDrawingInput(level)
        if input.svg.isEmpty {
            if let prepared = try? PreparedLevelDrawing.make(input) {
                levelDrawingCache.insert(prepared); installLevelDrawing(prepared)
            }
            prefetchAdjacentLevels(to: level.id)
            return
        }
        if let prepared = levelDrawingCache.cached(input) {
            installLevelDrawing(prepared)
            prefetchAdjacentLevels(to: level.id)
            return
        }
        loadingLevelID = level.id
        let request = levelDrawingRequest
        levelDrawingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await levelDrawingCache.load(input)
                guard !Task.isCancelled, levelDrawingRequest == request, routingFloorID == input.levelID else { return }
                guard let current = projectContents.levels.first(where: { $0.id == input.levelID }), LevelDrawingInput(current) == input else {
                    storeActiveLevel()
                    beginLevelDrawingLoad(routingFloorID); return
                }
                installLevelDrawing(prepared)
                levelDrawingTask = nil
                prefetchAdjacentLevels(to: input.levelID)
            } catch {
                guard !Task.isCancelled, levelDrawingRequest == request else { return }
                loadingLevelID = nil; levelDrawingTask = nil
                drawingLoadError = "도면을 열지 못했습니다: \(error.localizedDescription)"
                notify(drawingLoadError!, isError: true)
            }
        }
    }

    func prefetchAdjacentLevels(to id: UUID) {
        let levels = projectContents.levels.sorted { $0.info.ordinal < $1.info.ordinal }
        guard let i = levels.firstIndex(where: { $0.id == id }) else { return }
        let neighbors = [i + 1, i - 1].filter { levels.indices.contains($0) }.map { LevelDrawingInput(levels[$0]) }
        let request = levelDrawingRequest
        levelPrefetchTask = Task { [weak self] in
            guard let self else { return }
            for input in neighbors {
                guard !Task.isCancelled, levelDrawingRequest == request else { return }
                _ = try? await levelDrawingCache.load(input)
            }
        }
    }

    func waitForLevelDrawing() async {
        while let task = levelDrawingTask { await task.value }
        await canvasReferenceTask?.value
    }

    func clearLevelInteraction() {
        selection = SelectionStore(); expandedFeature = nil; faceSelection = []
        auxiliarySelection = []; focusedTwinKey = nil
        moves.reset(nil); isMoveEnabled = false; mode = .idle
        doorDraftPoints = []
        routingConnectionDrag = nil; routingSelectedNodeID = nil; routingSelectedEdgeID = nil
        routingPendingAnchor = nil; pendingDeletion = nil; pendingClearSelection = nil
        conflict = nil; exportBlockers = []; closedPolygonNotice = nil
    }

    func selectProjectLevel(_ id: UUID) {
        guard id != routingFloorID || drawingLoadError != nil, buildingProject.levels.contains(where: { $0.id == id }) else { return }
        storeActiveLevel()
        beginLevelDrawingLoad(id)
        if currentRoutingFloor?.imdfCoordinates != nil && routingTool == .calibrate { routingTool = .place }
        // The connection start is retained for stairs/elevator across Levels.
    }

    @discardableResult
    func addProjectLevel() -> UUID {
        storeActiveLevel()
        let ordinal = (buildingProject.levels.map { $0.info.ordinal }.max() ?? -1) + 1
        let info = ProjectLevelInfo(name: "\(ordinal + 1)층", ordinal: ordinal)
        perform("층 추가") {
            buildingProject.levels.append(ProjectLevel(info: info))
            beginLevelDrawingLoad(info.id)
        }
        hasCreatedProject = true
        return info.id
    }

    func removeProjectLevel(_ id: UUID) {
        guard buildingProject.levels.contains(where: { $0.id == id }) else { return }
        perform("층과 도면·노드 삭제") {
            storeActiveLevel()
            let removed = buildingProject.levels.first { $0.id == id }!
            levelDrawingCache.invalidate(id)
            var graph = routing; graph.removeFloor(id)
            buildingProject.applyRouting(graph)
            // Shared Features are indivisible. Remove only this Level reference,
            // retaining geometry/properties for their other Levels.
            for name in buildingProject.globalGeoJSON.keys {
                buildingProject.globalGeoJSON[name] = buildingProject.globalGeoJSON[name]?.compactMap { feature in
                    var value = feature
                    if var props = value["properties"], props["level_ids"]?.array.contains(where: { $0.uuid == id }) == true {
                        let remaining = props["level_ids"]!.array.filter { $0.uuid != id }
                        if remaining.isEmpty { return nil }
                        props["level_ids"] = .array(remaining); value["properties"] = props
                    }
                    return value
                }
            }
            // Footprint references must not point to a deleted Level.
            let deletedUnits = Set((removed.geoJSON["unit.geojson"] ?? []).compactMap { $0["id"]?.string?.lowercased() })
            pruneGlobalReferences(deletedUnits: deletedUnits)
            if routingFloorID == id { beginLevelDrawingLoad(buildingProject.levels.first?.id) }
            routingConnectStart = nil
        }
    }

    private func pruneGlobalReferences(deletedUnits: Set<String>) {
        for name in buildingProject.globalGeoJSON.keys {
            buildingProject.globalGeoJSON[name] = buildingProject.globalGeoJSON[name]?.map { feature in
                var value = feature
                if var props = value["properties"] {
                    if let units = props["unit_ids"] {
                        props["unit_ids"] = .array(units.array.filter { !deletedUnits.contains($0.string?.lowercased() ?? "") })
                    }
                    value["properties"] = props
                }
                return value
            }
        }
    }

    func updateProjectLevel(_ id: UUID, field: String? = nil, _ change: (inout ProjectLevelInfo) -> Void) {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == id }) else { return }
        var info = routing.floor(id)!
        change(&info)
        guard info.id == id else { notify("층 ID는 ID 적용 버튼으로 변경하세요.", isError: true); return }
        guard !buildingProject.levels.contains(where: { $0.id != id && $0.info.ordinal == info.ordinal }) else {
            notify("이미 다른 층에서 사용하는 층 번호입니다.", isError: true); return
        }
        perform("층 정보 편집", coalescingKey: field.map { "level:\(id):\($0)" }) {
            storeActiveLevel()
            let previous = buildingProject.levels[i].info
            buildingProject.levels[i].info = info
            updateLevelFeature(i, previous: previous)
            if id == routingFloorID { anchors = info.anchors }
        }
    }

    func renameProjectLevelID(_ old: UUID, to new: UUID) {
        guard new != old, let i = buildingProject.levels.firstIndex(where: { $0.id == old }) else { return }
        guard !buildingProject.levels.contains(where: { $0.id == new }) else {
            notify("이미 다른 층에서 사용하는 ID입니다.", isError: true); return
        }
        perform("층 ID 변경") {
            storeActiveLevel()
            buildingProject.levels[i].info.id = new
            for n in buildingProject.levels[i].nodes.indices { buildingProject.levels[i].nodes[n].floorID = new }
            for j in buildingProject.levels.indices {
                for name in buildingProject.levels[j].geoJSON.keys {
                    buildingProject.levels[j].geoJSON[name] = buildingProject.levels[j].geoJSON[name]?.map { rewriteLevelID($0, old: old, new: new) }
                }
            }
            for name in buildingProject.globalGeoJSON.keys {
                buildingProject.globalGeoJSON[name] = buildingProject.globalGeoJSON[name]?.map { rewriteLevelID($0, old: old, new: new) }
            }
            if routingFloorID == old { routingFloorID = new }
            levelDrawingCache.invalidate(old)
            if routingFloorID == new { beginLevelDrawingLoad(new) }
        }
    }

    func rewriteLevelID(_ feature: ProjectJSON, old: UUID, new: UUID) -> ProjectJSON {
        var value = feature
        if value["id"]?.uuid == old { value["id"] = .string(new.uuidString.lowercased()) }
        if var props = value["properties"] {
            if props["level_id"]?.uuid == old { props["level_id"] = .string(new.uuidString.lowercased()) }
            if let refs = props["level_ids"] { props["level_ids"] = .array(refs.array.map { $0.uuid == old ? .string(new.uuidString.lowercased()) : $0 }) }
            value["properties"] = props
        }
        return value
    }

    private func updateLevelFeature(_ index: Int, previous: ProjectLevelInfo) {
        let info = buildingProject.levels[index].info
        guard var feature = buildingProject.levels[index].geoJSON["level.geojson"]?.first else { return }
        var props = feature["properties"] ?? .object([:])
        if previous.ordinal != info.ordinal { props["ordinal"] = .number(Decimal(info.ordinal)) }
        // Preserve other localized languages when changing the displayed name.
        if previous.name != info.name {
            var names = props["name"]?.object ?? [:]; names["ko"] = .string(info.name)
            props["name"] = .object(names)
        }
        if previous.shortName != info.shortName, let short = info.shortName {
            var names = props["short_name"]?.object ?? [:]; names["ko"] = .string(short)
            props["short_name"] = .object(names)
        }
        feature["properties"] = props
        buildingProject.levels[index].geoJSON["level.geojson"]?[0] = feature
    }
}

extension ProjectFile {
    /// Adapter for the existing assignment merger and real pre-v5 fixtures.
    /// Normal v5 saves keep only the common Level data, without duplicate stores.
    func legacyEditorView(levelID: UUID? = nil) -> ProjectFile {
        guard let project = buildingProject,
              let level = project.levels.first(where: { $0.id == levelID }) ?? project.levels.first else { return self }
        var file = self
        file.buildingProject = nil
        file.sourceName = level.info.sourceName
        file.svg = level.info.svg; file.hasDrawing = !level.info.svg.isEmpty
        file.features = level.editing.features; file.ownership = level.editing.ownership
        file.segmentation = level.editing.segmentation; file.auxiliary = level.editing.auxiliary
        file.anchors = level.info.anchors; file.serials = level.editing.serials
        file.ids = level.editing.ids; file.openingGate = level.editing.openingGate
        file.borrow = level.editing.borrow; file.doorClosures = level.editing.doorClosures
        file.routing = project.routingGraph
        return file
    }

    /// Migrate once at the application boundary, retaining every old editor store.
    func commonProject() -> BuildingProject {
        if var buildingProject {
            buildingProject.migrateLevelFootprintsToGlobal()
            buildingProject.migrateSharedFootprint()
            return buildingProject
        }
        var project = BuildingProject()
        project.applyRouting(routing ?? RoutingGraph())
        if hasDrawing != false {
            let editing = LevelEditingState(features: features, ownership: ownership, segmentation: segmentation,
                auxiliary: auxiliary, openingGate: openingGate, borrow: borrow, doorClosures: doorClosures,
                serials: serials, ids: ids)
            if let i = project.levels.firstIndex(where: { $0.info.svg == svg }) {
                project.levels[i].editing = editing
                // Routing and old tagging sometimes used separate calibration.
                if project.levels[i].info.anchors.pairs.isEmpty { project.levels[i].info.anchors = anchors }
            } else {
                let ordinal = (project.levels.map { $0.info.ordinal }.max() ?? -1) + 1
                project.levels.append(ProjectLevel(info: ProjectLevelInfo(name: "\(ordinal + 1)층", ordinal: ordinal,
                    sourceName: sourceName, svg: svg, anchors: anchors), editing: editing))
            }
        }
        project.migrateLevelFootprintsToGlobal()
        project.migrateSharedFootprint()
        return project
    }
}
