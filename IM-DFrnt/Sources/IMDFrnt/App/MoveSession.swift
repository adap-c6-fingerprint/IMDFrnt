import CoreGraphics
import SwiftUI

/// 드래그 중의 개체 이동량만 담는 관찰 객체(`07) 성능 최적화 제안.md` 제안 4).
///
/// 이전에는 `AppEnvironment`의 `@Published var transientOffsets`였다. 그러면 개체를 1픽셀
/// 옮길 때마다 **그 환경을 보는 모든 화면**(좌·우 사이드바의 feature 목록·진행률·좌표 표까지)이
/// 다시 계산된다. 드래그와 아무 상관이 없는 화면들이다.
///
/// 이 객체를 `AppEnvironment`에 **`@Published`가 아닌 `let`으로** 들고, 캔버스와 상단바만
/// `@EnvironmentObject`로 구독한다. `@Published`로 두면 이 객체가 바뀔 때마다
/// `AppEnvironment`도 알림을 보내 분리한 의미가 사라진다.
@MainActor
final class MoveSession: ObservableObject {

    @Published private(set) var offsets: [VectorObjectID: CGSize] = [:]

    /// 이동 드래그 중인가.
    @Published private(set) var isMoving = false

    /// 드래그가 **끝났을 때만** 불린다. 메뉴('모든 개체 원위치')처럼 `AppEnvironment`만 보는
    /// 화면이 이동 결과를 알아야 하기 때문이다. 드래그 중에 부르면 프레임마다 환경 전체가
    /// 다시 그려져, 이 객체를 떼어낸 의미가 사라진다.
    var onSettled: (() -> Void)?

    func offset(for id: VectorObjectID) -> CGSize { offsets[id] ?? .zero }

    var hasAny: Bool { !offsets.isEmpty }

    /// 이동 시작 시점의 오프셋 스냅샷. 프레임마다 여기에 델타만 더해
    /// 반복 합산으로 인한 오차를 막는다(2026-08-25 이동 재도입과 같은 규칙).
    func begin(_ ids: Set<VectorObjectID>) -> [VectorObjectID: CGSize] {
        isMoving = true
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, offset(for: $0)) })
    }

    func apply(_ delta: CGSize, from base: [VectorObjectID: CGSize]) {
        for (id, start) in base {
            offsets[id] = CGSize(width: start.width + delta.width,
                                 height: start.height + delta.height)
        }
    }

    func end() {
        isMoving = false
        onSettled?()
    }

    /// 상단바 '원위치'(선택분) / `도구` 메뉴 '모든 개체 원위치'.
    func reset(_ ids: Set<VectorObjectID>?) {
        isMoving = false
        defer { onSettled?() }
        guard let ids else { offsets.removeAll(); return }
        for id in ids { offsets.removeValue(forKey: id) }
    }
}
