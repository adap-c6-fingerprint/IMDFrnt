import AppKit
import CryptoKit
import Foundation

/// 클라이언트(postech-library iOS 앱) 번들에 넣을 **지도·길찾기 데이터 묶음**을 만든다(#54).
///
/// 한 번 캡처한 프로젝트 데이터로 IMDF(`IMDFArchive.build`)와 그래프(`RoutingExporter.collection`)를 함께 만들어,
/// 서로 다른 시점의 지도와 그래프가 섞이지 않게 한다. 결과는 폴더 하나다.
///
/// ```text
/// <dataset-id>/
///   dataset.json             묶음 schema·dataset_id·layout_version·파일 SHA-256
///   IMDFData/                앱이 읽는 8종은 항상, 그 밖의 원본 IMDF 파일도 보존
///   routing-graph.geojson    노드와 간선(RoutingExporter 구조 그대로)
/// ```
///
/// - 서가 매핑(`shelves.json`)은 편집기에 명시적인 매핑이 없어 만들지 않는다. 가까운 노드나 이름으로 추정하지 않는다.
///   앱의 `dataset.json` schema 1은 `shelves_sha256`을 필수로 읽으므로 이 묶음은 **schema 2**로 표시한다.
/// - 해시는 최종 바이트로 계산하고, 검증도 그 바이트를 다시 읽어 한다(앱이 읽는 것과 같은 값을 검사한다).
enum ClientDataset {

    static let schemaVersion = 2
    /// 앱의 `BundledIndoorNavigationLoader.mapFiles`와 같은 목록. 비어 있어도 빈 FeatureCollection으로 넣는다.
    static let mapFiles = ["manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
                           "unit.geojson", "fixture.geojson", "opening.geojson", "amenity.geojson"]
    /// 비어 있으면 앱이 지도를 만들 수 없는 파일. 빈 파일로 누락을 숨기지 않는다.
    static let requiredNonEmpty = ["venue.geojson", "level.geojson"]
    static let datasetFile = "dataset.json"
    static let routingFile = "routing-graph.geojson"
    static let imdfDirectory = "IMDFData"

    struct Output: Sendable {
        /// 묶음 안 상대 경로 → 내용. `dataset.json`까지 포함한 최종 바이트다.
        var files: [String: Data]
        /// 새로 발급한 feature id. 프로젝트에 되돌려 넣어 재Export에서도 같은 id를 쓴다.
        var ids: [UUID: IDAssigner]
        var levelCount: Int
        var nodeCount: Int
        var edgeCount: Int
        var warnings: [String]
    }

    struct Blocked: Error, Sendable { let messages: [String] }

    // MARK: dataset_id

    /// 폴더 이름이 곧 dataset_id다. 경로·공백·대문자가 섞이면 번들 경로와 키가 흔들리므로 좁게 허용한다.
    static func isValidDatasetID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9][a-z0-9._-]{0,63}$", options: .regularExpression) != nil && !id.contains("..")
    }

    static func suggestedDatasetID(from name: String) -> String {
        let lowered = name.lowercased().map { c -> Character in
            c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "-") ? c : "-"
        }
        let collapsed = String(lowered).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        let trimmed = String(collapsed.prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return isValidDatasetID(trimmed) ? trimmed : "dataset"
        // 한글 프로젝트 이름은 ASCII가 남지 않아 기본값이 된다. 저장 창에서 바꿔 쓴다.
    }

    // MARK: 조립

    /// `projectData`는 내보내기를 시작한 순간의 프로젝트 파일이다. 지도와 그래프를 모두 이 값에서 만든다.
    static func build(projectData: Data, datasetID: String, documents: [UUID: DrawingDocument],
                      now: Date = Date(), reporter: LongTaskReporter? = nil) throws -> Output {
        guard isValidDatasetID(datasetID) else {
            throw Blocked(messages: ["dataset_id ‘\(datasetID)’를 쓸 수 없습니다. 영문 소문자·숫자·. _ -만 64자 이내로 쓰세요."])
        }
        var blockers: [String] = []
        let project = try ProjectFile.decoded(from: projectData).commonProject()
        let graph = project.routingGraph

        var archive: IMDFArchive.Output?
        do {
            archive = try IMDFArchive.build(projectData: projectData, documents: documents, now: now, reporter: reporter)
        } catch let blocked as IMDFArchive.Blocked {
            blockers += blocked.messages.map { "지도: \($0)" }
        }
        reporter?.report(0.9, "길찾기 그래프 확인 중")
        var routing: [String: Any]?
        do { routing = try RoutingExporter.collection(graph) }
        catch let failure as RoutingExporter.Failure { blockers += failure.messages.map { "길찾기: \($0)" } }
        guard blockers.isEmpty, let archive, let routing else { throw Blocked(messages: blockers) }

        // 1. 파일 — 앱이 읽는 8종이 빠졌으면 빈 FeatureCollection을 넣는다(유효한 빈 레이어).
        var imdf = archive.files
        for name in mapFiles where imdf[name] == nil {
            imdf[name] = try encode(["type": "FeatureCollection", "features": [Any]()])
        }
        var files: [String: Data] = [:]
        for (name, data) in imdf {
            guard isSafeRelativePath(name) else { blockers.append("지도: 파일 이름 ‘\(name)’을 묶음 안에 둘 수 없습니다."); continue }
            files[imdfDirectory + "/" + name] = data
        }
        files[routingFile] = try encode(routing)

        // 2. 통합 검증 — 최종 바이트를 다시 읽는다.
        var warnings = archive.warnings.map { "지도: \($0)" }
        let check = verify(files: files, project: project)
        blockers += check.blockers
        warnings += check.warnings
        guard blockers.isEmpty else { throw Blocked(messages: blockers) }

        // 3. 묶음 메타데이터 — 해시 뒤에는 파일을 바꾸지 않는다.
        var mapHashes: [String: String] = [:], extraHashes: [String: String] = [:]
        for (path, data) in files where path.hasPrefix(imdfDirectory + "/") {
            let name = String(path.dropFirst(imdfDirectory.count + 1))
            if mapFiles.contains(name) { mapHashes[name] = sha256(data) } else { extraHashes[name] = sha256(data) }
        }
        let dataset: [String: Any] = [
            "schema_version": schemaVersion,
            "dataset_id": datasetID,
            "layout_version": graph.layoutVersion,
            "map_files_sha256": mapHashes,
            "additional_map_files_sha256": extraHashes,
            "routing_sha256": sha256(files[routingFile]!),
            "shelves_sha256": NSNull(),
            // 명시적인 서가 매핑이 없다. null은 '미제공'이며 가짜 매핑을 만들지 않았다는 뜻이다.
            "generated_by": "IM-DFrnt"
        ]
        files[datasetFile] = try encode(dataset)
        reporter?.report(1, "완료")
        return Output(files: files, ids: archive.ids, levelCount: project.levels.count,
                      nodeCount: graph.nodes.count, edgeCount: graph.edges.count, warnings: warnings)
    }

    // MARK: 검증

    struct Check { var blockers: [String] = []; var warnings: [String] = [] }

    static func verify(files: [String: Data], project: BuildingProject) -> Check {
        var result = Check()
        func object(_ path: String) -> [String: Any]? {
            files[path].flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        }
        let levelNames = Dictionary(project.levels.map { ($0.id.uuidString.lowercased(), $0.info.name) }) { a, _ in a }

        // 지도 — 파일마다 Feature ID 유일, geometry·좌표 유효, 필수 파일은 비어 있지 않음.
        var typesByID: [String: Set<String>] = [:]
        var levelFeatures: [String: [String: Any]] = [:]
        for path in files.keys.sorted() where path.hasPrefix(imdfDirectory + "/") && path.hasSuffix(".geojson") {
            let name = String(path.dropFirst(imdfDirectory.count + 1))
            guard let collection = object(path), collection["type"] as? String == "FeatureCollection",
                  let features = collection["features"] as? [[String: Any]] else {
                result.blockers.append("\(name): FeatureCollection으로 읽을 수 없습니다."); continue
            }
            if requiredNonEmpty.contains(name) && features.isEmpty {
                result.blockers.append("\(name)에 feature가 없습니다. 앱이 건물·층을 만들 수 없어 빈 파일로 내보내지 않습니다.")
            }
            var seen = Set<String>()
            for feature in features {
                guard let id = (feature["id"] as? String)?.lowercased(), !id.isEmpty else {
                    result.blockers.append("\(name): id가 없는 feature가 있습니다."); continue
                }
                if !seen.insert(id).inserted { result.blockers.append("\(name): Feature ID \(id)가 중복됩니다.") }
                typesByID[id, default: []].insert(name)
                if let problem = geometryProblem(feature["geometry"]) {
                    result.blockers.append("\(name) \(id): \(problem)")
                }
                if name == "level.geojson" { levelFeatures[id] = feature }
            }
        }
        for (id, names) in typesByID where names.count > 1 {
            result.warnings.append("타입 간 ID 중복 \(id): \(names.sorted().joined(separator: ", ")) — 앱의 strict 검증에서 거부됩니다.")
            // C5 원본처럼 가져온 데이터의 호환 예외일 수 있다. 조용히 UUID를 바꾸지 않고 알린다.
        }

        // 층 — 프로젝트의 모든 층이 level.geojson에 같은 UUID·ordinal로 있어야 한다.
        var ordinals: [String: Int] = [:]
        for (id, feature) in levelFeatures {
            if let ordinal = (feature["properties"] as? [String: Any])?["ordinal"] as? Int { ordinals[id] = ordinal }
            else { result.blockers.append("level.geojson \(id): ordinal이 정수가 아닙니다.") }
        }
        for level in project.levels {
            let id = level.id.uuidString.lowercased()
            guard let ordinal = ordinals[id] else {
                if levelFeatures[id] == nil { result.blockers.append("\(level.info.name): level.geojson에 이 층(\(id))이 없습니다.") }
                continue
            }
            if ordinal != level.info.ordinal {
                result.blockers.append("\(level.info.name): level.geojson의 ordinal \(ordinal)이 층 번호 \(level.info.ordinal)과 다릅니다.")
            }
        }

        // 그래프 — 노드의 층 참조, 간선 끝점·길이.
        guard let routing = object(routingFile), let features = routing["features"] as? [[String: Any]] else {
            result.blockers.append("\(routingFile)를 읽을 수 없습니다."); return result
        }
        var nodes: [String: (level: String, ordinal: Int, coordinate: [Double], label: String)] = [:]
        var edges: [(id: String, from: String, to: String, coordinates: [[Double]])] = []
        for feature in features {
            guard let id = feature["id"] as? String, let props = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any] else {
                result.blockers.append("\(routingFile): id·properties·geometry가 없는 feature가 있습니다."); continue
            }
            if let problem = geometryProblem(geometry) { result.blockers.append("\(routingFile) \(id): \(problem)") }
            switch props["role"] as? String {
            case "node":
                let name = (props["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "노드 \(id.prefix(8))"
                guard let level = props["level_id"] as? String, let ordinal = props["level"] as? Int,
                      let coordinate = geometry["coordinates"] as? [Double] else {
                    result.blockers.append("\(name): level_id·level·Point 좌표가 없습니다."); continue
                }
                if let expected = ordinals[level] {
                    if expected != ordinal { result.blockers.append("\(name): level \(ordinal)이 level.geojson의 ordinal \(expected)과 다릅니다.") }
                } else {
                    result.blockers.append("\(name): level_id \(level)가 함께 내보낸 level.geojson에 없습니다.")
                }
                nodes[id] = (level, ordinal, coordinate, "\(levelNames[level] ?? level) \(name)")
            case "edge":
                guard let from = props["from"] as? String, let to = props["to"] as? String,
                      let coordinates = geometry["coordinates"] as? [[Double]] else {
                    result.blockers.append("연결 \(id.prefix(8)): from·to·LineString 좌표가 없습니다."); continue
                }
                edges.append((id, from, to, coordinates))
            default:
                result.blockers.append("\(routingFile) \(id): role이 node·edge가 아닙니다.")
            }
        }
        if nodes.isEmpty { result.blockers.append("길찾기 묶음에는 노드가 하나 이상 있어야 합니다.") }
        var degree: [String: Int] = [:]
        var crossLevel = 0
        for edge in edges {
            let tag = "연결 \(edge.id.prefix(8))"
            guard let a = nodes[edge.from], let b = nodes[edge.to] else {
                result.blockers.append("\(tag): 묶음 안에 없는 노드를 가리킵니다."); continue
            }
            if edge.from == edge.to { result.blockers.append("\(tag): 자기 자신에 연결됩니다.") }
            if edge.coordinates.first != a.coordinate || edge.coordinates.last != b.coordinate {
                result.blockers.append("\(tag) (\(a.label) ↔ \(b.label)): LineString 끝점이 노드 좌표와 다릅니다.")
            }
            if a.level == b.level {
                if !edge.coordinates.contains(where: { $0 != edge.coordinates.first }) {
                    result.blockers.append("\(tag) (\(a.label) ↔ \(b.label)): 같은 층 연결의 길이가 0입니다.")
                }
            } else { crossLevel += 1 }
            degree[edge.from, default: 0] += 1
            degree[edge.to, default: 0] += 1
        }

        // 경고 — 삭제·자동 연결 없이 알리기만 한다.
        let isolated = nodes.keys.filter { degree[$0] == nil }.sorted()
        if !isolated.isEmpty {
            result.warnings.append("고립 노드 \(isolated.count)개: " + isolated.prefix(5).map { nodes[$0]!.label }.joined(separator: ", ")
                                   + (isolated.count > 5 ? " 외" : ""))
        }
        let components = project.routingGraph.componentCount
        if components > 1 { result.warnings.append("그래프가 연결 그룹 \(components)개로 나뉘어 있습니다.") }
        var outside: [String] = []
        for (id, node) in nodes.sorted(by: { $0.key < $1.key }) {
            guard let geometry = levelFeatures[node.level]?["geometry"] as? [String: Any], node.coordinate.count >= 2 else { continue }
            if !contains(geometry, longitude: node.coordinate[0], latitude: node.coordinate[1]) { outside.append(id) }
        }
        if !outside.isEmpty {
            result.warnings.append("층 외곽 밖 노드 \(outside.count)개(의도한 바깥 출입구인지 확인): "
                                   + outside.prefix(5).map { nodes[$0]!.label }.joined(separator: ", ") + (outside.count > 5 ? " 외" : ""))
        }
        if crossLevel > 0 {
            result.warnings.append("층간 연결 \(crossLevel)개에 실제 거리·이동 시간이 없습니다. 임시 값을 채우지 않았습니다.")
        }
        result.warnings.append("명시적인 서가 매핑이 없어 shelves.json을 만들지 않았습니다(dataset.json의 shelves_sha256 = null).")
        return result
    }

    /// GeoJSON geometry가 WGS 84 `[경도, 위도]`이고 Polygon ring이 닫혀 있는지. 문제가 없으면 `nil`.
    /// IMDF는 address 등 일부 type에 geometry null을 허용한다.
    static func geometryProblem(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let geometry = value as? [String: Any], let type = geometry["type"] as? String else { return "geometry 형식이 올바르지 않습니다." }
        func position(_ p: Any) -> String? {
            guard let p = p as? [Double], (2...3).contains(p.count), p.allSatisfy(\.isFinite) else {
                return "좌표는 [경도, 위도] 유한값이어야 합니다."
            }
            return abs(p[0]) <= 180 && abs(p[1]) <= 90 ? nil : "WGS 84 좌표 범위를 벗어났습니다: \(p)"
        }
        func line(_ l: Any, minimum: Int) -> String? {
            guard let l = l as? [Any], l.count >= minimum else { return "좌표 수가 부족합니다." }
            return l.lazy.compactMap(position).first
        }
        func ring(_ r: Any) -> String? {
            if let problem = line(r, minimum: 4) { return problem }
            let r = r as! [[Double]]
            return r.first == r.last ? nil : "Polygon ring이 닫혀 있지 않습니다(첫 점과 마지막 점이 다릅니다)."
        }
        func polygon(_ p: Any) -> String? {
            guard let p = p as? [Any], !p.isEmpty else { return "Polygon ring이 없습니다." }
            return p.lazy.compactMap(ring).first
        }
        let coordinates = geometry["coordinates"] as Any
        switch type {
        case "Point": return position(coordinates)
        case "MultiPoint", "LineString": return line(coordinates, minimum: type == "LineString" ? 2 : 1)
        case "MultiLineString":
            guard let lines = coordinates as? [Any], !lines.isEmpty else { return "선이 없습니다." }
            return lines.lazy.compactMap { line($0, minimum: 2) }.first
        case "Polygon": return polygon(coordinates)
        case "MultiPolygon":
            guard let polygons = coordinates as? [Any], !polygons.isEmpty else { return "MultiPolygon이 비었습니다." }
            return polygons.lazy.compactMap(polygon).first
        default: return "지원하지 않는 geometry type \(type)입니다."
        }
    }

    /// 층 외곽 안에 있는지(경고용). 구멍 안이면 밖으로 본다.
    static func contains(_ geometry: [String: Any], longitude x: Double, latitude y: Double) -> Bool {
        func inside(_ ring: [[Double]]) -> Bool {
            var result = false
            var j = ring.count - 1
            for i in ring.indices {
                let (xi, yi, xj, yj) = (ring[i][0], ring[i][1], ring[j][0], ring[j][1])
                if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { result.toggle() }
                j = i
            }
            return result
        }
        func polygon(_ rings: [[[Double]]]) -> Bool {
            guard let outer = rings.first, inside(outer) else { return false }
            return !rings.dropFirst().contains(where: inside)
        }
        switch geometry["type"] as? String {
        case "Polygon": return (geometry["coordinates"] as? [[[Double]]]).map(polygon) ?? true
        case "MultiPolygon": return (geometry["coordinates"] as? [[[[Double]]]])?.contains(where: polygon) ?? true
        default: return true
        }
    }

    // MARK: 저장

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// 같은 볼륨의 임시 폴더에 모두 쓰고 확인한 뒤 한 번에 자리를 바꾼다.
    /// 중간에 실패하면 임시 폴더만 지우고 기존 결과는 그대로 둔다. 기존 폴더는 `replacing`일 때만 바꾼다.
    static func write(_ files: [String: Data], to destination: URL, replacing: Bool) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        for (path, data) in files {
            guard isSafeRelativePath(path) else { throw Blocked(messages: ["파일 이름 ‘\(path)’을 묶음 안에 둘 수 없습니다."]) }
            let url = staging.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        for (path, data) in files where (try? Data(contentsOf: staging.appendingPathComponent(path))) != data {
            throw Blocked(messages: ["\(path)를 저장한 내용이 만든 내용과 다릅니다."])
        }
        if fm.fileExists(atPath: destination.path) {
            guard replacing else { throw Blocked(messages: ["\(destination.lastPathComponent)이 이미 있습니다. 교체를 선택해야 바꿉니다."]) }
            let backup = parent.appendingPathComponent(".\(destination.lastPathComponent).previous-\(UUID().uuidString)", isDirectory: true)
            try fm.moveItem(at: destination, to: backup)
            do { try fm.moveItem(at: staging, to: destination) } catch {
                try? fm.moveItem(at: backup, to: destination)
                throw error
                // 새 묶음을 놓지 못하면 기존 묶음을 원래 자리로 돌린다.
            }
            try? fm.removeItem(at: backup)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

@MainActor
extension AppEnvironment {

    /// 모든 층의 지도와 길찾기 그래프를 클라이언트용 묶음 폴더로 내보낸다(#54).
    func exportClientDataset() {
        guard !isProjectBusy else { return }
        guard !buildingProject.levels.isEmpty else {
            notify("층이 없습니다. 건물·층 관리에서 층을 만든 뒤 내보내세요.", isError: true)
            return
        }
        var pending: [String] = []
        if !pointDraft.isEmpty { pending.append("작성 중인 도형(점 \(pointDraft.points.count)개)") }
        if !doorDraftPoints.isEmpty { pending.append("작성 중인 임시 문(점 \(doorDraftPoints.count)개)") }
        if routingPendingAnchor != nil { pending.append("경도·위도를 입력하지 않은 좌표 기준점") }
        if !pending.isEmpty {
            let alert = NSAlert()
            alert.messageText = "적용하지 않은 입력은 묶음에 들어가지 않습니다"
            alert.informativeText = pending.joined(separator: ", ")
                + "은(는) 아직 저장되지 않았습니다. 저장된 개체·노드·연결만 내보냅니다. 포함하려면 취소하고 먼저 마무리하세요."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "저장된 상태로 내보내기")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = ClientDataset.suggestedDatasetID(from: projectDisplayName)
        panel.canCreateDirectories = true
        panel.title = "클라이언트용 데이터 묶음 저장"
        panel.message = "폴더 이름이 dataset_id가 됩니다(영문 소문자·숫자·. _ -). 모든 층의 IMDF·길찾기 그래프·dataset.json을 담습니다."
        panel.prompt = "내보내기"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let datasetID = url.lastPathComponent
        guard ClientDataset.isValidDatasetID(datasetID) else {
            notify("폴더 이름 ‘\(datasetID)’는 dataset_id로 쓸 수 없습니다. 영문 소문자·숫자·. _ -만 64자 이내로 쓰세요.", isError: true)
            return
        }
        var replacing = false
        if FileManager.default.fileExists(atPath: url.path) {
            let alert = NSAlert()
            alert.messageText = "‘\(datasetID)’ 폴더를 통째로 교체할까요?"
            alert.informativeText = "기존 폴더 안의 파일(손으로 고친 파일 포함)이 새 묶음으로 바뀝니다. 취소하면 아무것도 바꾸지 않습니다."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "교체")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            replacing = true
        }

        guard var file = makeProjectFile() else { return }
        file.buildingProject = projectContents
        let projectData: Data
        do { projectData = try file.encoded() } catch {
            notify("프로젝트를 정리하지 못했습니다: \(error.localizedDescription)", isError: true)
            return
        }
        // 이 순간의 프로젝트 하나로 지도와 그래프를 모두 만든다. 내보내는 동안 편집해도 섞이지 않는다.
        var documents: [UUID: DrawingDocument] = [:]
        for level in projectContents.levels {
            if level.id == routingFloorID, let document { documents[level.id] = document }
            else if let cached = levelDrawingCache.cached(LevelDrawingInput(level))?.document { documents[level.id] = cached }
        }
        let drawings = documents, replace = replacing
        isProjectActionInProgress = true
        let task = beginLongTask("클라이언트용 묶음 만드는 중", detail: "층 확인 중")
        let reporter = longTaskReporter(task)
        Task {
            defer { isProjectActionInProgress = false; endLongTask(task) }
            let output: ClientDataset.Output
            do {
                output = try await Task.detached(priority: .userInitiated) {
                    let built = try ClientDataset.build(projectData: projectData, datasetID: datasetID,
                                                        documents: drawings, reporter: reporter)
                    reporter.report(1, "폴더에 쓰는 중")
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try ClientDataset.write(built.files, to: url, replacing: replace)
                    return built
                }.value
            } catch let blocked as ClientDataset.Blocked {
                endLongTask(task)
                clientDatasetBlockers = blocked.messages
                return
            } catch {
                notify("클라이언트용 묶음을 저장하지 못했습니다. 기존 결과는 그대로입니다: \(error.localizedDescription)", isError: true)
                return
            }
            adoptExportedIDs(output.ids)
            // 새로 발급한 id를 프로젝트에 남긴다. 다음 내보내기에서 같은 feature가 같은 id를 갖는다.
            let summary = "\(datasetID) 저장 완료 — 층 \(output.levelCount)개 · 노드 \(output.nodeCount)개 · 연결 \(output.edgeCount)개 · 파일 \(output.files.count)개"
            notify(([summary] + output.warnings).joined(separator: " · "))
        }
    }
}
