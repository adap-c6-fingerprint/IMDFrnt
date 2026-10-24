import Foundation

/// A reversible display projection, shared by all imported floors. Values are
/// derived from the IMDF geometry, rather than estimated from control points.
struct IMDFCoordinateSpace: Equatable, Codable, Sendable {
    var west: Double
    var north: Double
    var unitsPerLongitudeDegree: Double
    var unitsPerLatitudeDegree: Double
    var padding: Double

    var isValid: Bool {
        [west, north, unitsPerLongitudeDegree, unitsPerLatitudeDegree, padding].allSatisfy(\.isFinite)
            && abs(west) <= 180 && abs(north) <= 90
            && unitsPerLongitudeDegree > 0 && unitsPerLatitudeDegree > 0 && padding >= 0
    }

    func localPoint(longitude: Double, latitude: Double) -> LocalPoint {
        LocalPoint((longitude - west) * unitsPerLongitudeDegree + padding,
                   (north - latitude) * unitsPerLatitudeDegree + padding)
    }

    func geoPoint(for point: LocalPoint) -> GeoPoint {
        GeoPoint(longitude: west + (point.x - padding) / unitsPerLongitudeDegree,
                 latitude: north - (point.y - padding) / unitsPerLatitudeDegree)
    }
}

struct ImportedIMDFFloor: Sendable {
    var id: UUID
    var name: String
    var ordinal: Int
    var svg: String
}

struct ImportedIMDF: Sendable {
    var sourceName: String
    var layoutVersion: String
    var coordinates: IMDFCoordinateSpace
    var floors: [ImportedIMDFFloor]
    var files: [String: ProjectJSON] = [:]
}

enum IMDFImporter {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private static let drawingTypes = ["level", "unit", "section", "fixture", "detail", "opening", "amenity"]

    /// Accept an archive, an unpacked directory, or one of its JSON files.
    /// ZIP entries are read to memory; nothing is extracted into the filesystem.
    static func load(_ url: URL) throws -> ImportedIMDF {
        var files: [String: Data] = [:]
        let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        if !isDirectory && ["zip", "imdf"].contains(url.pathExtension.lowercased()) {
            let listing = try unzip(["-Z1", url.path])
            let entries = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
                .filter { !$0.hasPrefix("__MACOSX/") }
            let levels = entries.filter { ($0 as NSString).lastPathComponent == "level.geojson" }
            guard levels.count == 1, let level = levels.first else {
                throw Failure(message: "ZIP 안에 level.geojson이 포함된 IMDF 지도 하나가 있어야 합니다.")
            }
            let prefix = String(level.dropLast("level.geojson".count))
            for path in entries where path.hasPrefix(prefix) && !String(path.dropFirst(prefix.count)).contains("/") && ["json", "geojson"].contains((path as NSString).pathExtension.lowercased()) {
                let name = String(path.dropFirst(prefix.count))
                guard entries.contains(path) else { continue }
                guard entries.filter({ $0 == path }).count == 1 else {
                    throw Failure(message: "ZIP에 \(name)이 중복되어 있습니다.")
                }
                // unzip treats entry names as patterns, so quote wildcard characters.
                let literal = path.reduce(into: "") { result, character in
                    if "\\*?[]".contains(character) { result.append("\\") }
                    result.append(character)
                }
                files[name] = try unzip(["-p", url.path, literal])
            }
        } else {
            let directory = isDirectory ? url : url.deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where ["json", "geojson"].contains(file.pathExtension.lowercased()) {
                let name = file.lastPathComponent
                if FileManager.default.fileExists(atPath: file.path) { files[name] = try Data(contentsOf: file) }
            }
        }
        return try decode(files: files, sourceName: url.lastPathComponent)
    }

    private static func unzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(message: "IMDF ZIP을 읽지 못했습니다. \(String(decoding: data.prefix(500), as: UTF8.self))")
        }
        return data
    }

    static func decode(files: [String: Data], sourceName: String) throws -> ImportedIMDF {
        guard let levelData = files["level.geojson"] else {
            throw Failure(message: "level.geojson을 찾을 수 없습니다. IMDF ZIP, 폴더 또는 그 안의 manifest.json을 선택하세요.")
        }
        func features(_ data: Data, file: String) throws -> [[String: Any]] {
            guard let collection = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  collection["type"] as? String == "FeatureCollection",
                  let features = collection["features"] as? [[String: Any]] else {
                throw Failure(message: "\(file): GeoJSON FeatureCollection 형식이어야 합니다.")
            }
            return features
        }
        let levels = try features(levelData, file: "level.geojson")
        guard !levels.isEmpty else { throw Failure(message: "IMDF에 층이 없습니다.") }
        var parsedLevels: [(UUID, Int, String, [String: Any])] = []
        for level in levels {
            guard let idString = level["id"] as? String, let id = UUID(uuidString: idString),
                  let properties = level["properties"] as? [String: Any],
                  let ordinal = properties["ordinal"] as? Int else {
                throw Failure(message: "level.geojson: 층 UUID와 정수 ordinal이 필요합니다.")
            }
            let names = properties["name"] as? [String: String]
            let localized: String? = names?["ko"] ?? names?["en"]
            let fallback: String? = names?.sorted(by: { $0.key < $1.key }).first?.value ?? (properties["name"] as? String)
            let defaultName: String = ordinal < 0 ? "지하 \(-ordinal)층" : "\(ordinal + 1)층"
            let name: String = localized ?? fallback ?? defaultName
            parsedLevels.append((id, ordinal, name, level))
        }
        guard Set(parsedLevels.map { $0.0 }).count == levels.count,
              Set(parsedLevels.map { $0.1 }).count == levels.count else {
            throw Failure(message: "층 UUID 또는 ordinal이 중복되어 있습니다. 현재는 건물 하나의 IMDF를 불러올 수 있습니다.")
        }
        let levelIDs = Set(parsedLevels.map { $0.0 })
        var drawings: [UUID: [(String, [String: Any])]] = [:]
        for level in parsedLevels { drawings[level.0] = [("level", level.3)] }
        var unitLevels: [String: UUID] = [:]
        if let data = files["unit.geojson"] {
            for unit in try features(data, file: "unit.geojson") {
                if let id = unit["id"] as? String,
                   let properties = unit["properties"] as? [String: Any],
                   let level = properties["level_id"] as? String, let uuid = UUID(uuidString: level) {
                    unitLevels[id.lowercased()] = uuid
                }
            }
        }
        for type in drawingTypes where type != "level" {
            guard let data = files["\(type).geojson"] else { continue }
            for feature in try features(data, file: "\(type).geojson") {
                let properties = feature["properties"] as? [String: Any] ?? [:]
                var ids = Set<UUID>()
                if let id = properties["level_id"] as? String, let uuid = UUID(uuidString: id) { ids.insert(uuid) }
                for id in properties["level_ids"] as? [String] ?? [] {
                    if let uuid = UUID(uuidString: id) { ids.insert(uuid) }
                }
                // IMDF amenities belong to units, rather than directly to levels.
                for id in properties["unit_ids"] as? [String] ?? [] {
                    if let level = unitLevels[id.lowercased()] { ids.insert(level) }
                }
                if let id = properties["unit_id"] as? String, let level = unitLevels[id.lowercased()] { ids.insert(level) }
                for id in ids where levelIDs.contains(id) { drawings[id, default: []].append((type, feature)) }
            }
        }
        var allPoints: [[Double]] = []
        for items in drawings.values {
            for (_, feature) in items {
                if let geometry = feature["geometry"] as? [String: Any] {
                    allPoints += try coordinatePairs(geometry["coordinates"])
                }
            }
        }
        guard let west = allPoints.map({ $0[0] }).min(), let east = allPoints.map({ $0[0] }).max(),
              let south = allPoints.map({ $0[1] }).min(), let north = allPoints.map({ $0[1] }).max(),
              east > west, north > south, east - west < 180 else {
            throw Failure(message: "층이나 공간의 유효한 Polygon 좌표가 필요합니다.")
        }
        let coordinates = IMDFCoordinateSpace(west: west, north: north,
            unitsPerLongitudeDegree: 1_113_200 * cos((north + south) / 2 * .pi / 180),
            unitsPerLatitudeDegree: 1_113_200, padding: 40)
        guard coordinates.isValid else { throw Failure(message: "IMDF의 좌표 범위가 유효하지 않습니다.") }
        let size = coordinates.localPoint(longitude: east, latitude: south)
        var floors: [ImportedIMDFFloor] = []
        for (id, ordinal, name, _) in parsedLevels.sorted(by: { $0.1 < $1.1 }) {
            var elements: [String] = []
            for (type, feature) in drawings[id] ?? [] {
                guard let geometry = feature["geometry"] as? [String: Any] else { continue }
                let category = (feature["properties"] as? [String: Any])?["category"] as? String ?? ""
                elements.append(try svgElement(geometry, type: type, category: category, coordinates: coordinates))
            }
            guard !elements.isEmpty else { throw Failure(message: "\(name)에 표시할 IMDF 공간이 없습니다.") }
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(size.x + 40))\" height=\"\(number(size.y + 40))\">\n"
                + elements.joined(separator: "\n") + "\n</svg>"
            floors.append(ImportedIMDFFloor(id: id, name: name, ordinal: ordinal, svg: svg))
        }
        var version = "layout-1"
        if let data = files["manifest.json"] {
            guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure(message: "manifest.json 형식이 유효하지 않습니다.")
            }
            // The format version isn't a layout revision. Use the source creation date if present.
            if let created = manifest["created"] as? String, !created.isEmpty { version = created }
        }
        return ImportedIMDF(sourceName: sourceName, layoutVersion: version, coordinates: coordinates, floors: floors,
                            files: try files.mapValues { try ProjectJSON.parse($0) })
    }

    private static func coordinatePairs(_ value: Any?) throws -> [[Double]] {
        guard let array = value as? [Any], !array.isEmpty else { throw Failure(message: "IMDF geometry의 좌표가 비어 있습니다.") }
        if let pair = array as? [Double], pair.count >= 2 {
            guard pair.allSatisfy(\.isFinite), abs(pair[0]) <= 180, abs(pair[1]) <= 90 else {
                throw Failure(message: "IMDF geometry에 유효하지 않은 위경도가 있습니다.")
            }
            return [[pair[0], pair[1]]]
        }
        return try array.flatMap { try coordinatePairs($0) }
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func svgElement(_ geometry: [String: Any], type: String, category: String,
                                   coordinates: IMDFCoordinateSpace) throws -> String {
        _ = try coordinatePairs(geometry["coordinates"])
        func path(_ points: [[Double]], closed: Bool) throws -> String {
            guard points.count >= (closed ? 4 : 2), points.allSatisfy({ $0.count >= 2 }) else {
                throw Failure(message: "\(type).geojson의 선·다각형 좌표가 유효하지 않습니다.")
            }
            if closed && points.first != points.last { throw Failure(message: "\(type).geojson의 Polygon 링이 닫혀 있지 않습니다.") }
            return points.enumerated().map { index, pair in
                let p = coordinates.localPoint(longitude: pair[0], latitude: pair[1])
                return "\(index == 0 ? "M" : "L")\(number(p.x)),\(number(p.y))"
            }.joined(separator: " ") + (closed ? " Z" : "")
        }
        let kind = geometry["type"] as? String ?? ""
        let raw = geometry["coordinates"]
        let d: String
        var fill = type == "level" ? "#edf2f7" : "#cbd5e1"
        var stroke = "#475569"
        if category == "walkway" { fill = "#f8fafc" }
        if category == "stairs" || category == "elevator" { fill = "#a5b4fc" }
        if category == "structure" { fill = "#64748b" }
        if type == "fixture" { fill = "#94a3b8" }
        switch kind {
        case "Polygon":
            guard let rings = raw as? [[[Double]]], !rings.isEmpty else { throw Failure(message: "잘못된 Polygon입니다.") }
            d = try rings.map { try path($0, closed: true) }.joined(separator: " ")
        case "MultiPolygon":
            guard let polygons = raw as? [[[[Double]]]], !polygons.isEmpty, polygons.allSatisfy({ !$0.isEmpty }) else {
                throw Failure(message: "잘못된 MultiPolygon입니다.")
            }
            d = try polygons.flatMap { $0 }.map { try path($0, closed: true) }.joined(separator: " ")
        case "LineString":
            guard let points = raw as? [[Double]] else { throw Failure(message: "잘못된 LineString입니다.") }
            d = try path(points, closed: false); fill = "none"
        case "MultiLineString":
            guard let lines = raw as? [[[Double]]], !lines.isEmpty else { throw Failure(message: "잘못된 MultiLineString입니다.") }
            d = try lines.map { try path($0, closed: false) }.joined(separator: " "); fill = "none"
        case "Point":
            let pairs = try coordinatePairs(raw)
            guard pairs.count == 1 else { throw Failure(message: "잘못된 Point입니다.") }
            let point = coordinates.localPoint(longitude: pairs[0][0], latitude: pairs[0][1])
            return "<circle cx=\"\(number(point.x))\" cy=\"\(number(point.y))\" r=\"3\" fill=\"#818cf8\" stroke=\"#6366f1\"/>"
        default: throw Failure(message: "\(type).geojson: 지원하지 않는 geometry \(kind)입니다.")
        }
        if type == "opening" { stroke = "#059669" }
        return "<path d=\"\(d)\" fill=\"\(fill)\" fill-rule=\"evenodd\" stroke=\"\(stroke)\" stroke-width=\"\(type == "opening" ? "3" : "1")\"/>"
    }
}
