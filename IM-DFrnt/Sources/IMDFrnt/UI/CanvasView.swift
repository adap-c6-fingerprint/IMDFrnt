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
    @State private var labelHitBoxes = FeatureLabelHitBoxes()
    /// 이름표를 눌러 연 편집 창의 대상과 그 이름표 자리(화면 좌표).
    @State private var tagEditor: (id: FeatureGroupID, rect: CGRect)?
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
                        .onChange(of: env.tagEditorRequest) { _, id in
                            guard let id else { return }
                            DispatchQueue.main.async { openRequestedTagEditor(id, scale: effectiveScale) }
                            // 방금 저장한 feature의 이름표는 다음 그리기에서 생긴다. 한 박자 늦춰 그 자리를 찾는다.
                        }
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
                        CanvasBarFit { PolygonToolbar() }
                        // 폴리곤 type에서는 선택 대상이 개체가 아니라 면이라 상단바가 다르다.
                        // **선택이 없어도 항상 뜬다** — 이 모드에서는 무엇을 더 해야 하는지가 곧 안내다.
                    } else if env.isPointWorkMode {
                        CanvasBarFit { PointToolbar() }
                        // #21: property type 레이어의 기본 작업은 점 단위다.
                    } else if env.isObjectWorkMode {
                        CanvasBarFit { ObjectToolbar() }
                        // fixture 선 단위. 모드 전환이 늘 보여야 하므로 선택이 없어도 뜬다.
                    } else if !env.selection.isEmpty {
                        CanvasBarFit { SelectionToolbar() }
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .frame(width: geo.size.width, height: geo.size.height)
                // 캔버스 크기에 못 박는다. 없으면 상단바가 제 폭을 고집해 캔버스 칸을 넓히고,
                // 넓어진 캔버스가 오른쪽 사이드바를 덮는다(창을 좁혔을 때).

                VStack {
                    Spacer()
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            zoomControls(doc: displayedDocument, viewport: geo.size).fixedSize()
                            Spacer()
                            if !env.showRoutingScreen { modeChip.fixedSize() }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if !env.showRoutingScreen { modeChip.fixedSize() }
                            zoomControls(doc: displayedDocument, viewport: geo.size).fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 한 줄에 안 들어가면 모드 표시를 확대 막대 위로 올린다.
                        CanvasBarFit {
                            zoomControls(doc: displayedDocument, viewport: geo.size)
                        }
                    }
                    .padding(12)
                }
                .frame(width: geo.size.width, height: geo.size.height)
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
        featureLabelCanvas(doc: doc, viewport: viewport)
            .onContinuousHover(coordinateSpace: .local) { phase in
                var hit: FeatureGroupID?
                if case .active(let p) = phase { hit = labelHitBoxes.boxes.last { $0.1.contains(p) }?.0 }
                // 나중에 그린 태그가 위에 보이므로 뒤에서부터 찾는다.
                if env.hoveredFeature != hit { env.hoveredFeature = hit }
            }
            .overlay(alignment: .topLeading) {
                if let e = tagEditor {
                    Color.clear
                        .frame(width: e.rect.width, height: e.rect.height)
                        .popover(isPresented: Binding(get: { tagEditor?.id == e.id }, set: { if !$0 { tagEditor = nil } }),
                                 arrowEdge: .bottom) {
                            FeatureTagEditor(featureID: e.id).environmentObject(env)
                        }
                        .padding(.leading, max(0, e.rect.minX))
                        .padding(.top, max(0, e.rect.minY))
                        .allowsHitTesting(false)
                    // 눌린 이름표 자리에 보이지 않는 닻을 두고 거기서 창을 띄운다.
                    // offset은 그리는 자리만 옮겨 창이 엉뚱한 곳에 붙으므로 padding으로 자리를 잡는다.
                }
            }
    }

    private func featureLabelCanvas(doc: DrawingDocument, viewport: CGSize) -> some View {
        Canvas { ctx, size in
            let s = effectiveScale
            let visible = visibleDocRect(viewport: size)
            let states = env.renderStates()
            // 표시 상태는 프레임마다 개체별로 다시 판정하지 않고 **사전 하나**를 받아 쓴다(제안 3).
            let screenCtx = ctx
            // 변환 전의 화면 좌표 붓. 개체 이름표처럼 확대와 무관하게 같은 크기로 그릴 것에 쓴다.
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

            let renderCache = env.renderCache
            let segmentation = env.segmentation
            let background = env.canvasBackground
            let offsets = moves.offsets
            // 개체마다 읽는 값은 루프 밖에서 한 번만 읽는다(2026-10-19 캔버스 이동 렉).
            // `@Published` 값은 읽을 때마다 Combine을 거쳐, 6만 개 × 여러 번이면 그것만 한 프레임에 수십 ms였다.

            // 하위 기본 레이어 — 원위치를 20% opacity로. 히트테스트 대상이 아니다.
            if primary.isVisible, let ghost = ghostLayer, !ghost.isHidden {
                let ghostColor = GraphicsContext.Shading.color(background.ghostStroke.opacity(ghost.opacity * primary.opacity))
                // 수치를 여기 다시 적지 않고 `EditorLayer.opacity`를 쓴다(사용자 조절분 포함).
                // 명세 2-3의 수치가 두 곳에 흩어져 있으면 한쪽만 고쳐 어긋난다.
                if let ghostIndices = env.spatialIndex.drawIndices(in: visible, moved: [], count: doc.objects.count) {
                    for o in ghostIndices.map({ doc.objects[$0] }) {
                        let cache = renderCache.entry(for: o, segmentation: segmentation)
                        guard cache.box.insetBy(dx: -o.style.strokeWidth / 2 - 2,
                                                dy: -o.style.strokeWidth / 2 - 2).intersects(visible)
                        else { continue }
                        // 화면 밖은 그리지 않는다(제안 5). 고스트는 원위치를 그리는 레이어라
                        // 이동량을 얹지 않으므로 원본 상자 그대로 판정한다.
                        ctx.stroke(cache.path, with: ghostColor,
                                   lineWidth: CanvasZoom.strokeWidth(o.style.strokeWidth, at: s))
                    }
                } else {
                    for (width, path) in env.canvasGhostBatches(document: doc).paths {
                        ctx.stroke(path, with: ghostColor, lineWidth: CanvasZoom.strokeWidth(width, at: s))
                    }
                    // 도면 대부분이 보이면 굵기별로 묶은 경로 몇 개만 긋는다(`CanvasBatches`).
                }
            }

            // 상위 기본 레이어 / 현재 property type 레이어
            let onScreen = env.spatialIndex.drawIndices(in: visible, moved: Set(offsets.keys),
                                                        count: doc.objects.count)
            // 확대해 일부만 보고 있으면 격자로 화면 안의 개체만 돈다. 6만 개를 매 프레임 훑던 것이 이동·확대 버벅임의 큰 몫이었다.
            if primary.isVisible, onScreen == nil, offsets.isEmpty {
                let batches = env.canvasObjectBatches(document: doc, primaryOpacity: primary.opacity)
                var g = ctx
                g.opacity *= primary.opacity
                for (color, path) in batches.fills { g.fill(path, with: .color(color)) }
                for (key, path) in batches.strokes {
                    let style = StrokeStyle(lineWidth: CanvasZoom.strokeWidth(key.width, at: s, emphasis: key.emphasized ? 2.0 : 1.0),
                                            dash: key.borrowed
                                                ? [5, 3].map { CanvasZoom.screenLength($0, at: s) }
                                                : key.dash.map { CGFloat($0) })
                    g.stroke(path, with: .color(key.color), style: style)
                }
                for b in batches.selectedBoxes { drawSelectionBox(b, in: g, scale: s, background: background) }
                // 도면 대부분이 보이고 옮기는 개체가 없으면 같은 색·굵기끼리 묶은 경로를 그린다(`CanvasBatches`).
                // 묶음은 표시 상태·도형이 바뀔 때만 다시 만든다. 화면만 옮기는 동안은 만든 것을 그대로 쓴다.
            } else {
                for o in onScreen.map({ $0.map { doc.objects[$0] } }) ?? doc.objects {
                    let st = states[o.id] ?? env.renderState(for: o)
                    guard primary.isVisible, st.isVisible, st.opacity * primary.opacity > 0.01 else { continue }

                    let cache = renderCache.entry(for: o, segmentation: segmentation)
                    let off = offsets[o.id] ?? .zero
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
                            background.resolveFill(fill).opacity(st.opacity * 0.35)))
                    }
                    // 명세 10-2-2: 빌려온 개체는 **점선 테두리 + 다른 색**으로 구분한다.
                    // 소유·비활성·선택 어느 것과도 다른 상태라 색을 따로 준다 —
                    // 같은 색을 쓰면 "내가 저장한 것"과 "남에게 빌린 것"이 구분되지 않는다.
                    let strokeColor = Self.strokeColor(st, style: o.style, background: background)
                    let width = CanvasZoom.strokeWidth(
                        o.style.strokeWidth, at: s,
                        emphasis: st.isSelected || st.isBorrowed || st.isHighlighted ? 2.0 : 1.0)
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

                    if st.isSelected { drawSelectionBox(cache.box, in: g, scale: s, background: background) }
                }
            }

            // 다각형 선택 모드(신기능 5-4) — 폴리곤 type 레이어에서는 면을 그리고 고른다.
            // **면 → 선 → 점 순서가 규칙이다.** 면을 나중에 그리면 경계선과 꼭짓점을 덮어
            // 어디서 닫혔는지 확인할 수 없다.
            if env.isPolygonWorkMode {
                let saved = env.savedPolygonFaceIDs
                var highlighted = env.features.features.reduce(into: Set<String>()) { out, f in
                    if !f.isInTrash, env.isFeatureHighlighted(f.id) { out.formUnion(f.polygonFaceIDs) }
                }
                var taggedHere = env.features.features.reduce(into: Set<String>()) { out, f in
                    if !f.isInTrash, f.featureType == env.layers.activePropertyType { out.formUnion(f.polygonFaceIDs) }
                }
                let faceTypes = env.features.features.reduce(into: [String: IMDFFeatureType]()) { out, f in
                    guard !f.isInTrash else { return }
                    for id in f.polygonFaceIDs { out[id] = f.featureType }
                }
                let faces = env.faceModeFaces
                drawUnrepresentedSavedFeatures(in: ctx, faces: faces, scale: s, visible: visible)
                var filteredOut = env.features.features.reduce(into: Set<String>()) { out, f in
                    if !f.isInTrash, !env.passesCategoryFilter(f) { out.formUnion(f.polygonFaceIDs) }
                }
                // category 필터로 걸러진 feature의 면은 그리지 않는다(#52).
                for face in faces {
                    guard let owner = env.faceOwner(face) else { continue }
                    taggedHere.insert(face.id)
                    if env.isFeatureHighlighted(owner) { highlighted.insert(face.id) }
                    if let f = env.features.feature(owner), !env.passesCategoryFilter(f) { filteredOut.insert(face.id) }
                }
                // 저장된 개체 경계로 찾은 면은 면 기록이 없다. 같은 모양으로 저장된 feature로 색을 정한다.
                for face in faces {
                    guard face.boundingBox.intersects(visible), !filteredOut.contains(face.id) else { continue }
                    var facePath = Path()
                    facePath.addLines(face.ring.map(\.cg))
                    facePath.closeSubpath()
                    for hole in env.faceHoles(face) { facePath.addLines(hole.map(\.cg)); facePath.closeSubpath() }
                    // level 기준 면의 구멍(이미 덮인 unit 자리)은 짝홀 규칙으로 비운다.

                    let isSaved = saved.contains(face.id) || taggedHere.contains(face.id)
                    let isPicked = env.faceSelection.contains(face.id)
                    var dim = 1.0
                    if case .ungroupedOnly = env.mode, isSaved { dim = 0.25 }
                    if isSaved, let t = taggedHere.contains(face.id) ? env.layers.activePropertyType : faceTypes[face.id] {
                        dim *= env.polygonOpacity(for: t)
                    }
                    // 저장된 면은 표시된 다각형이라 그 type 레이어의 투명도를 따른다. 아직 고르지 않은 면은 그대로다.
                    // 면 단위 '미저장만 보기'(신기능 5-4 4번). 저장한 면을 지우지 않고 옅게 눌러
                    // 남은 것이 드러나게 한다 — 지우면 어디까지 했는지 대조할 수가 없다.
                    let isHighlighted = highlighted.contains(face.id)
                    let fill = isHighlighted ? ClosedPolygonAppearance.highlightFill
                        : (isSaved ? (taggedHere.contains(face.id) ? ClosedPolygonAppearance.savedFill
                                                                   : ClosedPolygonAppearance.otherLayerFill)
                                   : ClosedPolygonAppearance.faceFill)
                    let fillOpacity = isHighlighted ? ClosedPolygonAppearance.highlightFillOpacity
                        : isSaved ? (taggedHere.contains(face.id) ? ClosedPolygonAppearance.savedFillOpacity
                                                                  : ClosedPolygonAppearance.otherLayerFillOpacity)
                        : (isPicked ? ClosedPolygonAppearance.selectedFillOpacity
                                    : ClosedPolygonAppearance.faceFillOpacity)
                    ctx.fill(facePath, with: .color(fill.opacity(fillOpacity * dim)), style: FillStyle(eoFill: true))
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

            if env.isPointWorkMode || env.isPolygonWorkMode { drawOtherLayerFeatures(in: ctx, scale: s, visible: visible) }
            // 다른 레이어에서 점으로 그린 feature는 지금 레이어의 도형 아래에 깐다.
            if env.isPointWorkMode { drawPointWork(in: ctx, scale: s, visible: visible) }
            if env.layers.activePropertyType == .unit { drawGuides(in: ctx, scale: s, visible: visible) }
            if env.isShowingUnitCoverage { drawUnitCoverage(in: ctx, scale: s, visible: visible) }
            drawExpandedUnitOverlaps(in: ctx, scale: s, visible: visible)
            drawSelectedVertexDots(in: ctx, scale: s, visible: visible)
            if env.isShowingUnitCoverage { drawUnitCoverageLabels(in: screenCtx, scale: s, visible: visible) }
            drawFeatureLabels(in: screenCtx, document: doc, scale: s, viewport: size)
            // 겹침 이름표를 feature 이름표보다 먼저 깐다. 위에 얹으면 빨간 이름표(눌러서 구멍 뚫기)를 덮어
            // 토글을 켠 동안 MultiPolygon unit에 다각형을 더할 수 없었다(엔진 디버깅 6번).
            if env.isPointWorkMode { drawDraftOrderLabels(in: screenCtx, scale: s) }
            drawSelectedOrderLabels(in: screenCtx, scale: s, visible: visible)

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

    /// 선택 테두리. 도면의 일부가 아니라 화면에 얹은 표시다.
    /// 보정하지 않으면 200배에서 개체에서 한참 떨어진 곳에 그려진다.
    private func drawSelectionBox(_ box: CGRect, in g: GraphicsContext, scale s: CGFloat, background: CanvasBackground) {
        let margin = CanvasZoom.screenLength(3, at: s)
        g.stroke(Path(roundedRect: box.insetBy(dx: -margin, dy: -margin), cornerRadius: CanvasZoom.screenLength(2, at: s)),
                 with: .color(background.selection.opacity(0.6)),
                 style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1, at: s),
                                    dash: [3, 3].map { CanvasZoom.screenLength($0, at: s) }))
    }

    /// 다른 레이어(property type)에서 태깅한 feature의 좌표 도형 — 점으로 그린 링·선·점과 문 닫기 선분.
    /// 편집 중인 레이어만 보이면 이미 다른 레이어가 무엇을 그렸는지 모른 채 겹쳐 그리게 된다(2026-10-17 요청).
    /// 옅은 초록·얇은 선·꼭짓점 손잡이 없음으로, 지금 레이어 것과 구분되고 고를 수도 없다.
    /// 구성원 개체로 이뤄진 부분은 개체 루프가 `isTaggedOtherLayer`로 이미 같은 색을 칠한다.
    private func drawOtherLayerFeatures(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        guard let type = env.layers.activePropertyType else { return }
        let color = ClosedPolygonAppearance.otherLayerFill
        let stroke = color.opacity(ClosedPolygonAppearance.otherLayerStrokeOpacity)
        let width = CanvasZoom.screenLength(1, at: s)
        for f in env.features.features where !f.isInTrash && f.featureType != type && env.passesCategoryFilter(f) {
            // 다른 레이어도 그 레이어에서 고른 category 필터를 따른다(#52).
            var fc = ctx
            fc.opacity *= env.polygonOpacity(for: f.featureType)
            // 다른 레이어의 도형은 그 레이어의 투명도를 따른다.
            if !(env.isPolygonWorkMode && !f.polygonFaceIDs.isEmpty) {
                // 면 모드에서 면으로 저장한 링은 면 루프가 이미 옅은 초록으로 칠했다. 두 번 칠하면 진해진다.
                var area = Path()
                for ring in f.polygonRings where ring.count >= 3 { area.addLines(ring.map(\.cg)); area.closeSubpath() }
                if !area.isEmpty, area.boundingRect.intersects(visible) {
                    fc.fill(area, with: .color(color.opacity(ClosedPolygonAppearance.otherLayerFillOpacity)),
                             style: FillStyle(eoFill: true))
                    fc.stroke(area, with: .color(stroke), lineWidth: width)
                    // MultiPolygon의 구멍이 비어 보이게 짝홀 규칙으로 칠한다.
                }
            }
            let v = f.drawnVertices ?? []
            if v.count >= 2 {
                var line = Path(); line.addLines(v.map(\.cg))
                fc.stroke(line, with: .color(stroke), lineWidth: CanvasZoom.screenLength(2, at: s))
            }
            for p in v {
                let r = CanvasZoom.screenLength(v.count == 1 ? 4 : 2, at: s)
                fc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(stroke))
            }
            if let c = f.closureSegment {
                var line = Path(); line.move(to: c.start.cg); line.addLine(to: c.end.cg)
                fc.stroke(line, with: .color(stroke), lineWidth: CanvasZoom.screenLength(2, at: s))
            }
        }
    }

    /// 점 단위 편집(#21). **저장된 도형 → 꼭짓점·교점 → 작성 중인 도형 순서로 그린다.**
    /// 작성 중인 것이 맨 위에 와야 지금 찍은 점이 다른 표시에 가려지지 않는다.
    private func drawPointWork(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        guard let type = env.layers.activePropertyType else { return }
        let handle = CanvasZoom.screenLength(3.5, at: s)
        let all = env.features.features(ofType: type).filter { env.passesCategoryFilter($0) }
        // category 필터로 걸러진 feature는 그리지 않는다(#52).
        var fc = ctx
        fc.opacity *= env.polygonOpacity(for: type)
        // 레이어 투명도는 이 레이어에 표시된 다각형에 건다(2026-10-18 요청). 작성 중인 점·도면 점은 그대로다.
        for f in all.filter({ !env.isFeatureHighlighted($0.id) }) + all.filter({ env.isFeatureHighlighted($0.id) }) {
            // 강조할 feature를 마지막에 그린다. 겹친 이웃 도형에 가려지면 어디인지 못 찾는다.
            let isHighlighted = env.isFeatureHighlighted(f.id)
            let saved = isHighlighted ? ClosedPolygonAppearance.highlightFill : ClosedPolygonAppearance.savedFill
            let emphasis: CGFloat = isHighlighted ? 2 : 1
            let isTarget = env.multiPolygonTargetID == f.id
            var area = Path()
            for r in f.polygonRings.indices where env.pointDraft.source != PointDraftSource(featureID: f.id, ring: r) {
                let ring = env.previewRing(of: f, ring: r)
                if ring.count >= 3 { area.addLines(ring.map(\.cg)); area.closeSubpath() }
            }
            if !area.isEmpty, area.boundingRect.intersects(visible) {
                fc.fill(area, with: .color(saved.opacity(isHighlighted ? ClosedPolygonAppearance.highlightFillOpacity
                                                                        : ClosedPolygonAppearance.savedFillOpacity)),
                         style: FillStyle(eoFill: true))
                // 링을 한 경로로 짝홀 규칙으로 칠한다. MultiPolygon의 구멍(다른 링 안의 링)이 비어 보인다.
            }
            for r in f.polygonRings.indices where env.pointDraft.source != PointDraftSource(featureID: f.id, ring: r) {
                // 고치는 중인 링은 작성 중 도형으로 그린다. 원래 모양을 겹쳐 그리면 빠진 점이 그대로 보인다.
                let ring = env.previewRing(of: f, ring: r)
                guard ring.count >= 3 else { continue }
                var path = Path(); path.addLines(ring.map(\.cg)); path.closeSubpath()
                guard path.boundingRect.intersects(visible) else { continue }
                fc.stroke(path, with: .color(saved),
                           style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1.5 * emphasis * (isTarget ? 1.5 : 1), at: s),
                                              dash: isTarget ? [6, 3].map { CanvasZoom.screenLength($0, at: s) } : []))
                // 다각형을 받고 있는 MultiPolygon은 점선 테두리로 표시한다.
                if env.isVertexMoveEnabled, f.isPointDrawn {
                    for p in ring {
                        fc.stroke(Path(CGRect(x: p.x - handle, y: p.y - handle, width: handle * 2, height: handle * 2)),
                                   with: .color(saved), lineWidth: CanvasZoom.screenLength(1, at: s))
                    }
                }
            }
            let v = env.previewDrawnVertices(of: f)
            if v.count >= 2 {
                var line = Path(); line.addLines(v.map(\.cg))
                fc.stroke(line, with: .color(saved), lineWidth: CanvasZoom.screenLength(3 * emphasis, at: s))
            }
            for p in v {
                let r = CanvasZoom.screenLength((v.count == 1 ? 5 : 3) * emphasis, at: s)
                fc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(saved))
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

        drawFixtureTwins(in: ctx, scale: s, visible: visible)

        let draft = env.previewDraftPoints
        guard !draft.isEmpty else { return }
        let accent = env.canvasBackground.selection
        let state = env.pointDraft
        let dimmed = 0.25
        for i in 0..<max(0, draft.count - 1) where state.isConnected(i) {
            var line = Path(); line.move(to: draft[i].cg); line.addLine(to: draft[i + 1].cg)
            ctx.stroke(line, with: .color(accent.opacity(state.isDimmed(i + 1) ? dimmed : 1)),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(2, at: s), lineCap: .round))
            // 끊긴 자리(5-7)와 개체 편집 중 새 점 ↔ 흐린 점 사이는 긋지 않는다.
        }
        if state.source != nil, draft.count >= 3 {
            var closing = Path(); closing.move(to: draft.last!.cg); closing.addLine(to: draft[0].cg)
            let open = !state.breaks.isEmpty || state.edit != nil
            ctx.stroke(closing, with: .color(accent.opacity(state.isDimmed(draft.count - 1) ? dimmed : 1)),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(2, at: s), lineCap: .round,
                                          dash: open ? [4, 3].map { CanvasZoom.screenLength($0, at: s) } : []))
            // 저장된 도형은 이미 닫힌 링이다. 마지막 점과 첫 점 사이도 변으로 그린다.
        } else if draft.count >= 3, env.activeGeometryKind.isAreal, env.unitToolInUse == nil,
                  state.breaks.isEmpty, state.edit == nil {
            var closing = Path(); closing.move(to: draft.last!.cg); closing.addLine(to: draft[0].cg)
            ctx.stroke(closing, with: .color(accent.opacity(0.5)),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1, at: s),
                                          dash: [4, 3].map { CanvasZoom.screenLength($0, at: s) }))
            // 닫으면 생길 변을 점선으로 미리 보여준다.
        }
        for (i, p) in draft.enumerated() {
            let r = CanvasZoom.screenLength(i == 0 ? 6 : 4, at: s)
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            let opacity = state.isDimmed(i) ? dimmed : 1
            ctx.fill(dot, with: .color((i == 0 ? env.canvasBackground.fill : accent).opacity(opacity)))
            ctx.stroke(dot, with: .color(accent.opacity(opacity)), lineWidth: CanvasZoom.screenLength(i == 0 ? 2.5 : 1, at: s))
            // 시작점은 속이 빈 큰 원(◎)이다. 다시 누르면 닫힌다는 것을 모양으로 보여준다.
        }
    }

    /// fixture와 똑같이 생긴 자리(보라). 작성 중이면 그 도형을, 아니면 펼친 fixture 카드의 도형을 옮겨 점선으로 긋고
    /// 그 자리의 도면 개체를 굵게 덧그린다. '보조 개체 제외'의 쌍둥이와 같은 색이다.
    private func drawFixtureTwins(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        guard env.layers.activePropertyType == .fixture, let doc = env.document else { return }
        var shapes: [([LocalPoint], Bool)] = []
        var placements = env.draftFixtureTwins
        if !placements.isEmpty {
            shapes = [(env.pointDraft.points, false)]
        } else if env.pointDraft.isEmpty, let id = env.expandedFeature, let f = env.features.feature(id) {
            placements = env.fixtureTwinPlacements(of: f)
            shapes = f.polygonRings.map { ($0, true) }
        }
        guard !placements.isEmpty else { return }
        let twin = env.canvasBackground.twinStroke
        for t in placements {
            guard let o = doc.object(t.objectID) else { continue }
            let cache = env.renderCache.entry(for: o, segmentation: env.segmentation)
            guard cache.box.insetBy(dx: -2, dy: -2).intersects(visible) else { continue }
            ctx.stroke(cache.path, with: .color(twin.opacity(0.9)), lineWidth: CanvasZoom.screenLength(2, at: s))
            for (pts, closed) in shapes where !pts.isEmpty {
                let moved = t.moved(pts)
                var path = Path(); path.addLines(moved.map(\.cg))
                if closed { path.closeSubpath() }
                ctx.stroke(path, with: .color(twin),
                           style: StrokeStyle(lineWidth: CanvasZoom.screenLength(1.5, at: s),
                                              dash: [4, 3].map { CanvasZoom.screenLength($0, at: s) }))
                let r = CanvasZoom.screenLength(2.5, at: s)
                for p in moved {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(twin))
                }
            }
        }
    }

    /// 면 단위에서 **대응하는 면이 없는** 지금 레이어의 저장된 feature를 링 그대로 칠한다.
    /// level 기준은 이미 덮인 곳을 면에서 빼므로 저장된 unit이 면으로 나타나지 않는다. 그대로 두면
    /// 저장한 unit이 화면에서 사라지고, 우측 패널에서 펼쳐도 주황 강조가 보이지 않는다.
    private func drawUnrepresentedSavedFeatures(in ctx: GraphicsContext, faces: [ClosedPolygonFinder.Face],
                                                scale s: CGFloat, visible: CGRect) {
        guard let type = env.layers.activePropertyType else { return }
        let ids = Set(faces.map(\.id))
        let represented = Set(faces.compactMap { env.faceOwner($0) })
        var fc = ctx
        fc.opacity *= env.polygonOpacity(for: type)
        for f in env.features.features(ofType: type) where !f.polygonRings.isEmpty && !represented.contains(f.id)
            && f.polygonFaceIDs.isDisjoint(with: ids) && env.passesCategoryFilter(f) {
            var area = Path()
            for ring in f.polygonRings where ring.count >= 3 { area.addLines(ring.map(\.cg)); area.closeSubpath() }
            guard area.boundingRect.intersects(visible) else { continue }
            let isHighlighted = env.isFeatureHighlighted(f.id)
            let color = isHighlighted ? ClosedPolygonAppearance.highlightFill : ClosedPolygonAppearance.savedFill
            fc.fill(area, with: .color(color.opacity(isHighlighted ? ClosedPolygonAppearance.highlightFillOpacity
                                                                   : ClosedPolygonAppearance.savedFillOpacity)),
                    style: FillStyle(eoFill: true))
            fc.stroke(area, with: .color(color), lineWidth: CanvasZoom.screenLength(isHighlighted ? 2 : 1, at: s))
        }
    }

    /// unit의 보조 선분. 내보내지 않는 선이라 도면 선·저장한 도형과 다른 청록 점선으로 긋는다.
    private func drawGuides(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        let guides = env.features.guides
        guard !guides.isEmpty else { return }
        let r = CanvasZoom.screenLength(2.5, at: s)
        for g in guides {
            let box = CGRect(x: min(g.start.x, g.end.x), y: min(g.start.y, g.end.y),
                             width: abs(g.end.x - g.start.x), height: abs(g.end.y - g.start.y))
            guard box.insetBy(dx: -r, dy: -r).intersects(visible) else { continue }
            var line = Path(); line.move(to: g.start.cg); line.addLine(to: g.end.cg)
            ctx.stroke(line, with: .color(.teal),
                       style: StrokeStyle(lineWidth: CanvasZoom.screenLength(2, at: s), lineCap: .round,
                                          dash: [6, 3].map { CanvasZoom.screenLength($0, at: s) }))
            for p in [g.start, g.end] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.teal))
            }
        }
    }

    /// 펼친 unit과 겹치는 다른 unit을 빨간색으로 덧그린다(점·면 단위 모두). 펼친 unit 자신은 종전대로 주황이다.
    private func drawExpandedUnitOverlaps(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        let overlapping = env.unitsOverlappingExpanded
        guard !overlapping.isEmpty else { return }
        for id in overlapping {
            guard let f = env.features.feature(id) else { continue }
            var area = Path()
            for ring in f.polygonRings where ring.count >= 3 { area.addLines(ring.map(\.cg)); area.closeSubpath() }
            guard area.boundingRect.intersects(visible) else { continue }
            ctx.fill(area, with: .color(Color.red.opacity(0.22)), style: FillStyle(eoFill: true))
            ctx.stroke(area, with: .color(.red), lineWidth: CanvasZoom.screenLength(2, at: s))
        }
    }

    /// unit 사이 빈틈은 빨간 점무늬, 겹침은 빨간 빗금으로 칠한다. 무늬 간격·선 굵기는 화면 기준이라 확대와 무관하다.
    /// 0.03 폭의 틈처럼 무늬가 들어가지 않을 만큼 얇은 곳도 보이도록 테두리를 함께 긋는다.
    private func drawUnitCoverage(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        let coverage = env.unitCoverage
        let spacing = CanvasZoom.screenLength(7, at: s)
        for (paths, dotted) in [(coverage.gaps, true), (coverage.overlaps, false)] {
            let red = dotted ? UnitCoverage.gapColor : UnitCoverage.overlapColor
            // 이름은 예전 그대로지만 빈틈은 노랑, 겹침은 빨강이다(2026-10-18 요청).
            for cg in paths {
                let box = cg.boundingBoxOfPath
                guard box.insetBy(dx: -spacing, dy: -spacing).intersects(visible) else { continue }
                let shape = Path(cg)
                ctx.fill(shape, with: .color(red.opacity(0.12)), style: FillStyle(eoFill: true))
                var clipped = ctx
                clipped.clip(to: shape, style: FillStyle(eoFill: true))
                let area = box.intersection(visible.insetBy(dx: -spacing, dy: -spacing))
                if dotted {
                    let r = CanvasZoom.screenLength(1.4, at: s)
                    var dots = Path()
                    var y = (area.minY / spacing).rounded(.down) * spacing
                    while y <= area.maxY {
                        var x = (area.minX / spacing).rounded(.down) * spacing
                        while x <= area.maxX {
                            dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                            x += spacing
                        }
                        y += spacing
                    }
                    clipped.fill(dots, with: .color(red))
                } else {
                    var hatch = Path()
                    var c = ((area.minX - area.maxY) / spacing).rounded(.down) * spacing
                    while c <= area.maxX - area.minY {
                        hatch.move(to: CGPoint(x: c + area.minY, y: area.minY))
                        hatch.addLine(to: CGPoint(x: c + area.maxY, y: area.maxY))
                        c += spacing
                    }
                    // x - y = c 인 45° 선을 같은 간격으로 긋는다.
                    clipped.stroke(hatch, with: .color(red), lineWidth: CanvasZoom.screenLength(1, at: s))
                }
                ctx.stroke(shape, with: .color(red), lineWidth: CanvasZoom.screenLength(1.5, at: s))
            }
        }
    }

    /// 빈틈·겹침 조각의 이름표. 조각 상자의 왼쪽 위(화면 기준)에 그 색 바탕으로 단다.
    /// 화면 좌표로 그려 확대와 무관하게 글자 크기가 같다. 넓이 0.03짜리 틈도 이름표로 찾을 수 있다.
    private func drawUnitCoverageLabels(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        for label in env.unitCoverageLabels {
            let b = label.path.boundingBoxOfPath
            guard b.insetBy(dx: -2, dy: -2).intersects(visible) else { continue }
            let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)].map { docToScreen($0, scale: s) }
            let minX = corners.map(\.x).min()!, minY = corners.map(\.y).min()!
            let text = ctx.resolve(Text(label.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(label.isGap ? Color.black : Color.white))
            let size = text.measure(in: CGSize(width: 400, height: 30))
            let tag = CGRect(x: minX - 2, y: minY + 3, width: size.width + 8, height: size.height + 3)
            // 조각 상자 위쪽 안에 단다. feature 이름표는 상자 바로 위에 붙으므로 위에 달면 같은 자리에 겹친다 —
            // 안쪽 unit을 통째로 품은 겹침이면 조각 상자가 그 unit 상자와 같아 빨간 이름표를 완전히 덮었다.
            let color = label.isGap ? UnitCoverage.gapColor : UnitCoverage.overlapColor
            ctx.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(color.opacity(0.92)))
            ctx.draw(text, at: CGPoint(x: tag.minX + 4, y: tag.minY + 1.5), anchor: .topLeading)
        }
    }

    /// 우측 패널에서 펼친(고른) 지금 레이어의 feature. 저장된 도형을 고치는 중이면 그 feature는 작성 중 도형이 대신 보여 준다.
    private var selectedShapes: [(FeatureGroup, rings: [[LocalPoint]])] {
        guard let type = env.layers.activePropertyType else { return [] }
        return env.features.features(ofType: type)
            .filter { env.isFeatureExpanded($0.id) && env.pointDraft.source?.featureID != $0.id }
            .map { f in (f, f.polygonRings.isEmpty ? (f.drawnVertices.map { [$0] } ?? []) : f.polygonRings) }
    }

    /// 고른 feature의 꼭짓점을 파란 점으로 찍는다. 첫 점은 속이 빈 큰 원이다(작성 중 도형의 시작점과 같은 모양).
    private func drawSelectedVertexDots(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        let blue = env.canvasBackground.selection
        for (_, rings) in selectedShapes {
            for ring in rings {
                for (i, p) in ring.enumerated() where visible.insetBy(dx: -10, dy: -10).contains(p.cg) {
                    let r = CanvasZoom.screenLength(i == 0 ? 5 : 3, at: s)
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(i == 0 ? env.canvasBackground.fill : blue))
                    ctx.stroke(dot, with: .color(blue), lineWidth: CanvasZoom.screenLength(i == 0 ? 2 : 1, at: s))
                }
            }
        }
    }

    /// 고른 feature의 꼭짓점 순번(파랑, 2026-10-18 요청). 링이 여럿이면 `링번호·순번`이다(예: 2·5 = 둘째 링의 5번 점).
    /// 화면에 보이는 점만 단다. 확대하지 않은 채 수백 개를 달면 서로 덮여 읽을 수 없으므로 600개까지만 단다.
    private func drawSelectedOrderLabels(in ctx: GraphicsContext, scale s: CGFloat, visible: CGRect) {
        let blue = env.canvasBackground.selection
        var budget = 600
        for (_, rings) in selectedShapes {
            for (r, ring) in rings.enumerated() {
                for (i, p) in ring.enumerated() where visible.contains(p.cg) {
                    guard budget > 0 else { return }
                    budget -= 1
                    let center = docToScreen(p.cg, scale: s)
                    let text = ctx.resolve(Text(rings.count > 1 ? "\(r + 1)·\(i + 1)" : "\(i + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white))
                    let size = text.measure(in: CGSize(width: 60, height: 20))
                    let tag = CGRect(x: center.x + 7, y: center.y - size.height - 7,
                                     width: max(size.width + 6, size.height + 2), height: size.height + 2)
                    ctx.fill(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(blue.opacity(0.9)))
                    ctx.draw(text, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
                }
            }
        }
    }

    /// 작성 중인 도형의 점마다 찍은 순번(1, 2, 3 …)을 단다(엔진 디버깅 5-1, 모든 레이어).
    /// 화면 좌표로 그려 확대와 무관하게 글자 크기가 같다. 흐린 점은 순번도 흐리다.
    private func drawDraftOrderLabels(in ctx: GraphicsContext, scale s: CGFloat) {
        let draft = env.previewDraftPoints
        let state = env.pointDraft
        let accent = env.canvasBackground.selection
        for (i, p) in draft.enumerated() {
            let center = docToScreen(p.cg, scale: s)
            let text = ctx.resolve(Text("\(i + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white))
            let size = text.measure(in: CGSize(width: 60, height: 20))
            let tag = CGRect(x: center.x + 7, y: center.y - size.height - 7,
                             width: max(size.width + 6, size.height + 2), height: size.height + 2)
            // 점 오른쪽 위에 붙인다. 점 위에 얹으면 점을 다시 누를 자리를 가린다.
            let opacity = state.isDimmed(i) ? 0.3 : 0.9
            ctx.fill(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(accent.opacity(opacity)))
            ctx.draw(text, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
        }
    }

    /// 지금 레이어에서 태깅한 feature마다 왼쪽 위에 우측 사이드바의 표시명(일련번호)을 단다.
    /// 지울 것을 찾으려고 사이드바 카드를 하나하나 펼쳐 보지 않아도 되게 하려는 것이다.
    /// 화면 좌표로 그려 확대와 무관하게 글자 크기가 같다. 강조 중인 것은 강조색 바탕이다.
    private func drawFeatureLabels(in ctx: GraphicsContext, document doc: DrawingDocument,
                                   scale s: CGFloat, viewport: CGSize) {
        labelHitBoxes.boxes = []
        guard let type = env.layers.activePropertyType else { return }
        let screen = CGRect(origin: .zero, size: viewport)
        let overlapping = env.unitsOverlappingExpanded
        for f in env.features.features(ofType: type) where env.passesCategoryFilter(f) {
            // 걸러진 feature는 이름표도 달지 않는다(#52). 이름표를 누르는 동작도 함께 빠진다.
            var points = f.polygonRings.flatMap { $0 }.map(\.cg) + (f.drawnVertices ?? []).map(\.cg)
            if let c = f.closureSegment { points += [c.start.cg, c.end.cg] }
            for id in f.memberIDs {
                guard let o = doc.object(id) else { continue }
                let b = env.renderCache.entry(for: o, segmentation: env.segmentation).box
                points += [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
            }
            let onScreen = points.map { docToScreen($0, scale: s) }
            guard let minX = onScreen.map(\.x).min(), let minY = onScreen.map(\.y).min(),
                  let maxX = onScreen.map(\.x).max(), let maxY = onScreen.map(\.y).max(),
                  CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    .insetBy(dx: -40, dy: -20).intersects(screen) else { continue }
            // 회전한 도면에서도 화면 기준 왼쪽 위에 단다. 도면 기준으로 달면 회전 따라 이름표가 돌아간다.

            let text = ctx.resolve(Text(f.serialNumber)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white))
            let size = text.measure(in: CGSize(width: 300, height: 30))
            let tag = CGRect(x: minX - 2, y: minY - size.height - 5, width: size.width + 8, height: size.height + 3)
            // 도형 바로 위에 붙인다. 안쪽에 두면 작은 방·문 선을 이름표가 덮는다.
            let category = AppEnvironment.categoryValue(of: f)
            let color = env.isFeatureHighlighted(f.id) ? ClosedPolygonAppearance.highlightFill
                : overlapping.contains(f.id) ? Color.red
                : category.isEmpty ? ClosedPolygonAppearance.savedFill : ClosedPolygonAppearance.categorizedLabelFill
            // 펼친 unit과 겹치는 unit의 이름표는 빨강이다. 펼친 unit이 MultiPolygon이면 눌러서 그 모양대로 구멍을 뚫는다.
            // category를 정한 것은 진한 초록이다.
            ctx.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(color.opacity(0.9)))
            ctx.draw(text, at: CGPoint(x: tag.minX + 4, y: tag.minY + 1.5), anchor: .topLeading)
            let captionText = [category.isEmpty ? "" : CategoryLabel.display(category, type: f.featureType),
                           AppEnvironment.nameText(of: f)].filter { !$0.isEmpty }.joined(separator: " · ")
            // name을 정한 것은 name도 함께 단다(2026-10-19 요청). 예: `화장실(restroom) · 남자 화장실(Men)`.
            if !captionText.isEmpty {
                let caption = ctx.resolve(Text(captionText)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(ClosedPolygonAppearance.categorizedLabelFill))
                let captionSize = caption.measure(in: CGSize(width: 300, height: 20))
                let box = CGRect(x: tag.minX, y: tag.minY - captionSize.height - 2,
                                 width: captionSize.width + 6, height: captionSize.height + 1)
                ctx.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(.white.opacity(0.8)))
                ctx.draw(caption, at: CGPoint(x: box.minX + 3, y: box.minY + 0.5), anchor: .topLeading)
                // 이름표 바로 위에 작은 글씨로 단다. 흰 바탕을 깔아 도면 선 위에서도 읽힌다. 누르는 자리는 이름표 그대로다.
            }
            labelHitBoxes.boxes.append((f.id, tag))
            // 태그 자리를 기억해 둔다. 마우스가 그 위에 오면 이 feature를 주황색으로 강조한다.
        }
    }

    /// 도면 좌표 → 화면 좌표. 그리기 변환(이동 → 확대 → 도면 중심 회전)과 같은 순서다.
    private func docToScreen(_ p: CGPoint, scale s: CGFloat) -> CGPoint {
        var q = p
        if env.canvasRotation != 0 {
            let c = docCenter, r = env.rotationDegrees * .pi / 180
            let dx = p.x - c.x, dy = p.y - c.y
            q = CGPoint(x: c.x + dx * cos(r) - dy * sin(r), y: c.y + dx * sin(r) + dy * cos(r))
        }
        return CGPoint(x: q.x * s + offset.width, y: q.y * s + offset.height)
    }

    /// `tagEditorRequest`를 받아 이름표를 누른 것과 같은 편집 창을 연다.
    /// 이름표가 아직 안 그려졌으면 그 feature의 점 바로 위에 띄운다.
    private func openRequestedTagEditor(_ id: FeatureGroupID, scale s: CGFloat) {
        defer { if env.tagEditorRequest == id { env.tagEditorRequest = nil } }
        guard let f = env.features.feature(id), !FeatureTagEditor.fields(for: f.featureType).isEmpty else { return }
        if let hit = labelHitBoxes.boxes.last(where: { $0.0 == id }) {
            tagEditor = (id, hit.1)
        } else if let p = f.drawnVertices?.first {
            let q = docToScreen(p.cg, scale: s)
            tagEditor = (id, CGRect(x: q.x - 2, y: q.y - 20, width: 60, height: 15))
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
                    let onTag = labelHitBoxes.boxes.contains { $0.1.contains(value.startLocation) }
                    // 이름표는 도형 왼쪽 위 꼭짓점 바로 위에 붙는다. 꼭짓점 끌기를 먼저 잡으면 이름표를 누를 수 없다.
                    if env.isPointWorkMode, env.isVertexMoveEnabled, !NSEvent.modifierFlags.contains(.control), !onTag,
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
                                             freePoint: NSEvent.modifierFlags.contains(.option),
                                             editing: NSEvent.modifierFlags.contains(.control),
                                             removing: NSEvent.modifierFlags.contains(.shift))
                        // 꼭짓점 위를 끌지 않고 눌렀으면 클릭이다(시작점으로 닫기·점 지우기).
                    }
                } else if let m = marquee, moved >= MarqueeRect.dragThreshold {
                    selectByMarquee(m)
                } else if moveBase == nil, moved < MarqueeRect.dragThreshold {
                    if let hit = labelHitBoxes.boxes.last(where: { $0.1.contains(value.location) }),
                       env.handleFeatureTagClick(hit.0) {
                        let tag = hit.0
                        if env.expandedFeatures.contains(tag),
                           let f = env.features.feature(tag), !FeatureTagEditor.fields(for: f.featureType).isEmpty {
                            tagEditor = (tag, hit.1)
                        } else { tagEditor = nil }
                        // 골라졌으면 category·name 편집 창을 그 이름표에 띄운다. 다시 눌러 접었거나 구멍을 뚫었으면 닫는다.
                        // 이름표를 누르면 그 feature를 고른다. 빨간(겹친) unit의 이름표는 구멍을 뚫는다.
                        // 어느 쪽이든 점을 찍거나 면을 고르지 않는다.
                    } else if env.isPolygonWorkMode {
                        env.handleFaceClick(at: toLocal(value.location))
                        // 폴리곤 type에서는 클릭이 개체가 아니라 **면**을 고른다(신기능 5-4).
                    } else if env.isPointWorkMode, !env.mode.blocksSelection {
                        env.handlePointClick(at: toLocal(value.location), tolerance: 6 / Double(effectiveScale),
                                             freePoint: NSEvent.modifierFlags.contains(.option),
                                             editing: NSEvent.modifierFlags.contains(.control),
                                             removing: NSEvent.modifierFlags.contains(.shift))
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
            Button(".imdfrnt 불러오기…") { env.openProject() }
                .buttonStyle(.bordered)
                .disabled(env.isProjectBusy)
                .help(env.importsProjectIntoActiveLevel
                      ? "다른 .imdfrnt의 층 하나를 이 빈 층에 넣습니다. 지금 프로젝트는 그대로입니다."
                      : "자동 저장된 프로젝트의 도면·층·노드·연결을 불러옵니다. (⌘⇧O)")
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

/// 캔버스에 그린 일련번호 태그의 화면 위치. 그릴 때마다 채우고, 마우스오버 판정이 읽는다.
/// 그리기 중에 값을 바꿔도 화면을 다시 그리지 않도록 관찰 대상이 아닌 참조 타입으로 둔다.
final class FeatureLabelHitBoxes {
    var boxes: [(FeatureGroupID, CGRect)] = []
}
