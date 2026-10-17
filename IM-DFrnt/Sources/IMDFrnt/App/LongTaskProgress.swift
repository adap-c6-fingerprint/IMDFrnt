import SwiftUI

/// 계산이 오래 걸리는 작업의 진행 상태. 화면 가운데 팝업으로 보여 주고 끝나면 저절로 닫는다.
///
/// **짧게 끝나는 작업은 팝업을 띄우지 않는다.** 0.4초 안에 끝나면 아무것도 보이지 않는다 —
/// 면 계산처럼 자주 도는 작업마다 팝업이 깜빡이면 그 자체가 방해다.
struct LongTaskProgress: Equatable {
    let id: UUID
    var title: String
    var detail: String
    /// 0...1. nil이면 얼마나 남았는지 알 수 없는 작업이라 움직이는 막대로 보인다.
    var fraction: Double?
    var isVisible = false
}

/// 백그라운드 작업이 진행률을 메인 액터로 보낼 때 쓴다. 1%보다 작은 변화는 보내지 않아 화면 갱신이 몰리지 않는다.
final class LongTaskReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    private let send: @Sendable (Double, String) -> Void

    init(_ send: @escaping @Sendable (Double, String) -> Void) { self.send = send }

    func report(_ fraction: Double, _ detail: String) {
        lock.lock()
        let changed = fraction >= 1 || fraction - last >= 0.01 || fraction < last
        if changed { last = fraction }
        lock.unlock()
        if changed { send(min(max(fraction, 0), 1), detail) }
    }
}

@MainActor
extension AppEnvironment {
    static let longTaskShowDelay: UInt64 = 400_000_000

    /// 작업을 시작한다. 돌려받은 id로 진행률을 갱신하고 끝낸다. 나중에 시작한 작업이 자리를 차지한다.
    @discardableResult
    func beginLongTask(_ title: String, detail: String = "", fraction: Double? = 0,
                       showAfter delay: UInt64 = longTaskShowDelay) -> UUID {
        let id = UUID()
        longTask = LongTaskProgress(id: id, title: title, detail: detail, fraction: fraction)
        guard !Self.isRunningSelfTests else { return id }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, self.longTask?.id == id else { return }
            self.longTask?.isVisible = true
        }
        return id
    }

    func updateLongTask(_ id: UUID, fraction: Double?, detail: String? = nil) {
        guard longTask?.id == id else { return }
        longTask?.fraction = fraction
        if let detail { longTask?.detail = detail }
    }

    /// 끝난 작업만 닫는다. 그사이 다른 작업이 자리를 차지했으면 그대로 둔다.
    func endLongTask(_ id: UUID) {
        guard longTask?.id == id else { return }
        longTask = nil
    }

    /// 백그라운드에서 쓸 보고 창구.
    func longTaskReporter(_ id: UUID) -> LongTaskReporter {
        LongTaskReporter { [weak self] fraction, detail in
            Task { @MainActor in self?.updateLongTask(id, fraction: fraction, detail: detail) }
        }
    }
}

/// 진행률 팝업. 떠 있는 동안 아래 화면을 누를 수 없다 — 계산 중인 상태를 건드리면 결과가 어긋난다.
struct LongTaskOverlay: View {
    let task: LongTaskProgress

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title).font(.headline)
                if let fraction = task.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(task.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))%").font(.caption.monospacedDigit())
                    }
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text(task.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title) 진행 중")
    }
}
