import MapKit
import SwiftUI

struct RegistrationCanvasLayer: Identifiable {
    let id: String
    let rings: [[LocalPoint]]
    var color: Color = .blue
    var opacity = 1.0
}

/// Shared drawing surface for Footprint GPS and Level correspondence picking.
/// Clicks use the same vertex/intersection extractor as the main drawing tools.
struct RegistrationCanvas: View {
    let layers: [RegistrationCanvasLayer]
    let reference: [[LocalPoint]]
    var pickRings: [[LocalPoint]] = []
    var markers: [LocalPoint] = []
    var onPick: ((LocalPoint) -> Void)?
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var lastPan = CGSize.zero
    @State private var magnet: LocalPoint?

    private var bounds: CGRect {
        let points = reference.flatMap { $0 }
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 500, height: 500) }
        return points.reduce(CGRect(x: first.x, y: first.y, width: 1, height: 1)) { $0.union(CGRect(x: $1.x, y: $1.y, width: 1, height: 1)) }
    }

    var body: some View {
        GeometryReader { viewport in
            let box = bounds
            let fit = max(0.00001, min((viewport.size.width - 60) / max(1, box.width), (viewport.size.height - 60) / max(1, box.height)))
            let scale = fit * zoom
            let origin = CGPoint(x: viewport.size.width / 2 - box.midX * scale + pan.width,
                                 y: viewport.size.height / 2 - box.midY * scale + pan.height)
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, _ in
                    ctx.translateBy(x: origin.x, y: origin.y)
                    ctx.scaleBy(x: scale, y: scale)
                    for layer in layers {
                        var path = Path()
                        for ring in layer.rings where !ring.isEmpty { path.addLines(ring.map(\.cg)); path.closeSubpath() }
                        ctx.fill(path, with: .color(layer.color.opacity(layer.opacity * 0.08)), style: FillStyle(eoFill: true))
                        ctx.stroke(path, with: .color(layer.color.opacity(layer.opacity)), lineWidth: 2 / scale)
                    }
                    for (index, p) in markers.enumerated() {
                        let dot = Path(ellipseIn: CGRect(x: p.x - 5 / scale, y: p.y - 5 / scale, width: 10 / scale, height: 10 / scale))
                        ctx.fill(dot, with: .color(.red))
                        ctx.draw(Text("\(index + 1)").foregroundStyle(.red), at: CGPoint(x: p.x + 12 / scale, y: p.y - 12 / scale))
                    }
                    if let p = magnet {
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 8 / scale, y: p.y - 8 / scale, width: 16 / scale, height: 16 / scale)),
                                   with: .color(.orange), lineWidth: 2 / scale)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase {
                        let local = LocalPoint((p.x - origin.x) / scale, (p.y - origin.y) / scale)
                        magnet = RegistrationGeometry.snapped(local, rings: pickRings, tolerance: 14 / scale)
                    } else { magnet = nil }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if abs(value.translation.width) + abs(value.translation.height) > 5 {
                        pan = CGSize(width: lastPan.width + value.translation.width, height: lastPan.height + value.translation.height)
                    }
                }.onEnded { value in
                    if abs(value.translation.width) + abs(value.translation.height) < 5 {
                        let p = LocalPoint((value.location.x - origin.x) / scale, (value.location.y - origin.y) / scale)
                        if let snapped = RegistrationGeometry.snapped(p, rings: pickRings, tolerance: 14 / scale) { onPick?(snapped) }
                    }
                    lastPan = pan
                })
                HStack {
                    Button("−") { zoom = max(0.1, zoom / 1.25) }
                    Button("＋") { zoom = min(100, zoom * 1.25) }
                    Button("맞춤") { zoom = 1; pan = .zero; lastPan = .zero }
                }.buttonStyle(.bordered).padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct FootprintAnchorScreen: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var search = PlaceSearchModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var pending: LocalPoint?
    @State private var selected: UUID?
    @State private var pickGPS = true
    @State private var longitude = ""
    @State private var latitude = ""

    private var shared: SharedFootprint { env.sharedFootprint }
    private var rings: [[LocalPoint]] { shared.features.filter { !$0.isInTrash }.flatMap(\.polygonRings) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("돌아가기") { env.exitAnchorScreen() }
                Text("Footprint Anchor 지정").font(.headline)
                Text("Footprint 점 → 지도의 같은 위치 · 최소 3쌍").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(shared.isGeoreferenced ? "GPS 설정됨" : "GPS 설정 필요").foregroundStyle(shared.isGeoreferenced ? .green : .orange)
            }.padding(12)
            Divider()
            HSplitView {
                VStack(alignment: .leading) {
                    Text(pending == nil ? "Footprint의 꼭짓점·변·교점을 선택하세요." : "이제 지도에서 같은 위치를 찍거나 경도·위도를 입력하세요.")
                        .font(.caption).padding(8)
                    RegistrationCanvas(layers: [.init(id: "footprint", rings: rings)], reference: rings,
                        pickRings: rings, markers: shared.anchors.pairs.map(\.local)) { pending = $0 }
                }.frame(minWidth: 300)
                VStack(spacing: 6) {
                    HStack {
                        TextField("장소 검색", text: $search.query).onSubmit { search.search(around: nil) }
                        Button("검색") { search.search(around: nil) }
                        Toggle("GPS 찍기", isOn: $pickGPS).toggleStyle(.button)
                    }.padding(8)
                    ForEach(search.results) { place in
                        Button(place.name) { camera = .region(place.boundingRegion); search.dismissResults() }
                    }
                    if let message = search.message { Text(message).font(.caption) }
                    MapReader { proxy in
                        Map(position: $camera) {
                            ForEach(Array(shared.anchors.pairs.enumerated()), id: \.element.id) { i, pair in
                                Annotation("GPS \(i + 1)", coordinate: pair.geo.clCoordinate) {
                                    Text("\(i + 1)").padding(5).background(selected == pair.id ? Color.orange : .blue, in: Circle()).foregroundStyle(.white)
                                }
                            }
                            ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                                let coordinates = ring.compactMap { shared.geoPoint($0)?.clCoordinate }
                                if coordinates.count == ring.count, let first = coordinates.first {
                                    MapPolyline(coordinates: coordinates + [first]).stroke(.blue, lineWidth: 2)
                                }
                            }
                        }
                        .mapStyle(.imagery)
                        .overlay {
                            if pickGPS, pending != nil {
                                Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                                    if let coordinate = proxy.convert(value.location, from: .local) {
                                        save(GeoPoint(longitude: coordinate.longitude, latitude: coordinate.latitude))
                                    }
                                })
                            }
                        }
                    }
                }.frame(minWidth: 330)
            }
            HStack {
                TextField("경도", text: $longitude)
                TextField("위도", text: $latitude)
                Button(selected == nil ? "Anchor 추가" : "선택 Anchor 수정") {
                    guard let lon = Double(longitude), let lat = Double(latitude) else { return }
                    save(GeoPoint(longitude: lon, latitude: lat))
                }.disabled(pending == nil)
                Button("새 Anchor") { selected = nil; pending = nil; longitude = ""; latitude = "" }
            }.textFieldStyle(.roundedBorder).padding(8)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(shared.anchors.pairs.enumerated()), id: \.element.id) { index, pair in
                        HStack {
                            Button("\(index + 1) · \(pair.geo.longitude.formatted()), \(pair.geo.latitude.formatted())") {
                                selected = pair.id; pending = pair.local
                                longitude = String(pair.geo.longitude); latitude = String(pair.geo.latitude)
                            }
                            Button(role: .destructive) {
                                env.editFootprintAnchors("Footprint Anchor 삭제") { $0.remove(pair.id) }
                                selected = nil; pending = nil
                            } label: { Image(systemName: "trash") }
                        }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }.padding(8)
            }.frame(height: 55)
            if let error = Georeferencer(pairs: shared.anchors.pairs).fitError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(4)
            }
        }
        .onAppear {
            if let point = shared.anchors.pairs.first?.geo ?? rings.first?.first.flatMap({ shared.geoPoint($0) }) {
                camera = .region(MKCoordinateRegion(center: point.clCoordinate, latitudinalMeters: 400, longitudinalMeters: 400))
            }
        }
    }

    private func save(_ point: GeoPoint) {
        guard let local = pending else { return }
        guard point.longitude.isFinite, point.latitude.isFinite, abs(point.longitude) <= 180, abs(point.latitude) <= 90 else {
            env.notify("경도는 −180~180, 위도는 −90~90 범위로 입력하세요.", isError: true); return
        }
        env.editFootprintAnchors(selected == nil ? "Footprint GPS Anchor 추가" : "Footprint GPS Anchor 수정") { store in
            if let selected, let index = store.pairs.firstIndex(where: { $0.id == selected }) {
                store.pairs[index].local = local; store.pairs[index].geo = point
            } else { store.add(local: local, geo: point, label: "Footprint \(store.pairs.count + 1)") }
        }
        selected = nil; pending = nil
    }
}

struct LevelFootprintScreen: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedLevel: UUID?
    @State private var selectingPairs = false
    @State private var pendingLevelPoint: LocalPoint?
    @State private var replacingPair: UUID?

    private var project: BuildingProject { env.projectContents }
    private var footprint: [[LocalPoint]] { project.sharedFootprint?.features.filter { !$0.isInTrash }.flatMap(\.polygonRings) ?? [] }
    private var selected: ProjectLevel? { project.levels.first { $0.id == selectedLevel } }
    private var registration: LevelFootprintRegistration { selected?.info.footprintRegistration ?? LevelFootprintRegistration() }
    private var overlayLayers: [RegistrationCanvasLayer] {
        var layers = [RegistrationCanvasLayer(id: "footprint", rings: footprint)]
        for level in project.levels {
            let r = level.info.footprintRegistration ?? LevelFootprintRegistration()
            guard r.isVisible else { continue }
            let rings = RegistrationGeometry.levelRings(level).map { $0.map(r.transform.apply) }
            layers.append(.init(id: level.id.uuidString, rings: rings, color: level.id == selectedLevel ? .orange : .green, opacity: r.opacity))
        }
        return layers
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("돌아가기") { env.showLevelFootprintScreen = false }
                Text("Level · Footprint 정렬").font(.headline)
                Text("파랑: 전역 Footprint · 주황: 선택 층 · 초록: 다른 층").font(.caption)
                Spacer()
                Toggle("대응점 지정", isOn: $selectingPairs).toggleStyle(.button)
            }.padding(12)
            Divider()
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(project.levels.sorted { $0.info.ordinal < $1.info.ordinal }) { level in
                            levelCard(level)
                        }
                        if let id = selectedLevel {
                            Divider()
                            Text("선택 층 미세조정 (도면 단위)").font(.headline)
                            numberField("가로 이동", key: \.x)
                            numberField("세로 이동", key: \.y)
                            numberField("회전 °", key: \.rotation)
                            numberField("크기 배율", key: \.scale)
                            HStack {
                                Button("←") { adjust(id, \.x, -1) }; Button("→") { adjust(id, \.x, 1) }
                                Button("↑") { adjust(id, \.y, -1) }; Button("↓") { adjust(id, \.y, 1) }
                            }
                            HStack {
                                Button("회전 −0.1°") { adjust(id, \.rotation, -0.1) }
                                Button("회전 +0.1°") { adjust(id, \.rotation, 0.1) }
                            }
                            HStack {
                                Button("크기 −0.1%") { env.editLevelRegistration(id, name: "층 크기") { $0.transform.scale /= 1.001 } }
                                Button("크기 +0.1%") { env.editLevelRegistration(id, name: "층 크기") { $0.transform.scale *= 1.001 } }
                            }
                            Divider()
                            Text("대응점 \(registration.pairs.count)쌍").font(.headline)
                            Text("대응점 지정: 왼쪽 Level 점 → 오른쪽 Footprint 점. 기존 쌍을 누르면 다시 지정합니다.").font(.caption)
                            ForEach(Array(registration.pairs.enumerated()), id: \.element.id) { index, pair in
                                HStack {
                                    Button("대응점 \(index + 1) 다시 지정") { replacingPair = pair.id; pendingLevelPoint = nil; selectingPairs = true }
                                    Button(role: .destructive) { env.editLevelRegistration(id, name: "층 대응점 삭제") { $0.pairs.removeAll { $0.id == pair.id } } }
                                    label: { Image(systemName: "trash") }
                                }
                            }
                            Button("대응점으로 정렬") { env.fitLevelToFootprint(id) }.disabled(registration.pairs.count < 2)
                            Text("서로 떨어진 점을 2쌍 이상 지정하세요. 3~4쌍으로 정합을 확인할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(12)
                }.frame(minWidth: 270, idealWidth: 300, maxWidth: 340)
                if selectingPairs, let level = selected, let id = selectedLevel {
                    let levelRings = RegistrationGeometry.levelRings(level)
                    HSplitView {
                        VStack {
                            Text("① \(level.info.name) 기준점 선택").padding(8)
                            RegistrationCanvas(layers: [.init(id: "level", rings: levelRings, color: .orange)], reference: levelRings,
                                pickRings: levelRings, markers: registration.pairs.map(\.level) + [pendingLevelPoint].compactMap { $0 }) {
                                    pendingLevelPoint = $0
                                }
                        }
                        VStack {
                            Text(pendingLevelPoint == nil ? "② 왼쪽 Level 점을 먼저 선택하세요" : "② 같은 위치의 Footprint 점 선택").padding(8)
                            RegistrationCanvas(layers: [.init(id: "footprint", rings: footprint)], reference: footprint,
                                pickRings: footprint, markers: registration.pairs.map(\.footprint)) { point in
                                    guard let local = pendingLevelPoint else { return }
                                    env.editLevelRegistration(id, name: "층 대응점 지정") { r in
                                        if let replacingPair, let i = r.pairs.firstIndex(where: { $0.id == replacingPair }) {
                                            r.pairs[i].level = local; r.pairs[i].footprint = point
                                        } else { r.pairs.append(LevelFootprintPair(level: local, footprint: point)) }
                                    }
                                    pendingLevelPoint = nil; replacingPair = nil
                                }
                        }
                    }
                } else {
                    RegistrationCanvas(layers: overlayLayers, reference: footprint,
                        markers: registration.pairs.map { registration.transform.apply($0.level) })
                }
            }
        }
        .onAppear { selectedLevel = env.routingFloorID ?? project.levels.first?.id }
    }

    private func levelCard(_ level: ProjectLevel) -> some View {
        let r = level.info.footprintRegistration ?? LevelFootprintRegistration()
        return VStack(alignment: .leading) {
            HStack {
                Button(level.info.name) { selectedLevel = level.id; pendingLevelPoint = nil; replacingPair = nil }
                    .font(.headline)
                Spacer()
                Toggle("층 표시", isOn: Binding(get: { r.isVisible }, set: { value in
                    env.editLevelRegistration(level.id, name: "층 표시") { $0.isVisible = value }
                })).labelsHidden()
            }
            Slider(value: Binding(get: { r.opacity }, set: { value in
                env.editLevelRegistration(level.id, name: "층 불투명도") { $0.opacity = value }
            }), in: 0...1)
            Text("불투명도 \(Int(r.opacity * 100))% · \(r.pairs.count)쌍").font(.caption)
            if RegistrationGeometry.levelRings(level).isEmpty { Text("level 레이어에서 층 외곽을 먼저 그리세요.").font(.caption).foregroundStyle(.orange) }
        }.padding(8).background(selectedLevel == level.id ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func numberField(_ title: String, key: WritableKeyPath<LevelFootprintTransform, Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 82, alignment: .leading)
            TextField(title, value: Binding(get: { registration.transform[keyPath: key] }, set: { value in
                if let id = selectedLevel { env.editLevelRegistration(id, name: "층 \(title)") { $0.transform[keyPath: key] = value } }
            }), format: .number).textFieldStyle(.roundedBorder)
        }
    }
    private func adjust(_ id: UUID, _ key: WritableKeyPath<LevelFootprintTransform, Double>, _ delta: Double) {
        env.editLevelRegistration(id, name: "층 미세조정") { $0.transform[keyPath: key] += delta }
    }
}
