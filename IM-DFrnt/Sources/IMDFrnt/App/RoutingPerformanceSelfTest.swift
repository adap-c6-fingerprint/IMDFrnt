import Foundation

@MainActor
enum RoutingPerformanceSelfTest {
    static func run(check: (String, Bool) -> Void) {
        let benchmark = CommandLine.arguments.contains("--routing-performance-only")
        let env = AppEnvironment()
        env.openSample(); env.enterRoutingScreen()
        if benchmark, let i = CommandLine.arguments.firstIndex(of: "--routing-performance-input"),
           CommandLine.arguments.indices.contains(i + 1) {
            do {
                let file = try ProjectFile.decoded(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
                try env.adopt(file, from: nil)
                env.enterRoutingScreen()
            } catch { check("#97 성능 입력 파일 읽기", false); print(error); return }
        }
        var graph = env.routing
        let floor = graph.floors[0].id
        var other = RoutingFloor(name: "다른 층", ordinal: 1)
        var anchors = AnchorStore()
        anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "a")
        anchors.add(local: LocalPoint(1_000, 0), geo: GeoPoint(longitude: 129.001, latitude: 36), label: "b")
        anchors.add(local: LocalPoint(0, 700), geo: GeoPoint(longitude: 129, latitude: 35.999), label: "c")
        env.anchors = anchors; graph.floors[0].anchors = anchors; other.anchors = anchors
        graph.floors.append(other)
        let count = benchmark ? 1_000 : 40
        graph.nodes = []
        for i in 0..<count {
            let point = LocalPoint(Double(i % 40) * 20 + 10, Double(i / 40) * 20 + 10)
            graph.nodes.append(RoutingNode(floorID: i < count - 2 ? floor : other.id, point: point))
        }
        graph.edges = (1..<count).map { i in RoutingEdge(from: graph.nodes[i - 1].id, to: graph.nodes[i].id) }
        graph.nodes[count - 3].category = "stairs"; graph.nodes[count - 2].category = "stairs"
        graph.edges[count - 3].category = .stairs; graph.edges[count - 3].accessible = false
        if !benchmark {
            graph.nodes[2].point = graph.nodes[0].point
            graph.edges.append(RoutingEdge(from: graph.nodes[0].id, to: graph.nodes[2].id))
        }
        let group = RoutingEdgeGroup(name: "검사 그룹")
        graph.edgeGroups = [group]
        for i in graph.edges.indices where i.isMultiple(of: 2) { graph.edges[i].groupID = group.id }
        env.routing = graph
        func savedData() -> Data? {
            var file = env.makeProjectFile()
            file?.savedAt = Date(timeIntervalSince1970: 0)
            return try? file?.encoded()
        }
        let data = savedData()
        let exported = try? RoutingExporter.encoded(env.routing)
        let imdf = env.projectContents.imdfFiles()
        var duplicate = graph.nodes[0]; duplicate.name = "같은 UUID의 두 번째 값"
        let repeated = RoutingGraph(nodes: [graph.nodes[0], duplicate])
        check("#97 조회 색인은 기존 첫 UUID 선택 규칙 유지", repeated.nodesByID[duplicate.id] == repeated.node(duplicate.id))
        check("#97 빈 그래프 조회", RoutingGraph().visibleEdges(on: nil, filter: .all).isEmpty)

        // 변경 전 경로를 독립 기준으로 남겨 순서·층간/필터/동률 선택까지 대조한다.
        func originalVisible() -> [RoutingEdge] {
            let graph = env.routing, floor = env.currentRoutingFloor?.id
            return graph.edges.filter {
                env.routingEdgeFilter.includes($0) &&
                (graph.node($0.from)?.floorID == floor || graph.node($0.to)?.floorID == floor)
            }
        }
        func originalNearest(_ point: LocalPoint, tolerance: Double) -> UUID? {
            var best: (UUID, Double)?
            for edge in originalVisible() {
                guard let a = env.routing.node(edge.from), let b = env.routing.node(edge.to),
                      a.floorID == env.currentRoutingFloor?.id || b.floorID == env.currentRoutingFloor?.id else { continue }
                let distance: Double
                if a.floorID != b.floorID {
                    guard env.routingTool == .edges else { continue }
                    distance = point.distance(to: (a.floorID == env.currentRoutingFloor?.id ? a : b).point)
                } else {
                    let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
                    let length = dx * dx + dy * dy
                    guard length > 0 else { continue }
                    let t = max(0, min(1, ((point.x - a.point.x) * dx + (point.y - a.point.y) * dy) / length))
                    distance = point.distance(to: LocalPoint(a.point.x + t * dx, a.point.y + t * dy))
                }
                if distance <= tolerance && distance < (best?.1 ?? .infinity) { best = (edge.id, distance) }
            }
            return best?.0
        }
        for filter in benchmark ? [] : [RoutingEdgeFilter.all, .unassigned, .group(group.id)] {
            env.routingEdgeFilter = filter
            check("#97 필터·층간 엣지 순서 유지", env.visibleRoutingEdges == originalVisible())
            for tool in [RoutingTool.select, .edges] {
                env.routingTool = tool
                let points = [LocalPoint(20, 10), graph.nodes[count - 3].point, LocalPoint(-100, -100)]
                check("#97 최근접 엣지·층간 핀·빈 공간 선택 유지", points.allSatisfy {
                    env.nearestRoutingEdge(to: $0, tolerance: 5)?.id == originalNearest($0, tolerance: 5)
                })
            }
        }
        env.routingEdgeFilter = .all
        let target = LocalPoint(20, 10)
        if benchmark {
            func measure(_ name: String, _ operation: () -> UUID?) -> UUID? {
                let start = Date.timeIntervalSinceReferenceDate
                let result = operation()
                print(String(format: "[PERF #97] %@: %.3f ms (%d nodes / %d edges)",
                             name, (Date.timeIntervalSinceReferenceDate - start) * 1_000, graph.nodes.count, graph.edges.count))
                return result
            }
            let original = measure("original nearest edge", { originalNearest(target, tolerance: 5) })
            let current = measure("current nearest edge", { env.nearestRoutingEdge(to: target, tolerance: 5)?.id })
            check("#97 성능 비교의 선택 결과 일치", original == current)
        }
        check("#97 조회만으로 저장 데이터 불변 (저장 시각 제외)", data != nil && savedData() == data)
        check("#97 조회만으로 그래프 출력 불변", exported != nil && (try? RoutingExporter.encoded(env.routing)) == exported)
        check("#97 조회만으로 원본 IMDF 불변", env.projectContents.imdfFiles() == imdf)
        let before = env.routing
        env.moveRoutingNode(graph.nodes[0].id, to: LocalPoint(80, 80))
        check("#97 이동 후 최신 좌표로 히트테스트", env.nearestRoutingNode(to: LocalPoint(80, 80), tolerance: 1)?.id == graph.nodes[0].id)
        env.undo()
        check("#97 이동 Undo는 전체 그래프 복원", env.routing == before)
        env.redo()
        check("#97 이동 Redo는 최신 좌표 복원", env.routing.node(graph.nodes[0].id)?.point == LocalPoint(80, 80))
    }
}
