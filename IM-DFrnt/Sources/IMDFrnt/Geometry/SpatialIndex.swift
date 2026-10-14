import CoreGraphics
import Foundation

/// 도면을 바둑판으로 나눠 칸마다 그 칸에 걸치는 개체를 적어 둔다
/// (`07) 성능 최적화 제안.md` 제안 5).
///
/// 클릭 판정 · 사각형 선택 · 겹침 후보 찾기가 **도면 전체 대신 해당 칸만** 보게 한다.
/// 지도 앱이 화면에 보이는 타일만 다루는 것과 같은 발상이다. 개체 수가 늘어도
/// 한 번에 보는 후보 수는 거의 늘지 않는다.
///
/// **원본 좌표 기준이다.** 화면에서 옮긴 개체(이동은 화면 전용, 명세 2-3)는 격자와 어긋나므로,
/// 후보를 받는 쪽에서 이동한 개체를 항상 더해야 한다 — `candidates(...)`에 그 규칙을 넣어 뒀다.
struct SpatialIndex: Sendable {

    struct Cell: Hashable, Sendable { let x: Int; let y: Int }

    private(set) var cellSize: Double = 0
    private var buckets: [Cell: [VectorObjectID]] = [:]

    var isEmpty: Bool { buckets.isEmpty }

    init() {}

    init(objects: [VectorObject], canvasSize: CGSize, divisions: Int = 64) {
        let longest = max(canvasSize.width, canvasSize.height)
        guard longest > 0, !objects.isEmpty else { return }
        cellSize = max(1, Double(longest) / Double(divisions))

        for o in objects {
            for cell in cells(covering: o.boundingBox) {
                buckets[cell, default: []].append(o.id)
            }
        }
    }

    /// 사각형에 걸리는 후보. `moved`에는 화면에서 옮긴 개체를 넘긴다 —
    /// 격자는 원본 좌표로 만들어져 있어 옮긴 개체는 엉뚱한 칸에 있다.
    /// **이 인자를 빠뜨리면 옮긴 개체가 클릭되지 않는다.**
    func candidates(in rect: CGRect, moved: Set<VectorObjectID> = []) -> Set<VectorObjectID>? {
        guard cellSize > 0 else { return nil }
        var out = moved
        for cell in cells(covering: rect) {
            if let ids = buckets[cell] { out.formUnion(ids) }
        }
        return out
    }

    func candidates(near point: LocalPoint, tolerance: Double,
                    moved: Set<VectorObjectID> = []) -> Set<VectorObjectID>? {
        candidates(in: CGRect(x: point.x - tolerance, y: point.y - tolerance,
                              width: tolerance * 2, height: tolerance * 2),
                   moved: moved)
    }

    private func cells(covering rect: CGRect) -> [Cell] {
        guard cellSize > 0, rect.width.isFinite, rect.height.isFinite else { return [] }
        let minX = Int(floor(rect.minX / cellSize)), maxX = Int(floor(rect.maxX / cellSize))
        let minY = Int(floor(rect.minY / cellSize)), maxY = Int(floor(rect.maxY / cellSize))
        guard maxX >= minX, maxY >= minY else { return [] }
        var out: [Cell] = []
        out.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for x in minX...maxX {
            for y in minY...maxY { out.append(Cell(x: x, y: y)) }
        }
        return out
    }
}
