import CoreGraphics
import SwiftUI

/// 개체 하나에서 파생되는, 매 프레임 다시 만들 이유가 없는 것들.
struct ObjectRenderCache {
    let path: Path
    let segments: [LineSegment]
    let box: CGRect
}

/// 파생 데이터 보관소(`07) 성능 최적화 제안.md` 제안 2).
///
/// 이전에는 그리기 · 히트테스트 · 겹침 검사가 각자 `effectiveGeometry` → `swiftUIPath` /
/// `lineSegments()`를 **매번 새로** 만들었다. 곡선은 그때그때 잘게 쪼개지므로 개체 하나가
/// 선분 수십~수백 개로 불어나고, 개체 2,000개짜리 도면에서는 프레임마다 메모리 할당이
/// 수천 번 일어난다. 실제로는 지난 프레임과 같은 그림인데도 그렇다.
///
/// **원본 좌표는 도면이 열려 있는 동안 바뀌지 않는다**(이동은 화면 전용, 명세 2-3).
/// 그래서 이 캐시를 지워야 하는 경우는 **선분화 변경**과 **문서 교체** 둘뿐이다.
@MainActor
final class RenderCacheStore {
    private var entries: [VectorObjectID: ObjectRenderCache] = [:]

    func entry(for object: VectorObject, segmentation: SegmentationStore) -> ObjectRenderCache {
        if let hit = entries[object.id] { return hit }
        let geo = segmentation.effectiveGeometry(for: object.id, fallback: object.geometry)
        let made = ObjectRenderCache(path: geo.swiftUIPath,
                                     segments: geo.lineSegments(),
                                     box: geo.boundingBox)
        entries[object.id] = made
        return made
    }

    /// 히트테스트·겹침 검사에 넘기는 조회 함수.
    /// 이 둘은 `Path`가 필요 없고 선분과 경계 상자만 보므로, 캐시가 없는 곳(`--selftest` 등)에서는
    /// 예전과 같이 그때그때 계산하는 클로저를 넘기면 된다 — 호출부를 고치지 않아도 된다.
    func geometryProvider(_ segmentation: SegmentationStore)
    -> (VectorObject) -> (segments: [LineSegment], box: CGRect) {
        { [self] object in
            let e = entry(for: object, segmentation: segmentation)
            return (e.segments, e.box)
        }
    }

    func invalidate(_ id: VectorObjectID) { entries.removeValue(forKey: id) }

    func invalidateAll() { entries.removeAll() }

    var count: Int { entries.count }
}

extension SegmentationStore {
    /// 캐시를 지울 때 쓰는, **실제로 달라진 개체**의 집합.
    /// 전부 지우면 곡선 하나를 선분화할 때마다 도면 전체를 다시 만들어,
    /// 고치려던 문제가 그 순간 그대로 재현된다.
    func changedObjects(since old: SegmentationStore) -> Set<VectorObjectID> {
        var changed = segmentedObjectIDs.symmetricDifference(old.segmentedObjectIDs)
        for id in segmentedObjectIDs.intersection(old.segmentedObjectIDs)
        where segmentation(for: id) != old.segmentation(for: id) {
            changed.insert(id)
        }
        return changed
    }
}
