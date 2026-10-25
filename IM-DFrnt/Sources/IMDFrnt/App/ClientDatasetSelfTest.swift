import Foundation

/// 클라이언트용 묶음(#54) — 두 층·같은 층 연결·층간 연결을 가진 합성 프로젝트로 참조·해시·ID 유지·저장을 확인한다.
@MainActor
enum ClientDatasetSelfTest {
    static func run(check: (String, Bool) -> Void) {
        func level(_ name: String, _ ordinal: Int, withLevelPolygon: Bool = true, withVenue: Bool = false) -> ProjectLevel {
            var level = ProjectLevel(info: ProjectLevelInfo(name: name, ordinal: ordinal))
            level.info.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129.3250, latitude: 36.0150), label: "A")
            level.info.anchors.add(local: LocalPoint(1000, 0), geo: GeoPoint(longitude: 129.3260, latitude: 36.0150), label: "B")
            level.info.anchors.add(local: LocalPoint(0, 1000), geo: GeoPoint(longitude: 129.3250, latitude: 36.0140), label: "C")
            func add(_ type: IMDFFeatureType, _ serial: String, _ ring: [LocalPoint]) {
                var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
                for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
                f.polygonRings = [ring]
                level.editing.features.insert(f)
            }
            if withLevelPolygon {
                add(.level, "level-001", [LocalPoint(0, 0), LocalPoint(1000, 0), LocalPoint(1000, 800), LocalPoint(0, 800)])
            }
            if withVenue { add(.venue, "venue-001", [LocalPoint(0, 0), LocalPoint(1000, 0), LocalPoint(1000, 1000), LocalPoint(0, 1000)]) }
            add(.unit, "unit-001", [LocalPoint(0, 0), LocalPoint(1000, 0), LocalPoint(1000, 800), LocalPoint(0, 800)])
            return level
        }
        var ground = level("1층", 0, withVenue: true), upper = level("2층", 1)
        let stairs1 = RoutingNode(floorID: ground.id, point: LocalPoint(100, 100), name: "계단 1층", category: "stairs")
        let hall = RoutingNode(floorID: ground.id, point: LocalPoint(400, 100), name: "복도", category: "waypoint")
        let outside = RoutingNode(floorID: ground.id, point: LocalPoint(400, 900), category: "entrance")
        let stairs2 = RoutingNode(floorID: upper.id, point: LocalPoint(100, 100), name: "계단 2층", category: "stairs")
        ground.nodes = [stairs1, hall, outside]
        upper.nodes = [stairs2]
        ground.edges = [RoutingEdge(from: stairs1.id, to: hall.id)]
        let cross = RoutingEdge(from: stairs1.id, to: stairs2.id, accessible: false, category: .stairs)

        func projectData(_ levels: [ProjectLevel], cross: [RoutingEdge]) -> Data {
            var file = ProjectFile.empty()
            file.buildingProject = IMDFTestFixtures.authored(levels, cross: cross)
            return try! file.encoded()
        }
        func json(_ data: Data?) -> [String: Any] { (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:] }
        func features(_ data: Data?) -> [[String: Any]] { json(data)["features"] as? [[String: Any]] ?? [] }
        func props(_ f: [String: Any]) -> [String: Any] { f["properties"] as? [String: Any] ?? [:] }

        do {
            let out = try ClientDataset.build(projectData: projectData([ground, upper], cross: [cross]),
                                              datasetID: "synthetic-two-floors", documents: [:],
                                              now: Date(timeIntervalSince1970: 0))
            let dataset = json(out.files["dataset.json"])
            let mapHashes = dataset["map_files_sha256"] as? [String: String] ?? [:]
            check("클라이언트 묶음: IMDFData 8종·routing-graph·dataset.json이 한 묶음에 있다",
                  ClientDataset.mapFiles.allSatisfy { out.files["IMDFData/" + $0] != nil }
                      && out.files["routing-graph.geojson"] != nil && Set(mapHashes.keys) == Set(ClientDataset.mapFiles))
            check("클라이언트 묶음: 기록한 SHA-256이 최종 바이트와 같다",
                  mapHashes.allSatisfy { ClientDataset.sha256(out.files["IMDFData/" + $0.key]!) == $0.value }
                      && dataset["routing_sha256"] as? String == ClientDataset.sha256(out.files["routing-graph.geojson"]!)
                      && (dataset["additional_map_files_sha256"] as? [String: String])?["address.geojson"]
                          == ClientDataset.sha256(out.files["IMDFData/address.geojson"]!))
            check("클라이언트 묶음: schema 2·dataset_id·layout_version, 서가 매핑은 null(미제공)",
                  dataset["schema_version"] as? Int == 2 && dataset["dataset_id"] as? String == "synthetic-two-floors"
                      && dataset["layout_version"] as? String == json(out.files["routing-graph.geojson"])["layout_version"] as? String
                      && dataset["shelves_sha256"] is NSNull && out.files["shelves.json"] == nil)

            let levels = Dictionary(uniqueKeysWithValues: features(out.files["IMDFData/level.geojson"]).map {
                ($0["id"] as! String, props($0)["ordinal"] as? Int)
            })
            let graph = features(out.files["routing-graph.geojson"])
            let nodes = graph.filter { props($0)["role"] as? String == "node" }
            let edges = graph.filter { props($0)["role"] as? String == "edge" }
            check("클라이언트 묶음: 지금 층 밖의 노드·층간 연결까지 모두 들어간다", nodes.count == 4 && edges.count == 2)
            check("클라이언트 묶음: 노드 level_id·level이 함께 낸 level.geojson의 UUID·ordinal과 같다",
                  nodes.allSatisfy { n in
                      guard let id = props(n)["level_id"] as? String, let ordinal = levels[id] else { return false }
                      return ordinal == props(n)["level"] as? Int
                  } && Set(levels.keys) == [ground.id.uuidString.lowercased(), upper.id.uuidString.lowercased()])
            let coordinates = Dictionary(uniqueKeysWithValues: nodes.map {
                ($0["id"] as! String, ($0["geometry"] as? [String: Any])?["coordinates"] as? [Double] ?? [])
            })
            check("클라이언트 묶음: 간선 첫·끝 좌표가 from·to 노드 좌표와 정확히 같다",
                  edges.allSatisfy { e in
                      let line = (e["geometry"] as? [String: Any])?["coordinates"] as? [[Double]] ?? []
                      return line.first == coordinates[props(e)["from"] as? String ?? ""]
                          && line.last == coordinates[props(e)["to"] as? String ?? ""]
                  })
            check("클라이언트 묶음: 고립·층 외곽 밖 노드, 층간 비용 미제공, 서가 매핑 없음을 경고한다",
                  out.warnings.contains { $0.hasPrefix("고립 노드 1개") } && out.warnings.contains { $0.hasPrefix("층 외곽 밖 노드 1개") }
                      && out.warnings.contains { $0.contains("층간 연결 1개") } && out.warnings.contains { $0.contains("shelves.json") })
            // 바깥 출입구(outside)는 level 외곽(세로 800) 밖에 있고 연결이 없다. 지우거나 잇지 않고 알리기만 한다.

            var again1 = ground, again2 = upper
            again1.editing.ids = out.ids[ground.id]!; again2.editing.ids = out.ids[upper.id]!
            let second = try ClientDataset.build(projectData: projectData([again1, again2], cross: [cross]),
                                                 datasetID: "synthetic-two-floors", documents: [:],
                                                 now: Date(timeIntervalSince1970: 60))
            let changed = ClientDataset.mapFiles.filter { out.files["IMDFData/" + $0] != second.files["IMDFData/" + $0] }
            check("클라이언트 묶음: 수정 없이 다시 내보내면 manifest(created) 말고는 바이트가 같다",
                  changed == ["manifest.json"] && out.files["routing-graph.geojson"] == second.files["routing-graph.geojson"])

            let root = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntClientDataset-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("synthetic-two-floors")
            try ClientDataset.write(out.files, to: target, replacing: false)
            let written = try Data(contentsOf: target.appendingPathComponent("IMDFData/unit.geojson"))
            check("클라이언트 묶음: 폴더에 쓴 파일이 해시와 같다",
                  ClientDataset.sha256(written) == mapHashes["unit.geojson"])
            let edited = target.appendingPathComponent("routing-graph.geojson")
            try Data("손으로 고친 파일".utf8).write(to: edited)
            var refusedWithoutReplace = false
            do { try ClientDataset.write(second.files, to: target, replacing: false) } catch { refusedWithoutReplace = true }
            var bad = second.files; bad["../escape.json"] = Data("{}".utf8)
            var refusedUnsafe = false
            do { try ClientDataset.write(bad, to: target, replacing: true) } catch { refusedUnsafe = true }
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "synthetic-two-floors" }
            check("클라이언트 묶음: 교체를 고르지 않거나 저장에 실패하면 기존 폴더의 수정 파일을 그대로 둔다",
                  refusedWithoutReplace && refusedUnsafe && leftovers.isEmpty
                      && (try? Data(contentsOf: edited)) == Data("손으로 고친 파일".utf8))
            try ClientDataset.write(second.files, to: target, replacing: true)
            check("클라이언트 묶음: 교체를 고르면 묶음 전체가 새 파일로 바뀐다",
                  (try? Data(contentsOf: edited)) == second.files["routing-graph.geojson"]
                      && (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count == 1)
        } catch {
            check("클라이언트 묶음: 두 층 프로젝트를 묶는다 — \(error)", false)
        }

        func blocked(_ name: String, _ data: Data, datasetID: String = "blocked", _ match: (String) -> Bool) {
            do {
                _ = try ClientDataset.build(projectData: data, datasetID: datasetID, documents: [:])
                check(name, false)
            } catch let blocked as ClientDataset.Blocked {
                check(name, blocked.messages.contains(where: match))
            } catch { check(name + " — \(error)", false) }
        }
        var noNodes1 = ground, noNodes2 = upper
        noNodes1.nodes = []; noNodes1.edges = []; noNodes2.nodes = []
        blocked("클라이언트 묶음: 노드가 없으면 막는다", projectData([noNodes1, noNodes2], cross: [])) { $0.contains("노드") }
        blocked("클라이언트 묶음: level 다각형 없는 층은 지도 쪽 원인으로 막는다",
                projectData([ground, { var l = level("2층", 1, withLevelPolygon: false); l.info.id = upper.id; l.nodes = upper.nodes; return l }()],
                            cross: [cross])) { $0.hasPrefix("지도: 2층") }
        var zero = ground
        let twin = RoutingNode(floorID: ground.id, point: hall.point, category: "waypoint")
        zero.nodes.append(twin); zero.edges.append(RoutingEdge(from: hall.id, to: twin.id))
        blocked("클라이언트 묶음: 길이 0인 같은 층 연결은 막는다", projectData([zero, upper], cross: [cross])) { $0.contains("길이가 0") }
        blocked("클라이언트 묶음: dataset_id에 경로·대문자를 쓸 수 없다", projectData([ground, upper], cross: [cross]),
                datasetID: "../C5") { $0.contains("dataset_id") }

        check("클라이언트 묶음: 닫히지 않은 ring을 찾는다",
              ClientDataset.geometryProblem(["type": "Polygon", "coordinates": [[[129.0, 36.0], [129.1, 36.0], [129.1, 36.1], [129.0, 36.1]]]]) != nil
                  && ClientDataset.geometryProblem(["type": "Point", "coordinates": [36.0, 129.0]]) != nil)
        check("클라이언트 묶음: dataset_id 기본값은 폴더 이름으로 쓸 수 있는 값이다",
              ClientDataset.suggestedDatasetID(from: "Postech Library 2F") == "postech-library-2f"
                  && ClientDataset.suggestedDatasetID(from: "포스텍 도서관") == "dataset"
                  && !ClientDataset.isValidDatasetID("../c5") && !ClientDataset.isValidDatasetID("C5"))
    }
}
