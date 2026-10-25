import SwiftUI

/// IMDF HOURS는 OSM opening_hours 문자열이다. 요일 UI로 표현할 수 없는 규칙도 원문을 보존한다.
struct WeeklyOpeningHours: Equatable {
    static let days = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    struct Interval: Equatable, Identifiable {
        let id = UUID()
        var startHour = 9
        var startMinute = 0
        var endHour = 18
        var endMinute = 0
        var valid: Bool {
            (0...23).contains(startHour) && (0...59).contains(startMinute)
                && (0...24).contains(endHour) && (0...59).contains(endMinute)
                && (endHour != 24 || endMinute == 0)
                && startHour * 60 + startMinute != endHour * 60 + endMinute
        }
        var text: String { String(format: "%02d:%02d-%02d:%02d", startHour, startMinute, endHour, endMinute) }
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.startHour == rhs.startHour && lhs.startMinute == rhs.startMinute
                && lhs.endHour == rhs.endHour && lhs.endMinute == rhs.endMinute
        }
    }
    enum Mode: String, CaseIterable { case closed = "휴무", allDay = "24시간", intervals = "시간 지정" }
    struct Day: Equatable {
        var mode: Mode = .closed
        var intervals = [Interval()]

        func interval(_ id: UUID) -> Interval? { intervals.first { $0.id == id } }
        mutating func updateInterval(_ value: Interval) {
            guard let index = intervals.firstIndex(where: { $0.id == value.id }) else { return }
            intervals[index] = value
        }
        mutating func removeInterval(_ id: UUID) { intervals.removeAll { $0.id == id } }
    }
    var days = Array(repeating: Day(), count: 7)
    var valid: Bool { days.allSatisfy { $0.mode != .intervals || (!$0.intervals.isEmpty && $0.intervals.allSatisfy(\.valid)) } }
    var text: String {
        if days.allSatisfy({ $0.mode == .allDay }) { return "24/7" }
        // 자정 넘김을 다음 날 구간으로 분리한다. 뒤의 `Su off` 규칙이 토요일
        // 야간 구간을 덮어쓰는 OSM 우선순위 함정을 방지한다.
        var spans = Array(repeating: [(Int, Int)](), count: 7)
        for (index, day) in days.enumerated() {
            if day.mode == .allDay { spans[index].append((0, 1440)) }
            if day.mode == .intervals {
                for interval in day.intervals {
                    let start = interval.startHour * 60 + interval.startMinute
                    let end = interval.endHour * 60 + interval.endMinute
                    if end < start {
                        spans[index].append((start, 1440))
                        if end > 0 { spans[(index + 1) % 7].append((0, end)) }
                    } else { spans[index].append((start, end)) }
                }
            }
        }
        return spans.enumerated().map { index, ranges in
            var merged: [(Int, Int)] = []
            for span in ranges.sorted(by: { $0.0 < $1.0 }) {
                if let last = merged.last, span.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, span.1) }
                else { merged.append(span) }
            }
            let times = merged.isEmpty ? "off" : merged.map { start, end in
                String(format: "%02d:%02d-%02d:%02d", start / 60, start % 60, end / 60, end % 60)
            }.joined(separator: ",")
            return Self.days[index] + " " + times
        }.joined(separator: "; ")
    }

    /// Parse only a lossless weekly subset. Complex imported OSM rules stay in advanced editing.
    static func parse(_ text: String) -> Self? {
        if text.isEmpty { return Self() }
        if text == "24/7" { var result = Self(); result.days = Array(repeating: Day(mode: .allDay), count: 7); return result }
        var result = Self()
        var seen = Set<Int>()
        for rule in text.split(separator: ";", omittingEmptySubsequences: false) {
            let parts = rule.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let selector = String(parts[0])
            var indices: [Int] = []
            for component in selector.split(separator: ",") {
                let bounds = component.split(separator: "-")
                guard let first = bounds.first, let start = Self.days.firstIndex(of: String(first)) else { return nil }
                if bounds.count == 1 { indices.append(start) }
                else if bounds.count == 2, let end = Self.days.firstIndex(of: String(bounds[1])), start <= end {
                    indices += Array(start...end)
                } else { return nil }
            }
            guard !indices.isEmpty, indices.allSatisfy({ !seen.contains($0) }) else { return nil }
            var day = Day()
            let times = String(parts[1])
            if times == "off" || times == "closed" { day.mode = .closed }
            else if times == "00:00-24:00" { day.mode = .allDay }
            else {
                day.mode = .intervals; day.intervals = []
                for range in times.split(separator: ",", omittingEmptySubsequences: false) {
                    guard range.range(of: #"^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
                    let fields = range.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { Int($0) }
                    guard fields.count == 4 else { return nil }
                    let interval = Interval(startHour: fields[0], startMinute: fields[1], endHour: fields[2], endMinute: fields[3])
                    guard interval.valid else { return nil }
                    // 원문에 자정 넘김과 다음 날 예외가 함께 있으면 OSM 규칙의 순서가
                    // 의미를 바꾼다. 가져온 문자열은 임의로 재해석하지 않고 고급 모드로 보존한다.
                    guard interval.endHour * 60 + interval.endMinute > interval.startHour * 60 + interval.startMinute else { return nil }
                    day.intervals.append(interval)
                }
            }
            for index in indices { seen.insert(index); result.days[index] = day }
        }
        return result.valid ? result : nil
    }
}

struct OpeningHoursEditor: View {
    @Binding var value: String
    @State private var weekly = WeeklyOpeningHours()
    @State private var raw = ""
    @State private var advanced = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("고급 OSM 규칙 입력", isOn: Binding(get: { advanced }, set: { next in
                if next { raw = weekly.text; advanced = true }
                else if let parsed = WeeklyOpeningHours.parse(raw) {
                    if weekly != parsed { weekly = parsed }
                    advanced = false; error = nil
                }
                else { error = "요일별 입력으로 변환할 수 없는 규칙입니다. 원문을 고급 입력에서 유지하세요." }
            }))
            if advanced {
                TextEditor(text: $raw).font(.caption.monospaced()).frame(minHeight: 80)
                Text("공휴일(PH), 날짜·계절, 일출·일몰 등 OSM opening_hours 규칙을 입력할 수 있습니다. 고급 문법 전체는 앱에서 검증하지 않으며 AIMP 검사로 확인해야 합니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(0..<7, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(["월", "화", "수", "목", "금", "토", "일"][index])
                            Picker("운영", selection: $weekly.days[index].mode) {
                                ForEach(WeeklyOpeningHours.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden()
                        }
                        if weekly.days[index].mode == .intervals {
                            ForEach(weekly.days[index].intervals) { interval in
                                let binding = intervalBinding(day: index, fallback: interval)
                                HStack(spacing: 2) {
                                    clock(hour: binding.startHour, minute: binding.startMinute)
                                    Text("–")
                                    clock(hour: binding.endHour, minute: binding.endMinute)
                                    Button { weekly.days[index].removeInterval(interval.id) } label: { Image(systemName: "minus.circle") }
                                }
                            }
                            Button("시간 구간 추가") { weekly.days[index].intervals.append(.init()) }
                        }
                    }
                }
                Text("종료가 시작보다 이르면 다음 날 종료입니다. 저장 시 자정 이후 시간은 다음 요일에 합쳐집니다. 24시간은 ‘24시간’을 선택하세요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
            HStack {
                Button("운영시간 적용") {
                    guard advanced || weekly.valid else { error = "시·분 범위와 시작·종료를 확인하세요."; return }
                    value = advanced ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : weekly.text
                    error = nil
                }
                Button("미설정으로 지우기") { value = ""; load("") }
            }
        }.font(.caption)
            .onAppear { load(value) }
            .onChange(of: value) { _, next in load(next) }
    }

    private func intervalBinding(day: Int, fallback: WeeklyOpeningHours.Interval) -> Binding<WeeklyOpeningHours.Interval> {
        Binding(get: { weekly.days[day].interval(fallback.id) ?? fallback }, set: {
            // SwiftUI can finish an edit after deletion/load. Removed IDs must not index or resurrect a row.
            weekly.days[day].updateInterval($0)
        })
    }

    private func clock(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 1) {
            TextField("시", value: hour, format: .number).frame(minWidth: 25)
            Text(":")
            TextField("분", value: minute, format: .number).frame(minWidth: 25)
        }.textFieldStyle(.roundedBorder)
    }
    private func load(_ text: String) {
        raw = text
        if let parsed = WeeklyOpeningHours.parse(text) {
            if weekly != parsed { weekly = parsed }
            advanced = false
        }
        else { advanced = true }
        error = nil
    }
}

struct DisplayPointControls: View {
    @EnvironmentObject var env: AppEnvironment
    let feature: FeatureGroup
    private var hasPoint: Bool {
        env.isGlobalMetadata(feature.id) ? !feature.value("display_point").isNull : feature.displayPoint != nil
    }
    var body: some View {
        HStack {
            Text("display point").font(.caption.weight(.semibold))
            Spacer()
            Button(hasPoint ? "다시 찍기" : "찍기") { env.beginDisplayPointPicking(feature.id) }
                .disabled(env.document == nil)
            if hasPoint { Button("삭제") { env.clearDisplayPoint(feature.id) } }
        }.controlSize(.small)
    }
}
