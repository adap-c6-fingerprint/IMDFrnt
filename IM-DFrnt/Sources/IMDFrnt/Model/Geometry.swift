import CoreGraphics
import Foundation

// MARK: - 좌표 타입

struct LocalPoint: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    // SVG 도면 안에서만 통하는 좌표. 위경도가 아니다.

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(x: Double, y: Double) { self.x = x; self.y = y }

    var cg: CGPoint { CGPoint(x: x, y: y) }

    func distance(to other: LocalPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }

    func translated(by v: CGVector) -> LocalPoint {
        LocalPoint(x + v.dx, y + v.dy)
    }
}

struct GeoPoint: Hashable, Codable, Sendable {
    var longitude: Double
    var latitude: Double
    // GeoJSON coordinates 순서(경도, 위도)와 필드 순서를 일치시켰다.

    var geoJSONArray: [Double] { [longitude, latitude] }
}

// MARK: - 경로

enum PathSegment: Hashable, Sendable {
    case line(to: LocalPoint)
    case cubic(c1: LocalPoint, c2: LocalPoint, to: LocalPoint)
    // 2차 베지어와 호(A)는 파싱 시점에 전부 3차로 환산하므로 여기 케이스가 없다.

    var endPoint: LocalPoint {
        switch self {
        case .line(let p): return p
        case .cubic(_, _, let p): return p
        }
    }

    var isCurved: Bool {
        if case .cubic = self { return true }
        return false
    }
}

struct Subpath: Hashable, Sendable {
    var start: LocalPoint
    var segments: [PathSegment]
    var isClosed: Bool

    var points: [LocalPoint] {
        [start] + segments.map(\.endPoint)
    }

    var isCurved: Bool { segments.contains(where: \.isCurved) }
}

struct PathGeometry: Hashable, Sendable {
    var subpaths: [Subpath]

    var isEmpty: Bool { subpaths.isEmpty }
    var isCurved: Bool { subpaths.contains(where: \.isCurved) }

    var allPoints: [LocalPoint] { subpaths.flatMap(\.points) }

    var boundingBox: CGRect {
        let pts = allPoints
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func translated(by v: CGVector) -> PathGeometry {
        PathGeometry(subpaths: subpaths.map { sp in
            Subpath(
                start: sp.start.translated(by: v),
                segments: sp.segments.map { seg in
                    switch seg {
                    case .line(let p): return .line(to: p.translated(by: v))
                    case .cubic(let a, let b, let p):
                        return .cubic(c1: a.translated(by: v), c2: b.translated(by: v), to: p.translated(by: v))
                    }
                },
                isClosed: sp.isClosed
            )
        })
    }

    /// 곡선을 직선 근사한 선분 목록. 히트테스트·좌표추출의 공통 기반이다.
    func lineSegments(tolerance: Double = 0.4) -> [LineSegment] {
        var out: [LineSegment] = []
        for sp in subpaths {
            var cursor = sp.start
            for seg in sp.segments {
                switch seg {
                case .line(let p):
                    out.append(LineSegment(start: cursor, end: p))
                    cursor = p
                case .cubic(let c1, let c2, let p):
                    let pts = CurveFlattener.subdivideCubic(cursor, c1, c2, p, tolerance: tolerance)
                    var prev = cursor
                    for q in pts.dropFirst() {
                        out.append(LineSegment(start: prev, end: q))
                        prev = q
                    }
                    cursor = p
                }
            }
            if sp.isClosed, cursor.distance(to: sp.start) > 1e-9 {
                out.append(LineSegment(start: cursor, end: sp.start))
            }
        }
        return out
    }
}

struct LineSegment: Hashable, Codable, Sendable {
    var start: LocalPoint
    var end: LocalPoint

    var length: Double { start.distance(to: end) }

    /// 선분을 감싸는 상자. 교차 판정 전에 **먼저 걸러내는** 데 쓴다 —
    /// 상자가 안 겹치면 선분도 안 겹치고, 그 판정이 훨씬 싸다.
    var boundingBox: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// 점과 선분 사이의 최단거리. 히트테스트에 쓴다.
    func distance(to p: LocalPoint) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 1e-12 { return p.distance(to: start) }
        var t = ((p.x - start.x) * dx + (p.y - start.y) * dy) / lenSq
        t = max(0, min(1, t))
        return p.distance(to: LocalPoint(start.x + t * dx, start.y + t * dy))
    }
}

enum GeoJSONGeometryKind: String, Codable {
    case point = "Point"
    case lineString = "LineString"
    case polygon = "Polygon"
    case multiPolygon = "MultiPolygon"
    case none = "null"

    /// 빌려온 opening을 좌표에 넣어야 하는 geometry인가(명세 10-3-1).
    /// 링을 닫는 것이 목적이므로 폴리곤 계열만 해당한다.
    var usesBorrowedOpenings: Bool {
        self == .polygon || self == .multiPolygon
    }
}
