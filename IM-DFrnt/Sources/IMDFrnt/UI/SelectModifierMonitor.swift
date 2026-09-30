import AppKit
import Foundation

/// `fn+shift+z`(명세 5항) 눌림 상태를 전역으로 추적한다.
/// macOS에서 fn은 `NSEvent.ModifierFlags.function`으로 잡힌다.
///
/// 주의: 문자키 `z`를 길게 누르면 auto-repeat이 발생하므로 `isARepeat`을 걸러야 한다.
/// 또 fn 키는 시스템 설정(받아쓰기·이모지 등)에 선점될 수 있어,
/// UI에 대체 토글(`AppEnvironment.forceSelectMode`)을 함께 둔다.
final class SelectModifierMonitor {

    static let zKeyCode: UInt16 = 6

    private var monitor: Any?
    private var flagsDown = false
    private var zDown = false
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .flagsChanged:
                let f = event.modifierFlags
                self.flagsDown = f.contains(.function) && f.contains(.shift)
                if !self.flagsDown { self.zDown = false }
                self.publish()
                return event

            case .keyDown where event.keyCode == Self.zKeyCode:
                if event.isARepeat { return nil }
                // auto-repeat 이벤트는 유지 구간 판정에서 무시한다.
                if self.flagsDown {
                    self.zDown = true
                    self.publish()
                    return nil
                    // 시스템 경고음을 막기 위해 이벤트를 소비한다.
                }
                return event

            case .keyUp where event.keyCode == Self.zKeyCode:
                if self.zDown {
                    self.zDown = false
                    self.publish()
                    return nil
                }
                return event

            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func publish() {
        onChange(flagsDown && zDown)
    }
}
