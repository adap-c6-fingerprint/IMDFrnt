import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppEnvironment {
    var currentRoutingFloor: RoutingFloor? { activeLevel?.info ?? buildingProject.levels.first?.info }
    var selectedRoutingNode: RoutingNode? { routing.node(routingSelectedNodeID) }
    var selectedRoutingEdge: RoutingEdge? { routing.edge(routingSelectedEdgeID) }

    var routingDocument: DrawingDocument? {
        document
    }

    func enterRoutingScreen() {
        if buildingProject.levels.isEmpty { _ = addProjectLevel() }
        storeActiveLevel()
        showRoutingScreen = true
    }

    func importIMDF() {
        guard !isProjectBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "IMDF 불러오기"
        panel.message = "IMDF ZIP 또는 폴더를 선택하세요. 폴더 안의 manifest.json이나 level.geojson도 열 수 있습니다."
        panel.allowedContentTypes = [.zip, .json, UTType(filenameExtension: "geojson") ?? .json,
                                     UTType(filenameExtension: "imdf") ?? .data]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImportingIMDF = true
        let task = beginLongTask("IMDF 불러오는 중", detail: "IMDF 파일 읽는 중", fraction: nil)
        let reporter = longTaskReporter(task)
        Task {
            defer { isImportingIMDF = false; endLongTask(task) }
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try IMDFImporter.load(url)
                }.value
                updateLongTask(task, fraction: 0, detail: "\(imported.floors.count)개 층 구성 중")
                guard autosaveBeforeLeaving(action: "다른 IMDF 불러오기") else { return }
                let retainingEmptyProject = canFillEmptyProject
                let previousURL = projectURL
                var file = ProjectFile.empty()
                file.buildingProject = try BuildingProject.importing(imported)
                if retainingEmptyProject { file.projectID = projectID }
                try await adoptProjectAsync(file, from: retainingEmptyProject ? previousURL : nil, reporter: reporter)
                routingTool = .place; canvasRotation = 0; showRoutingScreen = true
                lastRecoveryProject = nil
                persist(showingBanner: false)
                notify("\(imported.sourceName) — \(imported.floors.count)개 층을 불러왔습니다. 바로 노드를 찍을 수 있습니다.")
            } catch { notify("IMDF를 불러오지 못했습니다: \(error.localizedDescription)", isError: true) }
        }
    }

    func adoptIMDF(_ imported: ImportedIMDF) throws {
        var file = ProjectFile.empty()
        file.buildingProject = try BuildingProject.importing(imported)
        let retainingEmptyProject = canFillEmptyProject
        let previousURL = projectURL
        if retainingEmptyProject { file.projectID = projectID }
        try adopt(file, from: retainingEmptyProject ? previousURL : nil)
        routingTool = .place
        canvasRotation = 0
        showRoutingScreen = true
        lastRecoveryProject = nil
    }

    func selectRoutingFloor(_ id: UUID) {
        selectProjectLevel(id)
    }

    func setRoutingTool(_ tool: RoutingTool) {
        if tool == .calibrate && currentRoutingFloor?.imdfCoordinates != nil { return }
        guard routingTool != tool else { return }
        routingTool = tool
        clearRoutingFeatureSelection()
        routingConnectionDrag = nil
        routingConnectStart = nil
        routingPendingAnchor = nil
    }

    func addRoutingFloor() {
        _ = addProjectLevel()
    }

    func removeRoutingFloor(_ id: UUID) { removeProjectLevel(id) }

    func updateRoutingFloor(_ id: UUID, field: String? = nil, _ change: (inout RoutingFloor) -> Void) {
        updateProjectLevel(id, field: field, change)
    }

    func assignRoutingLevelID(_ old: UUID, newID: UUID) { renameProjectLevelID(old, to: newID) }

    func importRoutingDrawing() {
        guard let floor = currentRoutingFloor else { return }
        let panel = NSOpenPanel()
        panel.title = "\(floor.name) 도면 불러오기"
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importDrawingAsync(at: url) }
    }

    func setRoutingDrawing(_ id: UUID, data: Data, name: String, sourceURL: URL? = nil) throws {
        let isImage = ["png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased())
        let svg = try isImage ? DrawingImageImporter.embeddedSVG(from: data)
            : DrawingImageImporter.embedLocalImages(in: data, relativeTo: sourceURL)
        let prepared = try PreparedLevelDrawing.make(LevelDrawingInput(levelID: id, svg: String(decoding: svg, as: UTF8.self), sourceName: name))
        try applyRoutingDrawing(prepared)
    }

    @discardableResult
    func applyRoutingDrawing(_ prepared: PreparedLevelDrawing) throws -> DocumentOpenResult {
        let id = prepared.input.levelID, name = prepared.input.sourceName
        guard let index = buildingProject.levels.firstIndex(where: { $0.id == id }) else { return .failed }
        let text = prepared.input.svg
        if buildingProject.levels[index].info.imdfCoordinates != nil {
            applyReferenceDrawing(prepared); return .opened
        }
        guard buildingProject.levels[index].info.svg != text else { return .opened }
        let hasWork = !projectContents.levels[index].editing.features.features.isEmpty || !routing.nodes(on: id).isEmpty
        if hasWork && !Self.isRunningSelfTests {
            let alert = NSAlert()
            alert.messageText = "\(buildingProject.levels[index].info.name)의 도면을 교체할까요?"
            alert.informativeText = "기존 SVG 태깅과 좌표 기준점은 초기화됩니다. 노드는 유지되므로 새 도면에 맞는 위치와 좌표를 확인하세요."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "교체")
            guard alert.runModal() == .alertSecondButtonReturn else { return .cancelled }
        }
        perform("층 도면 불러오기") {
            storeActiveLevel()
            buildingProject.levels[index].info.anchors = AnchorStore()
            buildingProject.levels[index].info.svg = text
            buildingProject.levels[index].info.sourceName = name
            buildingProject.levels[index].editing = LevelEditingState()
            levelDrawingCache.insert(prepared)
            if routingFloorID == id { beginLevelDrawingLoad(id) }
        }
        notify("\(name)을 \(buildingProject.levels[index].info.name)에 불러왔습니다.")
        return .opened
    }

    func nearestRoutingNode(to point: LocalPoint, tolerance: Double) -> RoutingNode? {
        routing.nodes(on: currentRoutingFloor?.id)
            .filter { $0.point.distance(to: point) <= tolerance }
            .min { $0.point.distance(to: point) < $1.point.distance(to: point) }
    }

    func nearestRoutingEdge(to point: LocalPoint, tolerance: Double) -> RoutingEdge? {
        var best: (RoutingEdge, Double)?
        for edge in visibleRoutingEdges {
            guard let a = routing.node(edge.from), let b = routing.node(edge.to),
                  a.floorID == currentRoutingFloor?.id || b.floorID == currentRoutingFloor?.id else { continue }
            if a.floorID != b.floorID {
                guard routingTool == .edges else { continue }
                let local = a.floorID == currentRoutingFloor?.id ? a : b
                let distance = point.distance(to: local.point)
                if distance <= tolerance && distance < (best?.1 ?? .infinity) { best = (edge, distance) }
                continue
            }
            let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
            let length = dx * dx + dy * dy
            guard length > 0 else { continue }
            let t = max(0, min(1, ((point.x-a.point.x)*dx + (point.y-a.point.y)*dy) / length))
            let distance = point.distance(to: LocalPoint(a.point.x+t*dx, a.point.y+t*dy))
            if distance <= tolerance && distance < (best?.1 ?? .infinity) { best = (edge, distance) }
        }
        return best?.0
    }

    func selectRoutingNode(_ id: UUID?) {
        routingFeatureCandidates = []
        routingSelectedNodeID = id
        routingSelectedEdgeID = nil
        routingSelectedEdgeIDs = []
    }

    func selectRoutingEdge(_ id: UUID?) {
        routingSelectedNodeID = nil
        routingSelectedEdgeIDs = Set(id.map { [$0] } ?? [])
        normalizeRoutingEdgeState()
    }

    /// Both Option-drag and the connection tool use the same drop behavior.
    func beginRoutingConnectionDrag(from id: UUID) {
        guard showRoutingScreen, !isImportingIMDF, let node = routing.node(id),
              node.floorID == currentRoutingFloor?.id else { return }
        routingConnectStart = nil
        selectRoutingNode(id)
        routingConnectionDrag = RoutingConnectionDrag(from: id, floorID: node.floorID, pointer: node.point)
    }

    func updateRoutingConnectionDrag(to point: LocalPoint, tolerance: Double) {
        guard var drag = routingConnectionDrag else { return }
        guard currentRoutingFloor?.id == drag.floorID, routing.node(drag.from)?.floorID == drag.floorID,
              point.x.isFinite, point.y.isFinite else { routingConnectionDrag = nil; return }
        drag.pointer = point
        let hit = nearestRoutingNode(to: point, tolerance: tolerance)
        drag.target = hit?.id == drag.from ? nil : hit?.id
        routingConnectionDrag = drag
    }

    func finishRoutingConnectionDrag(at point: LocalPoint, tolerance: Double) {
        updateRoutingConnectionDrag(to: point, tolerance: tolerance)
        guard let drag = routingConnectionDrag else { return }
        routingConnectionDrag = nil
        guard let target = drag.target else { return }
        var connected: UUID?
        perform("노드 연결") { connected = connectRoutingNodes(drag.from, target) }
        if let connected { selectRoutingEdge(connected) }
    }

    func handleRoutingClick(at point: LocalPoint, tolerance: Double, modifiers: NSEvent.ModifierFlags = []) {
        guard !isImportingIMDF, let floor = currentRoutingFloor, let doc = routingDocument,
              modifiers.intersection([.option, .control]).isEmpty else { return }
        let addingNode = modifiers.contains(.command)
        if routingTool == .featureLinks && !addingNode {
            guard !modifiers.contains(.shift) else { return }
            handleRoutingFeatureClick(at: point, tolerance: tolerance)
            return
        }
        if addingNode {
            routingConnectStart = nil
            routingPendingAnchor = nil
        }
        if routingTool == .calibrate && !addingNode {
            routingPendingAnchor = point
            return
        }
        if !addingNode, routingTool == .edges || modifiers.contains(.shift) {
            let edge = nearestRoutingEdge(to: point, tolerance: tolerance)
            selectRoutingEdge(edge?.id, additive: modifiers.contains(.shift))
            return
        }
        if let hit = nearestRoutingNode(to: point, tolerance: tolerance) {
            selectRoutingNode(hit.id)
            if routingTool == .connect && !addingNode {
                if let start = routingConnectStart {
                    guard start != hit.id else { routingConnectStart = nil; return }
                    var connected: UUID?
                    perform("노드 연결") { connected = connectRoutingNodes(start, hit.id) }
                    if let connected {
                        routingConnectStart = nil
                        selectRoutingEdge(connected)
                    } else {
                        notify("층간 연결은 같은 종류의 계단 또는 엘리베이터 노드를 선택하세요.", isError: true)
                    }
                } else { routingConnectStart = hit.id }
            }
            return
        }
        if !addingNode, routingTool == .select || routingTool == .place,
           let edge = nearestRoutingEdge(to: point, tolerance: tolerance / 2) {
            selectRoutingEdge(edge.id)
            return
        }
        if addingNode {
            guard point.x >= 0, point.y >= 0, point.x <= doc.canvasSize.width, point.y <= doc.canvasSize.height else {
                notify("도면 안에 노드를 찍어 주세요.", isError: true); return
            }
            perform("노드 추가") {
                let node = RoutingNode(floorID: floor.id, point: point)
                routing.nodes.append(node)
                selectRoutingNode(node.id)
            }
        } else {
            selectRoutingNode(nil)
            routingConnectStart = nil
        }
    }

    func moveRoutingNode(_ id: UUID, to point: LocalPoint) {
        guard let index = routing.nodes.firstIndex(where: { $0.id == id }), let doc = routingDocument,
              point.x.isFinite, point.y.isFinite else { return }
        perform("노드 이동") {
            routing.nodes[index].point = LocalPoint(max(0, min(doc.canvasSize.width, point.x)),
                                                   max(0, min(doc.canvasSize.height, point.y)))
        }
    }

    func updateRoutingNode(_ id: UUID, field: String, _ change: (inout RoutingNode) -> Void) {
        guard let index = routing.nodes.firstIndex(where: { $0.id == id }) else { return }
        perform("노드 정보 편집", coalescingKey: field == "metadata" ? nil : "node:\(id):\(field)") { change(&routing.nodes[index]) }
    }

    func updateRoutingEdge(_ id: UUID, _ change: (inout RoutingEdge) -> Void) {
        guard let index = routing.edges.firstIndex(where: { $0.id == id }) else { return }
        perform("연결 정보 편집") {
            change(&routing.edges[index])
            if routing.edges[index].category == .stairs { routing.edges[index].accessible = false }
        }
    }

    func deleteRoutingSelection() {
        if let id = routingSelectedNodeID { deleteRoutingNode(id) }
        else { deleteRoutingEdges(Set(selectedRoutingEdges.map(\.id))) }
    }

    func deleteRoutingNode(_ id: UUID) {
        guard routing.node(id) != nil else { return }
        perform("노드와 연결 삭제") {
            routing.removeNode(id)
            if routingSelectedNodeID == id { selectRoutingNode(nil) }
            normalizeRoutingEdgeState()
            if routingConnectStart == id { routingConnectStart = nil }
            if routingConnectionDrag?.from == id || routingConnectionDrag?.target == id { routingConnectionDrag = nil }
        }
    }

    func deleteRoutingEdge(_ id: UUID) {
        deleteRoutingEdges([id])
    }

    func addRoutingAnchor(longitude: Double, latitude: Double) {
        guard let point = routingPendingAnchor, let floor = currentRoutingFloor,
              longitude.isFinite, latitude.isFinite, abs(longitude) <= 180, abs(latitude) <= 90 else {
            notify("도면에 기준점을 찍고 올바른 경도·위도를 입력하세요.", isError: true); return
        }
        updateRoutingFloor(floor.id) {
            $0.anchors.add(local: point, geo: GeoPoint(longitude: longitude, latitude: latitude),
                           label: "기준점 \($0.anchors.pairs.count + 1)")
        }
        routingPendingAnchor = nil
    }

    func importRoutingLevels() {
        let panel = NSOpenPanel()
        panel.title = "클라이언트 층 목록 불러오기 (level.geojson 또는 IndoorMapDocument JSON)"
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "geojson") ?? .json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let floors = try RoutingLevelImporter.decode(Data(contentsOf: url))
            adoptRoutingLevels(floors)
            notify("클라이언트 층 \(floors.count)개를 가져왔습니다. 층별 도면을 불러오세요.")
        } catch { notify("층 목록을 읽지 못했습니다: \(error.localizedDescription)", isError: true) }
    }

    func adoptRoutingLevels(_ floors: [RoutingFloor]) {
        guard !floors.isEmpty else { return }
        perform("클라이언트 층 목록 가져오기") {
            storeActiveLevel()
            for floor in floors {
                let ordinalMatches = buildingProject.levels.filter { $0.info.ordinal == floor.ordinal }
                let uniqueOrdinal = ordinalMatches.count == 1 && floors.filter { $0.ordinal == floor.ordinal }.count == 1
                if let existing = buildingProject.levels.first(where: { $0.id == floor.id }) ?? (uniqueOrdinal ? ordinalMatches.first : nil) {
                    renameProjectLevelID(existing.id, to: floor.id)
                    updateProjectLevel(floor.id) { $0.ordinal = floor.ordinal; $0.name = floor.name }
                } else { buildingProject.levels.append(ProjectLevel(info: floor)) }
            }
            selectRoutingFloor(routing.floors.first!.id)
        }
    }

    func exportRoutingGraph() {
        do {
            let collection = try RoutingExporter.collection(routing)
            if let url = try GeoJSONExporter.write(collection, suggestedName: "routing-graph.geojson") {
                notify("\(url.lastPathComponent) — 노드 \(routing.nodes.count)개·연결 \(routing.edges.count)개 저장 완료")
            }
        } catch {
            routingExportError = error.localizedDescription
        }
    }
}

enum RoutingLevelImporter {
    static func decode(_ data: Data) throws -> [RoutingFloor] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoutingExporter.Failure(messages: ["층 목록이 JSON 객체가 아닙니다."])
        }
        let rows: [[String: Any]]
        let geoJSON: Bool
        if let levels = object["levels"] as? [[String: Any]] { rows = levels; geoJSON = false }
        else if let features = object["features"] as? [[String: Any]] {
            rows = features.filter { $0["feature_type"] as? String == "level" }; geoJSON = true
        } else { throw RoutingExporter.Failure(messages: ["level.geojson 또는 IndoorMapDocument JSON을 선택하세요."]) }
        let floors = try rows.map { row -> RoutingFloor in
            let properties = geoJSON ? (row["properties"] as? [String: Any] ?? [:]) : row
            guard let idString = row["id"] as? String, let id = UUID(uuidString: idString),
                  let ordinal = properties["ordinal"] as? Int else {
                throw RoutingExporter.Failure(messages: ["층의 UUID 또는 ordinal이 올바르지 않습니다."])
            }
            let localized = properties["name"] as? [String: String]
            let name = localized?["ko"] ?? localized?["en"] ?? properties["name"] as? String ?? "층 \(ordinal)"
            return RoutingFloor(id: id, name: name, ordinal: ordinal)
        }
        guard !floors.isEmpty, Set(floors.map(\.id)).count == floors.count else {
            throw RoutingExporter.Failure(messages: ["층 목록이 비었거나 층 ID가 중복됩니다."])
        }
        return floors.sorted { $0.ordinal < $1.ordinal }
    }
}
