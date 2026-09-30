import CoreLocation
import Foundation

/// OpenStreetMap의 건물 외곽. 지도 타일은 MapKit이 그리며 이 자료는 정합 후보에만 쓴다.
struct BuildingFootprint: Identifiable {
    let id: String
    let name: String?
    let coordinates: [GeoPoint] // 닫는 점은 중복 저장하지 않는다.
    let areaSquareMeters: Double
    let distanceMeters: Double

    var center: GeoPoint {
        GeoPoint(longitude: coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count),
                 latitude: coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count))
    }

    var displayName: String {
        let title = name ?? "건물 \(id)"
        return String(format: "%@ · %.0f m² · %.0f m", title, areaSquareMeters, distanceMeters)
    }
}

enum BuildingFootprintService {
    enum Failure: LocalizedError {
        case invalidCoordinate
        case httpStatus(Int)
        case responseTooLarge
        case invalidXML

        var errorDescription: String? {
            switch self {
            case .invalidCoordinate: return "장소 좌표가 올바르지 않습니다."
            case .httpStatus(let code): return "건물 외곽 서버가 응답하지 않았습니다 (HTTP \(code))."
            case .responseTooLarge: return "검색 영역의 지도 데이터가 너무 큽니다."
            case .invalidXML: return "건물 외곽 데이터를 읽지 못했습니다."
            }
        }
    }

    /// OSM API 0.6의 bbox map 조회. 장소 근처 180 m만 요청하며 도면은 전송하지 않는다.
    /// https://wiki.openstreetmap.org/wiki/API_0.6#Retrieving_map_data_by_bounding_box:_GET_/api/0.6/map
    static func fetch(near center: GeoPoint) async throws -> [BuildingFootprint] {
        guard (-180...180).contains(center.longitude), (-85...85).contains(center.latitude),
              center.longitude.isFinite, center.latitude.isFinite else {
            throw Failure.invalidCoordinate
        }
        let latDelta = 180.0 / 111_000
        let lonDelta = 180.0 / (111_000 * cos(center.latitude * .pi / 180))
        var components = URLComponents(string: "https://api.openstreetmap.org/api/0.6/map")!
        components.queryItems = [URLQueryItem(
            name: "bbox",
            value: String(format: "%.7f,%.7f,%.7f,%.7f",
                          center.longitude - lonDelta, center.latitude - latDelta,
                          center.longitude + lonDelta, center.latitude + latDelta))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("IM-DFrnt anchor assistant/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidXML }
        guard http.statusCode == 200 else { throw Failure.httpStatus(http.statusCode) }
        guard data.count <= 5_000_000 else { throw Failure.responseTooLarge }
        return try parse(data, near: center)
    }

    static func parse(_ data: Data, near center: GeoPoint) throws -> [BuildingFootprint] {
        let reader = OSMBuildingReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw Failure.invalidXML }

        let metersPerLongitude = 111_000 * cos(center.latitude * .pi / 180)
        var footprints: [BuildingFootprint] = []
        for way in reader.ways where way.tags["building"] != nil && way.tags["building"] != "no" {
            let points = way.nodeIDs.compactMap { reader.nodes[$0] }
            guard points.count == way.nodeIDs.count, points.count >= 4,
                  points.first == points.last else { continue }
            let ring = Array(points.dropLast())
            let xy = ring.map { (($0.longitude - center.longitude) * metersPerLongitude,
                                 ($0.latitude - center.latitude) * 111_000) }
            let doubleArea = xy.indices.reduce(0.0) { sum, i in
                let next = xy[(i + 1) % xy.count]
                return sum + xy[i].0 * next.1 - next.0 * xy[i].1
            }
            let area = abs(doubleArea) / 2
            guard area >= 25 else { continue }
            let meanX = xy.map(\.0).reduce(0, +) / Double(xy.count)
            let meanY = xy.map(\.1).reduce(0, +) / Double(xy.count)
            let distance = hypot(meanX, meanY)
            footprints.append(BuildingFootprint(id: way.id, name: way.tags["name"],
                                                coordinates: ring, areaSquareMeters: area,
                                                distanceMeters: distance))
        }
        return footprints.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(30).map { $0 }
    }
}

private final class OSMBuildingReader: NSObject, XMLParserDelegate {
    struct Way {
        let id: String
        var nodeIDs: [String] = []
        var tags: [String: String] = [:]
    }

    var nodes: [String: GeoPoint] = [:]
    var ways: [Way] = []
    private var currentWay: Way?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "node":
            if let id = attributes["id"], let lon = Double(attributes["lon"] ?? ""),
               let lat = Double(attributes["lat"] ?? "") {
                nodes[id] = GeoPoint(longitude: lon, latitude: lat)
            }
        case "way":
            if let id = attributes["id"] { currentWay = Way(id: id) }
        case "nd":
            if let ref = attributes["ref"] { currentWay?.nodeIDs.append(ref) }
        case "tag":
            if let key = attributes["k"], let value = attributes["v"] {
                currentWay?.tags[key] = value
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "way", let way = currentWay {
            ways.append(way)
            currentWay = nil
        }
    }
}
