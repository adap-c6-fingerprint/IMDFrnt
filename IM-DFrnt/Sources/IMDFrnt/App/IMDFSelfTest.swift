import Foundation

@MainActor
enum IMDFSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func rejects(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); check(name, false) } catch { check(name, true) }
        }
        func data(_ features: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
        }
        let ground = UUID(), basement = UUID(), unit = UUID()
        let ring = [[129.0, 36.0], [129.0002, 36.0], [129.0002, 36.0002], [129.0, 36.0002], [129.0, 36.0]]
        let hole = [[129.00008, 36.00008], [129.00012, 36.00008], [129.00012, 36.00012],
                    [129.00008, 36.00012], [129.00008, 36.00008]]
        func level(_ id: UUID, ordinal: Int, name: String) -> [String: Any] {
            ["type": "Feature", "id": id.uuidString, "feature_type": "level",
             "properties": ["ordinal": ordinal, "name": ["ko": name]],
             "geometry": ["type": "Polygon", "coordinates": [ring, hole]]]
        }
        do {
            var files: [String: Data] = [
                "level.geojson": try data([level(ground, ordinal: 0, name: "1층"), level(basement, ordinal: -1, name: "지하 1층")]),
                "unit.geojson": try data([["type": "Feature", "id": unit.uuidString,
                    "properties": ["level_id": ground.uuidString, "category": "walkway"],
                    "geometry": ["type": "MultiPolygon", "coordinates": [[ring, hole]]]]]),
                "amenity.geojson": try data([["type": "Feature", "id": UUID().uuidString,
                    "properties": ["unit_ids": [unit.uuidString], "category": "stairs"],
                    "geometry": ["type": "Point", "coordinates": [129.00005, 36.00005]]]]),
                "opening.geojson": try data([["type": "Feature", "id": UUID().uuidString,
                    "properties": ["level_id": ground.uuidString],
                    "geometry": ["type": "LineString", "coordinates": [[129.0, 36.0], [129.00005, 36.0]]]]])
            ]
            let imported = try IMDFImporter.decode(files: files, sourceName: "test.imdf.zip")
            let env = AppEnvironment()
            env.enterRoutingScreen()
            check("원본 도면 없이 노드 편집 진입", env.showRoutingScreen && env.document == nil)
            try env.adoptIMDF(imported)
            check("IMDF로 새 작업 시작·지하 ordinal과 층 UUID 유지", env.showRoutingScreen && env.projectURL == nil &&
                  env.routing.floors.map(\.id) == [basement, ground] && env.currentRoutingFloor?.ordinal == -1)
            check("IMDF는 수동 좌표 기준점 없이 좌표 변환 가능", env.routing.floors.allSatisfy {
                $0.anchors.pairs.isEmpty && $0.hasGeographicCoordinates
            })
            env.selectRoutingFloor(ground)
            check("IMDF 공간·복수 Polygon·출입구·unit 연결 amenity 표시", env.routingDocument?.objects.count == 4)
            check("Polygon 안쪽 구멍 유지", env.routingDocument?.objects.first?.geometry.subpaths.count == 2)
            let original = GeoPoint(longitude: 129.00005, latitude: 36.00005)
            let local = imported.coordinates.localPoint(longitude: original.longitude, latitude: original.latitude)
            env.handleRoutingClick(at: local, tolerance: 0.1, modifiers: .command)
            let id = env.routingSelectedNodeID!
            env.handleRoutingClick(at: imported.coordinates.localPoint(longitude: 129.00006, latitude: 36.00005), tolerance: 0.1, modifiers: .command)
            _ = env.routing.connect(id, env.routingSelectedNodeID!)
            let output = try RoutingExporter.collection(env.routing)
            let node = (output["features"] as! [[String: Any]]).first { $0["id"] as? String == id.uuidString.lowercased() }!
            let coordinates = (node["geometry"] as! [String: Any])["coordinates"] as! [Double]
            let properties = node["properties"] as! [String: Any]
            check("IMDF에 찍은 노드를 원본 위경도·level ID로 바로 내보내기", abs(coordinates[0] - original.longitude) < 1e-10 &&
                  abs(coordinates[1] - original.latitude) < 1e-10 && properties["level_id"] as? String == ground.uuidString.lowercased() &&
                  properties["level"] as? Int == 0 && env.routing.edges.count == 1)
            env.selectRoutingFloor(basement)
            check("IMDF 층 전환 시 다른 층 노드 숨김", env.routing.nodes(on: basement).isEmpty && env.routingDocument?.objects.count == 1)
            let bytes = try RoutingExporter.encoded(env.routing)
            let reopened = AppEnvironment()
            let project = env.makeProjectFile()!
            try reopened.adopt(ProjectFile.decoded(from: project.encoded()), from: nil)
            let reopenedBytes = try RoutingExporter.encoded(reopened.routing)
            check("IMDF 지도·좌표·노드 저장 및 재열기 후 바로 노드 화면", reopened.routing == env.routing &&
                  reopened.showRoutingScreen && reopenedBytes == bytes)
            let beforeFailure = env.routing
            rejects("층 파일 없는 IMDF 거절") { _ = try IMDFImporter.decode(files: [:], sourceName: "empty.zip") }
            rejects("손상된 IMDF 거절") { _ = try IMDFImporter.decode(files: ["level.geojson": Data("{}".utf8)], sourceName: "broken.zip") }
            check("입력 오류가 기존 작업을 변경하지 않음", env.routing == beforeFailure)
            files["level.geojson"] = try data([level(ground, ordinal: 0, name: "1층"), level(UUID(), ordinal: 0, name: "중복층")])
            check("동일 ordinal의 별도 Level 입력 허용", try IMDFImporter.decode(files: files, sourceName: "duplicate.zip").floors.count == 2)

            let legacy = AppEnvironment()
            legacy.openSample()
            legacy.enterRoutingScreen()
            let oldProject = legacy.makeProjectFile()!
            var old = try JSONSerialization.jsonObject(with: oldProject.legacyEditorView().encoded()) as! [String: Any]
            old["version"] = 3
            var graph = old["routing"] as! [String: Any]
            graph.removeValue(forKey: "imdfSourceName")
            var floors = graph["floors"] as! [[String: Any]]
            floors[0].removeValue(forKey: "imdfCoordinates")
            graph["floors"] = floors; old["routing"] = graph
            try reopened.adopt(ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: old)), from: nil)
            check("기존 버전 3 노드 작업 호환", reopened.routing == legacy.routing && !reopened.showRoutingScreen)

            for flag in ["--imdf-test-input", "--imdf-test-zip"] {
                guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) else { continue }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                let real = try IMDFImporter.load(url)
                try env.adoptIMDF(real)
                check("실제 클라이언트 C5 입력 \(flag): 층 6개·모든 층 공간 표시", env.routing.floors.count == 6 &&
                      env.routing.floors.allSatisfy { floor in
                          ((try? SVGParser.parse(data: Data(floor.svg.utf8), sourceName: floor.sourceName))?.objects.count ?? 0) > 1
                      })
                let p = real.coordinates.localPoint(longitude: 129.3258293, latitude: 36.0141502)
                env.handleRoutingClick(at: p, tolerance: 0.1, modifiers: .command)
                let nodeID = env.routingSelectedNodeID!
                let next = real.coordinates.localPoint(longitude: 129.3258793, latitude: 36.0141902)
                env.handleRoutingClick(at: next, tolerance: 0.1, modifiers: .command)
                _ = env.routing.connect(nodeID, env.routingSelectedNodeID!)
                let collection = try RoutingExporter.collection(env.routing)
                let feature = (collection["features"] as! [[String: Any]]).first {
                    $0["id"] as? String == nodeID.uuidString.lowercased()
                }!
                let c = (feature["geometry"] as! [String: Any])["coordinates"] as! [Double]
                check("실제 C5 지도에서 기준점 없이 원본 좌표 내보내기 \(flag)", abs(c[0] - 129.3258293) < 1e-10 && abs(c[1] - 36.0141502) < 1e-10)
                let dataset = try ClientDataset.build(projectData: env.makeProjectFile()!.encoded(), datasetID: "c5-check", documents: [:])
                let unitIDs = { (features: [Any]) in Set(features.compactMap { (($0 as? [String: Any])?["id"] as? String)?.lowercased() }) }
                let original = unitIDs(real.files["unit.geojson"]?["features"]?.array.map(\.anyValue) ?? [])
                let exported = unitIDs((try JSONSerialization.jsonObject(with: dataset.files["IMDFData/unit.geojson"]!) as? [String: Any])?["features"] as? [Any] ?? [])
                check("실제 C5로 클라이언트 묶음: 원본 unit ID 유지·노드 2개 \(flag)",
                      !original.isEmpty && original == exported && dataset.nodeCount == 2)
                print("  클라이언트 묶음 경고: " + dataset.warnings.joined(separator: " | "))
                if let index = CommandLine.arguments.firstIndex(of: "--routing-imdf-test-output"),
                   CommandLine.arguments.indices.contains(index + 1) {
                    try RoutingExporter.encoded(env.routing).write(
                        to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
                }
                if flag == "--imdf-test-zip" {
                    try env.makeProjectFile()!.encoded().write(to: URL(fileURLWithPath: "/tmp/imdfrnt-imdf-qa.imdfrnt"), options: .atomic)
                }
            }
        } catch { check("IMDF 입력·표시·저장 검증", false); print(error) }
    }
}
