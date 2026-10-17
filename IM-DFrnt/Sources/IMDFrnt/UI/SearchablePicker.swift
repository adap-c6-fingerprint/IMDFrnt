import SwiftUI

/// 검색해서 고르는 선택 칸. 우측 사이드바의 category·참조(일련번호) 칸이 쓴다.
///
/// **드롭다운만 두지 않는 이유:** unit category만 해도 값이 수십 개라 드롭다운을 끝까지 내려
/// 눈으로 찾아야 했다(2026-10-17 요청). 누르면 검색 칸이 있는 목록이 뜨고, 글자를 치면 바로 좁혀진다.
/// Return은 맨 위 결과를 고르고, esc는 닫는다.
struct SearchablePicker: View {
    let selection: String
    // 빈 문자열이면 null이다.
    let options: [String]
    let onSelect: (String) -> Void

    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        Button {
            query = ""
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(selection.isEmpty ? "null" : selection)
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { panel }
    }

    private var matches: [String] { Self.filter(options, query: query) }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("검색", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = matches.first { choose(first) } }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty { row("", title: "null") }
                    // 검색 중에는 null을 빼야 Return이 맨 위 검색 결과를 고른다.
                    ForEach(matches, id: \.self) { row($0, title: $0) }
                    if matches.isEmpty && !query.isEmpty {
                        Text("'\(query)'와 맞는 항목이 없습니다").font(.caption).foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(height: min(280, CGFloat(matches.count + 1) * 24 + 4))

            Text("\(matches.count) / \(options.count)개 · Return: 맨 위 항목 선택")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 260)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        // 팝오버가 뜬 다음 차례에 초점을 준다. 같은 차례에는 칸이 아직 창에 붙지 않아 초점이 안 들어간다.
    }

    private func row(_ value: String, title: String) -> some View {
        Button { choose(value) } label: {
            HStack {
                Text(title).font(.callout)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                Spacer()
                if value == selection { Image(systemName: "checkmark").font(.caption) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(value == selection ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ value: String) {
        onSelect(value)
        isOpen = false
    }

    /// 검색어로 좁힌다. 대소문자와 공백·밑줄·하이픈을 무시한다 — "rest room"으로 `restroom.male`이,
    /// "unit 3"으로 `unit-003`이 걸려야 한다. 앞에서부터 맞는 항목을 먼저 보인다.
    static func filter(_ options: [String], query: String) -> [String] {
        let q = plain(query), qn = numbered(query)
        guard !q.isEmpty else { return options }
        let hits = options.filter { plain($0).contains(q) || numbered($0).contains(qn) }
        // 원래 글자 그대로("unit-00" → `unit-003`)와 번호를 맞춘 꼴("unit 3" → `unit-003`) 둘 다 본다.
        return hits.filter { plain($0).hasPrefix(q) } + hits.filter { !plain($0).hasPrefix(q) }
    }

    /// 소문자로 바꾸고 공백·밑줄·하이픈·점을 뺀다.
    static func plain(_ s: String) -> String {
        s.lowercased().filter { !" _-.".contains($0) }
    }

    /// `plain`에서 숫자 앞의 0까지 버린다. "003"과 "3"을 같은 번호로 본다.
    static func numbered(_ s: String) -> String {
        var out = "", digits = ""
        func flush() {
            guard !digits.isEmpty else { return }
            let trimmed = digits.drop { $0 == "0" }
            out += trimmed.isEmpty ? "0" : String(trimmed)
            digits = ""
        }
        for c in plain(s) {
            if c.isNumber { digits.append(c) } else { flush(); out.append(c) }
        }
        flush()
        return out
    }
}
