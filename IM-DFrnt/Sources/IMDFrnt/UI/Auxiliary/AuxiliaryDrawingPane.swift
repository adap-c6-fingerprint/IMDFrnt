import AppKit
import CoreGraphics
import SwiftUI

/// 보조 개체 제외 창의 도면 패널.
/// 메인 캔버스와 달리 그룹화·소유권이 없고, 개체를 골라 제외 표시만 한다.
/// 그래서 **수식키 없이 그냥 클릭해도 선택된다** — 이 창에 들어온 목적 자체가 고르는 것이라,
/// 메인 화면의 fn+shift+z 안전장치(실수 선택 방지)가 여기서는 방해만 된다.
struct AuxiliaryDrawingPane: View {
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
                        .gesture(gesture(doc: doc))
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

    // MARK: 그리기

    private func canvas(_ doc: DrawingDocument) -> some View {
        // 강조 집합은 **루프 바깥에서 한 번만** 받는다. 개체마다 다시 물으면 개체 수만큼
        // 집합을 새로 만들게 되고, 그것이 '똑같이 생긴 개체 모두 보기'에서 화면이
        // 멈추던 원인이었다(엔진 디버깅 1-1번).
        let highlighted = env.auxiliaryHighlightedIDs
        let twinPending = env.auxiliaryTwinPendingIDs
        // ✅ 2026-08-30 — 강조 집합과 같은 이유로 **루프 바깥에서 한 번만** 받는다.

        return Canvas { ctx, _ in
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: scale, y: scale)

            for o in doc.objects {
                let path = env.geometry(for: o).swiftUIPath
                let isSelected = env.auxiliarySelection.contains(o.id)
                let isExcluded = env.auxiliary.isExcluded(o.id)
                let isTwinPending = twinPending.contains(o.id) // ✅ 2026-08-30
                let opacity = AuxiliaryOpacity.value(for: o.id, highlighted: highlighted)

                if let fill = o.style.fill {
                    ctx.fill(path, with: .color(
                        env.canvasBackground.resolveFill(fill).opacity(opacity * 0.3)))
                }

                // ✅ 2026-08-30 — 판정 순서가 곧 뜻의 우선순위다.
                // 직접 고른 것(파랑) > 이미 제외된 것(주황) > 함께 지정될 쌍둥이(보라) > 원본.
                // 제외를 쌍둥이보다 앞에 두는 이유: 이미 빠진 개체는 버튼을 눌러도 달라지지
                // 않으므로 '끝난 것'으로 읽혀야 한다.
                let color: Color = isSelected ? env.canvasBackground.selection
                    : (isExcluded ? env.canvasBackground.excludedStroke
                       : (isTwinPending ? env.canvasBackground.twinStroke
                                        : env.canvasBackground.resolve(o.style.stroke)))
                let width = CanvasZoom.strokeWidth(
                    o.style.strokeWidth, at: scale,
                    emphasis: isSelected ? 2.2 : (isTwinPending ? 1.8 : 1.0))
                // 색만으로는 얇은 보조선에서 잘 안 읽힌다. 고른 것보다는 얇게 둬서
                // '고른 것'과 '딸려 오는 것'의 서열은 유지한다.
                ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: width)

                if isExcluded {
                    // 제외된 개체는 옅게만 두면 '아직 안 고른 것'과 구별이 안 된다.
                    // bounding box에 사선 표시를 얹어 상태를 눈으로 확정한다.
                    drawStrikeThrough(ctx, box: o.boundingBox,
                                      color: env.canvasBackground.excludedStroke.opacity(opacity))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func drawStrikeThrough(_ ctx: GraphicsContext, box: CGRect, color: Color) {
        let b = box.insetBy(dx: -2 / scale, dy: -2 / scale)
        var p = Path()
        p.move(to: CGPoint(x: b.minX, y: b.minY)); p.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
        p.move(to: CGPoint(x: b.maxX, y: b.minY)); p.addLine(to: CGPoint(x: b.minX, y: b.maxY))
        ctx.stroke(p, with: .color(color), lineWidth: 1 / scale)
        ctx.stroke(Path(b), with: .color(color),
                   style: StrokeStyle(lineWidth: 1 / scale, dash: [3 / scale, 3 / scale]))
    }

    private var legend: some View {
        let twinPendingCount = env.auxiliaryTwinPendingIDs.count
        // ✅ 2026-08-30 — 한 번만 센다. `twins(of:)`는 호출할 때마다 집합을 새로 만든다.
        return HStack(spacing: 12) {
            legendItem(color: env.canvasBackground.selection, text: "선택")
            legendItem(color: env.canvasBackground.excludedStroke, text: "보조 개체로 제외됨")
            // ✅ 2026-08-30 — 쌍둥이 색은 '모두 표시'가 켜졌을 때만 화면에 나타나므로,
            // 범례도 그때만 보여준다. 늘 띄우면 아무것도 그 색이 아닌 상태에서 범례만 남는다.
            if twinPendingCount > 0 {
                legendItem(color: env.canvasBackground.twinStroke,
                           text: "함께 지정될 쌍둥이 \(twinPendingCount)개")
            }
            ToolbarDivider().frame(height: 12)
            // ✅ 2026-08-30 — 상단바 '드래그: 선택 / 해제' 토글과 같은 사실을 도면 위에서도 말해 준다.
            // 상단바는 선택이 있을 때만 뜨는데, 이 안내는 선택이 없을 때도 필요하다.
            Text(env.marqueeSubtracts
                 ? "드래그로 여러 개 해제 · → 감싸기 / ← 스치기 · ⌥드래그는 화면 이동"
                 : "드래그로 여러 개 선택 · → 감싸기 / ← 스치기 · ⌥드래그는 화면 이동")
                .lineLimit(1).truncationMode(.tail)
            // 도면 위에 뜬 캡슐이라 줄이 늘면 도면을 가린다. 좁아지면 뒤를 자른다.
        }
        .font(.caption2)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .toolbarCapsuleCard()
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 3)
            Text(text)
        }
    }

    // MARK: 확대·축소·팬

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
                height: anchor.y - (anchor.y - o.height) * ratio
            )
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

    // MARK: 입력

    private func toLocal(_ p: CGPoint) -> LocalPoint {
        LocalPoint((p.x - offset.width) / scale, (p.y - offset.height) / scale)
    }

    /// 이 창은 **그냥 드래그가 사각형 선택**이다.
    /// 메인 캔버스는 fn+shift+z를 눌러야 선택 모드로 들어가지만, 여기는 화면에 들어온 목적
    /// 자체가 개체를 골라내는 것이라 클릭도 수식키 없이 먹는다(위 주석). 드래그만 예외로 두면
    /// 클릭은 되는데 드래그는 안 되는, 지금 겪은 그 상태가 된다.
    ///
    /// 대신 화면 이동은 **option 드래그**로 옮겼다. 두 손가락 스크롤(`zoomMonitor.onPan`)도
    /// 그대로 살아 있어서, 팬 수단이 사라지는 것은 아니다.
    private func gesture(doc: DrawingDocument) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIsPan == nil { dragIsPan = NSEvent.optionHeld }
                // 드래그 도중 option을 놓으면 팬이 선택으로 돌변한다.
                // 시작 시점에 무엇을 하는 드래그인지 확정하고 끝까지 유지한다.

                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation

                if dragIsPan == true {
                    offset.width += delta.width
                    offset.height += delta.height
                } else {
                    marquee = MarqueeRect(start: value.startLocation, current: value.location)
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)

                if let m = marquee, moved >= MarqueeRect.dragThreshold {
                    let a = toLocal(m.start), b = toLocal(m.current)
                    env.handleAuxiliaryMarquee(
                        rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                     width: abs(b.x - a.x), height: abs(b.y - a.y)),
                        mode: m.mode)
                } else if moved < MarqueeRect.dragThreshold {
                    if let hit = HitTester.hitTest(toLocal(value.location), candidates: doc.objects,
                                                   cached: env.renderCache.geometryProvider(env.segmentation),
                                                   tolerance: 6 / Double(scale)) {
                        if env.auxiliarySelection.contains(hit) {
                            env.auxiliarySelection.remove(hit)
                        } else {
                            env.auxiliarySelection.insert(hit)
                        }
                        // 캔버스에서 직접 고르면 목록 강조는 풀어준다 — 둘이 어긋나면 무엇이 100%인지 헷갈린다.
                        env.focusedTwinKey = nil
                    }
                }

                marquee = nil
                dragIsPan = nil
                lastDrag = .zero
            }
    }

    private func fit(doc: DrawingDocument, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let sx = (viewport.width - 60) / max(1, doc.canvasSize.width)
        let sy = (viewport.height - 90) / max(1, doc.canvasSize.height)
        scale = max(0.1, min(sx, sy))
        offset = CGSize(width: (viewport.width - doc.canvasSize.width * scale) / 2,
                        height: (viewport.height - doc.canvasSize.height * scale) / 2)
    }
}
