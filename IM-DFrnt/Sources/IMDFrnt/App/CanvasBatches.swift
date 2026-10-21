import SwiftUI

/// 도면 대부분이 화면에 보일 때 개체를 **색·굵기가 같은 것끼리 한 경로로 묶어** 그린다(2026-10-19 캔버스 이동 렉).
///
/// 포스텍 도서관 2층(도면 개체 64,006개)을 화면에 다 띄우고 옮기면, 개체마다 `stroke`·`fill`을 부르는 것만
/// 한 프레임에 40 ms(상위 레이어) + 25 ms(하위 기본 레이어)였다. 화면을 옮기는 동안 개체의 색·모양은 그대로라
/// 묶음은 표시 상태·도형이 바뀔 때만 다시 만들고, 프레임마다는 묶음 수십 개만 그린다.
/// 예: 회색(비활성) 굵기 1 선 5만 개 → 경로 하나, `stroke` 한 번.
///
/// 확대해 일부만 보거나(격자로 화면 안만 도는 쪽이 싸다) 개체를 옮기는 중이면 종전처럼 하나씩 그린다.
/// 묶으면 같은 묶음 안에서 반투명 선이 겹친 자리가 두 번 칠해지지 않는다(겹친 곳이 더 진해지지 않음).
/// 면은 묶지 않는다 — 방향이 반대인 두 면을 한 경로로 칠하면 겹친 자리가 구멍으로 빠진다(0이 되는 감김 수).
struct CanvasBatches {
    /// 선 묶음 하나. 굵기는 도면 단위이고, 화면 굵기·빌림 점선 간격은 그릴 때 확대 배율로 정한다.
    struct Stroke: Hashable {
        var color: Color
        var width: Double
        var emphasized: Bool
        var borrowed: Bool
        var dash: [Double]
    }

    struct Key: Equatable {
        var states: Int
        var geometry: Int
        var background: CanvasBackground
        var primaryOpacity: Double
        var objectCount: Int
    }

    var key: Key
    /// 면이 있는 개체. 묶지 않고 도면 순서대로 하나씩 칠한다.
    var fills: [(Color, Path)] = []
    /// 선 묶음. 평범한 선 → 다른 레이어 태깅 → 이 레이어 태깅 → 강조 → 빌림 → 선택 순으로 그려 상태 표시가 위에 온다.
    var strokes: [(Stroke, Path)] = []
    /// 선택한 개체의 테두리 상자(화면에 얹는 점선 상자).
    var selectedBoxes: [CGRect] = []
}

/// 하위 기본 레이어(고스트) 묶음. 색이 하나라 굵기별로만 나눈다.
struct GhostBatches {
    var geometry: Int
    var objectCount: Int
    var paths: [(width: Double, path: Path)]
}

/// 묶음을 들고 있는 곳. `@Published`가 아니라 바뀌어도 화면을 다시 그리게 하지 않는다.
@MainActor
final class CanvasBatchStore {
    var objects: CanvasBatches?
    var ghost: GhostBatches?
}

extension CanvasView {
    /// 개체 선 색. 하나씩 그리는 경로와 묶어 그리는 경로가 같은 규칙을 쓴다.
    static func strokeColor(_ st: ObjectRenderState, style: VectorStyle, background: CanvasBackground) -> Color {
        st.isBorrowed
            ? background.marker(.displayPoint)
            : (st.isSelected
                ? background.selection
                : (st.isHighlighted
                    ? ClosedPolygonAppearance.highlightFill
                    : (st.isTaggedHere
                        ? ClosedPolygonAppearance.savedFill
                        : (st.isTaggedOtherLayer
                            ? ClosedPolygonAppearance.otherLayerFill
                            : (st.isDisabled
                                ? background.disabledStroke
                                : background.resolve(style.stroke))))))
        // 강조 중인 feature의 구성원은 이미 소유된 개체여도 강조색이 이긴다 —
        // 지금 보고 있는 것을 찾으려는 표시라서다.
        // 다른 레이어에서 태깅한 개체는 회색(비활성) 대신 옅은 초록이다. 고를 수 없는 것은 같다.
    }
}

@MainActor
extension AppEnvironment {
    /// 지금 표시 상태로 만든 개체 묶음. 표시 상태·도형·배경·상위 레이어 투명도가 같으면 만든 것을 그대로 준다.
    func canvasObjectBatches(document doc: DrawingDocument, primaryOpacity: Double) -> CanvasBatches {
        let states = renderStates()
        let key = CanvasBatches.Key(states: renderStateRevision, geometry: geometryRevision,
                                    background: canvasBackground, primaryOpacity: primaryOpacity,
                                    objectCount: doc.objects.count)
        if let hit = canvasBatchStore.objects, hit.key == key { return hit }
        let background = canvasBackground, segmentation = segmentation, cache = renderCache
        var fills: [(Color, Path)] = []
        var strokes: [CanvasBatches.Stroke: Path] = [:], strokeOrder: [(rank: Int, key: CanvasBatches.Stroke)] = []
        var boxes: [CGRect] = []
        for o in doc.objects {
            let st = states[o.id] ?? renderState(for: o)
            guard st.isVisible, st.opacity * primaryOpacity > 0.01 else { continue }
            let entry = cache.entry(for: o, segmentation: segmentation)
            if let fill = o.style.fill {
                fills.append((background.resolveFill(fill).opacity(st.opacity * 0.35), entry.path))
            }
            let stroke = CanvasBatches.Stroke(
                color: CanvasView.strokeColor(st, style: o.style, background: background).opacity(st.opacity),
                width: o.style.strokeWidth,
                emphasized: st.isSelected || st.isBorrowed || st.isHighlighted,
                borrowed: st.isBorrowed,
                dash: st.isBorrowed ? [] : o.style.dashPattern)
            if strokes[stroke] == nil {
                let rank = st.isSelected ? 5 : st.isBorrowed ? 4 : st.isHighlighted ? 3
                    : st.isTaggedHere ? 2 : st.isTaggedOtherLayer ? 1 : 0
                strokeOrder.append((rank, stroke))
            }
            strokes[stroke, default: Path()].addPath(entry.path)
            if st.isSelected { boxes.append(entry.box) }
        }
        let ordered = strokeOrder.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
        let made = CanvasBatches(key: key,
                                 fills: fills,
                                 strokes: ordered.map { ($0.element.key, strokes[$0.element.key] ?? Path()) },
                                 selectedBoxes: boxes)
        canvasBatchStore.objects = made
        return made
    }

    /// 하위 기본 레이어 묶음. 도형이 같으면 만든 것을 그대로 준다.
    func canvasGhostBatches(document doc: DrawingDocument) -> GhostBatches {
        if let hit = canvasBatchStore.ghost, hit.geometry == geometryRevision, hit.objectCount == doc.objects.count { return hit }
        let segmentation = segmentation, cache = renderCache
        var paths: [Double: Path] = [:], order: [Double] = []
        for o in doc.objects {
            if paths[o.style.strokeWidth] == nil { order.append(o.style.strokeWidth) }
            paths[o.style.strokeWidth, default: Path()].addPath(cache.entry(for: o, segmentation: segmentation).path)
        }
        let made = GhostBatches(geometry: geometryRevision, objectCount: doc.objects.count,
                                paths: order.map { ($0, paths[$0] ?? Path()) })
        canvasBatchStore.ghost = made
        return made
    }
}
