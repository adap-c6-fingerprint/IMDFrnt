import AppKit
import CoreGraphics
import SwiftUI

/// 곡선 개체 창의 도면 패널(명세 3-3).
///
/// 보조 개체 제외 창과 같은 규칙이다 — **수식키 없이 그냥 클릭해도 선택된다.**
/// 이 창에 들어온 목적 자체가 곡선을 고르는 것이라, 메인 화면의 fn+shift+z 안전장치는
/// 여기서는 방해만 된다.
struct CurvedDrawingPane: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var marquee: MarqueeRect?
    @State private var dragIsPan: Bool?
    @StateObject private var zoomMonitor = ZoomEventMonitor()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                env.canvasBackground.fill

                if let doc = env.document {
                    canvas(doc)
                        .overlay { MarqueeOverlay(marquee: marquee, background: env.canvasBackground) }
                        .gesture(gesture())
                        .onAppear { fit(doc: doc, viewport: geo.size) }
                }

                HStack {
                    zoomControls(doc: env.document, viewport: geo.size)
                    Spacer()
                    legend
                }
                .padding(10)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { zoomMonitor.canvasFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { f in
                            zoomMonitor.canvasFrame = f
                        }
                }
            )
        }
        .onAppear { installZoomMonitor() }
        .onDisappear { zoomMonitor.stop() }
    }

    private func canvas(_ doc: DrawingDocument) -> some View {
        let showSegmentedOnly = env.curvedShowsSegmentedOnly
        // 루프 바깥에서 한 번만 받는다(엔진 디버깅 1-1번).

        return Canvas { ctx, _ in
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: scale, y: scale)

            for o in doc.objects {
                let cache = env.renderCache.entry(for: o, segmentation: env.segmentation)
                let isSelected = env.selection.selected.contains(o.id)
                let isSegmented = env.segmentation.isSegmented(o.id)

                // 명세 3-3: 곡선이 아닌 개체는 75%.
                // 3-3-3: '선분화된 것만 보기'에서는 모든 곡선 50%, 선분화된 곡선만 100%.
                var opacity = 1.0
                if !o.isCurved { opacity = 0.75 }
                else if showSegmentedOnly { opacity = isSegmented ? 1.0 : 0.5 }
                if env.auxiliary.isExcluded(o.id) { opacity *= 0.4 }

                let color: Color = !o.isCurved
                    ? env.canvasBackground.disabledStroke
                    : (isSelected ? env.canvasBackground.selection
                                  : (isSegmented ? CurvedAppearance.segmented
                                                 : CurvedAppearance.curved))
                // **직선과 곡선을 색으로 가른다.** 옅기 차이(100% vs 75%)만으로는 눈에 띄지 않아,
                // 이 창이 "눌러도 아무 변화가 없다"로 읽혔다(2026-08-27 보고).

                ctx.stroke(cache.path, with: .color(color.opacity(opacity)),
                           lineWidth: CanvasZoom.strokeWidth(
                            o.style.strokeWidth, at: scale,
                            emphasis: isSelected ? 2.0 : (o.isCurved ? 1.4 : 1.0)))

                if isSelected {
                    let pad = CanvasZoom.screenLength(3, at: scale)
                    let b = cache.box.insetBy(dx: -pad, dy: -pad)
                    ctx.stroke(Path(roundedRect: b, cornerRadius: CanvasZoom.screenLength(2, at: scale)),
                               with: .color(env.canvasBackground.selection.opacity(0.6)),
                               style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1, at: scale),
                                                  dash: [3, 3].map { CanvasZoom.screenLength($0, at: scale) }))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(CurvedAppearance.curved, "곡선 (선분화 전)")
            legendItem(CurvedAppearance.segmented, "선분화됨")
            legendItem(env.canvasBackground.disabledStroke, "직선 — 고를 수 없음")
        }
        .font(.caption2)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .toolbarCard(cornerRadius: 8)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    // MARK: 제스처

    private func toLocal(_ p: CGPoint) -> LocalPoint {
        LocalPoint((p.x - offset.width) / scale, (p.y - offset.height) / scale)
    }

    private func gesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIsPan == nil { dragIsPan = env.selectModifierDown || env.forceSelectMode ? false : nil }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation

                let moved = abs(value.translation.width) + abs(value.translation.height)
                if marquee != nil || (dragIsPan == false && moved >= MarqueeRect.dragThreshold) {
                    marquee = MarqueeRect(start: value.startLocation, current: value.location)
                } else {
                    offset.width += delta.width
                    offset.height += delta.height
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if let m = marquee, moved >= MarqueeRect.dragThreshold {
                    let a = toLocal(m.start), b = toLocal(m.current)
                    env.handleCurvedScreenMarquee(
                        rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                     width: abs(b.x - a.x), height: abs(b.y - a.y)),
                        mode: m.mode)
                } else if moved < MarqueeRect.dragThreshold {
                    env.handleCurvedScreenClick(at: toLocal(value.location),
                                                tolerance: 8 / Double(scale))
                    // 곡선은 선이 가늘어 겨냥이 어렵다. 메인 캔버스(6pt)보다 조금 넉넉하게 준다.
                }
                marquee = nil
                dragIsPan = nil
                lastDrag = .zero
            }
    }

    // MARK: 확대·축소 (다른 창과 같은 규칙)

    private func installZoomMonitor() {
        let scaleBinding = $scale
        let offsetBinding = $offset

        zoomMonitor.onZoom = { anchor, factor in
            let current = scaleBinding.wrappedValue
            let next = CanvasZoom.clamp(current * factor)
            guard abs(next - current) > 0.0001 else { return }
            let o = offsetBinding.wrappedValue
            let ratio = next / current
            offsetBinding.wrappedValue = CGSize(
                width: anchor.x - (anchor.x - o.width) * ratio,
                height: anchor.y - (anchor.y - o.height) * ratio)
            scaleBinding.wrappedValue = next
        }
        zoomMonitor.onPan = { dx, dy in
            let o = offsetBinding.wrappedValue
            offsetBinding.wrappedValue = CGSize(width: o.width + dx, height: o.height + dy)
        }
        zoomMonitor.start()
    }

    private func zoomControls(doc: DrawingDocument?, viewport: CGSize) -> some View {
        HStack(spacing: 6) {
            Button {
                zoomMonitor.onZoom?(CGPoint(x: viewport.width / 2, y: viewport.height / 2), 1 / 1.25)
            } label: { Image(systemName: "minus.magnifyingglass") }
            Text(CanvasZoom.label(scale)).font(.caption.monospacedDigit()).frame(width: 52)
            Button {
                zoomMonitor.onZoom?(CGPoint(x: viewport.width / 2, y: viewport.height / 2), 1.25)
            } label: { Image(systemName: "plus.magnifyingglass") }
            Button("맞춤") { if let doc { fit(doc: doc, viewport: viewport) } }
        }
        .buttonStyle(.toolbarIcon)
        .padding(6)
        .toolbarCard(cornerRadius: 8)
    }

    private func fit(doc: DrawingDocument, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let sx = (viewport.width - 60) / max(1, doc.canvasSize.width)
        let sy = (viewport.height - 120) / max(1, doc.canvasSize.height)
        scale = max(0.1, min(sx, sy))
        offset = CGSize(width: (viewport.width - doc.canvasSize.width * scale) / 2,
                        height: (viewport.height - doc.canvasSize.height * scale) / 2 + 20)
    }
}

/// 곡선 창의 색. 뷰에서 떼어낸 이유는 검증이다 — 직선·곡선·선분화된 곡선이 서로 구분되는지가
/// 이 창이 성립하는 조건인데, 색이 뷰 안에 박혀 있으면 `--selftest`가 확인할 방법이 없다.
enum CurvedAppearance {
    static let curved = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let segmented = Color(red: 0.2, green: 0.8, blue: 0.55)

    static var curvedAndSegmentedAreDistinct: Bool {
        curved.description != segmented.description
    }
}
