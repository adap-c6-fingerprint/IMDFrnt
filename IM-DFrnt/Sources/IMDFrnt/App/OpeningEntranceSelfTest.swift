import Foundation

/// 신기능 14항(#69): opening 중앙 출입구 노드 자동 배치 검사.
@MainActor
enum OpeningEntranceSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func near(_ a: LocalPoint?, _ b: LocalPoint, _ tolerance: Double = 1e-9) -> Bool {
            guard let a else { return false }
            return a.distance(to: b) < tolerance
        }
        // 기하 기준: 두 점은 중점, 여러 선분은 길이 기준 중간점.
        check("두 점 선의 중앙은 중점", near(OpeningEntrancePlacer.midpoint(of: [LocalPoint(0, 0), LocalPoint(10, 4)]), LocalPoint(5, 2)))
        let bent = [LocalPoint(0, 0), LocalPoint(10, 0), LocalPoint(10, 2)]
        check("여러 선분은 길이 기준 중간점(꺾임 있어도)", near(OpeningEntrancePlacer.midpoint(of: bent), LocalPoint(6, 0)))
        check("점 나열 방향을 뒤집어도 같은 중앙", near(OpeningEntrancePlacer.midpoint(of: bent.reversed()), LocalPoint(6, 0)))
        let angle = 0.7, scale = 3.0
        func transform(_ p: LocalPoint) -> LocalPoint {
            LocalPoint(scale * (p.x * cos(angle) - p.y * sin(angle)) + 40, scale * (p.x * sin(angle) + p.y * cos(angle)) - 15)
        }
        check("회전·확대한 출입구도 같은 기준(중앙이 같은 비율로 이동)",
              near(OpeningEntrancePlacer.midpoint(of: bent.map(transform)), transform(LocalPoint(6, 0)), 1e-9))
        check("길이 0은 중앙을 정하지 않음", OpeningEntrancePlacer.midpoint(of: [LocalPoint(3, 3), LocalPoint(3, 3)]) == nil)
        check("점이 부족하면 중앙을 정하지 않음", OpeningEntrancePlacer.midpoint(of: [LocalPoint(3, 3)]) == nil)

        // IMDF 가져오기 → 자동 배치.
        do {
            let ground = UUID(), upper = UUID()
            let ring = [[129.0, 36.0], [129.0004, 36.0], [129.0004, 36.0004], [129.0, 36.0004], [129.0, 36.0]]
            func data(_ features: [[String: Any]]) throws -> Data {
                try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
            }
            func level(_ id: UUID, _ ordinal: Int) -> [String: Any] {
                ["type": "Feature", "id": id.uuidString, "feature_type": "level",
                 "properties": ["ordinal": ordinal, "name": ["ko": "\(ordinal + 1)층"]],
                 "geometry": ["type": "Polygon", "coordinates": [ring]]]
            }
            func opening(_ id: UUID, _ levelID: UUID, _ geometry: [String: Any]?) -> [String: Any] {
                var feature: [String: Any] = ["type": "Feature", "id": id.uuidString,
                    "properties": ["level_id": levelID.uuidString, "category": "pedestrian"]]
                feature["geometry"] = geometry ?? NSNull()
                return feature
            }
            let twoPoint = UUID(), polyline = UUID(), zero = UUID(), polygon = UUID(), missing = UUID(), upperDoor = UUID()
            let files: [String: Data] = [
                "level.geojson": try data([level(ground, 0), level(upper, 1)]),
                "opening.geojson": try data([
                    opening(twoPoint, ground, ["type": "LineString", "coordinates": [[129.0001, 36.0001], [129.0003, 36.0001]]]),
                    opening(polyline, ground, ["type": "LineString", "coordinates": [[129.0001, 36.0002], [129.0002, 36.0002], [129.0002, 36.00024]]]),
                    opening(zero, ground, ["type": "LineString", "coordinates": [[129.0002, 36.0003], [129.0002, 36.0003]]]),
                    opening(polygon, ground, ["type": "Polygon", "coordinates": [ring]]),
                    opening(missing, ground, nil),
                    opening(upperDoor, upper, ["type": "LineString", "coordinates": [[129.0001, 36.0001], [129.0003, 36.0001]]])
                ])
            ]
            let imported = try IMDFImporter.decode(files: files, sourceName: "entrance.imdf")
            let env = AppEnvironment()
            try env.adoptIMDF(imported)
            let originalOpenings = env.buildingProject.levels.flatMap { $0.geoJSON["opening.geojson"] ?? [] }
            check("opening이 있는 IMDF에서 자동 배치 버튼이 활성화됨", env.hasOpeningFeatures)

            let plan = env.placeEntranceNodes()
            let nodes = env.routing.nodes
            check("정상 opening마다 entrance 노드 하나씩(3곳)", nodes.count == 3 && plan.nodes.count == 3 &&
                  nodes.allSatisfy { $0.category == "entrance" })
            check("층 UUID가 opening이 속한 층과 일치", nodes.filter { $0.floorID == ground }.count == 2 &&
                  nodes.filter { $0.floorID == upper }.count == 1)
            let two = nodes.first { $0.sourceOpeningID == twoPoint.uuidString.lowercased() }
            let expected = imported.coordinates.localPoint(longitude: 129.0002, latitude: 36.0001)
            check("두 점 opening은 정확히 중점에 배치", near(two?.point, expected, 1e-6))
            check("제외 대상 3곳(길이 0·Polygon·geometry 없음)이 사유와 함께 구분됨", plan.skipped.count == 3 &&
                  plan.skipped.allSatisfy { !$0.reason.isEmpty } && plan.skipped.contains { $0.reason.contains("길이가 0") })
            check("유효하지 않은 opening으로는 노드를 만들지 않음", !nodes.contains { [zero, polygon, missing].map { $0.uuidString.lowercased() }.contains($0.sourceOpeningID ?? "") })
            check("원본 opening 도형은 변경되지 않음", env.buildingProject.levels.flatMap { $0.geoJSON["opening.geojson"] ?? [] } == originalOpenings)
            check("주변 노드와의 연결은 만들지 않음", env.routing.edges.isEmpty)

            // 내보내기 계약: [경도, 위도].
            let output = try RoutingExporter.collection(env.routing)
            let feature = (output["features"] as! [[String: Any]]).first { $0["id"] as? String == two?.id.uuidString.lowercased() }!
            let coordinates = (feature["geometry"] as! [String: Any])["coordinates"] as! [Double]
            let properties = feature["properties"] as! [String: Any]
            check("내보낸 Point는 WGS 84 [경도, 위도]이고 category·level_id 유지", abs(coordinates[0] - 129.0002) < 1e-9 &&
                  abs(coordinates[1] - 36.0001) < 1e-9 && properties["category"] as? String == "entrance" &&
                  properties["level_id"] as? String == ground.uuidString.lowercased())

            // 반복 실행·수동 편집 보존.
            let moved = LocalPoint((two?.point.x ?? 0) + 25, (two?.point.y ?? 0) + 25)
            env.moveRoutingNode(two!.id, to: moved)
            env.updateRoutingNode(two!.id, field: "name") { $0.name = "정문" }
            let manual = env.routing
            let again = env.placeEntranceNodes()
            check("재실행해도 노드가 중복되지 않음", env.routing.nodes.count == 3 && again.nodes.isEmpty && again.alreadyPlaced == 3)
            check("사용자가 옮기거나 이름 붙인 노드를 덮어쓰지 않음", env.routing == manual &&
                  env.routing.node(two!.id)?.point == moved && env.routing.node(two!.id)?.name == "정문")

            // 수동 노드가 이미 중앙에 있으면 겹쳐 만들지 않음.
            let handmade = AppEnvironment()
            try handmade.adoptIMDF(imported)
            handmade.selectRoutingFloor(ground)
            handmade.handleRoutingClick(at: expected, tolerance: 0.1, modifiers: .command)
            let manualCount = handmade.routing.nodes.count
            let covered = handmade.placeEntranceNodes()
            check("중앙에 이미 있는 수동 노드와 겹치는 노드는 만들지 않음", manualCount == 1 && covered.coveredByExisting == 1 &&
                  handmade.routing.nodes.count == 3)

            // 실행취소/다시실행, 저장·재열기.
            let fresh = AppEnvironment()
            try fresh.adoptIMDF(imported)
            fresh.placeEntranceNodes()
            let placed = fresh.routing
            fresh.undo()
            check("실행취소 한 번으로 자동 배치 전체 취소", fresh.routing.nodes.isEmpty)
            fresh.redo()
            check("다시실행 시 같은 UUID·위치·카테고리·층 복원", fresh.routing == placed)
            let file = try ProjectFile.decoded(from: fresh.makeProjectFile()!.encoded())
            let reopened = AppEnvironment()
            try reopened.adopt(file, from: nil)
            check("저장·재열기 후 노드 UUID·위치·카테고리·층·원본 대응 유지", reopened.routing.nodes == placed.nodes)
            let rerun = reopened.placeEntranceNodes()
            check("재열기 뒤 재실행도 중복 없음", rerun.nodes.isEmpty && reopened.routing.nodes.count == 3)
            let removedKey = twoPoint.uuidString.lowercased()
            fresh.routing.nodes.removeAll { $0.sourceOpeningID == removedKey }
            let regenerated = fresh.placeEntranceNodes()
            check("삭제한 출입구 노드는 재실행 시 다시 만들어짐", regenerated.nodes.count == 1 && fresh.routing.nodes.count == 3)
        } catch { check("출입구 노드 자동 배치 검증", false); print(error) }
    }
}
