import SwiftUI

/// 우측 패널 카드 목록 위의 category 필터(#52). 고른 category의 feature만 카드 목록·캔버스에 남는다.
///
/// 고를 수 있는 값은 **이 레이어에 실제로 저장된 category**뿐이다. unit만 해도 스펙 값이 65개라
/// 전부 늘어놓으면 쓰지도 않은 값 사이에서 찾아야 한다. 여러 개를 함께 고를 수 있다.
struct CategoryFilterBar: View {
    @EnvironmentObject var env: AppEnvironment
    let type: IMDFFeatureType
    let features: [FeatureGroup]

    @State private var isOpen = false

    private var picked: Set<String> { env.categoryFilters[type] ?? [] }

    /// (category 값, 개수). 개수 많은 순, 같으면 보이는 이름 순이다. null은 맨 뒤다.
    private var options: [(value: String, count: Int)] {
        var counts: [String: Int] = [:]
        for f in features { counts[AppEnvironment.categoryValue(of: f), default: 0] += 1 }
        for v in picked where counts[v] == nil { counts[v] = 0 }
        // 고른 값의 feature를 모두 지우거나 바꿔도 고른 채로 남는다. 목록에서 사라지면 풀 방법이 없다.
        return counts.map { (value: $0.key, count: $0.value) }.sorted {
            if $0.value.isEmpty != $1.value.isEmpty { return !$0.value.isEmpty }
            if $0.count != $1.count { return $0.count > $1.count }
            return title($0.value) < title($1.value)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { isOpen = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: picked.isEmpty ? "line.3.horizontal.decrease.circle"
                                                     : "line.3.horizontal.decrease.circle.fill")
                    Text(summary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((picked.isEmpty ? Color.secondary : Color.accentColor).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { panel }
            .help("고른 category의 feature만 카드 목록과 캔버스에 보입니다")

            if !picked.isEmpty {
                Button("해제") { env.categoryFilters[type] = nil }
                    .controlSize(.small)
            }
        }
    }

    private var summary: String {
        switch picked.count {
        case 0: return "category 전체"
        case 1: return "category: \(title(picked.first!))"
        default: return "category \(picked.count)개"
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("category 필터").font(.caption.weight(.semibold))
                Spacer()
                Button("모두 보기") { env.categoryFilters[type] = nil }
                    .controlSize(.small)
                    .disabled(picked.isEmpty)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.value) { row($0.value, count: $0.count) }
                }
            }
            .frame(height: min(320, CGFloat(options.count) * 24 + 4))
            Text("아무것도 고르지 않으면 전부 보입니다.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 280)
    }

    private func row(_ value: String, count: Int) -> some View {
        let on = picked.contains(value)
        return Button { toggle(value) } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                Text(title(value)).font(.callout)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ value: String) {
        var next = picked
        if next.contains(value) { next.remove(value) } else { next.insert(value) }
        env.categoryFilters[type] = next.isEmpty ? nil : next
        // 펼쳐 둔 카드가 걸러지면 캔버스 강조만 남아 어느 카드인지 찾을 수 없다. 걸러진 카드는 접는다.
        for f in features where env.isFeatureExpanded(f.id) && !env.passesCategoryFilter(f) {
            env.toggleFeatureExpansion(f.id)
        }
    }

    private func title(_ value: String) -> String {
        value.isEmpty ? "null (미지정)" : CategoryLabel.display(value, type: type)
    }
}
