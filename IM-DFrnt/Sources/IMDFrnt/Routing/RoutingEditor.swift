import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppEnvironment {
    var currentRoutingFloor: RoutingFloor? { routing.floor(routingFloorID) ?? routing.floors.first }
    var selectedRoutingNode: RoutingNode? { routing.node(routingSelectedNodeID) }
    var selectedRoutingEdge: RoutingEdge? { routing.edge(routingSelectedEdgeID) }

    var routingDocument: DrawingDocument? {
        guard let floor = currentRoutingFloor, !floor.svg.isEmpty else { return nil }
        if let cached = routingDrawingCache[floor.id], cached.0 == floor.svg { return cached.1 }
        guard let doc = try? SVGParser.parse(data: Data(floor.svg.utf8), sourceName: floor.sourceName) else { return nil }
        routingDrawingCache[floor.id] = (floor.svg, doc)
        return doc
    }

    func enterRoutingScreen() {
        if routing.floors.isEmpty, let doc = document, let svg = loadedSVGText {
            perform("길찾기 작업 시작") {
                let floor = RoutingFloor(name: "1층", ordinal: 0, sourceName: doc.sourceName,
                                         svg: svg, anchors: anchors)
                routing.floors.append(floor)
                routingFloorID = floor.id
            }
        }
        routingFloorID = currentRoutingFloor?.id
        showRoutingScreen = true
    }

    func importIMDF() {
        guard !isImportingIMDF else { return }
        let panel = NSOpenPanel()
        panel.title = "IMDF 불러오기"
        panel.message = "IMDF ZIP 또는 폴더를 선택하세요. 폴더 안의 manifest.json이나 level.geojson도 열 수 있습니다."
        panel.allowedContentTypes = [.zip, .json, UTType(filenameExtension: "geojson") ?? .json,
                                     UTType(filenameExtension: "imdf") ?? .data]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImportingIMDF = true
        Task {
            defer { isImportingIMDF = false }
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try IMDFImporter.load(url)
                }.value
                try adoptIMDF(imported)
                notify("\(imported.sourceName) — \(imported.floors.count)개 층을 불러왔습니다. 바로 노드를 찍을 수 있습니다.")
            } catch { notify("IMDF를 불러오지 못했습니다: \(error.localizedDescription)", isError: true) }
        }
    }

    func adoptIMDF(_ imported: ImportedIMDF) throws {
        guard let first = imported.floors.first else { throw IMDFImporter.Failure(message: "IMDF에 층이 없습니다.") }
        var graph = RoutingGraph()
        graph.imdfSourceName = imported.sourceName
        graph.layoutVersion = imported.layoutVersion
        graph.floors = imported.floors.map {
            RoutingFloor(id: $0.id, name: $0.name, ordinal: $0.ordinal,
                         sourceName: imported.sourceName, svg: $0.svg,
                         imdfCoordinates: imported.coordinates)
        }
        // Open as a separate project so Save cannot overwrite an earlier source drawing project.
        var file = ProjectFile(sourceName: imported.sourceName, svg: first.svg,
            features: FeatureStore(), ownership: OwnershipRegistry(), segmentation: SegmentationStore(),
            auxiliary: AuxiliaryStore(), anchors: AnchorStore(), serials: SerialNumberAllocator(),
            ids: IDAssigner(), openingGate: OpeningGateStore(), borrow: BorrowRegistry())
        file.routing = graph
        try adopt(file, from: nil)
        routingTool = .place
        canvasRotation = 0
        showRoutingScreen = true
        lastSavedSnapshot = nil
    }

    func selectRoutingFloor(_ id: UUID) {
        guard routing.floor(id) != nil else { return }
        routingFloorID = id
        routingConnectionDrag = nil
        routingSelectedNodeID = nil
        routingSelectedEdgeID = nil
        routingPendingAnchor = nil
        if currentRoutingFloor?.imdfCoordinates != nil && routingTool == .calibrate { routingTool = .place }
        // Keep the first connection endpoint while the user changes floors.
    }

    func setRoutingTool(_ tool: RoutingTool) {
        if tool == .calibrate && currentRoutingFloor?.imdfCoordinates != nil { return }
        guard routingTool != tool else { return }
        routingTool = tool
        routingConnectionDrag = nil
        routingConnectStart = nil
        routingPendingAnchor = nil
    }

    func addRoutingFloor() {
        let ordinal = (routing.floors.map(\.ordinal).max() ?? -1) + 1
        perform("층 추가") {
            let floor = RoutingFloor(name: "\(ordinal + 1)층", ordinal: ordinal)
            routing.floors.append(floor)
            selectRoutingFloor(floor.id)
        }
    }

    func removeRoutingFloor(_ id: UUID) {
        perform("층과 길찾기 노드 삭제") {
            routing.removeFloor(id)
            routingConnectStart = nil
            routingConnectionDrag = nil
            routingSelectedNodeID = nil
            routingSelectedEdgeID = nil
            routingFloorID = routing.floors.first?.id
        }
    }

    func updateRoutingFloor(_ id: UUID, field: String? = nil, _ change: (inout RoutingFloor) -> Void) {
        guard let index = routing.floors.firstIndex(where: { $0.id == id }) else { return }
        perform("층 정보 편집", coalescingKey: field.map { "floor:\(id):\($0)" }) { change(&routing.floors[index]) }
    }

    func assignRoutingLevelID(_ old: UUID, newID: UUID) {
        guard old == newID || routing.floor(newID) == nil else {
            notify("이미 다른 층에서 사용하는 ID입니다.", isError: true); return
        }
        guard let index = routing.floors.firstIndex(where: { $0.id == old }) else { return }
        perform("클라이언트 층 ID 지정") {
            routing.floors[index].id = newID
            for i in routing.nodes.indices where routing.nodes[i].floorID == old { routing.nodes[i].floorID = newID }
            routingFloorID = newID
        }
    }

    func importRoutingDrawing() {
        guard let floor = currentRoutingFloor else { return }
        let panel = NSOpenPanel()
        panel.title = "\(floor.name) 도면 불러오기"
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try setRoutingDrawing(floor.id, data: Data(contentsOf: url), name: url.lastPathComponent, sourceURL: url)
        } catch { notify("도면을 불러오지 못했습니다: \(error.localizedDescription)", isError: true) }
    }

    func setRoutingDrawing(_ id: UUID, data: Data, name: String, sourceURL: URL? = nil) throws {
        let isImage = ["png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased())
        let svg = try isImage ? DrawingImageImporter.embeddedSVG(from: data)
            : DrawingImageImporter.embedLocalImages(in: data, relativeTo: sourceURL)
        let doc = try SVGParser.parse(data: svg, sourceName: name)
        guard let index = routing.floors.firstIndex(where: { $0.id == id }) else { return }
        // Replacing a drawing removes its old coordinate calibration; existing nodes remain editable.
        perform("층 도면 불러오기") {
            if routing.floors[index].svg != String(decoding: svg, as: UTF8.self) {
                routing.floors[index].anchors = AnchorStore()
                routing.floors[index].imdfCoordinates = nil
            }
            routing.floors[index].svg = String(decoding: svg, as: UTF8.self)
            routing.floors[index].sourceName = name
            routingPendingAnchor = nil
        }
        routingDrawingCache[id] = (String(decoding: svg, as: UTF8.self), doc)
        notify("\(name)을 \(routing.floors[index].name)에 불러왔습니다.")
    }

    func nearestRoutingNode(to point: LocalPoint, tolerance: Double) -> RoutingNode? {
        routing.nodes(on: currentRoutingFloor?.id)
            .filter { $0.point.distance(to: point) <= tolerance }
            .min { $0.point.distance(to: point) < $1.point.distance(to: point) }
    }

    func nearestRoutingEdge(to point: LocalPoint, tolerance: Double) -> RoutingEdge? {
        var best: (RoutingEdge, Double)?
        for edge in routing.edges {
            guard let a = routing.node(edge.from), let b = routing.node(edge.to),
                  a.floorID == currentRoutingFloor?.id, b.floorID == a.floorID else { continue }
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
        routingSelectedNodeID = id
        routingSelectedEdgeID = nil
    }

    func selectRoutingEdge(_ id: UUID?) {
        routingSelectedNodeID = nil
        routingSelectedEdgeID = id
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
        perform("노드 연결") { connected = routing.connect(drag.from, target) }
        if let connected { selectRoutingEdge(connected) }
    }

    func handleRoutingClick(at point: LocalPoint, tolerance: Double, modifiers: NSEvent.ModifierFlags = []) {
        guard !isImportingIMDF, let floor = currentRoutingFloor, let doc = routingDocument,
              modifiers.intersection([.option, .control]).isEmpty else { return }
        let addingNode = modifiers.contains(.command)
        if addingNode {
            routingConnectStart = nil
            routingPendingAnchor = nil
        }
        if routingTool == .calibrate && !addingNode {
            routingPendingAnchor = point
            return
        }
        if let hit = nearestRoutingNode(to: point, tolerance: tolerance) {
            selectRoutingNode(hit.id)
            if routingTool == .connect && !addingNode {
                if let start = routingConnectStart {
                    guard start != hit.id else { routingConnectStart = nil; return }
                    var connected: UUID?
                    perform("노드 연결") { connected = routing.connect(start, hit.id) }
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
        if let id = routingSelectedNodeID {
            perform("노드와 연결 삭제") {
                routing.removeNode(id)
                selectRoutingNode(nil)
                if routingConnectStart == id { routingConnectStart = nil }
                if routingConnectionDrag?.from == id || routingConnectionDrag?.target == id { routingConnectionDrag = nil }
            }
        } else if let id = routingSelectedEdgeID {
            perform("연결 삭제") {
                routing.edges.removeAll { $0.id == id }
                routingSelectedEdgeID = nil
            }
        }
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
            for floor in floors {
                if let i = routing.floors.firstIndex(where: { $0.id == floor.id || $0.ordinal == floor.ordinal }) {
                    let oldID = routing.floors[i].id
                    routing.floors[i].id = floor.id
                    routing.floors[i].ordinal = floor.ordinal
                    routing.floors[i].name = floor.name
                    for n in routing.nodes.indices where routing.nodes[n].floorID == oldID { routing.nodes[n].floorID = floor.id }
                } else { routing.floors.append(floor) }
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
        guard !floors.isEmpty, Set(floors.map(\.id)).count == floors.count,
              Set(floors.map(\.ordinal)).count == floors.count else {
            throw RoutingExporter.Failure(messages: ["층 목록이 비었거나 층 ID·번호가 중복됩니다. 한 건물의 층 목록을 사용하세요."])
        }
        return floors.sorted { $0.ordinal < $1.ordinal }
    }
}
