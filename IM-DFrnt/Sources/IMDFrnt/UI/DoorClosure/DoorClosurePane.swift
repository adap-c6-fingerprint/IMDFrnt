import AppKit
import CoreGraphics
import SwiftUI

/// '문 임시로 닫기' 창의 도면 패널(신기능 3-1·3-2·3-3).
struct DoorClosurePane: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var dragIsPan: Bool?
    @StateObject private var zoomMonitor = ZoomEventMonitor()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                env.canvasBackground.fill

                if let doc = env.document {
                    canvas(doc, viewport: geo.size)
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

    private func canvas(_ doc: DrawingDocument, viewport: CGSize) -> some View {
        // 후보 점은 확대해도 화면상 크기가 일정해야 한다. 도면 좌표로 그리면
        // 200배에서 점 하나가 화면을 덮는다(`CanvasZoom` 참조).
        let bg = env.canvasBackground
        let draft = env.doorDraftPoints

        // **화면에 들어오는 점만 그린다.** 꼭짓점까지 후보에 넣으면 실도면에서 마커가
        // 수만 개가 되는데, 그걸 매 프레임 다 그리면 창이 그대로 멈춘다.
        // 안 보이는 것을 그리지 않는 것은 결과를 바꾸지 않으면서 가장 크게 줄이는 방법이다.
        let visible = visibleRect(viewport: viewport)
        let snaps = env.doorSnapPoints.filter { visible.contains($0.point.cg) }

        return Canvas { ctx, _ in
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: scale, y: scale)

            // 1) 도면. 제외된 보조 개체는 20%로, 조작 불가(신기능 3-1).
            for o in doc.objects {
                let path = env.geometry(for: o).swiftUIPath
                let isExcluded = env.auxiliary.isExcluded(o.id)
                let role = env.doorRole(of: o.id)

                let color: Color
                switch role {
                case .door:  color = bg.selection
                case .arc:   color = bg.marker(.pending)
                case .saved: color = bg.marker(.displayPoint)
                case .none:  color = isExcluded ? bg.excludedStroke : bg.resolve(o.style.stroke)
                }
                // 문짝과 호를 **다른 색**으로 그린다. 둘 다 선택 색이면 무엇이 무엇으로
                // 잡혔는지 확인할 방법이 없고, 곡선 판정이 틀렸을 때 알아챌 수 없다.

                let opacity = isExcluded ? DoorClosureAppearance.excludedOpacity
                                         : DoorClosureAppearance.activeOpacity
                // 명세가 요구한 20%. `EditorLayer.baseOpacity`(하위 기본 레이어)를 빌려 쓰지 않는다 —
                // 그쪽은 사노 요청으로 50%가 됐다. 우연히 같았던 수치를 묶으면 한쪽이 조용히 끌려간다.

                ctx.stroke(path, with: .color(color.opacity(opacity)),
                           style: StrokeStyle(
                            lineWidth: CanvasZoom.strokeWidth(o.style.strokeWidth, at: scale,
                                                              emphasis: role == .none ? 1 : 2.2),
                            dash: o.style.dashPattern.map { CGFloat($0) }))
            }

            // 2) 이미 저장한 임시 문 — 실선으로 굵게. 여기는 '이미 닫힌 자리'다.
            for d in env.doorClosures.doors {
                var p = Path()
                p.move(to: d.start.cg); p.addLine(to: d.end.cg)
                ctx.stroke(p, with: .color(bg.marker(.displayPoint)),
                           style: StrokeStyle(lineWidth: CanvasZoom.screenLength(3, at: scale),
                                              lineCap: .round))
            }

            // 3) 찍을 수 있는 점. 세 종류를 **모양으로** 가른다 —
            // 색만 다르면 배경 대비에 따라 한쪽이 묻힌다.
            // 끝점 ○ · 교차점 □ · 꼭짓점 ◇. 꼭짓점은 수가 압도적으로 많아 더 작게,
            // 더 옅게 그린다 — 같은 크기로 그리면 도면이 마커로 덮여 정작 끝점이 안 보인다.
            let lw = CanvasZoom.screenLength(1, at: scale)
            let snapDim = env.doorClickStage == .pickingObjects ? 0.35 : 1.0
            // 점을 다 찍은 뒤에는 후보 점을 옅게 그린다. 그 단계의 클릭은 개체를 고르므로,
            // 마커가 그대로 진하면 아직 점을 찍는 화면으로 읽힌다.
            for s in snaps {
                let r = CanvasZoom.screenLength(s.kind == .vertex ? 2.5 : 3.5, at: scale)
                let rect = CGRect(x: s.point.x - r, y: s.point.y - r, width: r * 2, height: r * 2)
                let color = bg.disabledStroke.opacity((s.kind == .vertex ? 0.55 : 1.0) * snapDim)
                switch s.kind {
                case .endpoint:
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lw)
                case .crossing:
                    ctx.stroke(Path(rect), with: .color(color), lineWidth: lw)
                case .vertex:
                    var d = Path()
                    d.move(to: CGPoint(x: s.point.x, y: s.point.y - r))
                    d.addLine(to: CGPoint(x: s.point.x + r, y: s.point.y))
                    d.addLine(to: CGPoint(x: s.point.x, y: s.point.y + r))
                    d.addLine(to: CGPoint(x: s.point.x - r, y: s.point.y))
                    d.closeSubpath()
                    ctx.stroke(d, with: .color(color), lineWidth: lw)
                }
            }

            // 4) 지금 찍은 점과 그 사이를 잇는 미리보기 선.
            if draft.count == 2 {
                var p = Path()
                p.move(to: draft[0].cg); p.addLine(to: draft[1].cg)
                ctx.stroke(p, with: .color(bg.selection),
                           style: StrokeStyle(lineWidth: CanvasZoom.screenLength(2.5, at: scale),
                                              dash: [6, 4].map { CanvasZoom.screenLength($0, at: scale) }))
                // 저장 전이라는 것을 점선으로 알린다. 저장된 문(실선)과 눈으로 갈려야
                // "저장을 눌렀던가?"를 화면에서 바로 읽는다.
            }
            let dr = CanvasZoom.screenLength(5, at: scale)
            for p in draft {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - dr, y: p.y - dr,
                                                width: dr * 2, height: dr * 2)),
                         with: .color(bg.selection))
            }
        }
        .contentShape(Rectangle())
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: env.canvasBackground.selection, text: "찍은 점 · 열려 있는 문")
            legendItem(color: env.canvasBackground.marker(.pending), text: "호")
            legendItem(color: env.canvasBackground.marker(.displayPoint), text: "저장된 임시 문")
            legendItem(color: env.canvasBackground.excludedStroke, text: "보조 개체(조작 불가)")
            ToolbarDivider().frame(height: 12)
            Text("○ 끝점 · □ 교차점 · ◇ 꼭짓점 · 점 2개 → 문짝·호 순서 · 드래그는 화면 이동")
                .lineLimit(1).truncationMode(.tail)
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

    /// 지금 화면에 보이는 도면 영역. 후보 점을 걸러내는 데 쓴다.
    /// 가장자리에 여유(20pt)를 두는 이유는, 딱 맞게 자르면 화면 경계의 점이 깜빡이기 때문이다.
    private func visibleRect(viewport: CGSize) -> CGRect {
        let pad = CanvasZoom.screenLength(20, at: scale)
        let topLeft = toLocal(.zero)
        let bottomRight = toLocal(CGPoint(x: viewport.width, y: viewport.height))
        return CGRect(x: topLeft.x - pad, y: topLeft.y - pad,
                      width: bottomRight.x - topLeft.x + pad * 2,
                      height: bottomRight.y - topLeft.y + pad * 2)
    }

    /// 이 창은 **점을 정확히 찍는 것**이 목적이라 그냥 드래그를 사각형 선택에 쓰지 않는다.
    /// 고를 것이 점과 개체 두 종류뿐이고 둘 다 하나씩 지정하는 것이라, 여러 개를 훑을 일이 없다.
    /// 그냥 드래그는 화면 이동으로 둔다 — 확대한 채로 도면을 훑는 시간이 대부분인 작업이다.
    private func gesture(doc: DrawingDocument) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIsPan == nil { dragIsPan = true }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                offset.width += delta.width
                offset.height += delta.height
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if moved < MarqueeRect.dragThreshold {
                    env.handleDoorClosureClick(at: toLocal(value.location),
                                               tolerance: 6 / Double(scale))
                }
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
