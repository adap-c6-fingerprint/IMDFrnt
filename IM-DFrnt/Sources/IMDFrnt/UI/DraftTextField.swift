import SwiftUI

/// 입력 중인 글자. 저장된 값과 따로 들고 있다가 잠깐 멈추거나 확정할 때 한 번에 저장한다(2026-10-19 name 입력 렉).
///
/// 예전에는 글자 하나(한글은 자모 하나)마다 feature를 저장했고, 저장할 때마다 캔버스·좌우 패널이 통째로 다시 그려져
/// 포스텍 도서관에서 한 글자에 약 38 ms가 들었다. 이제 입력 중에는 이 칸만 바뀐다.
/// 예: "사무실"을 치면 입력 중에는 칸만 바뀌고, 0.4초 멈추거나 Return·다른 칸으로 옮기기·창 닫기 때 한 번 저장한다.
struct TextDraft: Equatable {
    /// 입력 중인 글자. nil이면 저장된 값을 그대로 보인다.
    var text: String?

    func shown(_ saved: String) -> String { text ?? saved }

    mutating func edit(_ s: String) { text = s }

    /// 저장할 글자. 입력 중이 아니거나 저장된 값과 같으면 nil이다.
    func pending(against saved: String) -> String? {
        guard let text, text != saved else { return nil }
        return text
    }

    /// 저장된 값이 바뀌었을 때. 입력한 글자가 저장되었으면 입력 중 상태를 끝내 이후 실행취소·다른 칸의 변경이 그대로 보이게 한다.
    mutating func savedChanged(_ saved: String) { if text == saved { text = nil } }
}

/// 속성 입력칸. 우측 패널과 이름표 편집 창이 같은 칸(`PropertySlotRow`)을 쓰므로 두 곳의 저장·실행취소가 같다.
struct DraftTextField: View {
    let placeholder: String
    let saved: String
    let commit: (String) -> Void

    /// 마지막 글자를 친 뒤 이만큼 멈추면 저장한다.
    static let settleDelay: Duration = .milliseconds(400)

    @State private var draft = TextDraft()
    @State private var settle: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: Binding(get: { draft.shown(saved) }, set: { s in
            draft.edit(s)
            settle?.cancel()
            settle = Task { @MainActor in
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                flush(ending: false)
            }
        }))
        .focused($focused)
        .onSubmit { flush(ending: true) }
        .onChange(of: focused) { _, now in if !now { flush(ending: true) } }
        .onChange(of: saved) { _, value in draft.savedChanged(value) }
        .onDisappear { flush(ending: true) }
        // 창을 닫거나 다른 이름표로 옮겨도 친 글자를 버리지 않는다.
    }

    /// 친 글자를 저장한다. `ending`이면 입력 중 상태도 끝내 저장된 값(숫자 칸이면 고쳐진 값)을 보인다.
    /// 잠깐 멈춰 저장할 때는 끝내지 않는다 — 한글을 조합하는 중에 칸의 글자를 바꾸면 조합이 깨진다.
    private func flush(ending: Bool) {
        settle?.cancel()
        settle = nil
        if let text = draft.pending(against: saved) { commit(text) }
        if ending { draft = TextDraft() }
    }
}
