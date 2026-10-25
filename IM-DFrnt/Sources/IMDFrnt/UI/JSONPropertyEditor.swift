import SwiftUI

/// Nested official properties and arbitrary language tags are editable without a lossy string schema.
struct JSONPropertyEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let feature: FeatureGroup
    let key: String
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextEditor(text: $text).font(.caption.monospaced()).frame(minHeight: 48, maxHeight: 110)
            HStack {
                Button("JSON 적용") {
                    do {
                        let value = try ProjectJSON.parse(Data(text.utf8))
                        env.updateProperty(key, value: PropertyValue.from(value), in: feature.id)
                        error = nil
                    } catch { self.error = "JSON 형식을 확인하세요: \(error.localizedDescription)" }
                }.controlSize(.mini)
                if let error { Text(error).font(.caption2).foregroundStyle(.red) }
            }
        }
        .onAppear { text = feature.value(key).projectJSON.text }
        .onChange(of: feature.value(key)) { _, value in text = value.projectJSON.text }
    }
}

struct LegacyManifestChoices: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        if let copies = env.buildingProject.legacyManifests, !copies.isEmpty,
           env.buildingProject.manifestConflictsResolved != true {
            VStack(alignment: .leading, spacing: 6) {
                Text("이전 층별 Manifest 값이 서로 다릅니다. 내보내기 전에 사용할 값을 선택하세요.")
                    .font(.caption).foregroundStyle(.orange)
                Button("현재 공통 Manifest 유지") { resolve(nil) }
                ForEach(Array(copies.enumerated()), id: \.offset) { _, copy in
                    DisclosureGroup(copy["imdfrnt_source_level"]?.string ?? "기존 Manifest") {
                        Text(copy.text).font(.caption2.monospaced())
                        Button("이 값 적용") { resolve(copy) }
                    }
                }
            }
        }
    }

    private func resolve(_ copy: ProjectJSON?) {
        env.perform("이전 Manifest 선택") {
            if let copy {
                for (key, value) in copy.object where key != "imdfrnt_source_level" { env.buildingProject.manifest[key] = value }
            }
            // Keep original copies in the project as a recovery record, even after explicit resolution.
            env.buildingProject.manifestConflictsResolved = true
        }
    }
}

struct MetadataRecordEditor: View {
    @EnvironmentObject var env: AppEnvironment
    let type: IMDFFeatureType
    let id: UUID
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        let value = env.globalFeatures(type.rawValue).first { $0["id"]?.uuid == id }
        DisclosureGroup("geometry·확장 속성 JSON") {
            Text("UUID와 Feature 타입은 유지합니다. Relationship의 선택 geometry 등은 여기서 편집합니다.")
                .font(.caption2).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.caption.monospaced()).frame(height: 170)
            Button("Feature JSON 적용") {
                do { try env.replaceGlobalRecord(text, type: type, id: id); error = nil }
                catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .onAppear { text = value?.text ?? "{}" }
        .onChange(of: value) { _, new in text = new?.text ?? "{}" }
    }
}
