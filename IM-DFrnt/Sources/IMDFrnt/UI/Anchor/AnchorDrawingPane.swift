import CoreGraphics
import SwiftUI

/// Anchor 지정 화면의 왼쪽 도면 패널.
/// 메인 캔버스와 달리 개체 선택·그룹화가 없고, Anchor 찍기와 마커 드래그만 한다.
struct AnchorDrawingPane: View {
    @EnvironmentObject var env: AppEnvironment
    @Binding var draggingAnchor: AnchorID?
    @Binding var isOutliningBuilding: Bool
    @Binding var outlinePoints: [LocalPoint]
    let proposedAnchors: [AnchorPair]

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var panning = false
    @StateObject private var zoomMonitor = ZoomEventMonitor()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                env.canvasBackground.fill

                if let doc = env.document {
                    canvas(doc)
                        .gesture(gesture(doc: doc))
                        .onAppear { fit(doc: doc, viewport: geo.size) }
                }

                header

                VStack {
                    Spacer()
                    HStack {
                        zoomControls(doc: env.document, viewport: geo.size)
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { zoomMonitor.canvasFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, f in
                            zoomMonitor.canvasFrame = f
                        }
                }
            )
        }
        .onAppear { installZoomMonitor() }
        .onDisappear { zoomMonitor.stop() }
    }

    // MARK: 확대·축소

    /// 커서 위치를 초점으로 삼는다. Anchor는 건물 모서리처럼 좁은 지점을 찍어야 해서
    /// 메인 캔버스보다 오히려 정밀한 확대가 더 필요하다.
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
        // 메인 캔버스 zoomControls와 같은 규칙(디버깅 10번).
        .padding(6)
        .toolbarCard(cornerRadius: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(env.canvasBackground.marker(.pending))
            if let p = env.pendingAnchorLocal {
                Text(String(format: "찍은 점: %.1f, %.1f — 이제 지도에서 같은 지점을 클릭", p.x, p.y))
                    .font(.caption)
                Button("취소") { env.pendingAnchorLocal = nil }
                    .buttonStyle(.toolbarIcon)
                    .controlSize(.mini)
            } else if isOutliningBuilding {
                Text("건물 외곽 모서리를 순서대로 찍으세요 (\(outlinePoints.count)점 · 최소 4점)")
                    .font(.caption)
            } else {
                Text("도면에서 Anchor로 쓸 지점을 클릭하세요 (건물 모서리·기둥 중심처럼 지도에서도 특정 가능한 곳)")
                    .font(.caption)
                    .lineLimit(1).truncationMode(.tail)
                // 도면 위에 얹힌 안내 줄이라 줄이 늘면 도면을 덮는다.
            }
            Spacer()
        }
        // 안내 문구와 '취소' 버튼이 도면 위에서 묻히지 않도록 캔버스 배경에서 색을 뽑는다.
        .padding(.horizontal, 10).padding(.vertical, 7)
        .toolbarCard(cornerRadius: 0)
    }

    private func canvas(_ doc: DrawingDocument) -> some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: scale, y: scale)
            doc.drawImages(in: ctx)

            for o in doc.objects {
                let path = o.geometry.swiftUIPath
                ctx.stroke(path,
                           with: .color(env.canvasBackground.resolve(o.style.stroke).opacity(0.55)),
                           lineWidth: CanvasZoom.strokeWidth(o.style.strokeWidth, at: scale))
            }

            for (i, pair) in env.anchors.pairs.enumerated() {
                drawMarker(ctx, at: pair.local, index: i + 1,
                           color: env.canvasBackground.marker(
                               env.outlierIndices.contains(i) ? .outlier : .normal))
            }
            if !outlinePoints.isEmpty {
                var outline = Path()
                outline.move(to: outlinePoints[0].cg)
                for p in outlinePoints.dropFirst() { outline.addLine(to: p.cg) }
                if outlinePoints.count >= 4 { outline.closeSubpath() }
                ctx.stroke(outline, with: .color(.orange), lineWidth: 2 / scale)
                for (i, point) in outlinePoints.enumerated() {
                    drawMarker(ctx, at: point, index: i + 1, color: .orange)
                }
            }
            for (i, pair) in proposedAnchors.enumerated() {
                drawMarker(ctx, at: pair.local, index: i + 1, color: .purple)
            }
            if let pending = env.pendingAnchorLocal {
                drawMarker(ctx, at: pending, index: nil,
                           color: env.canvasBackground.marker(.pending))
            }
        }
        .contentShape(Rectangle())
    }

    private func drawMarker(_ ctx: GraphicsContext, at p: LocalPoint, index: Int?, color: Color) {
        let r: CGFloat = 11 / scale
        var cross = Path()
        cross.move(to: CGPoint(x: p.x - r, y: p.y)); cross.addLine(to: CGPoint(x: p.x + r, y: p.y))
        cross.move(to: CGPoint(x: p.x, y: p.y - r)); cross.addLine(to: CGPoint(x: p.x, y: p.y + r))
        ctx.stroke(cross, with: .color(color), lineWidth: 2 / scale)
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                   with: .color(color), lineWidth: 1.6 / scale)
        if let index {
            ctx.draw(Text("\(index)").font(.system(size: 10)).foregroundStyle(color),
                     at: CGPoint(x: p.x + r, y: p.y - r))
        }
    }

    private func toLocal(_ p: CGPoint) -> LocalPoint {
        LocalPoint((p.x - offset.width) / scale, (p.y - offset.height) / scale)
    }

    private func gesture(doc: DrawingDocument) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggingAnchor == nil && !panning && lastDrag == .zero {
                    let start = toLocal(value.startLocation)
                    if !isOutliningBuilding, let hit = nearestAnchor(to: start) { draggingAnchor = hit }
                    else { panning = true }
                }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation

                if let id = draggingAnchor {
                    env.updateAnchorLocal(id, to: toLocal(value.location))
                } else if panning {
                    offset.width += delta.width
                    offset.height += delta.height
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if draggingAnchor == nil && moved < 5 {
                    if isOutliningBuilding { outlinePoints.append(toLocal(value.location)) }
                    else { env.pendingAnchorLocal = toLocal(value.location) }
                }
                draggingAnchor = nil
                panning = false
                lastDrag = .zero
            }
    }

    private func nearestAnchor(to p: LocalPoint) -> AnchorID? {
        let threshold = 14 / Double(scale)
        var best: (AnchorID, Double)?
        for pair in env.anchors.pairs {
            let d = pair.local.distance(to: p)
            if d <= threshold, d < (best?.1 ?? .greatestFiniteMagnitude) { best = (pair.id, d) }
        }
        return best?.0
    }

    private func fit(doc: DrawingDocument, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let sx = (viewport.width - 60) / max(1, doc.canvasSize.width)
        let sy = (viewport.height - 90) / max(1, doc.canvasSize.height)
        scale = max(0.1, min(sx, sy))
        offset = CGSize(width: (viewport.width - doc.canvasSize.width * scale) / 2,
                        height: (viewport.height - doc.canvasSize.height * scale) / 2 + 14)
    }
}
