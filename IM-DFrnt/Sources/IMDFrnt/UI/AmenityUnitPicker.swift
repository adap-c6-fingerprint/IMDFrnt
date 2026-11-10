import SwiftUI

/// Uses the existing Unit UUID array; opening the picker never changes connections.
struct AmenityUnitPicker: View {
    @EnvironmentObject var env: AppEnvironment
    let feature: FeatureGroup
    @State private var isOpen = false
    @State private var query = ""
    @State private var choices: [AmenityUnitChoice] = []

    private var selected: [String] {
        (env.features.feature(feature.id) ?? feature).value("unit_ids").projectJSON.array.compactMap(\.string)
    }

    var body: some View {
        Button {
            choices = env.amenityUnitChoices(for: feature)
            query = ""
            isOpen = true
        } label: {
            Label(selected.isEmpty ? "Unit 선택" : "Unit 선택 · \(selected.count)개 연결", systemImage: "checklist")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("연결할 Unit 선택 (복수 선택)").font(.headline)
                Text("현재 층: 포함된 Unit → 외곽선까지 가까운 순. 다른 층은 뒤에 표시합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Unit 이름 · 일련번호 · UUID 검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let known = Set(choices.map(\.id))
                        ForEach(Array(Set(selected.filter { !known.contains($0.lowercased()) })).sorted(), id: \.self) { id in
                            unitToggle(id, label: "기존 참조 · \(id)")
                        }
                        let labels = Dictionary(uniqueKeysWithValues: choices.map { ($0.id, $0.label) })
                        let matches = SearchablePicker.filter(choices.map(\.id), query: query, label: { labels[$0] ?? $0 })
                        // Keep the spatial order after filtering, rather than moving name-prefix matches ahead.
                        let visible = Set(matches)
                        ForEach(choices.filter { visible.contains($0.id) }) { choice in
                            unitToggle(choice.id, label: choice.label)
                        }
                        if matches.isEmpty { Text("선택 가능한 Unit이 없습니다.").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 280)
                HStack {
                    Text("\(selected.count)개 연결").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("완료") { isOpen = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .frame(width: 380)
        }
    }

    private func unitToggle(_ id: String, label: String) -> some View {
        Toggle(isOn: Binding(get: { selected.contains { $0.lowercased() == id.lowercased() } }, set: {
            env.setAmenityUnit(id, selected: $0, for: feature.id)
        })) {
            Text(label).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
    }
}
