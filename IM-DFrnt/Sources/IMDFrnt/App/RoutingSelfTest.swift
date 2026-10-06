import AppKit
import Foundation

@MainActor
enum RoutingSelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--routing-selftest") else { return }
        var failures = 0, count = 0
        func check(_ name: String, _ valid: Bool) {
            count += 1
            if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        func expectFailure(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); check(name, false) } catch { check(name, true) }
        }
        func calibration() -> AnchorStore {
            var anchors = AnchorStore()
            for (point, geo) in [
                (LocalPoint(0, 0), GeoPoint(longitude: 129, latitude: 36)),
                (LocalPoint(1000, 0), GeoPoint(longitude: 129.001, latitude: 36)),
                (LocalPoint(0, 700), GeoPoint(longitude: 129, latitude: 35.999))
            ] { anchors.add(local: point, geo: geo, label: "기준") }
            return anchors
        }

        let env = AppEnvironment()
        env.openSample()
        env.anchors = calibration()
        env.enterRoutingScreen()
        let firstFloor = env.currentRoutingFloor!.id
        check("기존 도면과 좌표 기준점 재사용", env.routingDocument?.fingerprint == env.document?.fingerprint &&
              env.currentRoutingFloor?.anchors == env.anchors)
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 10)
        let first = env.routingSelectedNodeID!
        env.handleRoutingClick(at: LocalPoint(300, 100), tolerance: 10)
        let second = env.routingSelectedNodeID!
        check("빈 곳 클릭으로 노드 두 개 생성", env.routing.nodes.count == 2)
        env.handleRoutingClick(at: LocalPoint(102, 100), tolerance: 10)
        check("기존 핀 클릭은 선택하며 중복 생성하지 않음", env.routingSelectedNodeID == first && env.routing.nodes.count == 2)
        env.setRoutingTool(.connect)
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 10)
        env.handleRoutingClick(at: LocalPoint(300, 100), tolerance: 10)
        check("두 핀 클릭으로 양방향 연결 생성", env.routing.edges.count == 1 && env.selectedRoutingEdge != nil)
        let edgeID = env.routing.edges[0].id
        _ = env.routing.connect(second, first)
        check("반대 순서의 중복 연결 방지", env.routing.edges.count == 1 && env.routing.edges[0].id == edgeID)
        check("자기 자신 연결 방지", env.routing.connect(first, first) == nil)
        env.setRoutingTool(.select)
        env.handleRoutingClick(at: LocalPoint(200, 100), tolerance: 10)
        check("연결선 클릭으로 선택", env.routingSelectedEdgeID == edgeID)
        env.selectRoutingNode(first)
        let monitor = RoutingKeyMonitor(env: env)
        check("텍스트 입력 중 Delete는 노드를 지우지 않음", !monitor.handle(keyCode: 51, textIsEditing: true) && env.routing.nodes.count == 2)
        check("모달·명령 키 Delete는 노드를 지우지 않음", !monitor.handle(keyCode: 51, hasModal: true) &&
              !monitor.handle(keyCode: 51, modifiers: .command) && env.routing.nodes.count == 2)
        let beforeDelete = env.routing
        check("Delete로 노드와 연결을 함께 삭제", monitor.handle(keyCode: 51) && env.routing.nodes.count == 1 && env.routing.edges.isEmpty)
        env.undo()
        check("삭제 실행취소로 ID·연결·선택 복원", env.routing == beforeDelete && env.routingSelectedNodeID == first)
        env.redo()
        check("삭제 다시실행", env.routing.nodes.count == 1 && env.routing.edges.isEmpty)
        env.undo()
        env.moveRoutingNode(first, to: LocalPoint(120, 150))
        check("노드 위치 이동", env.routing.node(first)?.point == LocalPoint(120, 150))
        env.undo()
        check("이동 실행취소", env.routing.node(first)?.point == LocalPoint(100, 100))
        env.updateRoutingNode(first, field: "name") { $0.name = "정문" }
        env.updateRoutingNode(first, field: "metadata") { $0.metadataJSON = "{\"unit_id\":\"entrance-1\",\"priority\":2,\"tags\":[\"entry\"]}" }
        do {
            let data = try RoutingExporter.encoded(env.routing)
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let features = object["features"] as! [[String: Any]]
            let nodeFeature = features.first { $0["id"] as? String == first.uuidString.lowercased() }!
            let properties = nodeFeature["properties"] as! [String: Any]
            let geometry = nodeFeature["geometry"] as! [String: Any]
            let coords = geometry["coordinates"] as! [Double]
            check("클라이언트 Point·경도/위도 순서 및 층 번호", geometry["type"] as? String == "Point" &&
                  abs(coords[0]-129.0001) < 1e-9 && abs(coords[1]-(36-0.001/7)) < 1e-9 && properties["level"] as? Int == 0)
            check("이름·중첩 메타데이터 보존", properties["name"] as? String == "정문" &&
                  (properties["metadata"] as? [String: Any])?["priority"] as? Int == 2)
            let edge = features.first { ($0["properties"] as? [String: Any])?["role"] as? String == "edge" }!
            let edgeProps = edge["properties"] as! [String: Any]
            let edgeGeometry = edge["geometry"] as! [String: Any]
            check("연결은 실제 노드 ID와 LineString으로 내보냄", edgeProps["from"] as? String == first.uuidString.lowercased() &&
                  edgeProps["to"] as? String == second.uuidString.lowercased() && edgeProps["direction"] as? String == "undirected" &&
                  edgeGeometry["type"] as? String == "LineString")
            check("반복 내보내기에 UUID와 파일 내용 유지", try RoutingExporter.encoded(env.routing) == data)
            if let arg = CommandLine.arguments.firstIndex(of: "--routing-test-output"), CommandLine.arguments.indices.contains(arg+1) {
                try data.write(to: URL(fileURLWithPath: CommandLine.arguments[arg+1]), options: .atomic)
            }
        } catch { check("클라이언트 내보내기", false); print(error) }
        expectFailure("잘못된 JSON 메타데이터 차단") { _ = try RoutingExporter.metadata("[]") }
        var invalid = env.routing
        invalid.floors[0].anchors = AnchorStore()
        expectFailure("좌표 기준점 없이 픽셀 좌표를 내보내지 않음") { _ = try RoutingExporter.encoded(invalid) }
        invalid = env.routing
        invalid.floors[0].anchors.pairs = [env.anchors.pairs[0], env.anchors.pairs[1],
            AnchorPair(local: LocalPoint(500, 0), geo: GeoPoint(longitude: 129.0005, latitude: 36), label: "직선")]
        expectFailure("일직선 기준점으로 좌표 확정하지 않음") { _ = try RoutingExporter.encoded(invalid) }

        env.addRoutingFloor()
        let secondFloor = env.currentRoutingFloor!.id
        check("새 층에 다른 층 도면을 임의 표시하지 않음", env.routingDocument == nil && env.routing.nodes(on: secondFloor).isEmpty)
        do {
            try env.setRoutingDrawing(secondFloor, data: Data(SampleFloorplan.svg.utf8), name: "2층.svg")
            env.updateRoutingFloor(secondFloor) { $0.anchors = calibration() }
        } catch { check("층 도면 불러오기", false) }
        env.setRoutingTool(.place)
        env.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 10)
        let third = env.routingSelectedNodeID!
        check("같은 위치의 노드를 층별로 따로 관리", env.routing.nodes(on: firstFloor).count == 2 &&
              env.routing.nodes(on: secondFloor).count == 1 && env.nearestRoutingNode(to: LocalPoint(100,100), tolerance: 10)?.id == third)
        env.updateRoutingNode(first, field: "category") { $0.category = "stairs" }
        env.updateRoutingNode(third, field: "category") { $0.category = "stairs" }
        env.selectRoutingFloor(firstFloor)
        env.setRoutingTool(.connect)
        env.handleRoutingClick(at: LocalPoint(100,100), tolerance: 10)
        env.selectRoutingFloor(secondFloor)
        check("층을 바꿔도 연결 시작 노드 유지", env.routingConnectStart == first)
        env.handleRoutingClick(at: LocalPoint(100,100), tolerance: 10)
        check("층간 계단 연결 및 접근성", env.routing.edges.count == 2 && env.selectedRoutingEdge?.category == .stairs &&
              env.selectedRoutingEdge?.accessible == false)
        check("일반 통로 노드의 층간 연결 방지", env.routing.connect(second, third) == nil)
        check("연결 안 된 그룹 감지", env.routing.componentCount == 1 && env.routing.isolatedNodes.isEmpty)
        let allFloors = env.routing
        env.removeRoutingFloor(secondFloor)
        check("층 삭제는 노드와 층간 연결을 정리", env.routing.nodes.count == 2 && env.routing.edges.count == 1)
        env.undo()
        check("층 삭제 실행취소는 도면과 그래프 전체 복원", env.routing == allFloors)

        do {
            let file = env.makeProjectFile()!
            let decoded = try ProjectFile.decoded(from: file.encoded())
            let reopened = AppEnvironment()
            try reopened.adopt(decoded, from: nil)
            check("프로젝트 재열기에 층별 도면·노드·연결·메타데이터 유지", reopened.routing == env.routing)
            var legacy = try JSONSerialization.jsonObject(with: file.encoded()) as! [String: Any]
            legacy["version"] = 2
            legacy.removeValue(forKey: "routing")
            let old = try ProjectFile.decoded(from: JSONSerialization.data(withJSONObject: legacy))
            try reopened.adopt(old, from: nil)
            check("노드 기능 이전 버전 2 작업 열기", reopened.document != nil && reopened.routing.floors.isEmpty)
            let importedID = UUID()
            let levelJSON: [String: Any] = ["type": "FeatureCollection", "features": [
                ["feature_type": "level", "id": importedID.uuidString,
                 "properties": ["ordinal": 0, "name": ["ko": "클라이언트 1층"]]]
            ]]
            let levels = try RoutingLevelImporter.decode(JSONSerialization.data(withJSONObject: levelJSON))
            env.adoptRoutingLevels(levels)
            check("클라이언트 층 ID를 기존 노드에 함께 적용", env.routing.floor(importedID)?.name == "클라이언트 1층" &&
                  env.routing.node(first)?.floorID == importedID && env.routing.node(second)?.floorID == importedID)
            let beforeIDChange = env.routing
            env.assignRoutingLevelID(importedID, newID: UUID())
            env.undo()
            check("층 ID 편집도 실행취소 가능", env.routing == beforeIDChange)
        } catch { check("작업 저장·호환·층 목록 검증", false); print(error) }

        do {
            env.selectRoutingFloor(secondFloor)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.setColor(.red, atX: 0, y: 0)
            bitmap.setColor(.blue, atX: 1, y: 1)
            let png = bitmap.representation(using: .png, properties: [:])!
            try env.setRoutingDrawing(secondFloor, data: png, name: "원본.png")
            check("원본 PNG가 도형으로 바뀌지 않고 표시됨", env.routingDocument?.rasterImages.count == 1 && env.routingDocument?.objects.isEmpty == true)
            let file = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded())
            let restored = AppEnvironment()
            try restored.adopt(file, from: nil)
            restored.selectRoutingFloor(secondFloor)
            check("이미지 도면을 프로젝트에 내장하여 재열기", restored.routingDocument?.rasterImages.first?.digest == env.routingDocument?.rasterImages.first?.digest)
        check("도면 교체 시 이전 좌표 기준점 초기화", env.currentRoutingFloor?.anchors.pairs.isEmpty == true)
        } catch { check("PNG 원본 저장·재열기", false); print(error) }
        env.showRoutingScreen = true
        env.export()
        check("노드 화면의 공통 내보내기 명령은 길찾기 검증을 사용", env.routingExportError?.contains("좌표 기준점") == true)
        let currentGraph = env.routing
        for floor in env.routing.floors { env.removeRoutingFloor(floor.id) }
        check("모든 층 삭제 후 빈 그래프에서 새 층 추가 가능", env.routing.floors.isEmpty && env.routing.nodes.isEmpty && env.routing.edges.isEmpty)
        env.addRoutingFloor()
        check("빈 그래프의 새 층은 별도 도면을 기다림", env.currentRoutingFloor?.ordinal == 0 && env.routingDocument == nil)
        _ = currentGraph
        env.showRoutingScreen = false
        check("일반 IMDF 편집에서 Delete를 가로채지 않음", !monitor.handle(keyCode: 51))
        RoutingInteractionSelfTest.run(check: check)
        IMDFSelfTest.run(check: check)
        print("== Routing: \(count-failures)/\(count) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
