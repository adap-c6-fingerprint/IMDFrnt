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
    /// 개체 → 도면 순서(`objects` 안의 자리). 화면에 그릴 후보를 원래 겹침 순서대로 돌려주는 데 쓴다.
    private var order: [VectorObjectID: Int] = [:]
    /// 모든 개체 상자를 감싼 범위. 화면이 이 범위의 절반 넘게 덮으면 후보를 모으지 않고 바로 '전체'로 답한다.
    private(set) var extent: CGRect = .null

    var isEmpty: Bool { buckets.isEmpty }

    init() {}

    init(objects: [VectorObject], canvasSize: CGSize, divisions: Int = 64) {
        let longest = max(canvasSize.width, canvasSize.height)
        guard longest > 0, !objects.isEmpty else { return }
        cellSize = max(1, Double(longest) / Double(divisions))

        order.reserveCapacity(objects.count)
        for (i, o) in objects.enumerated() {
            order[o.id] = i
            extent = extent.union(o.boundingBox)
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

    /// 화면에 그릴 개체의 도면 순서 번호(오름차순). 그리기 순서가 곧 겹침 순서라 정렬해 돌려준다.
    /// 화면에 도면 대부분이 보이면 `nil`이다 — 그때는 전체를 차례로 도는 편이 정렬보다 싸다.
    /// 격자가 이 도면으로 만든 것이 아니면(`count`가 다르면) 역시 `nil`이다.
    func drawIndices(in rect: CGRect, moved: Set<VectorObjectID>, count: Int) -> [Int]? {
        guard cellSize > 0, order.count == count, !rect.isNull, !rect.isInfinite,
              rect.width < cellSize * 1_000, rect.height < cellSize * 1_000 else { return nil }
        // 화면 범위를 모르거나(`.infinite`는 폭이 유한한 아주 큰 수다) 도면보다 터무니없이 크면 칸 번호가 Int를 넘는다.
        // 그때는 격자를 쓰지 않고 전체를 그린다.
        let seen = rect.insetBy(dx: -cellSize, dy: -cellSize).intersection(extent)
        if !seen.isNull, extent.width * extent.height > 0,
           seen.width * seen.height * 2 >= extent.width * extent.height { return nil }
        // 도면 범위의 절반 넘게 보이면 후보를 모으지 않고 바로 전체로 답한다(2026-10-19 캔버스 이동 렉).
        // 6만 개를 집합에 넣었다가 결국 버리는 데만 한 번에 5 ms, 한 프레임에 두 번이었다.
        guard let ids = candidates(in: rect.insetBy(dx: -cellSize, dy: -cellSize), moved: moved),
              ids.count * 2 < count else { return nil }
        // 선 두께·곡선을 펴서 생긴 차이로 상자가 칸 경계를 살짝 넘을 수 있어 한 칸 넉넉히 본다.
        return ids.compactMap { order[$0] }.sorted()
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
