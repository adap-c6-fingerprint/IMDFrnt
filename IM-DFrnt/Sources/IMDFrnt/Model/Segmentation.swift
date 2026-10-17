import Foundation

/// 선분화 결과를 담는 파생 모델. 원본 `VectorObject`를 대체하지 않고 옆에 붙는다.
/// 그래서 "선분화 해제"와 "곡선 개체 단위 선택"이 가능하다(명세 3-3-3, 8-4-4).
struct Segmentation: Hashable, Codable, Sendable {
    let sourceObjectID: VectorObjectID
    let segments: [LineSegment]
    let tolerance: Double
    let createdAt: Date

    var vertices: [LocalPoint] {
        var out: [LocalPoint] = []
        for s in segments {
            if out.last?.distance(to: s.start) ?? .infinity > 1e-9 { out.append(s.start) }
            out.append(s.end)
        }
        return out
    }

    var geometry: PathGeometry {
        guard let first = segments.first else { return PathGeometry(subpaths: []) }
        let sub = Subpath(
            start: first.start,
            segments: segments.map { .line(to: $0.end) },
            isClosed: segments.last.map { $0.end.distance(to: first.start) < 1e-6 } ?? false
        )
        return PathGeometry(subpaths: [sub])
    }
}

enum SegmentationDefect: Hashable {
    case gap(index: Int, distance: Double)
    // 인접 선분의 끝점이 벌어짐 — 명세 8-4-3) "반드시 만나야 한다" 위반
    case crossing(Int, Int, at: LocalPoint)
    // 인접하지 않은 선분이 서로를 가로지름 — 명세 8-4-3) "교차해서는 안 된다" 위반

    var isCrossing: Bool { if case .crossing = self { return true }; return false }
    var isGap: Bool { if case .gap = self { return true }; return false }

    var message: String {
        switch self {
        case .gap(let i, let d):
            return "선분 \(i)–\(i + 1) 사이가 \(String(format: "%.3f", d))만큼 벌어졌습니다."
        case .crossing(let a, let b, _):
            return "선분 \(a)와 \(b)가 교차합니다."
        }
    }
}
