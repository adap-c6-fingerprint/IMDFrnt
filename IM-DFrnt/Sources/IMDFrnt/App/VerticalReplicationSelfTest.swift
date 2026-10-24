import Foundation

/// 신기능 13항(B안) — 기준 노드의 층별 복제: 같은 실제 좌표·카테고리 유지, 엘리베이터만 연결, 반복 실행 중복 방지.
@MainActor
enum VerticalReplicationSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func floor(_ name: String, _ ordinal: Int, scale: Double = 1, calibrated: Bool = true) -> RoutingFloor {
            var info = RoutingFloor(name: name, ordinal: ordinal)
            guard calibrated else { return info }
            // 층마다 도면 크기가 달라도 같은 위경도가 나오도록 축척만 다르게 둔다.
            for (local, geo) in [(LocalPoint(0, 0), GeoPoint(longitude: 129.0, latitude: 36.0)),
                                 (LocalPoint(1000 * scale, 0), GeoPoint(longitude: 129.001, latitude: 36.0)),
                                 (LocalPoint(0, 700 * scale), GeoPoint(longitude: 129.0, latitude: 35.999))] {
                info.anchors.add(local: local, geo: geo, label: "기준")
            }
            return info
        }
        let f1 = floor("1층", 0), f2 = floor("2층", 1, scale: 2), f3 = floor("3층", 2), nocoord = floor("4층", 3, calibrated: false)
        var graph = RoutingGraph()
        graph.floors = [f1, f2, f3, nocoord]

        let geo = GeoPoint(longitude: 129.0004, latitude: 35.9995)
        let local1 = f1.localPoint(for: geo)
        check("기준점 좌표 변환 왕복(도면→위경도→도면)", local1 != nil &&
              f1.geoPoint(for: local1!).map { abs($0.longitude - geo.longitude) < 1e-9 && abs($0.latitude - geo.latitude) < 1e-9 } == true)

        let elevator = RoutingNode(floorID: f1.id, point: local1!, name: "엘리베이터 A", category: "elevator", metadataJSON: "{\"k\":1}")
        graph.nodes = [elevator]
        let result = graph.replicateVerticalNode(elevator.id)
        let copies = graph.nodes.filter { $0.id != elevator.id }
        check("모든 층에 노드 생성(좌표 없는 층은 건너뜀)", result?.created.count == 2 && result?.skipped == [nocoord.id] && copies.count == 2)
        check("복제 노드는 같은 실제 좌표", copies.allSatisfy { node in
            guard let fl = graph.floor(node.floorID), let g = fl.geoPoint(for: node.point) else { return false }
            return abs(g.longitude - geo.longitude) < 1e-9 && abs(g.latitude - geo.latitude) < 1e-9
        })
        check("층마다 도면 좌표는 다르다(축척 2배 층)", graph.nodes.first { $0.floorID == f2.id }.map {
            abs($0.point.x - local1!.x * 2) < 1e-6 } == true)
        check("카테고리·이름·메타데이터 유지, 새 UUID·층 참조", copies.allSatisfy {
            $0.category == "elevator" && $0.name == "엘리베이터 A" && $0.metadataJSON == "{\"k\":1}" && $0.id != elevator.id
        } && Set(copies.map(\.floorID)) == [f2.id, f3.id])
        check("같은 시설 묶음 열쇠 공유", Set(graph.nodes.map(\.verticalGroupID)).count == 1 && graph.nodes[0].verticalGroupID != nil)
        check("엘리베이터는 이웃한 층끼리 연결", graph.edges.count == 2 && graph.edges.allSatisfy { $0.category == .elevator && $0.accessible })

        let snapshot = graph
        let again = graph.replicateVerticalNode(elevator.id)
        check("반복 실행해도 노드·연결 중복 없음", graph == snapshot && again?.created.isEmpty == true && again?.existing.count == 2)

        // 사람이 옮겨 둔 위치는 덮어쓰지 않는다.
        let moved = graph.nodes.firstIndex { $0.floorID == f3.id }!
        graph.nodes[moved].point = LocalPoint(graph.nodes[moved].point.x + 30, graph.nodes[moved].point.y)
        let movedPoint = graph.nodes[moved].point
        _ = graph.replicateVerticalNode(elevator.id)
        check("사용자가 보정한 위치 유지", graph.nodes[moved].point == movedPoint && graph.nodes.count == 3)

        // 서로 다른 시설은 카테고리가 같아도 연결되지 않는다.
        let other = RoutingNode(floorID: f1.id, point: LocalPoint(10, 10), category: "elevator")
        graph.nodes.append(other)
        _ = graph.replicateVerticalNode(other.id, to: [f2.id])
        let otherCopy = graph.nodes.first { $0.floorID == f2.id && $0.verticalGroupID == graph.node(other.id)?.verticalGroupID }
        check("다른 엘리베이터군은 섞어 연결하지 않음", otherCopy != nil &&
              graph.connections(of: other.id).allSatisfy { $0.from == otherCopy!.id || $0.to == otherCopy!.id } &&
              graph.edges.filter { $0.from == otherCopy!.id || $0.to == otherCopy!.id }.count == 1 &&
              graph.verticalGroup(elevator.verticalGroupID ?? graph.node(elevator.id)!.verticalGroupID!).count == 3)

        // 일부 층만 복제하고 나중에 다른 층을 추가해도 모든 층의 묶음이 이어진다.
        var partial = RoutingGraph()
        partial.floors = [f1, f2, f3]
        let base = RoutingNode(floorID: f1.id, point: local1!, category: "elevator")
        partial.nodes = [base]
        _ = partial.replicateVerticalNode(base.id, to: [f2.id])
        _ = partial.replicateVerticalNode(base.id, to: [f3.id])
        check("일부 층 복제 후 나머지 층 추가", partial.nodes.count == 3 && partial.edges.count == 2 && partial.componentCount == 1)

        // 이미 같은 자리에 사람이 찍은 노드는 옮기지 않고 같은 시설로만 묶는다.
        var manual = RoutingGraph()
        manual.floors = [f1, f2]
        let m1 = RoutingNode(floorID: f1.id, point: local1!, category: "elevator")
        let m2 = RoutingNode(floorID: f2.id, point: f2.localPoint(for: geo)!, name: "수동", category: "elevator")
        manual.nodes = [m1, m2]
        let r = manual.replicateVerticalNode(m1.id)
        check("같은 자리의 수동 노드는 새로 만들지 않고 묶기만 함", manual.nodes.count == 2 && r?.created.isEmpty == true &&
              manual.node(m2.id)?.name == "수동" && manual.node(m2.id)?.point == m2.point &&
              manual.node(m2.id)?.verticalGroupID == manual.node(m1.id)?.verticalGroupID && manual.edges.count == 1)

        // 계단·에스컬레이터: 노드만 복제하고 층간 연결 없음.
        for category in ["stairs", "escalator"] {
            var g = RoutingGraph()
            g.floors = [f1, f2, f3]
            let s = RoutingNode(floorID: f1.id, point: local1!, category: category)
            g.nodes = [s]
            let res = g.replicateVerticalNode(s.id)
            check("\(category): 모든 층에 노드 생성·층간 연결 없음", res?.created.count == 2 && g.edges.isEmpty &&
                  g.nodes.allSatisfy { $0.category == category })
        }
        var plain = RoutingGraph()
        plain.floors = [f1, f2]
        let w = RoutingNode(floorID: f1.id, point: local1!, category: "waypoint")
        plain.nodes = [w]
        check("수직 시설이 아닌 노드는 복제하지 않음", plain.replicateVerticalNode(w.id) == nil && plain.nodes.count == 1)
        check("에스컬레이터 카테고리 지원·층간 연결 불가", RoutingNodeCategory(rawValue: "escalator")?.isVertical == true &&
              RoutingNodeCategory.escalator.title == "에스컬레이터")

        // 저장·내보내기: 묶음 열쇠가 유지되고 이전 파일(열쇠 없음)도 읽힌다.
        do {
            let data = try JSONEncoder().encode(partial.nodes)
            let decoded = try JSONDecoder().decode([RoutingNode].self, from: data)
            check("저장·재열기에서 UUID·층 참조·묶음 열쇠 보존", decoded == partial.nodes)
            var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
            legacy.removeValue(forKey: "verticalGroupID")
            let old = try JSONDecoder().decode(RoutingNode.self, from: JSONSerialization.data(withJSONObject: legacy))
            check("묶음 열쇠가 없는 이전 노드도 읽힘", old.verticalGroupID == nil && old.id == base.id)
            let exported = try RoutingExporter.collection(partial)
            let features = (exported["features"] as? [[String: Any]]) ?? []
            let groups = Set(features.compactMap { ($0["properties"] as? [String: Any])?["vertical_group_id"] as? String })
            check("길찾기 내보내기에 vertical_group_id 포함", groups.count == 1 && features.filter { ($0["properties"] as? [String: Any])?["role"] as? String == "edge" }.count == 2)
        } catch { check("저장·내보내기 검사", false); print(error) }

        // 환경: 복제와 연결이 한 번의 실행취소로 되돌아간다.
        let env = AppEnvironment()
        env.routing = partialStart(f1, f2, f3, local1!)
        let before = env.routing
        let id = env.routing.nodes[0].id
        _ = env.replicateVerticalNode(id)
        check("환경 복제: 노드 3개·연결 2개", env.routing.nodes.count == 3 && env.routing.edges.count == 2)
        env.undo()
        check("실행취소 한 번으로 복제 전체 복원", env.routing == before)
        env.redo()
        check("다시 실행으로 복제 재적용", env.routing.nodes.count == 3 && env.routing.edges.count == 2)
    }

    private static func partialStart(_ a: RoutingFloor, _ b: RoutingFloor, _ c: RoutingFloor, _ p: LocalPoint) -> RoutingGraph {
        var g = RoutingGraph()
        g.floors = [a, b, c]
        g.nodes = [RoutingNode(floorID: a.id, point: p, category: "elevator")]
        return g
    }
}
