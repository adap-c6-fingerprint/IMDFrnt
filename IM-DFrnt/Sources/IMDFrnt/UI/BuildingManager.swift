import CoreLocation
import MapKit
import SwiftUI

struct BuildingManager: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("건물과 공통 층 관리").font(.title2)
                Spacer()
                Button("완료") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Level").font(.headline)
                        Spacer()
                        Button { env.addRoutingFloor() } label: { Image(systemName: "plus") }
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(env.buildingProject.levels.sorted { $0.info.ordinal < $1.info.ordinal }) { level in
                                Button { env.selectProjectLevel(level.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(level.info.name).font(.headline)
                                        Text("\(level.info.ordinal) · 도형 \(level.geoJSON.values.reduce(0) { $0 + $1.count }) · 노드 \(level.nodes.count)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(env.routingFloorID == level.id ? Color.accentColor.opacity(0.14) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { env.requestRoutingFloorDeletion(level.id) } label: {
                                            Text("층 삭제").foregroundStyle(.red)
                                        }
                                    }
                            }
                        }
                    }
                    if let floor = env.currentRoutingFloor { RoutingFloorEditor(floor: floor).id(floor.id) }
                }.padding().frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(["building", "venue", "address"], id: \.self) { type in
                            GroupBox(type == "building" ? "건물" : type == "venue" ? "Venue" : "주소") {
                                VStack(alignment: .leading, spacing: 10) {
                                    if env.globalFeatures(type).isEmpty {
                                        if type == "building" { Button("건물 생성") { env.createBuilding() } }
                                        else { Text("IMDF를 불러오면 기존 정보가 보존됩니다.").foregroundStyle(.secondary) }
                                    }
                                    ForEach(env.globalFeatures(type), id: \.featureID) { feature in
                                        if let id = feature["id"]?.uuid { GlobalMetadataEditor(type: type, feature: feature).id(id) }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }
                        }
                        GroupBox("건물 Footprint") { FootprintEditor().padding(6) }
                        GroupBox("도면 레이어") { DrawingLayersPanel().padding(6) }
                        GroupBox("Manifest") { ManifestEditor().padding(6) }
                    }.padding()
                }.frame(minWidth: 470, idealWidth: 600)
            }
        }
        .frame(width: 920, height: 760)
        .textFieldStyle(.roundedBorder)
        .alert(env.pendingDeletion?.title ?? "삭제할까요?", isPresented: Binding(
            get: { env.pendingDeletion != nil }, set: { if !$0 { env.cancelDeletion() } }
        ), presenting: env.pendingDeletion) { request in
            Button("취소", role: .cancel) { env.cancelDeletion() }.keyboardShortcut(.defaultAction)
            Button(role: .destructive) { env.confirmDeletion(request.id) } label: { Text("삭제").foregroundStyle(.red) }
        } message: { Text($0.message) }
    }
}

private struct GlobalMetadataEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let type: String
    let feature: ProjectJSON
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        DisclosureGroup(feature["id"]?.string ?? type) {
            VStack(alignment: .leading, spacing: 8) {
                Text("properties").font(.caption).foregroundStyle(.secondary)
                JSONTextEditor(text: $text, height: 160)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Button("정보 적용") {
                    do { try env.setGlobalMetadata(type: type, id: feature["id"]!.uuid!, text: text); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }.padding(.top, 8)
        }.font(.caption)
            .onAppear { text = feature["properties"]?.text ?? "{}" }
            .onChange(of: feature) { _, value in text = value["properties"]?.text ?? "{}" }
    }
}

private struct ManifestEditor: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            JSONTextEditor(text: $text, height: 120)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Button("Manifest 적용") {
                do { try env.setManifest(text); error = nil } catch { self.error = error.localizedDescription }
            }
        }.onAppear { text = env.buildingProject.manifest.text }
            .onChange(of: env.buildingProject.manifest) { _, value in text = value.text }
    }
}

private struct FootprintEditor: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var category = "ground"
    @State private var geometry = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(env.globalFeatures("footprint"), id: \.featureID) { feature in
                if let id = feature["id"]?.uuid {
                    HStack {
                        Button { select(feature) } label: {
                            Label("\(feature["properties"]?["category"]?.string ?? "Footprint") · \(id.uuidString.prefix(8))",
                                  systemImage: selectedID == id ? "checkmark.circle.fill" : "circle")
                        }
                        Spacer()
                        Button(role: .destructive) { env.requestFootprintDeletion(id) } label: { Text("삭제").foregroundStyle(.red) }
                    }
                }
            }
            HStack {
                Button("새 Footprint") { selectedID = nil; geometry = ""; error = nil }
                Button {
                    env.beginGlobalFootprintDrawing()
                    if env.isDrawingGlobalFootprint { dismiss() }
                } label: {
                    Label("현재 층에서 그리기", systemImage: "pencil.and.outline")
                }
                .disabled(env.currentRoutingFloor?.hasGeographicCoordinates != true || env.document == nil)
                Button("현재 층 윤곽 가져오기") {
                    geometry = env.activeLevel?.geoJSON["level.geojson"]?.first?["geometry"]?.text ?? ""
                }.disabled(env.activeLevel?.geoJSON["level.geojson"]?.first?["geometry"] == nil)
                Picker("분류", selection: $category) {
                    Text("지상").tag("ground"); Text("상부").tag("aerial"); Text("지하").tag("subterranean")
                }.frame(width: 160)
            }
            Text("실제 경도·위도의 Polygon/MultiPolygon geometry를 입력합니다. 좌표를 적용하면 저장되는 도형 자체가 바뀝니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let value = try? ProjectJSON.parse(Data(geometry.utf8)),
               let rings = try? FootprintGeometry.rings(value), value["type"]?.string == "Polygon" {
                FootprintMapEditor(rings: rings) { updated in
                    do {
                        let ringJSON = updated.map { point in
                            ProjectJSON.array([.number(Decimal(point.longitude)), .number(Decimal(point.latitude))])
                        }
                        let coordinates = ProjectJSON.array([.array([.array(ringJSON)])])
                        let value: ProjectJSON = .object(["type": .string("Polygon"), "coordinates": coordinates])
                        geometry = value.text
                        selectedID = try env.saveFootprint(id: selectedID, geometryText: geometry, category: category)
                        error = nil
                    } catch let saveError { error = saveError.localizedDescription }
                }
                .frame(height: 270)
            }
            JSONTextEditor(text: $geometry, height: 200)
            if let value = try? ProjectJSON.parse(Data(geometry.utf8)),
               let rings = try? FootprintGeometry.rings(value) {
                FootprintPreview(rings: rings).frame(height: 140)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button(selectedID == nil ? "Footprint 생성" : "Footprint 좌표 적용") {
                do {
                    selectedID = try env.saveFootprint(id: selectedID, geometryText: geometry, category: category)
                    error = nil
                } catch { self.error = error.localizedDescription }
            }.disabled(geometry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: env.globalFeatures("footprint")) { _, features in
                if let id = selectedID {
                    if let feature = features.first(where: { $0["id"]?.uuid == id }) { select(feature) }
                    else { selectedID = nil; geometry = "" }
                }
            }
    }

    private func select(_ feature: ProjectJSON) {
        selectedID = feature["id"]?.uuid
        category = feature["properties"]?["category"]?.string ?? "ground"
        geometry = feature["geometry"]?.text ?? ""
        error = nil
    }
}

/// WGS84 Footprint의 꼭짓점을 지도에서 다시 찍는 간단한 편집기.
/// 기존 Feature의 ID와 나머지 properties는 saveFootprint가 그대로 보존한다.
private struct FootprintMapEditor: View {
    let rings: [[[Double]]]
    let apply: ([GeoPoint]) -> Void
    @State private var points: [GeoPoint] = []
    @State private var isPicking = false
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GPS 꼭짓점 다시 찍기").font(.caption.weight(.semibold))
                Spacer()
                Button(isPicking ? "찍기 완료" : "GPS 점 다시 찍기") {
                    if isPicking { isPicking = false }
                    else { points = []; isPicking = true }
                }
                .buttonStyle(.bordered)
                Button("GPS 좌표 적용") { apply(points) }
                    .buttonStyle(.borderedProminent)
                    .disabled(points.count < 3)
            }
            Text(isPicking ? "지도를 클릭해 꼭짓점을 순서대로 찍으세요. 기존 점은 초기화됩니다." : "현재 Footprint를 지도에서 확인하고, 필요하면 GPS 점을 다시 찍어 적용합니다.")
                .font(.caption2).foregroundStyle(.secondary)
            MapReader { proxy in
                Map(position: $camera) {
                    if points.count >= 2 {
                        MapPolyline(coordinates: points.map(\.clCoordinate) + [points[0].clCoordinate])
                            .stroke(.blue, lineWidth: 3)
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Annotation("GPS \(index + 1)", coordinate: point.clCoordinate) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .padding(4)
                                .background(.blue, in: Circle())
                                .foregroundStyle(.white)
                        }
                    }
                    if !isPicking {
                        ForEach(Array(Array(rings.first ?? []).dropLast().enumerated()), id: \.offset) { index, value in
                            if value.count >= 2 {
                                Annotation("기존 GPS \(index + 1)", coordinate: CLLocationCoordinate2D(latitude: value[1], longitude: value[0])) {
                                    Image(systemName: "circle.fill").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if isPicking {
                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                                points.append(GeoPoint(longitude: coordinate.longitude, latitude: coordinate.latitude))
                            })
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
        .onAppear {
            points = rings.first?.dropLast().compactMap { value in
                guard value.count >= 2 else { return nil }
                return GeoPoint(longitude: value[0], latitude: value[1])
            } ?? []
        }
        .onChange(of: rings) { _, value in
            points = value.first?.dropLast().compactMap { point in
                guard point.count >= 2 else { return nil }
                return GeoPoint(longitude: point[0], latitude: point[1])
            } ?? []
            isPicking = false
        }
    }
}

/// Preview the entered WGS84 geometry, including holes, before applying it.
private struct FootprintPreview: View {
    let rings: [[[Double]]]
    var body: some View {
        Canvas { context, size in
            let points = rings.flatMap { $0 }.filter { $0.count >= 2 && $0[0].isFinite && $0[1].isFinite }
            guard let west = points.map({ $0[0] }).min(), let east = points.map({ $0[0] }).max(),
                  let south = points.map({ $0[1] }).min(), let north = points.map({ $0[1] }).max(),
                  east > west, north > south else { return }
            let longitudeScale = max(0.001, cos((south + north) / 2 * .pi / 180))
            let width = (east - west) * longitudeScale, height = north - south
            let scale = min((size.width - 20) / width, (size.height - 20) / height)
            let x = (size.width - width * scale) / 2, y = (size.height - height * scale) / 2
            var path = Path()
            for ring in rings {
                for (i, point) in ring.enumerated() where point.count >= 2 {
                    let p = CGPoint(x: x + (point[0] - west) * longitudeScale * scale,
                                    y: y + (north - point[1]) * scale)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
            }
            context.fill(path, with: .color(.blue.opacity(0.15)), style: FillStyle(eoFill: true))
            context.stroke(path, with: .color(.blue), lineWidth: 1)
        }.background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Footprint 위경도 도형 미리보기")
    }
}

private struct JSONTextEditor: View {
    @Binding var text: String
    let height: CGFloat
    var body: some View {
        TextEditor(text: $text).font(.system(.caption, design: .monospaced))
            .frame(height: height).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}
