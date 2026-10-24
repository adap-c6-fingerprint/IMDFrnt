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
                                    if type == "building" { Button("건물 추가") { env.createBuilding() } }
                                    if type == "address" { Button("주소 추가") { env.addMetadataFeature(.address) } }
                                    if env.globalFeatures(type).isEmpty {
                                        Text(type == "venue" ? "메인 venue 레이어에서 장소 전체의 경계를 하나 그리세요." : "공통 정보가 없습니다.")
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(env.globalFeatures(type), id: \.featureID) { feature in
                                        if let id = feature["id"]?.uuid { GlobalMetadataEditor(type: type, feature: feature).id(id) }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }
                        }
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
                if let kind = IMDFFeatureType(rawValue: type), let id = feature["id"]?.uuid {
                    MetadataRecordEditor(type: kind, id: id)
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
            LegacyManifestChoices()
            JSONTextEditor(text: $text, height: 120)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Button("Manifest 적용") {
                do { try env.setManifest(text); error = nil } catch { self.error = error.localizedDescription }
            }
        }.onAppear { text = env.buildingProject.manifest.text }
            .onChange(of: env.buildingProject.manifest) { _, value in text = value.text }
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
