import AppKit
import CoreGraphics
import SwiftUI

extension PathGeometry {
    var swiftUIPath: Path {
        var path = Path()
        for sp in subpaths {
            path.move(to: sp.start.cg)
            for seg in sp.segments {
                switch seg {
                case .line(let p): path.addLine(to: p.cg)
                case .cubic(let c1, let c2, let p):
                    path.addCurve(to: p.cg, control1: c1.cg, control2: c2.cg)
                }
            }
            if sp.isClosed { path.closeSubpath() }
        }
        return path
    }
}

/// 중앙 캔버스. 줌·팬과 하위/상위 기본 레이어를 함께 그린다.
struct CanvasView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var moves: MoveSession
    // 이동량은 `AppEnvironment`가 아니라 이 객체가 들고 있다(제안 4).
    // 드래그 한 프레임마다 사이드바까지 다시 그려지던 것을 막는다.

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var lastDrag: CGSize = .zero
    @State private var gestureScale: CGFloat = 1
    @State private var marquee: MarqueeRect?
    @State private var dragIsMarquee: Bool?
    /// 이동 재도입(명세 2-3, 2026-08-25). `nil`이면 이동 중이 아니다.
    @State private var moveBase: [VectorObjectID: CGSize]?
    @State private var routingDragNode: UUID?
    @State private var routingDragPoint: LocalPoint?
    @State private var routingDragIsConnection = false
    @State private var routingDragOptionHeld = false
    @State private var routingDragCommandHeld = false
    @State private var routingDragConnectCandidate: UUID?
    @State private var routingConnectionStarted = false
    /// 꼭짓점을 끄는 드래그인가(#21). 시작할 때 정하고 끝까지 유지한다.
    @State private var dragIsVertex = false
    @State private var pointKeys: PointKeyMonitor?
    @StateObject private var zoomMonitor = ZoomEventMonitor()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                env.canvasBackground.fill

                if let doc = displayedDocument {
                    canvas(doc: doc, viewport: geo.size)
                        .overlay { MarqueeOverlay(marquee: marquee, background: env.canvasBackground) }
                        .gesture(dragGesture(viewport: geo.size))
                        .accessibilityChildren {
                            if env.showRoutingScreen { routingAccessibilityElements }
                        }
                        .onAppear { fit(doc: doc, viewport: geo.size) }
                        .onChange(of: doc.fingerprint) { _, _ in fit(doc: doc, viewport: geo.size) }
                        .onChange(of: env.routingFloorID) { _, _ in fit(doc: doc, viewport: geo.size) }
                        .onChange(of: geo.size) { _, size in
                            // Switching from the drawing editor changes sidebar widths and layout.
                            if env.showRoutingScreen { fit(doc: doc, viewport: size) }
                        }
                } else if let levelID = env.loadingLevelID {
                    VStack(spacing: 10) {
                        ProgressView("\(env.buildingProject.levels.first { $0.id == levelID }?.info.name ?? "층") 도면을 불러오는 중…")
                        Text("다른 층을 선택할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error = env.drawingLoadError {
                    VStack(spacing: 10) {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        Button("다시 불러오기") {
                            if let id = env.routingFloorID { env.selectProjectLevel(id) }
                        }
                    }
                } else {
                    emptyState
                }

                VStack {
                    if env.showRoutingScreen {
                        Text(env.routingTool.hint)
                            .font(.caption).padding(10).toolbarCard(cornerRadius: 8)
                            .allowsHitTesting(false)
                    } else if env.isPolygonWorkMode {
                        PolygonToolbar()
                        // 폴리곤 type에서는 선택 대상이 개체가 아니라 면이라 상단바가 다르다.
                        // **선택이 없어도 항상 뜬다** — 이 모드에서는 무엇을 더 해야 하는지가 곧 안내다.
                    } else if env.isPointWorkMode {
                        PointToolbar()
                        // #21: property type 레이어의 기본 작업은 점 단위다.
                    } else if !env.selection.isEmpty {
                        SelectionToolbar()
                    }
                    Spacer()
                }
                .padding(.top, 12)

                VStack {
                    Spacer()
                    HStack {
                        zoomControls(doc: displayedDocument, viewport: geo.size)
                        Spacer()
                        if !env.showRoutingScreen { modeChip }
                    }
                    .padding(12)
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
        .onAppear {
            installZoomMonitor()
            if pointKeys == nil { pointKeys = PointKeyMonitor(env: env) }
            pointKeys?.start()
        }
        .onDisappear {
            zoomMonitor.stop()
            pointKeys?.stop()
            env.routingConnectionDrag = nil
        }
    }

    // MARK: 확대·축소

    /// 스크롤휠·핀치를 커서 위치를 초점으로 삼아 확대/축소한다.
    private func installZoomMonitor() {
        let scaleBinding = $scale
        let offsetBinding = $offset

        zoomMonitor.onZoom = { anchor, factor in
            let current = scaleBinding.wrappedValue
            let next = CanvasZoom.clamp(current * factor)
            guard abs(next - current) > 0.0001 else { return }

            // 커서 아래에 있던 도면 지점이 그 자리에 그대로 남도록 offset을 보정한다.
            // 화면좌표 = offset + 도면좌표 × scale 이므로,
            // offset' = anchor − (anchor − offset) × next / current
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

    /// 버튼 확대·축소는 캔버스 중앙을 초점으로 삼는다.
    private func zoomByButton(_ factor: CGFloat, viewport: CGSize) {
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        zoomMonitor.onZoom?(center, factor)
    }

    // MARK: 그리기

    private var displayedDocument: DrawingDocument? { env.showRoutingScreen ? env.routingDocument : env.document }

    @ViewBuilder
    private var routingAccessibilityElements: some View {
        ForEach(env.routing.nodes(on: env.currentRoutingFloor?.id)) { node in
            Button(node.label) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                env.selectRoutingNode(node.id)
            }
            .accessibilityValue(env.routingSelectedNodeID == node.id ? "선택됨" : "")
        }
        ForEach(env.routing.edges.filter { edge in
            env.routing.node(edge.from)?.floorID == env.currentRoutingFloor?.id ||
                env.routing.node(edge.to)?.floorID == env.currentRoutingFloor?.id
        }) { edge in
            Button("연결 \(env.routing.node(edge.from)?.label ?? "") ↔ \(env.routing.node(edge.to)?.label ?? "")") {
                NSApp.keyWindow?.makeFirstResponder(nil)
                env.selectRoutingEdge(edge.id)
            }
            .accessibilityValue(env.routingSelectedEdgeID == edge.id ? "선택됨" : "")
        }
    }

    private func canvas(doc: DrawingDocument, viewport: CGSize) -> some View {
        Canvas { ctx, size in
            let s = effectiveScale
            let visible = visibleDocRect(viewport: size)
            let states = env.renderStates()
            // 표시 상태는 프레임마다 개체별로 다시 판정하지 않고 **사전 하나**를 받아 쓴다(제안 3).
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: s, y: s)
            // 도면 중심을 축으로 90° 단위 회전. 표시 전용이라 도면 좌표는 그대로다.
            if env.canvasRotation != 0 {
                let c = docCenter
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: .degrees(env.rotationDegrees))
                ctx.translateBy(x: -c.x, y: -c.y)
            }

            drawReferenceLayers(in: ctx, canvasSize: doc.canvasSize, scale: s)
            let primary = env.currentRoutingFloor?.imdfCoordinates == nil ? env.primarySVGPresentation : DrawingLayerPresentation(isVisible: true, opacity: 1)
            if primary.isVisible {
                var images = ctx; images.opacity *= primary.opacity
                doc.drawImages(in: images)
            }
            if env.showRoutingScreen {
                drawRouting(in: &ctx, document: doc, scale: s, visible: visible)
                return
            }

            // 하위 기본 레이어 — 원위치를 20% opacity로. 히트테스트 대상이 아니다.
            if primary.isVisible, let ghost = ghostLayer, !ghost.isHidden {
                for o in doc.objects {
                    let cache = env.renderCache.entry(for: o, segmentation: env.segmentation)
                    guard cache.box.insetBy(dx: -o.style.strokeWidth / 2 - 2,
                                            dy: -o.style.strokeWidth / 2 - 2).intersects(visible)
                    else { continue }
                    // 화면 밖은 그리지 않는다(제안 5). 고스트는 원위치를 그리는 레이어라
                    // 이동량을 얹지 않으므로 원본 상자 그대로 판정한다.
                    ctx.stroke(cache.path,
                               with: .color(env.canvasBackground.ghostStroke.opacity(ghost.opacity * primary.opacity)),
                               lineWidth: CanvasZoom.strokeWidth(o.style.strokeWidth, at: s))
                    // 수치를 여기 다시 적지 않고 `EditorLayer.opacity`를 쓴다(사용자 조절분 포함).
                    // 명세 2-3의 수치가 두 곳에 흩어져 있으면 한쪽만 고쳐 어긋난다.
                }
            }

            // 상위 기본 레이어 / 현재 property type 레이어
            for o in doc.objects {
                let st = states[o.id] ?? env.renderState(for: o)
                guard primary.isVisible, st.isVisible, st.opacity * primary.opacity > 0.01 else { continue }

                let cache = env.renderCache.entry(for: o, segmentation: env.segmentation)
                let off = moves.offset(for: o.id)
                let pad = o.style.strokeWidth / 2 + 2
                let box = (off == .zero ? cache.box
                                        : cache.box.offsetBy(dx: off.width, dy: off.height))
                    .insetBy(dx: -pad, dy: -pad)
                guard box.intersects(visible) else { continue }
                // 화면 밖 개체는 건너뛴다(제안 5). 200배로 확대해 귀퉁이만 보고 있어도
                // 이전에는 도면 전체를 그렸다.

                var g = ctx
                g.opacity *= primary.opacity
                if off != .zero { g.translateBy(x: off.width, y: off.height) }
                // 옮긴 개체는 좌표를 옮긴 사본을 만드는 대신 **자를 옮긴다**(제안 2).
                // `GraphicsContext`는 값 타입이라 복사가 싸다.
                let path = cache.path

                if let fill = o.style.fill {
                    g.fill(path, with: .color(
                        env.canvasBackground.resolveFill(fill).opacity(st.opacity * 0.35)))
                }
                // 명세 10-2-2: 빌려온 개체는 **점선 테두리 + 다른 색**으로 구분한다.
                // 소유·비활성·선택 어느 것과도 다른 상태라 색을 따로 준다 —
                // 같은 색을 쓰면 "내가 저장한 것"과 "남에게 빌린 것"이 구분되지 않는다.
                let strokeColor: Color = st.isBorrowed
                    ? env.canvasBackground.marker(.displayPoint)
                    : (st.isSelected
                        ? env.canvasBackground.selection
                        : (st.isDisabled
                            ? env.canvasBackground.disabledStroke
                            : env.canvasBackground.resolve(o.style.stroke)))
                let width = CanvasZoom.strokeWidth(
                    o.style.strokeWidth, at: s,
                    emphasis: st.isSelected || st.isBorrowed ? 2.0 : 1.0)
                let style = StrokeStyle(lineWidth: width,
                                        dash: st.isBorrowed
                                            ? [5, 3].map { CanvasZoom.screenLength($0, at: s) }
                                            : o.style.dashPattern.map { CGFloat($0) })
                // 빌림 표시 점선은 **화면상** 간격이 일정해야 한다. 도면 좌표로 두면
                // 확대할수록 점선 한 칸이 화면을 가로질러 실선처럼 보인다.
                // 반면 원본 점선(`dashPattern`)은 도면이 가진 성질이라 확대와 함께 커지는 게 맞다.
                // 원본이 점선이든 실선이든 빌린 동안에는 같은 점선으로 덮어쓴다.
                // 상태 표시가 도면 원본 스타일에 따라 달라지면 알아볼 수 없다.
                g.stroke(path, with: .color(strokeColor.opacity(st.opacity)), style: style)

                if st.isSelected {
                    // 선택 테두리는 도면의 일부가 아니라 화면에 얹은 표시다.
                    // 보정하지 않으면 200배에서 개체에서 한참 떨어진 곳에 그려진다.
                    let margin = CanvasZoom.screenLength(3, at: s)
                    let b = cache.box.insetBy(dx: -margin, dy: -margin)
                    g.stroke(Path(roundedRect: b, cornerRadius: CanvasZoom.screenLength(2, at: s)),
                               with: .color(env.canvasBackground.selection.opacity(0.6)),
                               style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1, at: s),
                                                  dash: [3, 3].map { CanvasZoom.screenLength($0, at: s) }))
                }
            }

            // 다각형 선택 모드(신기능 5-4) — 폴리곤 type 레이어에서는 면을 그리고 고른다.
            // **면 → 선 → 점 순서가 규칙이다.** 면을 나중에 그리면 경계선과 꼭짓점을 덮어
            // 어디서 닫혔는지 확인할 수 없다.
            if env.isPolygonWorkMode {
                let saved = env.savedPolygonFaceIDs
                for face in env.closedPolygonFaces {
                    guard face.boundingBox.intersects(visible) else { continue }
                    var facePath = Path()
                    facePath.addLines(face.ring.map(\.cg))
                    facePath.closeSubpath()

                    let isSaved = saved.contains(face.id)
                    let isPicked = env.faceSelection.contains(face.id)
                    var dim = 1.0
                    if case .ungroupedOnly = env.mode, isSaved { dim = 0.25 }
                    // 면 단위 '미저장만 보기'(신기능 5-4 4번). 저장한 면을 지우지 않고 옅게 눌러
                    // 남은 것이 드러나게 한다 — 지우면 어디까지 했는지 대조할 수가 없다.
                    let fill = isSaved ? ClosedPolygonAppearance.savedFill
                                       : ClosedPolygonAppearance.faceFill
                    let fillOpacity = isSaved ? ClosedPolygonAppearance.savedFillOpacity
                        : (isPicked ? ClosedPolygonAppearance.selectedFillOpacity
                                    : ClosedPolygonAppearance.faceFillOpacity)
                    ctx.fill(facePath, with: .color(fill.opacity(fillOpacity * dim)))
                    ctx.stroke(facePath,
                               with: .color((face.usesTemporaryDoor
                                             ? ClosedPolygonAppearance.temporaryDoorAccent
                                             : ClosedPolygonAppearance.edgeStroke).opacity(dim)),
                               lineWidth: CanvasZoom.screenLength(
                                ClosedPolygonAppearance.edgeWidth * (isPicked ? 2 : 1), at: s))

                    let vr = CanvasZoom.screenLength(ClosedPolygonAppearance.vertexRadius, at: s)
                    for p in face.ring {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - vr, y: p.y - vr,
                                                        width: vr * 2, height: vr * 2)),
                                 with: .color(ClosedPolygonAppearance.vertexFill.opacity(dim)))
                    }
                }
            }

            if env.isPointWorkMode { drawPointWork(in: ctx, scale: s, visible: visible) }

            // 겹침 윤곽 — 개체를 옮겨보는 대신 겹치는 곳을 제자리에 표시한다(명세 2-3 대체).
            let overlap = moves.isMoving ? OverlapDetector.Result() : env.overlapHighlight
            // 겹침은 원본 좌표로 계산하므로 이동 중에는 어긋난 자리를 가리킨다(A12).
            if !overlap.isEmpty {
                let color = env.canvasBackground.overlapOutline
                for seg in overlap.sharedSegments {
                    var p = Path()
                    p.move(to: seg.start.cg); p.addLine(to: seg.end.cg)
                    ctx.stroke(p, with: .color(color),
                               style: StrokeStyle(lineWidth: 3 / s, lineCap: .round))
                }
                for pt in overlap.crossings {
                    // 교차점은 구간과 구분되도록 마름모로 그린다. 확대해도 크기가 일정하게 1/s.
                    let r: CGFloat = 5 / s
                    var d = Path()
                    d.move(to: CGPoint(x: pt.x, y: pt.y - r))
                    d.addLine(to: CGPoint(x: pt.x + r, y: pt.y))
                    d.addLine(to: CGPoint(x: pt.x, y: pt.y + r))
                    d.addLine(to: CGPoint(x: pt.x - r, y: pt.y))
                    d.closeSubpath()
                    ctx.stroke(d, with: .color(color), lineWidth: 1.6 / s)
                }
            }

            // 링이 열린 지점(명세 10-4-3). 겹침 표시와 색·모양을 일부러 다르게 한다 —
            // 겹침은 "여기 뭔가 있다", 이쪽은 "여기가 비어 있다"로 뜻이 정반대라
            // 같은 기호를 쓰면 도면을 반대로 고치게 된다.
            for gap in env.openRingGaps {
                let r: CGFloat = 7 / s
                let c = env.canvasBackground.marker(.outlier)
                var ring = Path(ellipseIn: CGRect(x: gap.point.x - r, y: gap.point.y - r,
                                                  width: r * 2, height: r * 2))
                ctx.stroke(ring, with: .color(c),
                           style: StrokeStyle(lineWidth: 2 / s, dash: [3 / s, 2.5 / s]))
                // 점선 원 — 끊겨 있다는 것을 기호 자체로 드러낸다.
                ring = Path()
                ring.move(to: CGPoint(x: gap.point.x - r / 2, y: gap.point.y))
                ring.addLine(to: CGPoint(x: gap.point.x + r / 2, y: gap.point.y))
                ctx.stroke(ring, with: .color(c), lineWidth: 2 / s)
            }

            // display point
            for f in env.features.features where !f.isInTrash {
                guard let dp = f.displayPoint else { continue }
                let r: CGFloat = 5 / s
                ctx.fill(Path(ellipseIn: CGRect(x: dp.x - r, y: dp.y - r, width: r * 2, height: r * 2)),
                         with: .color(env.canvasBackground.marker(.displayPoint)))
            }

            // Anchor
            for (i, cp) in env.anchors.pairs.enumerated() {
                drawCross(ctx, at: cp.local, scale: s,
                          color: env.canvasBackground.marker(
                              env.outlierIndices.contains(i) ? .outlier : .normal))
            }
            if let pending = env.pendingAnchorLocal {
                drawCross(ctx, at: pending, scale: s,
                          color: env.canvasBackground.marker(.pending))
            }
        }
        .contentShape(Rectangle())
    }

    /// 점 단위 편집(#21). **저장된 도형 → 꼭짓점·교점 → 작성 중인 도형 순서로 그린다.**
    /// 작성 중인 것이 맨 위에 와야 지금 찍은 점이 다른 표시에 가려지지 않는다.
    private func drawPointWork(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        guard let type = env.layers.activePropertyType else { return }
        let saved = ClosedPolygonAppearance.savedFill
        let handle = CanvasZoom.screenLength(3.5, at: s)
        for f in env.features.features(ofType: type) {
            for r in f.polygonRings.indices {
                let ring = env.previewRing(of: f, ring: r)
                guard ring.count >= 3 else { continue }
                var path = Path(); path.addLines(ring.map(\.cg)); path.closeSubpath()
                guard path.boundingRect.intersects(visible) else { continue }
                ctx.fill(path, with: .color(saved.opacity(ClosedPolygonAppearance.savedFillOpacity)))
                ctx.stroke(path, with: .color(saved), lineWidth: CanvasZoom.screenLength(1.5, at: s))
                if env.isVertexMoveEnabled, f.isPointDrawn {
                    for p in ring {
                        ctx.stroke(Path(CGRect(x: p.x - handle, y: p.y - handle, width: handle * 2, height: handle * 2)),
                                   with: .color(saved), lineWidth: CanvasZoom.screenLength(1, at: s))
                    }
                }
            }
            let v = env.previewDrawnVertices(of: f)
            if v.count >= 2 {
                var line = Path(); line.addLines(v.map(\.cg))
                ctx.stroke(line, with: .color(saved), lineWidth: CanvasZoom.screenLength(3, at: s))
            }
            for p in v {
                let r = CanvasZoom.screenLength(v.count == 1 ? 5 : 3, at: s)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(saved))
            }
        }

        // 꼭짓점·교점. 화면에 너무 많으면 그리지 않는다 — 수만 개를 그리면 화면이 점으로 덮여
        // 도면이 안 보이고 그리기도 느려진다. 확대하면 나타난다.
        let visibleIndices = env.snapPointIndex.indices(in: visible)
        if visibleIndices.count <= 4000 {
            let r = CanvasZoom.screenLength(2.2, at: s)
            for i in visibleIndices {
                let sp = env.snapPointIndex.points[i]
                let rect = CGRect(x: sp.point.x - r, y: sp.point.y - r, width: r * 2, height: r * 2)
                let shape = sp.kind == .crossing ? Path(rect) : Path(ellipseIn: rect)
                ctx.stroke(shape, with: .color(ClosedPolygonAppearance.vertexFill),
                           lineWidth: CanvasZoom.screenLength(1, at: s))
            }
        }

        let draft = env.previewDraftPoints
        guard !draft.isEmpty else { return }
        let accent = env.canvasBackground.selection
        if draft.count >= 2 {
            var line = Path(); line.addLines(draft.map(\.cg))
            ctx.stroke(line, with: .color(accent),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(2, at: s), lineJoin: .round))
        }
        if draft.count >= 3, env.activeGeometryKind.isAreal {
            var closing = Path(); closing.move(to: draft.last!.cg); closing.addLine(to: draft[0].cg)
            ctx.stroke(closing, with: .color(accent.opacity(0.5)),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1, at: s),
                                          dash: [4, 3].map { CanvasZoom.screenLength($0, at: s) }))
            // 닫으면 생길 변을 점선으로 미리 보여준다.
        }
        for (i, p) in draft.enumerated() {
            let r = CanvasZoom.screenLength(i == 0 ? 6 : 4, at: s)
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(i == 0 ? env.canvasBackground.fill : accent))
            ctx.stroke(dot, with: .color(accent), lineWidth: CanvasZoom.screenLength(i == 0 ? 2.5 : 1, at: s))
            // 시작점은 속이 빈 큰 원(◎)이다. 다시 누르면 닫힌다는 것을 모양으로 보여준다.
        }
    }

    private func drawCross(_ ctx: GraphicsContext, at p: LocalPoint, scale s: CGFloat, color: Color) {
        let r: CGFloat = 9 / s
        var path = Path()
        path.move(to: CGPoint(x: p.x - r, y: p.y)); path.addLine(to: CGPoint(x: p.x + r, y: p.y))
        path.move(to: CGPoint(x: p.x, y: p.y - r)); path.addLine(to: CGPoint(x: p.x, y: p.y + r))
        ctx.stroke(path, with: .color(color), lineWidth: 2 / s)
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                   with: .color(color), lineWidth: 1.5 / s)
    }

    private func drawReferenceLayers(in context: GraphicsContext, canvasSize: CGSize, scale: CGFloat) {
        guard let prepared = env.canvasReferences, prepared.input.levelID == env.routingFloorID else { return }
        let footprint = env.footprintPresentation
        if footprint.isVisible {
            for path in prepared.footprintPaths {
                context.fill(path, with: .color(.purple.opacity(footprint.opacity * 0.15)), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(.purple.opacity(footprint.opacity)), lineWidth: CanvasZoom.screenLength(2, at: scale))
            }
        }
        guard let doc = prepared.reference, let presentation = env.activeLevel?.referenceDrawing?.presentation,
              presentation.isVisible, doc.canvasSize.width > 0, doc.canvasSize.height > 0 else { return }
        let fit = min(canvasSize.width / doc.canvasSize.width, canvasSize.height / doc.canvasSize.height)
        var layer = context
        layer.opacity *= presentation.opacity
        layer.translateBy(x: (canvasSize.width - doc.canvasSize.width * fit) / 2,
                          y: (canvasSize.height - doc.canvasSize.height * fit) / 2)
        layer.scaleBy(x: fit, y: fit)
        doc.drawImages(in: layer)
        for (object, path) in zip(doc.objects, prepared.paths) {
            if let fill = object.style.fill { layer.fill(path, with: .color(env.canvasBackground.resolveFill(fill)), style: FillStyle(eoFill: true)) }
            layer.stroke(path, with: .color(env.canvasBackground.resolve(object.style.stroke)), lineWidth: object.style.strokeWidth)
        }
    }

    private func drawRouting(in ctx: inout GraphicsContext, document: DrawingDocument, scale s: CGFloat, visible: CGRect) {
        let presentation = env.currentRoutingFloor?.imdfCoordinates == nil ? env.primarySVGPresentation : DrawingLayerPresentation(isVisible: true, opacity: 1)
        for object in document.objects where presentation.isVisible {
            let cached = env.renderCache.entry(for: object, segmentation: env.segmentation)
            guard cached.box.insetBy(dx: -2, dy: -2).intersects(visible) else { continue }
            let path = cached.path
            if let fill = object.style.fill {
                ctx.fill(path, with: .color(env.canvasBackground.resolveFill(fill).opacity(0.25 * presentation.opacity)),
                         style: FillStyle(eoFill: env.currentRoutingFloor?.imdfCoordinates != nil))
            }
            ctx.stroke(path, with: .color(env.canvasBackground.resolve(object.style.stroke).opacity(0.6 * presentation.opacity)),
                       lineWidth: CanvasZoom.strokeWidth(object.style.strokeWidth, at: s))
        }
        func point(_ node: RoutingNode) -> LocalPoint {
            node.id == routingDragNode ? (routingDragPoint ?? node.point) : node.point
        }
        let floorID = env.currentRoutingFloor?.id
        for edge in env.routing.edges {
            guard let a = env.routing.node(edge.from), let b = env.routing.node(edge.to),
                  a.floorID == floorID || b.floorID == floorID else { continue }
            let selected = env.routingSelectedEdgeID == edge.id
            let color = selected ? Color.orange : (edge.accessible ? Color.blue : Color.purple)
            if a.floorID == b.floorID {
                var line = Path()
                line.move(to: point(a).cg); line.addLine(to: point(b).cg)
                ctx.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: (selected ? 4 : 2) / s,
                                              dash: edge.accessible ? [] : [6 / s, 4 / s]))
            } else {
                let local = a.floorID == floorID ? a : b
                let other = a.floorID == floorID ? b : a
                let p = point(local)
                ctx.draw(Text("↕ \(env.routing.floor(other.floorID)?.name ?? "")")
                    .font(.system(size: 11 / s)).foregroundStyle(color),
                         at: CGPoint(x: p.x, y: p.y + 20 / s))
            }
        }
        if let drag = env.routingConnectionDrag, let from = env.routing.node(drag.from), drag.floorID == floorID {
            let destination = env.routing.node(drag.target)?.point ?? drag.pointer
            var line = Path()
            line.move(to: from.point.cg)
            line.addLine(to: destination.cg)
            ctx.stroke(line, with: .color(.blue.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5 / s, lineCap: .round,
                                          dash: drag.target == nil ? [4 / s, 3 / s] : []))
        }
        let displayIDs = env.routing.nodeDisplayIDs
        for node in env.routing.nodes(on: floorID) {
            let p = point(node)
            let selected = env.routingSelectedNodeID == node.id || env.routingConnectStart == node.id ||
                env.routingConnectionDrag?.target == node.id
            let r: CGFloat = 4 / s
            if selected {
                let glowRadius: CGFloat = 12 / s
                let glow = Path(ellipseIn: CGRect(x: p.x-glowRadius, y: p.y-glowRadius,
                                                 width: 2*glowRadius, height: 2*glowRadius))
                ctx.fill(glow, with: .radialGradient(Gradient(colors: [.blue.opacity(0.55), .blue.opacity(0)]),
                                                     center: p.cg, startRadius: 0, endRadius: glowRadius))
            }
            let circle = Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: 2*r, height: 2*r))
            ctx.fill(circle, with: .color(RoutingNodeCategory.color(for: node.category)))
            ctx.stroke(circle, with: .color(env.canvasBackground.fill), lineWidth: 1 / s)
            var labels = ctx
            labels.translateBy(x: p.x, y: p.y)
            labels.rotate(by: .degrees(-env.rotationDegrees))
            labels.draw(Text(displayIDs[node.id] ?? node.shortID)
                .font(.system(size: 8 / s, weight: .regular, design: .monospaced))
                .foregroundStyle(env.canvasBackground.toolbarForeground.opacity(0.5)),
                        at: CGPoint(x: 0, y: 13 / s))
            if !node.name.isEmpty {
                labels.draw(Text(node.name).font(.system(size: 10 / s)).foregroundStyle(env.canvasBackground.toolbarForeground),
                            at: CGPoint(x: 0, y: -13 / s))
            }
        }
        if env.routingTool == .calibrate {
            for pair in env.currentRoutingFloor?.anchors.pairs ?? [] {
                drawCross(ctx, at: pair.local, scale: s, color: .green)
            }
            if let pending = env.routingPendingAnchor { drawCross(ctx, at: pending, scale: s, color: .orange) }
        }
    }

    /// 지금 화면에 보이는 도면 범위. 화면 네 모서리를 도면 좌표로 옮겨 감싸는 사각형을 만든다.
    /// `toLocal`이 회전까지 역변환하므로 90° 회전 상태에서도 정확하다.
    private func visibleDocRect(viewport: CGSize) -> CGRect {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: viewport.width, y: 0),
                       CGPoint(x: 0, y: viewport.height),
                       CGPoint(x: viewport.width, y: viewport.height)].map { toLocal($0) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .infinite }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var ghostLayer: EditorLayer? {
        env.layers.layers.first { if case .baseGhost = $0.kind { return true }; return false }
    }

    // MARK: 제스처

    private var effectiveScale: CGFloat { scale * gestureScale }

    /// 문서 중심 — 회전축.
    private var docCenter: CGPoint {
        guard let d = displayedDocument else { return .zero }
        return CGPoint(x: d.canvasSize.width / 2, y: d.canvasSize.height / 2)
    }

    /// 화면 좌표 → 도면 좌표. 그리기 변환의 역순(역회전 포함)이다.
    private func toLocal(_ p: CGPoint) -> LocalPoint {
        let s = effectiveScale
        var x = (p.x - offset.width) / s
        var y = (p.y - offset.height) / s

        if env.canvasRotation != 0 {
            let c = docCenter
            let r = -env.rotationDegrees * .pi / 180
            let dx = x - c.x, dy = y - c.y
            x = c.x + dx * cos(r) - dy * sin(r)
            y = c.y + dx * sin(r) + dy * cos(r)
        }
        return LocalPoint(x, y)
    }

    private func dragGesture(viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = offset
                    lastDrag = .zero
                    dragIsMarquee = !env.showRoutingScreen && env.isSelectModeActive && !env.isPointWorkMode
                    // 점 단위 편집에는 개체를 고르는 사각형 선택이 없다(#21, 선분 단위 작업 폐지).
                    dragIsVertex = false
                    if env.isPointWorkMode, env.isVertexMoveEnabled,
                       let target = env.vertexHit(at: toLocal(value.startLocation),
                                                  tolerance: 6 / Double(effectiveScale)) {
                        dragIsVertex = true
                        dragIsMarquee = false
                        env.beginVertexDrag(target, at: toLocal(value.startLocation))
                    }
                    if env.showRoutingScreen {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        let hit = env.nearestRoutingNode(to: toLocal(value.startLocation),
                                                        tolerance: 9 / Double(effectiveScale))
                        let modifiers = NSEvent.modifierFlags
                        routingDragOptionHeld = modifiers.contains(.option)
                        routingDragCommandHeld = modifiers.contains(.command) &&
                            modifiers.intersection([.option, .control]).isEmpty
                        routingDragIsConnection = routingDragOptionHeld ||
                            (!routingDragCommandHeld && env.routingTool == .connect && hit != nil)
                        routingDragConnectCandidate = routingDragIsConnection ? hit?.id : nil
                        if !routingDragIsConnection && !routingDragCommandHeld &&
                            (env.routingTool == .place || env.routingTool == .select) {
                            routingDragNode = hit?.id
                            if let routingDragNode { env.selectRoutingNode(routingDragNode) }
                        }
                    }
                    // 드래그 도중 fn+shift+z를 놓으면 팬으로 돌변해 화면이 튄다.
                    // 시작 시점에 무엇을 하는 드래그인지 확정하고 끝까지 유지한다.
                    if !env.showRoutingScreen, dragIsMarquee == false, !dragIsVertex, !env.isPolygonWorkMode, env.isMoveEnabled {
                        // fn+shift+z가 없을 때만 이동 후보다 — 사각형 선택이 최우선이다.
                        // '개체 이동' 토글이 꺼져 있으면 여기를 아예 건너뛴다(2026-08-29 사노 요청).
                        // `moveBase`가 nil로 남으므로 아래 분기에서 화면 팬이 된다 — 드래그가
                        // 먹통이 되는 것이 아니라, 토글 도입 전의 조작으로 돌아간다.
                        let tol = 6 / Double(effectiveScale)
                        if env.movableHit(at: toLocal(value.startLocation), tolerance: tol) != nil {
                            moveBase = env.beginMove()
                        }
                    }
                }
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation

                // Command is a click shortcut, so a Command-drag neither moves pins nor pans the map.
                if routingDragCommandHeld && !routingDragIsConnection { return }
                if dragIsVertex {
                    env.updateVertexDrag(to: toLocal(value.location), tolerance: 6 / Double(effectiveScale),
                                         freePoint: NSEvent.modifierFlags.contains(.option))
                } else if routingDragIsConnection {
                    let moved = abs(value.translation.width) + abs(value.translation.height)
                    if !routingConnectionStarted, let from = routingDragConnectCandidate,
                       routingDragOptionHeld || moved >= MarqueeRect.dragThreshold {
                        routingConnectionStarted = true
                        env.beginRoutingConnectionDrag(from: from)
                    }
                    env.updateRoutingConnectionDrag(to: toLocal(value.location), tolerance: 9 / Double(effectiveScale))
                } else if routingDragNode != nil {
                    routingDragPoint = toLocal(value.location)
                } else if dragIsMarquee == true {
                    marquee = MarqueeRect(start: value.startLocation, current: value.location)
                } else if let base = moveBase {
                    // 화면 델타를 그대로 도면 좌표 델타로 쓰면 확대 배율만큼 실제보다 크게 옮겨진다.
                    let s = effectiveScale
                    let docDelta = CGSize(width: value.translation.width / s,
                                          height: value.translation.height / s)
                    env.applyMove(docDelta, from: base)
                } else {
                    offset.width += delta.width
                    offset.height += delta.height
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if env.showRoutingScreen {
                    if routingDragIsConnection {
                        if routingConnectionStarted {
                            if CGRect(origin: .zero, size: viewport).contains(value.location) {
                                env.finishRoutingConnectionDrag(at: toLocal(value.location), tolerance: 9 / Double(effectiveScale))
                            } else { env.routingConnectionDrag = nil }
                        } else if !routingDragOptionHeld, moved < MarqueeRect.dragThreshold {
                            env.handleRoutingClick(at: toLocal(value.location), tolerance: 9 / Double(effectiveScale))
                        }
                    } else if routingDragCommandHeld {
                        if moved < MarqueeRect.dragThreshold {
                            env.handleRoutingClick(at: toLocal(value.location), tolerance: 9 / Double(effectiveScale), modifiers: .command)
                        }
                    } else if let id = routingDragNode, moved >= MarqueeRect.dragThreshold {
                        env.moveRoutingNode(id, to: toLocal(value.location))
                    } else if moved < MarqueeRect.dragThreshold {
                        env.handleRoutingClick(at: toLocal(value.location), tolerance: 9 / Double(effectiveScale))
                    }
                } else if dragIsVertex {
                    if moved >= MarqueeRect.dragThreshold {
                        env.endVertexDrag()
                    } else {
                        env.vertexDrag = nil
                        env.handlePointClick(at: toLocal(value.location), tolerance: 6 / Double(effectiveScale),
                                             freePoint: NSEvent.modifierFlags.contains(.option))
                        // 꼭짓점 위를 끌지 않고 눌렀으면 클릭이다(시작점으로 닫기·점 지우기).
                    }
                } else if let m = marquee, moved >= MarqueeRect.dragThreshold {
                    selectByMarquee(m)
                } else if moveBase == nil, moved < MarqueeRect.dragThreshold {
                    if env.isPolygonWorkMode {
                        env.handleFaceClick(at: toLocal(value.location))
                        // 폴리곤 type에서는 클릭이 개체가 아니라 **면**을 고른다(신기능 5-4).
                    } else if env.isPointWorkMode, !env.mode.blocksSelection {
                        env.handlePointClick(at: toLocal(value.location), tolerance: 6 / Double(effectiveScale),
                                             freePoint: NSEvent.modifierFlags.contains(.option))
                        // #21: property type 레이어의 클릭은 개체가 아니라 **점**을 찍는다.
                        // display point·Anchor 찍기 중이면 아래 종전 경로가 받는다.
                    } else {
                        env.handleCanvasClick(at: toLocal(value.location),
                                              tolerance: 6 / Double(effectiveScale))
                    }
                }
                marquee = nil
                dragIsMarquee = nil
                dragIsVertex = false
                if moveBase != nil { env.endMove() }
                moveBase = nil
                routingDragNode = nil
                routingDragPoint = nil
                routingDragIsConnection = false
                routingDragOptionHeld = false
                routingDragCommandHeld = false
                routingDragConnectCandidate = nil
                routingConnectionStarted = false
                dragStart = nil
                lastDrag = .zero
            }
    }

    // MARK: 드래그 사각형 선택 (명세 디버깅 9번)

    /// 화면 사각형을 도면 좌표로 옮겨 선택에 넘긴다.
    /// 회전은 90° 단위뿐이라, 화면과 축이 나란한 사각형은 도면에서도 축과 나란하다 —
    /// 그래서 두 꼭짓점만 변환해 min/max를 취하면 정확한 사각형이 된다.
    private func selectByMarquee(_ m: MarqueeRect) {
        let a = toLocal(m.start), b = toLocal(m.current)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        if env.isPolygonWorkMode {
            env.handleFaceMarquee(rect: rect, mode: m.mode)
            // 신기능 5-4 3번: 다각형도 드래그로 복수 선택한다.
        } else {
            env.handleMarqueeSelection(rect: rect, mode: m.mode)
        }
    }

    private func fit(doc: DrawingDocument, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let rotated = env.canvasRotation % 2 == 1
        let w = rotated ? doc.canvasSize.height : doc.canvasSize.width
        let h = rotated ? doc.canvasSize.width : doc.canvasSize.height
        let sx = (viewport.width - 80) / max(1, w)
        let sy = (viewport.height - 120) / max(1, h)
        scale = max(0.1, min(sx, sy))
        offset = CGSize(width: (viewport.width - doc.canvasSize.width * scale) / 2,
                        height: (viewport.height - doc.canvasSize.height * scale) / 2)
    }

    // MARK: 보조 UI

    /// 캔버스 배경 위에 직접 얹으면 배경 밝기에 따라 글씨가 묻힌다.
    /// 상단바와 같은 불투명 카드에 올려, 시스템 외관과 무관하게 캔버스 배경만 보고 색을 정한다.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(env.canvasBackground.toolbarForeground.opacity(0.65))
            Text(env.showRoutingScreen
                 ? (env.currentRoutingFloor == nil ? "완성된 IMDF를 불러와 노드를 찍으세요" : "이 층의 원본 도면을 불러오세요")
                 : "도면을 열어 시작하세요")
                .font(.title3)
            Button("IMDF 불러오기…") { env.importIMDF() }
                .buttonStyle(.borderedProminent).disabled(env.isImportingIMDF)
            Button("프로젝트 열기 (.imdfrnt)…") { env.openProject() }
                .buttonStyle(.bordered)
                .disabled(env.isProjectBusy)
                .help("저장한 프로젝트의 도면·층·노드·연결을 불러옵니다. (⌘⇧O)")
            Button(env.showRoutingScreen && env.currentRoutingFloor == nil ? "층 추가" : "도면 불러오기…") {
                if env.showRoutingScreen {
                    if env.currentRoutingFloor == nil { env.addRoutingFloor() } else { env.importRoutingDrawing() }
                } else { env.openFile() }
            }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .toolbarCard(cornerRadius: 14)
    }

    private func zoomControls(doc: DrawingDocument?, viewport: CGSize) -> some View {
        HStack(spacing: 6) {
            Button { zoomByButton(1 / 1.25, viewport: viewport) } label: { Image(systemName: "minus.magnifyingglass") }
            Text(CanvasZoom.label(scale)).font(.caption.monospacedDigit()).frame(width: 52)
            Button { zoomByButton(1.25, viewport: viewport) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("맞춤") { if let doc { fit(doc: doc, viewport: viewport) } }

            ToolbarDivider().frame(height: 16)

            Button { env.rotateCanvas(-1) } label: { Image(systemName: "rotate.left") }
                .help("도면 왼쪽으로 90° 회전")
            Button { env.rotateCanvas(1) } label: { Image(systemName: "rotate.right") }
                .help("도면 오른쪽으로 90° 회전")
            if env.canvasRotation != 0 {
                Text("\(Int(env.rotationDegrees))°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ToolbarDivider().frame(height: 16)
            backgroundToggle
        }
        .buttonStyle(.toolbarIcon)
        // 시스템 외관을 따르는 `.bordered`+`.primary`를 쓰면 캔버스 배경과 어긋나
        // 밝은 도면 위에서 글씨가 묻힌다(디버깅 10번). 색은 캔버스 배경에서만 뽑는다.
        .padding(6)
        .toolbarCard(cornerRadius: 8)
    }

    /// 도면 배경 밝게/어둡게 전환.
    private var backgroundToggle: some View {
        Button {
            env.canvasBackground = env.canvasBackground == .light ? .dark : .light
        } label: {
            Label(env.canvasBackground.label,
                  systemImage: env.canvasBackground.symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .help("도면 배경 밝게/어둡게 전환")
    }

    private var modeChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(env.isSelectModeActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(env.isSelectModeActive
                 ? "선택 모드 — 클릭 또는 드래그(→ 감싸기 / ← 스치기)"
                 : "화면 이동 모드 — fn+shift+z를 누르면 선택")
                .font(.caption)
            Toggle("고정", isOn: $env.forceSelectMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("fn 키가 시스템에 선점될 때 쓰는 대체 토글")
        }
        // zoomControls와 같은 이유. 모드 표시가 흐리면 지금 어느 모드인지 읽기 어렵다.
        .padding(.horizontal, 10).padding(.vertical, 7)
        .toolbarCapsuleCard()
    }
}
