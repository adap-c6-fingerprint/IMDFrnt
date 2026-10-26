import AppKit
import Foundation

/// 빈 층에 다른 `.imdfrnt`의 층 하나를 넣는다(#31, 2026-10-20).
///
/// 새 층을 만들고 `.imdfrnt 불러오기`를 누르면 예전에는 프로젝트가 통째로 전환됐다.
/// 다른 곳에서 한 층만 따로 작업한 파일을 이 건물에 붙이려는 것이므로, **지금 층이 비어 있고
/// 다른 층에 작업이 있으면** 프로젝트를 바꾸지 않고 그 층에 넣는다.
@MainActor
extension AppEnvironment {

    /// 도면·태깅·좌표·노드가 하나도 없는 층. 이름과 층 번호만 있다.
    static func isBlankLevel(_ level: ProjectLevel) -> Bool {
        level.info.svg.isEmpty && level.info.imdfCoordinates == nil && level.info.anchors.pairs.isEmpty
            && level.geoJSON.isEmpty && level.nodes.isEmpty && level.referenceDrawing == nil
            && level.editing.features.features.isEmpty
    }

    /// `.imdfrnt 불러오기`가 프로젝트 전환 대신 지금 층에 넣기로 동작하는가.
    /// 모든 층이 비어 있으면(막 만든 프로젝트) 전환과 다를 것이 없어 예전처럼 연다.
    var importsProjectIntoActiveLevel: Bool {
        let levels = projectContents.levels
        guard let active = levels.first(where: { $0.id == routingFloorID }), Self.isBlankLevel(active) else { return false }
        return levels.contains { $0.id != active.id && !Self.isBlankLevel($0) }
    }

    func importProjectLevel(from url: URL) async {
        guard !isProjectBusy, let target = activeLevel else { return }
        isProjectActionInProgress = true
        let task = beginLongTask("층 불러오는 중", detail: url.deletingPathExtension().lastPathComponent, fraction: nil)
        defer { isProjectActionInProgress = false; endLongTask(task) }
        do {
            let project = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let project = try ProjectFile.decoded(from: Data(contentsOf: url)).commonProject()
                try project.validate()
                return project
            }.value
            let candidates = project.levels.filter { !Self.isBlankLevel($0) }.sorted { $0.info.ordinal < $1.info.ordinal }
            guard !candidates.isEmpty else {
                notify("‘\(url.lastPathComponent)’에 작업된 층이 없습니다.", isError: true); return
            }
            endLongTask(task)
            // 층 고르기 창이 진행률 팝업에 가리지 않게 먼저 닫는다.
            guard let source = chooseSourceLevel(candidates, for: target, fileName: url.lastPathComponent) else { return }
            let prepared = try await Task.detached(priority: .userInitiated) {
                try PreparedLevelDrawing.make(LevelDrawingInput(levelID: target.id, svg: source.info.svg, sourceName: source.info.sourceName))
            }.value
            guard importLevel(source, into: target.id, drawing: prepared, metadata: project) else { return }
            persist(showingBanner: false)
            notify("‘\(url.deletingPathExtension().lastPathComponent)’의 \(source.info.name)을 \(target.info.name)에 넣었습니다.")
        } catch {
            notify("층을 불러오지 못했습니다: \(error.localizedDescription)", isError: true)
        }
    }

    /// 파일에 작업된 층이 하나면 그대로, 여럿이면 묻는다. 이름이 같은 층을 먼저 고른 채 보여준다.
    private func chooseSourceLevel(_ candidates: [ProjectLevel], for target: ProjectLevel, fileName: String) -> ProjectLevel? {
        if candidates.count == 1 || Self.isRunningSelfTests { return candidates.first }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItems(withTitles: candidates.map(\.info.name))
        popup.selectItem(at: candidates.firstIndex { $0.info.name == target.info.name } ?? 0)
        let alert = NSAlert()
        alert.messageText = "‘\(fileName)’의 어느 층을 \(target.info.name)에 넣을까요?"
        alert.informativeText = "고른 층의 도면·태깅·anchor·지도 정렬·노드가 \(target.info.name)에 들어갑니다. 층 이름과 층 번호는 그대로입니다."
        alert.accessoryView = popup
        alert.addButton(withTitle: "넣기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return candidates[popup.indexOfSelectedItem]
    }

    /// 층 내용을 `targetID` 층에 옮긴다. 층 ID·이름·층 번호는 지금 층 것을 유지한다.
    /// 다른 층과 잇는 연결은 이 건물에 그 층이 없으니 가져오지 않는다.
    @discardableResult
    func importLevel(_ original: ProjectLevel, into targetID: UUID, drawing: PreparedLevelDrawing? = nil,
                     metadata originalMetadata: BuildingProject? = nil) -> Bool {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == targetID }) else { return false }
        // Validate the complete metadata merge before touching the floor, undo stack or drawing cache.
        let source: ProjectLevel
        let metadata: BuildingProject?
        let mergedRecords: [String: [ProjectJSON]]?
        do {
            let prepared = try LevelImportIdentity.prepare(original, targetID: targetID,
                project: projectContents, metadata: originalMetadata)
            source = prepared.level; metadata = prepared.metadata
            mergedRecords = try metadata.map { try prepareLevelMetadata($0, source: source, targetID: targetID) }
        }
        catch {
            notify("층을 가져오지 않았습니다: \(error.localizedDescription)", isError: true)
            return false
        }
        let existingNodes = Set(projectContents.levels.flatMap(\.nodes).map(\.id))
        let existingEdges = Set(projectContents.levels.flatMap(\.edges).map(\.id) + buildingProject.crossLevelEdges.map(\.id))
        let collides = source.nodes.contains { existingNodes.contains($0.id) } || source.edges.contains { existingEdges.contains($0.id) }
        // 같은 건물 사본에서 온 파일이면 노드 ID가 겹칠 수 있다. 겹치면 새 ID로 바꾸고 연결도 따라 바꾼다.
        let nodeID = Dictionary(uniqueKeysWithValues: source.nodes.map { ($0.id, collides ? UUID() : $0.id) })
        let nodes = source.nodes.map { n -> RoutingNode in
            var n = n; n.id = nodeID[n.id]!; n.floorID = targetID; return n
        }
        let edges = source.edges.compactMap { e -> RoutingEdge? in
            guard let from = nodeID[e.from], let to = nodeID[e.to] else { return nil }
            var e = e; e.from = from; e.to = to
            if collides { e.id = UUID() }
            return e
        }

        perform("\(buildingProject.levels[i].info.name)에 층 불러오기") {
            storeActiveLevel()
            var level = source
            level.info.id = targetID
            level.info.name = buildingProject.levels[i].info.name
            level.info.ordinal = buildingProject.levels[i].info.ordinal
            level.info.shortName = buildingProject.levels[i].info.shortName
            level.nodes = nodes
            level.edges = edges
            if source.id != targetID {
                for name in level.geoJSON.keys {
                    level.geoJSON[name] = level.geoJSON[name]?.map { rewriteLevelID($0, old: source.id, new: targetID) }
                }
            }
            // IMDF에서 온 층은 GeoJSON이 원래 층 ID를 가리킨다. 지금 층 ID로 바꿔야 내보낼 때 어긋나지 않는다.
            buildingProject.levels[i] = level
            if let metadata, let mergedRecords {
                mergeLevelMetadata(metadata, source: source, targetID: targetID, records: mergedRecords)
            }
            levelDrawingCache.invalidate(targetID)
            if let drawing { levelDrawingCache.insert(drawing) }
            if routingFloorID == targetID { beginLevelDrawingLoad(targetID) }
        }
        if let j = buildingProject.levels.firstIndex(where: { $0.id == targetID }) {
            buildingProject.levels[j].lastEdited = source.lastEdited
        }
        // 불러오면서 feature가 새로 생겨 '지금 고친 것'으로 찍힌다. 불러오기는 고친 것이 아니니 원래 시각으로 돌린다.
        return true
    }

    /// A single-floor import must bring the common records that its old floor-owned metadata now
    /// references. Do not guess that equal names/addresses mean equal IDs or overwrite the target Venue.
    private func prepareLevelMetadata(_ project: BuildingProject, source: ProjectLevel,
                                      targetID: UUID) throws -> [String: [ProjectJSON]] {
        var merged = buildingProject.globalGeoJSON
        var known: [UUID: ProjectJSON] = [:]
        for record in merged.values.flatMap({ $0 }) {
            if let id = record["id"]?.uuid { known[id] = record }
        }
        let target = projectContents
        let copiesVenue = target.globalGeoJSON["venue.geojson"]?.isEmpty != false
            && !target.levels.filter { $0.id != targetID }.contains { !$0.editing.features.features(ofType: .venue).isEmpty }
            && source.editing.features.features(ofType: .venue).isEmpty
        let selected = LevelImportMetadata.records(in: project, source: source, targetID: targetID,
            includingVenue: copiesVenue, includingFootprint: target.sharedFootprint == nil)
        for name in ["address.geojson", "building.geojson", "occupant.geojson", "relationship.geojson"] {
            for original in selected[name] ?? [] {
                let value = rewriteLevelID(original, old: source.id, new: targetID)
                guard let id = value["id"]?.uuid else {
                    throw IMDFImporter.Failure(message: "\(name): 공통 정보에 유효한 UUID가 없습니다.")
                }
                if var existing = known[id] {
                    // UUID spelling is case-insensitive, while all other content must agree.
                    var candidate = value
                    existing["id"] = .string(id.uuidString.lowercased())
                    candidate["id"] = existing["id"]
                    guard existing == candidate else {
                        throw IMDFImporter.Failure(message: "\(name) · \(id.uuidString.lowercased()): 같은 UUID의 공통 정보 내용이 다릅니다. 두 프로젝트의 값을 일치시킨 뒤 다시 가져오세요.")
                    }
                    continue
                }
                known[id] = value
                merged[name, default: []].append(value)
            }
        }
        return merged
    }

    private func mergeLevelMetadata(_ project: BuildingProject, source: ProjectLevel, targetID: UUID,
                                    records: [String: [ProjectJSON]]) {
        buildingProject.globalGeoJSON = records
        if buildingProject.globalGeoJSON["venue.geojson"]?.isEmpty != false,
           !buildingProject.levels.contains(where: { !$0.editing.features.features(ofType: .venue).isEmpty }) {
            buildingProject.globalGeoJSON["venue.geojson"] = project.globalGeoJSON["venue.geojson"]
        }
        if buildingProject.sharedFootprint == nil, var shared = project.sharedFootprint {
            if shared.sourceLevelID == source.id { shared.sourceLevelID = targetID }
            buildingProject.sharedFootprint = shared
            buildingProject.globalGeoJSON["footprint.geojson"] = project.globalGeoJSON["footprint.geojson"]
        }
        var conflicts: [String: ProjectJSON] = [:]
        for (key, value) in project.manifest.object where !["version", "created"].contains(key) {
            if let current = buildingProject.manifest[key], current != .null, current != value { conflicts[key] = value }
            else { buildingProject.manifest[key] = value }
        }
        if !conflicts.isEmpty {
            conflicts["imdfrnt_source_level"] = .string(source.info.name)
            let copy = ProjectJSON.object(conflicts)
            if !(buildingProject.legacyManifests ?? []).contains(copy) {
                buildingProject.legacyManifests = (buildingProject.legacyManifests ?? []) + [copy]
                buildingProject.manifestConflictsResolved = false
            }
        }
    }
}
