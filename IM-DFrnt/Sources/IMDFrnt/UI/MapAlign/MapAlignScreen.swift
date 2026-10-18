import CoreLocation
import MapKit
import SwiftUI

/// 지도 정렬 화면(신기능 11항, #31).
///
/// 위성사진(또는 일반 지도) 위에 층 도면을 올려 **이동·회전·크기(비율 고정)·투명도**로 맞춘다.
/// 맞춘 뒤에는 같은 화면에서 (가) 정렬된 도면의 꼭짓점·교점을 찍어 지오레퍼런싱 Anchor 쌍을 만들고,
/// (나) 그중 고른 점을 IMDF anchor feature로 지정한다. 기존 Anchor 화면(1:1 찍기)은 그대로 둔다.
struct MapAlignScreen: View {
    @EnvironmentObject var env: AppEnvironment

    enum Mode: String, CaseIterable {
        case align, anchor
        var title: String { self == .align ? "도면 정렬" : "Anchor 찍기" }
    }

    enum MapKind: String, CaseIterable {
        case standard, imagery, hybrid
        var title: String {
            switch self {
            case .standard: return "일반 지도"
            case .imagery: return "위성"
            case .hybrid: return "위성+이름"
            }
        }
        var mapType: MKMapType {
            switch self {
            case .standard: return .standard
            case .imagery: return .satellite
            case .hybrid: return .hybrid
            }
        }
    }

    /// 끌고 있는 것. 시작할 때 정하고 놓을 때까지 유지한다.
    enum DragKind { case move, scale, rotate, pan }

    @State private var mode: Mode = .align
    @State private var mapKind: MapKind = .imagery
    @StateObject private var map = MapAlignMapController()
    @State private var didPinCamera = false
    @State private var preview: MapAlignment?
    @State private var dragKind: DragKind?
    @State private var dragStart: MapAlignment?
    @State private var panStartCenter: CLLocationCoordinate2D?
    // 도면 위에서 지도를 끌 때(⌥ 끌기·Anchor 모드·잠긴 층) 시작한 순간의 지도 중심.
    @State private var selectedAnchor: AnchorID?
    /// 투명도 슬라이더를 끄는 동안의 값. 놓을 때 한 번만 저장한다 — 값마다 저장하면 실행취소 스냅샷과
    /// 지도 오버레이 교체가 1초에 수십 번 일어나 앱이 멈춘다.
    @State private var opacityDraft: (levelID: UUID, value: Double)?
    @State private var isEditingOpacity = false
    @StateObject private var placeSearch = PlaceSearchModel()
    @FocusState private var searchFocused: Bool

    private var editingID: UUID? { env.routingFloorID }
    private var editingLevel: ProjectLevel? { env.buildingProject.levels.first { $0.id == editingID } }
    private var editingAlignment: MapAlignment? { preview ?? editingID.flatMap { env.mapAlignment(of: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                mapPane
                if mode == .anchor {
                    Divider()
                    anchorPanel.frame(width: 300)
                }
            }
            Divider()
            levelPanel
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { DispatchQueue.main.async { pinCameraIfNeeded() } }
        // 지도 뷰가 만들어진 다음 차례에 화면을 잡는다. 같은 차례에는 아직 지도가 없다.
        .onChange(of: env.document?.fingerprint) { _, _ in placeEditingLevelIfStacked() }
    }

    // MARK: 상단 바

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { env.exitMapAlignScreen() } label: { Label("돌아가기", systemImage: "chevron.left") }
                .keyboardShortcut(.escape, modifiers: [])
            VStack(alignment: .leading, spacing: 1) {
                Text("지도 정렬").font(.headline).fixedSize()
                Text("도면을 지도 위에 직접 맞추고, 맞춘 도면에서 Anchor를 찍습니다")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 8)
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("도면 정렬: 도면을 끌어 옮기고, 모서리로 크기, 위 손잡이로 회전합니다. ⌥를 누른 채 끌면 도면 위에서도 지도를 옮깁니다. Anchor 찍기: 정렬된 도면의 꼭짓점·교점을 눌러 Anchor 쌍을 만들고, 끌면 지도를 옮깁니다.")
            Picker("", selection: $mapKind) {
                ForEach(MapKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            searchBar.frame(maxWidth: 300)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
            TextField("장소 검색", text: $placeSearch.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { placeSearch.search(around: map.region) }
            if placeSearch.isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: 지도

    private var mapPane: some View {
        AlignMapView(controller: map, mapType: mapKind.mapType, layers: overlayLayers)
            .overlay { previewCanvas.allowsHitTesting(false) }
            .overlay { interactionLayer }
            .overlay(alignment: .top) {
                if placeSearch.isShowingResults { searchResults }
            }
            .overlay(alignment: .center) { placeHint }
    }

    /// 지도에 얹을 겹들(아래 → 위). 편집 중인 층은 도면 선 위에 테두리·손잡이·Anchor 겹을 하나 더 얹는다.
    /// **끄는 동안에는 편집 중인 층을 지도에서 빼고 미리보기로 그린다** — 지도는 그동안 멈춰 있어 흔들릴 일이 없고,
    /// 프레임마다 지도 오버레이를 갈아 끼우는 것보다 가볍다.
    private var overlayLayers: [AlignOverlay] {
        var out: [AlignOverlay] = []
        for level in env.mapAlignStack {
            guard let a = level.info.mapAlignment, a.isVisible,
                  let drawing = env.mapAlignDrawing(for: level) else { continue }
            let isEditing = level.id == editingID
            if isEditing && preview != nil { continue }
            var shape = a
            shape.opacity = 1
            // 투명도는 모양 비교에서 뺀다. 넣으면 투명도만 바뀌어도 오버레이를 통째로 다시 그린다.
            out.append(AlignOverlay(signature: .init(levelID: level.id, kind: .drawing, alignment: shape,
                                                     pathKey: drawing.key, isStandardMap: mapKind == .standard,
                                                     showHandles: false, anchors: [], snapKey: 0),
                                    path: drawing.path.cgPath, canvasSize: drawing.canvasSize,
                                    snaps: nil, opacity: opacity(of: level.id, saved: a)))
            guard isEditing else { continue }
            let pairMarks = mode == .anchor ? env.anchors.pairs.map {
                AlignOverlay.AnchorMark(point: $0.local, isFeature: env.imdfAnchorFeature(for: $0) != nil,
                                        isSelected: $0.id == selectedAnchor, isPaired: true)
            } : []
            let layerMarks = env.anchorLayerPoints
                .filter { mode != .anchor || env.anchorPair(at: $0.point) == nil }
                .map { AlignOverlay.AnchorMark(point: $0.point, isFeature: true, isSelected: false, isPaired: false) }
            // anchor 레이어에 저장된 점은 두 모드 모두 보인다. 정렬할 때도 맞출 기준점이 되기 때문이다.
            // Anchor 찍기 모드에서 이미 쌍이 된 점은 쌍 표시로 그리므로 겹쳐 그리지 않는다.
            let marks = layerMarks + pairMarks
            out.append(AlignOverlay(signature: .init(levelID: level.id, kind: .decoration, alignment: shape,
                                                     pathKey: drawing.key, isStandardMap: mapKind == .standard,
                                                     showHandles: mode == .align && !a.isLocked, anchors: marks,
                                                     snapKey: mode == .anchor ? env.snapPoints.count : -1),
                                    path: CGMutablePath(), canvasSize: drawing.canvasSize,
                                    snaps: mode == .anchor ? env.snapPointIndex : nil, opacity: 1))
        }
        return out
    }

    /// 지금 보여 줄 투명도. 슬라이더를 끄는 중이면 아직 저장하지 않은 값이다.
    private func opacity(of levelID: UUID, saved: MapAlignment) -> Double {
        opacityDraft.flatMap { $0.levelID == levelID ? $0.value : nil } ?? saved.opacity
    }

    private func commitOpacityDraft() {
        guard let draft = opacityDraft else { return }
        opacityDraft = nil
        env.updateMapAlignment(draft.levelID, name: "층 투명도") { $0.opacity = draft.value }
    }

    /// 도면 좌표 → 화면 좌표. 건물 하나 범위에서 지도는 사실상 평면이라 세 점으로 어파인 변환을 만든다.
    private func screenTransform(_ a: MapAlignment) -> CGAffineTransform? {
        let c = a.canvasCenter
        let k = 100.0
        guard let p0 = map.screenPoint(a.geoPoint(for: c)),
              let px = map.screenPoint(a.geoPoint(for: LocalPoint(c.x + k, c.y))),
              let py = map.screenPoint(a.geoPoint(for: LocalPoint(c.x, c.y + k)))
        else { return nil }
        let ax = (px.x - p0.x) / k, bx = (px.y - p0.y) / k
        let cy = (py.x - p0.x) / k, dy = (py.y - p0.y) / k
        return CGAffineTransform(a: ax, b: bx, c: cy, d: dy,
                                 tx: p0.x - ax * c.x - cy * c.y,
                                 ty: p0.y - bx * c.x - dy * c.y)
    }

    private func frameCorners(size: CGSize, t: CGAffineTransform) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
         CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)].map { $0.applying(t) }
    }

    /// 끄는 동안의 미리보기. 지도가 멈춰 있는 동안만 그린다.
    private var previewCanvas: some View {
        Canvas { ctx, _ in
            guard let p = preview, let level = editingLevel,
                  let drawing = env.mapAlignDrawing(for: level), let t = screenTransform(p) else { return }
            var layer = ctx
            layer.opacity = p.opacity
            layer.stroke(drawing.path.applying(t), with: .color(mapKind == .standard ? .black : .white), lineWidth: 0.8)
            let corners = frameCorners(size: drawing.canvasSize, t: t)
            var frame = Path(); frame.addLines(corners); frame.closeSubpath()
            ctx.stroke(frame, with: .color(.blue), lineWidth: 2)
        }
    }

    /// 손 동작을 받는 층. **도면 위에서만** 받는다 — 바깥은 지도가 그대로 끌리고 확대된다.
    /// 도면 위의 스크롤·핀치는 `MapAlignMapController`가 지도로 넘기고, ⌥ 끌기는 지도를 옮긴다.
    @ViewBuilder
    private var interactionLayer: some View {
        let _ = map.tick
        if let level = editingLevel, let a = editingAlignment, a.isVisible,
           let drawing = env.mapAlignDrawing(for: level), let t = screenTransform(a) {
            let corners = frameCorners(size: drawing.canvasSize, t: t)
            let shape = hitShape(corners: corners, includeHandles: mode == .align && !a.isLocked)
            GeometryReader { geo in
                Color.white.opacity(0.001)
                    .contentShape(shape.intersection(Path(CGRect(origin: .zero, size: geo.size))))
                    // 받는 자리를 지도 화면 안으로 자른다. 도면이 화면보다 크면 테두리가 지도 밖까지 나가는데,
                    // SwiftUI는 뷰 밖이라도 모양 안이면 클릭을 받아 상단 바(돌아가기·지도 종류)가 눌리지 않았다(2026-10-18).
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in dragChanged(value, level: level, corners: corners, canvasSize: drawing.canvasSize) }
                        .onEnded { value in dragEnded(value, level: level, t: t) })
            }
        }
    }

    private func hitShape(corners: [CGPoint], includeHandles: Bool) -> Path {
        var p = Path(); p.addLines(corners); p.closeSubpath()
        if includeHandles {
            for c in corners { p.addEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)) }
            let h = AlignHandles.rotate(corners: corners, outward: 28)
            p.addEllipse(in: CGRect(x: h.knob.x - 12, y: h.knob.y - 12, width: 24, height: 24))
        }
        return p
    }

    private func dragChanged(_ value: DragGesture.Value, level: ProjectLevel, corners: [CGPoint], canvasSize: CGSize) {
        if dragKind == nil, NSEvent.modifierFlags.contains(.option) || mode == .anchor
            || env.mapAlignment(of: level.id)?.isLocked == true {
            dragKind = .pan
            panStartCenter = map.region?.center
        }
        // 도면이 화면을 덮으면 지도를 끌 자리가 없다. ⌥ 끌기, Anchor 찍기 모드, 잠긴 층에서는 도면 위에서도 지도를 끈다.
        if dragKind == .pan {
            if let start = panStartCenter { map.pan(from: start, by: value.translation) }
            return
        }
        guard mode == .align, let saved = env.mapAlignment(of: level.id), !saved.isLocked else { return }
        if dragKind == nil {
            let s = value.startLocation
            let h = AlignHandles.rotate(corners: corners, outward: 28)
            if hypot(s.x - h.knob.x, s.y - h.knob.y) <= 14 { dragKind = .rotate }
            else if corners.contains(where: { hypot(s.x - $0.x, s.y - $0.y) <= 12 }) { dragKind = .scale }
            else { dragKind = .move }
            dragStart = saved
        }
        guard let start = dragStart else { return }
        var next = start
        switch dragKind {
        case .move:
            // 기준은 시작할 때의 화면 중심이다. 끄는 동안 미리보기가 바뀌어도 기준은 움직이지 않는다.
            guard let startCenter = map.screenPoint(start.center),
                  let c = map.coordinate(CGPoint(x: startCenter.x + value.translation.width,
                                                 y: startCenter.y + value.translation.height)) else { return }
            next.center = c
        case .scale:
            guard let sc = map.screenPoint(start.center) else { return }
            let d0 = hypot(value.startLocation.x - sc.x, value.startLocation.y - sc.y)
            let d1 = hypot(value.location.x - sc.x, value.location.y - sc.y)
            guard d0 > 1 else { return }
            next.metersPerUnit = MapAlignment.clampedMetersPerUnit(start.metersPerUnit * Double(d1 / d0),
                                                                   canvasSize: canvasSize)
            // 모서리를 끌어도 가로·세로 비율은 그대로다(닮음 변환만, 사용자 결정).
        case .rotate:
            guard let sc = map.screenPoint(start.center) else { return }
            let a0 = atan2(value.startLocation.y - sc.y, value.startLocation.x - sc.x)
            let a1 = atan2(value.location.y - sc.y, value.location.x - sc.x)
            var deg = start.rotationDegrees + Double(a1 - a0) * 180 / .pi
            if NSEvent.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
            // shift를 누르면 15° 단위로 돌린다.
            next.rotationDegrees = deg.truncatingRemainder(dividingBy: 360)
        case .pan, .none:
            return
        }
        preview = next
    }

    private func dragEnded(_ value: DragGesture.Value, level: ProjectLevel, t: CGAffineTransform) {
        defer { dragKind = nil; dragStart = nil; panStartCenter = nil }
        let moved = abs(value.translation.width) + abs(value.translation.height)
        if dragKind == .pan, moved >= 4 { return }
        // 지도를 끈 것이면 Anchor를 찍거나 도면을 옮기지 않는다. 끌지 않고 누른 것은 아래 클릭으로 처리한다.
        if mode == .anchor {
            guard moved < 4 else { return }
            pickAnchor(at: value.location, t: t)
            return
        }
        if let p = preview {
            env.commitMapAlignment(level.id, p, name: dragKind == .rotate ? "도면 회전" : dragKind == .scale ? "도면 크기" : "도면 이동")
        }
        preview = nil
    }

    /// (가) 누른 자리에서 가장 가까운 꼭짓점·교점을 Anchor로 만든다. 이미 찍은 Anchor를 누르면 목록에서 고른다.
    private func pickAnchor(at screen: CGPoint, t: CGAffineTransform) {
        let local = screen.applying(t.inverted())
        let scale = sqrt(abs(t.a * t.d - t.b * t.c))
        let radius = Double(12 / max(scale, 1e-9))
        let p = LocalPoint(Double(local.x), Double(local.y))
        if let hit = env.anchors.pairs.first(where: { $0.local.distance(to: p) <= radius }) {
            selectedAnchor = hit.id
            return
        }
        if let layer = env.anchorLayerPoint(near: p, within: radius) {
            selectedAnchor = env.importAnchorLayerPoints([layer.feature.id]).first?.id
            return
            // anchor 레이어 점은 꼭짓점·교점보다 먼저 잡는다. 사용자가 이미 고른 자리라 그대로 쓴다.
        }
        guard let snap = env.snapPointIndex.nearest(to: p, within: radius) else {
            env.notify(env.isComputingDerivedGeometry
                       ? "꼭짓점·교점을 계산하는 중입니다. 잠시 후 다시 누르세요."
                       : "꼭짓점·교점 근처를 누르세요. 지도를 확대하면 노란 점이 보입니다.")
            return
        }
        selectedAnchor = env.addAlignmentAnchor(at: snap.point)?.id
    }

    @ViewBuilder
    private var placeHint: some View {
        if let level = editingLevel, level.info.mapAlignment == nil {
            VStack(spacing: 8) {
                Text("\(level.info.name) 도면이 아직 지도에 없습니다").font(.headline)
                Text("장소를 검색해 건물 근처로 지도를 옮긴 뒤 올리세요.").font(.caption).foregroundStyle(.secondary)
                Button("이 층을 지도 가운데에 올리기") { placeEditingLevel() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlaceHere || env.document == nil)
                if let tooWide = tooWideHint { Text(tooWide).font(.caption).foregroundStyle(.orange) }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// 지금 지도에 보이는 가로 폭(m).
    private var visibleWidthMeters: Double? {
        map.region.map { $0.span.longitudeDelta * MapAlignment.metersPerDegreeLatitude * cos($0.center.latitude * .pi / 180) }
    }

    /// 지금 화면에서 도면을 올리거나 가져올 수 있는가. 전국 보기처럼 너무 넓으면 막는다.
    private var canPlaceHere: Bool {
        guard let w = visibleWidthMeters else { return false }
        return w <= AppEnvironment.maxPlacingWidthMeters
    }

    private var tooWideHint: String? {
        guard let w = visibleWidthMeters, w > AppEnvironment.maxPlacingWidthMeters else { return nil }
        return String(format: "지도가 너무 넓습니다(가로 %.0fkm). 건물이 보이도록 %.0fkm 이하로 확대하세요.",
                      w / 1000, AppEnvironment.maxPlacingWidthMeters / 1000)
    }

    private func placeEditingLevel() {
        guard let id = editingID, let doc = env.document, let region = map.region,
              let widthMeters = visibleWidthMeters, canPlaceHere else { return }
        env.placeOnMapIfNeeded(id, canvasSize: doc.canvasSize,
                               mapCenter: GeoPoint(longitude: region.center.longitude, latitude: region.center.latitude),
                               visibleWidthMeters: widthMeters)
    }

    /// 이미 올린 층을 지금 지도 가운데로 가져온다. 엉뚱한 곳에 올라가 화면에서 찾을 수 없을 때 쓴다.
    private func bringLevelToMapCenter(_ level: ProjectLevel) {
        guard let region = map.region, let widthMeters = visibleWidthMeters, canPlaceHere,
              let size = env.mapAlignDrawing(for: level)?.canvasSize else { return }
        env.bringToMapCenter(level.id, canvasSize: size,
                             mapCenter: GeoPoint(longitude: region.center.longitude, latitude: region.center.latitude),
                             visibleWidthMeters: widthMeters)
    }

    /// 아래층이 이미 정렬돼 있으면 위층은 그 자리에 바로 올린다(11항 2번).
    private func placeEditingLevelIfStacked() {
        guard let level = editingLevel, level.info.mapAlignment == nil, let doc = env.document,
              env.mapAlignLevels.contains(where: { $0.info.ordinal < level.info.ordinal && $0.info.mapAlignment != nil })
        else { return }
        let center = map.region.map { GeoPoint(longitude: $0.center.longitude, latitude: $0.center.latitude) }
            ?? GeoPoint(longitude: 0, latitude: 0)
        env.placeOnMapIfNeeded(level.id, canvasSize: doc.canvasSize, mapCenter: center, visibleWidthMeters: 100)
    }

    private func pinCameraIfNeeded() {
        guard !didPinCamera else { return }
        let aligned = env.mapAlignStack.compactMap { $0.info.mapAlignment }
        if let first = editingAlignment ?? aligned.first {
            map.setRegion(MKCoordinateRegion(center: first.center.clCoordinate,
                                             latitudinalMeters: 300, longitudinalMeters: 300))
            didPinCamera = true
        } else if let region = AnchorMapMath.regionFitting(env.anchors.pairs.map(\.geo.clCoordinate)) {
            map.setRegion(region)
            didPinCamera = true
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = placeSearch.message {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(8)
            }
            ForEach(placeSearch.results) { result in
                Button {
                    map.setRegion(PlaceSearchModel.focusRegion(for: result))
                    didPinCamera = true
                    placeSearch.dismissResults()
                    searchFocused = false
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.name).font(.callout)
                        Text(result.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    // MARK: 층 패널 (아래)

    private var levelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(env.mapAlignLevels) { level in levelCard(level) }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 10) {
                Button("이전 층") { step(-1) }.disabled(neighbor(-1) == nil)
                Button("다음 층") { step(1) }.disabled(neighbor(1) == nil)
                let progress = env.mapAlignProgress
                ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                    .frame(maxWidth: 260)
                Text("\(progress.done) / \(progress.total)층 정렬됨").font(.caption.monospacedDigit())
                Spacer()
                if let id = editingID, let a = env.mapAlignment(of: id) {
                    Button(a.isConfirmed ? "정렬 완료 취소" : "이 층 정렬 완료") {
                        env.updateMapAlignment(id, name: a.isConfirmed ? "정렬 완료 취소" : "정렬 완료") {
                            $0.isConfirmed.toggle()
                            if $0.isConfirmed { $0.isLocked = true }
                            // 완료한 층은 잠근다. 위층을 맞추다 아래층이 따라 움직이면 기준이 사라진다.
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    private func neighbor(_ delta: Int) -> ProjectLevel? {
        let levels = env.mapAlignLevels
        guard let i = levels.firstIndex(where: { $0.id == editingID }) else { return levels.first }
        let j = i + delta
        return levels.indices.contains(j) ? levels[j] : nil
    }

    private func step(_ delta: Int) {
        guard let next = neighbor(delta) else { return }
        preview = nil
        env.selectProjectLevel(next.id)
        env.prepareMapAlignDrawings()
    }

    private func levelCard(_ level: ProjectLevel) -> some View {
        let a = level.info.mapAlignment
        let isEditing = level.id == editingID
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(level.info.name).font(.callout.weight(.semibold)).lineLimit(1)
                if a?.isConfirmed == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                Spacer(minLength: 4)
                if let a {
                    Button { env.updateMapAlignment(level.id, name: "층 잠금") { $0.isLocked.toggle() } } label: {
                        Image(systemName: a.isLocked ? "lock.fill" : "lock.open")
                    }
                    .buttonStyle(.borderless).help(a.isLocked ? "잠금 해제" : "잠그면 끌거나 돌릴 수 없습니다")
                    Button { env.updateMapAlignment(level.id, name: "층 표시") { $0.isVisible.toggle() } } label: {
                        Image(systemName: a.isVisible ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    Menu {
                        Button("맨 앞으로 보내기") { env.moveOnMapStack(level.id, .front) }
                        Button("앞으로 보내기") { env.moveOnMapStack(level.id, .forward) }
                        Button("뒤로 보내기") { env.moveOnMapStack(level.id, .backward) }
                        Button("맨 뒤로 보내기") { env.moveOnMapStack(level.id, .back) }
                    } label: { Image(systemName: "square.3.layers.3d") }
                    .menuStyle(.borderlessButton).fixedSize().help("쌓는 순서")
                }
            }
            if let a {
                HStack(spacing: 6) {
                    Text("투명도").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { opacity(of: level.id, saved: a) },
                                          set: { v in
                                              opacityDraft = (level.id, v)
                                              if !isEditingOpacity { commitOpacityDraft() }
                                              // 끄지 않고 바뀐 값(키보드 조작 등)은 바로 저장한다.
                                          }),
                           in: 0.05...1,
                           onEditingChanged: { editing in
                               isEditingOpacity = editing
                               if !editing { commitOpacityDraft() }
                           })
                    Text(String(format: "%.2f", opacity(of: level.id, saved: a))).font(.caption2.monospacedDigit())
                }
                Button("지도 가운데로 가져오기") { bringLevelToMapCenter(level) }
                    .controlSize(.small)
                    .disabled(a.isLocked || !canPlaceHere || env.mapAlignDrawing(for: level) == nil)
                    .help(tooWideHint ?? "지금 보는 지도 가운데로 이 층 도면을 옮기고, 크기를 화면에 맞춥니다. 회전은 그대로입니다. 도면이 화면을 덮어 지도를 찾기 어려우면 ⌥ 끌기로 지도를 옮긴 뒤 누르세요.")
                // 도면이 엉뚱한 곳에 올라가 화면에서 보이지 않을 때 되찾는 길이다.
            } else {
                Text("지도에 없음").font(.caption).foregroundStyle(.secondary)
            }
            Button(isEditing ? "편집 중" : "이 층 편집") {
                preview = nil
                env.selectProjectLevel(level.id)
                env.prepareMapAlignDrawings()
            }
            .disabled(isEditing)
            .controlSize(.small)
        }
        .padding(10)
        .frame(width: 250)
        .background(isEditing ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isEditing ? Color.accentColor : .clear))
    }

    // MARK: Anchor 패널 (오른쪽, Anchor 찍기 모드)

    private var anchorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("(가) 지오레퍼런싱 Anchor").font(.subheadline.weight(.semibold))
            Text("정렬된 도면의 꼭짓점·교점(노란 점)을 누르면 그 점의 도면 좌표와 정렬로 계산한 위경도가 한 쌍으로 저장됩니다. 3쌍 이상이면 지오레퍼런싱이 설정됩니다.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                let n = env.anchors.pairs.count
                Image(systemName: n >= AnchorStore.minimumPairs ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(n >= AnchorStore.minimumPairs ? .green : .orange)
                Text("\(n) / \(AnchorStore.minimumPairs)쌍").font(.caption.monospacedDigit())
            }
            layerPointSection
            Divider()
            Text("(나) IMDF anchor feature").font(.subheadline.weight(.semibold))
            Text("(가)로 저장한 점 중 체크한 점이 anchor.geojson의 Point가 됩니다.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(env.anchors.pairs.enumerated()), id: \.element.id) { n, pair in
                        anchorRow(n: n, pair: pair)
                    }
                }
            }
        }
        .padding(12)
    }

    /// anchor 레이어에 저장했지만 아직 Anchor 쌍이 아닌 점. 누르면 정렬로 위경도를 계산해 쌍으로 불러온다.
    @ViewBuilder
    private var layerPointSection: some View {
        let waiting = env.anchorLayerPoints.filter { env.anchorPair(at: $0.point) == nil }
        if !waiting.isEmpty {
            HStack {
                Text("anchor 레이어 점 \(waiting.count)개").font(.caption.weight(.semibold))
                Spacer()
                Button("모두 불러오기") { env.importAnchorLayerPoints() }
                    .controlSize(.small)
                    .disabled(editingAlignment == nil)
            }
            ForEach(waiting, id: \.feature.id) { item in
                HStack(spacing: 6) {
                    Image(systemName: "circle.dashed").foregroundStyle(.purple)
                    Text(item.feature.serialNumber).font(.caption)
                    Text(String(format: "%.1f, %.1f", item.point.x, item.point.y))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button("불러오기") {
                        selectedAnchor = env.importAnchorLayerPoints([item.feature.id]).first?.id
                    }
                    .controlSize(.small)
                    .disabled(editingAlignment == nil)
                }
            }
            Text("메인 화면 anchor 레이어에서 찍은 점입니다. 지도의 보라색 테두리 점을 눌러도 불러옵니다.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func anchorRow(n: Int, pair: AnchorPair) -> some View {
        let feature = env.imdfAnchorFeature(for: pair)
        return HStack(spacing: 6) {
            Text("\(n + 1)").font(.caption.bold()).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(pair.label).font(.caption).lineLimit(1)
                Text(String(format: "%.6f, %.6f", pair.geo.latitude, pair.geo.longitude))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                if pair.fromAlignment != true {
                    Text("기존 1:1 Anchor").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 4)
            Toggle(isOn: Binding(get: { feature != nil }, set: { _ in env.toggleIMDFAnchor(pair.id) })) {
                Text(feature?.serialNumber ?? "anchor").font(.caption2)
            }
            .toggleStyle(.checkbox)
            .help("이 점을 IMDF anchor feature로 지정합니다")
            Button(role: .destructive) {
                env.requestDeletion(title: "\(pair.label)을 삭제할까요?",
                                    message: feature == nil ? "실행 취소로 복구할 수 있습니다."
                                        : "이 점으로 지정한 \(feature!.serialNumber)도 함께 휴지통으로 갑니다. 실행 취소로 복구할 수 있습니다.") {
                    $0.removeAlignmentAnchor(pair.id)
                }
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
            .buttonStyle(.borderless)
        }
        .padding(6)
        .background(pair.id == selectedAnchor ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6))
        .onTapGesture { selectedAnchor = pair.id }
    }
}
