import CoreGraphics
import Foundation

/// Tests the geographic output, not source SVG bounds. All boolean operations use one metre-based
/// local projection; the tiny area tolerance is numerical noise, not a surveying accuracy allowance.
enum IMDFSpatialValidation {
    static let areaEpsilon = 0.0001
    static let distanceEpsilon = 0.00001

    struct Geometry {
        var polygons: [[[LocalPoint]]] = []
        var lines: [[LocalPoint]] = []
        var points: [LocalPoint] = []
        var rings: [[LocalPoint]] { polygons.flatMap { $0 } }
        var vertices: [LocalPoint] { rings.flatMap { $0 } + lines.flatMap { $0 } + points }
        var path: CGPath { UnitCoverage.path(rings) }
    }

    struct Projection {
        var longitude: Double
        var latitude: Double
        func point(_ p: [Double]) -> LocalPoint {
            LocalPoint((p[0] - longitude) * 111_319.490793 * max(1e-8, cos(latitude * .pi / 180)),
                       (p[1] - latitude) * 111_319.490793)
        }
    }

    struct Invalid: Error { let message: String }

    static func check(_ records: [IMDFValidation.Record], byID: [String: IMDFValidation.Record], result: inout IMDFValidation.Report,
                      openingBoundaryPolicy: IMDFValidation.OpeningBoundaryPolicy = .strict) {
        func coordinate(_ value: ProjectJSON?) -> [Double]? {
            guard let value else { return nil }
            let a = value.array
            if a.count >= 2, let x = a[0].double, let y = a[1].double { return [x, y] }
            return a.lazy.compactMap { coordinate($0) }.first
        }
        let first = records.lazy.compactMap { coordinate($0.value["geometry"]?["coordinates"]) }.first ?? [0, 0]
        let projection = Projection(longitude: first[0], latitude: first[1])
        var geometries: [String: Geometry] = [:]
        var displayPoints: [String: LocalPoint] = [:]
        for record in records {
            do {
                guard let raw = record.value["geometry"] else { throw Invalid(message: "geometry 멤버가 필요합니다.") }
                if let type = record.type {
                    let kind = raw["type"]?.string ?? "null"
                    let allowed: [String] = switch type {
                    case .address, .building, .occupant, .manifest: ["null"]
                    case .anchor, .amenity: ["Point"]
                    case .opening: ["LineString"]
                    case .detail: ["LineString", "MultiLineString"]
                    case .relationship: ["null", "Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon", "GeometryCollection"]
                    default: ["Polygon", "MultiPolygon"]
                    }
                    if !allowed.contains(kind) { throw Invalid(message: "geometry는 \(allowed.joined(separator: "/"))이어야 합니다.") }
                }
                let geometry = try parse(raw, projection: projection)
                geometries[record.id] = geometry
                let officialDisplayPoint = record.type.map { type in
                    PropertySchema.fields(for: type).contains { $0.key == "display_point" && !$0.isNonStandard }
                } ?? false
                if officialDisplayPoint, let point = record.properties["display_point"], point != .null {
                    guard point["type"]?.string == "Point" else { throw Invalid(message: "display_point는 GeoJSON Point여야 합니다.") }
                    let parsed = try parse(point, projection: projection)
                    displayPoints[record.id] = parsed.points.first
                }
                for polygon in geometry.polygons {
                    for (index, ring) in polygon.enumerated() {
                        let area = ClosedPolygonFinder.signedArea(ring)
                        if (index == 0 && area < 0) || (index > 0 && area > 0) {
                            result.warnings.append("\(record.label): Polygon 바깥 링은 반시계, 구멍은 시계 방향을 권장합니다. Apple은 현재 이를 경고로 처리합니다.")
                            break
                        }
                    }
                }
            } catch let error as Invalid { result.errors.append("\(record.label) · geometry: \(error.message)") }
            catch { result.errors.append("\(record.label) · geometry: 도형을 읽을 수 없습니다.") }
        }

        let venues = records.filter { $0.type == .venue }
        if venues.count == 1, let venue = geometries[venues[0].id], !venue.polygons.isEmpty {
            for record in records where record.type != .venue {
                guard let shape = geometries[record.id] else { continue }
                if !covered(shape, by: venue) { result.errors.append("\(record.label): geometry가 Venue 경계를 벗어납니다.") }
            }
        }

        for record in records {
            let p = record.properties
            if let dp = displayPoints[record.id] {
                if record.type == .building {
                    let footprints = records.filter { $0.type == .footprint && $0.properties["building_ids"]?.array.contains(where: { $0.string?.lowercased() == record.id }) == true }
                    if !footprints.contains(where: { geometries[$0.id].map { contains(dp, in: $0) } == true }) {
                        result.errors.append("\(record.label) · display_point: 이 Building을 참조하는 Footprint 안에 있어야 합니다.")
                    }
                } else if let shape = geometries[record.id], !contains(dp, in: shape) {
                    result.errors.append("\(record.label) · display_point: 해당 Feature 도형 안에 있어야 합니다.")
                }
            }
            if record.type == .anchor, let unitID = p["unit_id"]?.string?.lowercased(), let unit = geometries[unitID],
               let point = geometries[record.id]?.points.first, !contains(point, in: unit) {
                result.errors.append("\(record.label): Anchor는 unit_id가 가리키는 Unit 안에 있어야 합니다.")
            }
            if record.type == .unit, let levelID = p["level_id"]?.string?.lowercased(),
               let unit = geometries[record.id], let level = geometries[levelID], !covered(unit, by: level) {
                result.errors.append("\(record.label): Unit이 참조 Level 경계를 벗어납니다.")
            }
            if record.type == .opening, let opening = geometries[record.id] {
                let levelID = p["level_id"]?.string?.lowercased()
                let units = records.filter { $0.type == .unit && $0.properties["level_id"]?.string?.lowercased() == levelID }
                if !units.contains(where: { candidate in
                    guard let unit = geometries[candidate.id] else { return false }
                    return opening.lines.allSatisfy { lineOnBoundary($0, rings: unit.rings) }
                }) {
                    switch openingBoundaryPolicy {
                    case .strict:
                        result.errors.append("\(record.label): Opening은 같은 Level의 Unit 경계 위에 있어야 합니다.")
                    case .allowMismatchForSandbox:
                        result.warnings.append("\(record.label): Sandbox 검사용으로 Opening–Unit 경계 불일치를 허용했습니다. 도형은 수정하지 않았으므로 Sandbox에서 확인하세요.")
                    }
                }
            }
            if record.type == .geofence, let shape = geometries[record.id] {
                for levelID in p["level_ids"]?.array.compactMap({ $0.string?.lowercased() }) ?? [] {
                    if let level = geometries[levelID], !intersects(shape, level) { result.errors.append("\(record.label) · level_ids: 참조 Level과 Geofence가 겹치지 않습니다.") }
                }
                for buildingID in p["building_ids"]?.array.compactMap({ $0.string?.lowercased() }) ?? [] {
                    let footprints = records.filter { $0.type == .footprint && $0.properties["building_ids"]?.array.contains(where: { $0.string?.lowercased() == buildingID }) == true }
                    if !footprints.contains(where: { geometries[$0.id].map { intersects(shape, $0) } == true }) { result.errors.append("\(record.label) · building_ids: 참조 Building의 Footprint와 겹치지 않습니다.") }
                }
            }
        }

        let levels = records.filter { $0.type == .level }
        for level in levels {
            guard let boundary = geometries[level.id], !boundary.polygons.isEmpty else { continue }
            let units = records.filter { $0.type == .unit && $0.properties["level_id"]?.string?.lowercased() == level.id }
            let shapes = units.compactMap { geometries[$0.id] }
            let coverage = UnitCoverage.analyze(units: shapes.map(\.rings), levels: [boundary.rings])
            if !coverage.gaps.isEmpty { result.errors.append("\(level.label): Unit 합집합이 Level 전체를 덮지 않습니다. unit 빈틈 표시에서 확인하세요.") }
            if !coverage.overlaps.isEmpty { result.errors.append("\(level.label): 같은 Level의 Unit끼리 면적으로 겹칩니다. unit 겹침 표시에서 확인하세요.") }
            let hasOpening = records.contains { $0.type == .opening && $0.properties["level_id"]?.string?.lowercased() == level.id }
            let exception = units.contains { unit in
                ["nonpublic", "walkway.island"].contains(unit.properties["category"]?.string ?? "")
                    && geometries[unit.id].map { equal($0, boundary) } == true
            }
            let verticalAmenities = records.contains { amenity in
                guard amenity.type == .amenity, ["elevator", "escalator", "movingwalkway", "ramp", "stairs"].contains(amenity.properties["category"]?.string ?? "") else { return false }
                return amenity.properties["unit_ids"]?.array.contains { value in
                    byID[value.string?.lowercased() ?? ""]?.properties["level_id"]?.string?.lowercased() == level.id
                } == true
            }
            if !hasOpening && !exception && !verticalAmenities { result.errors.append("\(level.label): Opening이 필요합니다. nonpublic/walkway.island와 동일한 Level 또는 층간 Amenity가 있는 경우만 예외입니다.") }
        }
        for (i, a) in levels.enumerated() {
            for b in levels.dropFirst(i + 1) where a.properties["ordinal"] == b.properties["ordinal"] {
                let aBuildings = Set(a.properties["building_ids"]?.array.compactMap { $0.string?.lowercased() } ?? [])
                let bBuildings = Set(b.properties["building_ids"]?.array.compactMap { $0.string?.lowercased() } ?? [])
                if !aBuildings.isDisjoint(with: bBuildings), let ga = geometries[a.id], let gb = geometries[b.id], intersects(ga, gb) {
                    result.errors.append("\(a.label) / \(b.label): 같은 Building·ordinal의 Level은 면적으로 겹칠 수 없습니다.")
                }
            }
        }
    }

    private static func parse(_ value: ProjectJSON, projection: Projection, depth: Int = 0) throws -> Geometry {
        if value == .null { return Geometry() }
        guard depth < 32, value.isObject, let type = value["type"]?.string else { throw Invalid(message: "GeoJSON geometry 객체가 필요합니다.") }
        func point(_ value: ProjectJSON) throws -> LocalPoint {
            let numbers = value.array.compactMap(\.double)
            guard value.isArray, numbers.count == value.array.count, numbers.count >= 2,
                  numbers.allSatisfy(\.isFinite), abs(numbers[0]) <= 180, abs(numbers[1]) <= 90 else { throw Invalid(message: "유한한 경도(-180…180)·위도(-90…90)가 필요합니다.") }
            return projection.point(numbers)
        }
        func line(_ value: ProjectJSON) throws -> [LocalPoint] {
            guard value.isArray, value.array.count >= 2 else { throw Invalid(message: "LineString에는 점이 최소 2개 필요합니다.") }
            let points = try value.array.map(point)
            guard Set(points).count >= 2 else { throw Invalid(message: "길이가 0인 LineString입니다.") }
            return points
        }
        func polygon(_ value: ProjectJSON) throws -> [[LocalPoint]] {
            guard value.isArray, !value.array.isEmpty else { throw Invalid(message: "Polygon 외곽 링이 필요합니다.") }
            let rings = try value.array.map { raw -> [LocalPoint] in
                guard raw.isArray, raw.array.count >= 4, raw.array.first == raw.array.last else { throw Invalid(message: "Polygon 링은 점 4개 이상이고 처음·마지막 좌표가 같아야 합니다.") }
                let ring = try raw.array.dropLast().map(point)
                guard Set(ring).count >= 3, !PolygonValidity.isDegenerate(ring), !PolygonValidity.selfIntersects(ring),
                      !ring.indices.contains(where: { ring[$0] == ring[($0 + 1) % ring.count] }) else { throw Invalid(message: "Polygon 링에 중복 변·자기 교차·면적 0이 있습니다.") }
                return ring
            }
            for hole in rings.dropFirst() where RingNesting.relation(hole, to: rings[0]) != .inside { throw Invalid(message: "Polygon의 구멍은 외곽 링 안에 있어야 합니다.") }
            for (i, a) in rings.dropFirst().enumerated() {
                for b in rings.dropFirst(i + 2) where RingNesting.relation(a, to: b) != .disjoint { throw Invalid(message: "Polygon 구멍끼리 겹치거나 포함될 수 없습니다.") }
            }
            return rings
        }
        let coordinates = value["coordinates"] ?? .null
        switch type {
        case "Point": return Geometry(points: [try point(coordinates)])
        case "MultiPoint":
            guard coordinates.isArray, !coordinates.array.isEmpty else { throw Invalid(message: "MultiPoint 좌표가 필요합니다.") }
            return Geometry(points: try coordinates.array.map(point))
        case "LineString": return Geometry(lines: [try line(coordinates)])
        case "MultiLineString":
            guard coordinates.isArray, !coordinates.array.isEmpty else { throw Invalid(message: "MultiLineString 좌표가 필요합니다.") }
            return Geometry(lines: try coordinates.array.map(line))
        case "Polygon": return Geometry(polygons: [try polygon(coordinates)])
        case "MultiPolygon":
            guard coordinates.isArray, !coordinates.array.isEmpty else { throw Invalid(message: "MultiPolygon 좌표가 필요합니다.") }
            let polygons = try coordinates.array.map(polygon)
            for (i, a) in polygons.enumerated() {
                for b in polygons.dropFirst(i + 1) where intersects(Geometry(polygons: [a]), Geometry(polygons: [b])) { throw Invalid(message: "MultiPolygon 구성 다각형끼리 면적으로 겹칩니다.") }
            }
            return Geometry(polygons: polygons)
        case "GeometryCollection":
            guard value["geometries"]?.isArray == true else { throw Invalid(message: "GeometryCollection geometries 배열이 필요합니다.") }
            var output = Geometry()
            for child in value["geometries"]!.array {
                let parsed = try parse(child, projection: projection, depth: depth + 1)
                output.polygons += parsed.polygons; output.lines += parsed.lines; output.points += parsed.points
            }
            return output
        default: throw Invalid(message: "지원되는 GeoJSON geometry 타입이 아닙니다: \(type)")
        }
    }

    private static func area(_ path: CGPath) -> Double { abs(UnitCoverage.area(path)) }
    private static func intersects(_ a: Geometry, _ b: Geometry) -> Bool {
        a.path.boundingBoxOfPath.intersects(b.path.boundingBoxOfPath)
            && area(a.path.intersection(b.path, using: .evenOdd)) > areaEpsilon
    }
    private static func equal(_ a: Geometry, _ b: Geometry) -> Bool { covered(a, by: b) && covered(b, by: a) }
    private static func contains(_ point: LocalPoint, in shape: Geometry) -> Bool {
        shape.path.contains(point.cg, using: .evenOdd) || onBoundary(point, rings: shape.rings)
            || shape.lines.contains { line in zip(line, line.dropFirst()).contains { distance(point, $0.0, $0.1) <= distanceEpsilon } }
    }
    private static func covered(_ a: Geometry, by b: Geometry) -> Bool {
        if !a.polygons.isEmpty, area(a.path.subtracting(b.path, using: .evenOdd)) > areaEpsilon { return false }
        if !a.points.allSatisfy({ contains($0, in: b) }) { return false }
        return a.lines.allSatisfy { line in
            zip(line, line.dropFirst()).allSatisfy { segment in
                segmentParts(segment.0, segment.1, rings: b.rings).allSatisfy { contains($0, in: b) }
            }
        }
    }
    private static func onBoundary(_ point: LocalPoint, rings: [[LocalPoint]]) -> Bool {
        rings.contains { ring in ring.indices.contains { distance(point, ring[$0], ring[($0 + 1) % ring.count]) <= distanceEpsilon } }
    }
    private static func lineOnBoundary(_ line: [LocalPoint], rings: [[LocalPoint]]) -> Bool {
        zip(line, line.dropFirst()).allSatisfy { segment in
            segmentParts(segment.0, segment.1, rings: rings).allSatisfy { onBoundary($0, rings: rings) }
        }
    }
    /// Split at every boundary crossing, not just endpoints/midpoint (concavities and holes matter).
    private static func segmentParts(_ a: LocalPoint, _ b: LocalPoint, rings: [[LocalPoint]]) -> [LocalPoint] {
        let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
        guard length2 > 0 else { return [a] }
        var parameters: [Double] = [0, 1]
        for ring in rings {
            for i in ring.indices {
                let c = ring[i], d = ring[(i + 1) % ring.count]
                let ex = d.x - c.x, ey = d.y - c.y
                let cross = dx * ey - dy * ex
                if abs(cross) > 1e-12 {
                    let t = ((c.x - a.x) * ey - (c.y - a.y) * ex) / cross
                    let u = ((c.x - a.x) * dy - (c.y - a.y) * dx) / cross
                    if t > 0 && t < 1 && u >= 0 && u <= 1 { parameters.append(t) }
                } else {
                    for point in [c, d] where distance(point, a, b) <= distanceEpsilon {
                        let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / length2
                        if t > 0 && t < 1 { parameters.append(t) }
                    }
                }
            }
        }
        parameters.sort()
        var samples = parameters
        samples += zip(parameters, parameters.dropFirst()).map { ($0 + $1) / 2 }
        return samples.map { LocalPoint(a.x + dx * $0, a.y + dy * $0) }
    }
    private static func distance(_ p: LocalPoint, _ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, l = dx * dx + dy * dy
        let t = l == 0 ? 0 : min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
