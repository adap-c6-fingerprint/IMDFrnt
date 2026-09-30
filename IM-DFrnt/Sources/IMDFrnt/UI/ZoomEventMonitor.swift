import AppKit
import SwiftUI

/// 스크롤휠·핀치(magnify) 이벤트를 캔버스 좌표와 함께 넘겨주는 로컬 모니터.
/// SwiftUI의 `MagnificationGesture`는 확대 중심 좌표를 주지 않아 커서 기준 확대를 만들 수 없다.
/// 그래서 `NSEvent`에서 `locationInWindow`를 직접 받는다.
/// 로컬 모니터라 입력 모니터링 권한이 필요 없고, 앱이 최전면일 때만 동작한다.
@MainActor
final class ZoomEventMonitor: ObservableObject {

    /// (캔버스 좌표계 기준 커서 위치, 배율 증분)
    var onZoom: ((CGPoint, CGFloat) -> Void)?
    /// (가로 이동량, 세로 이동량)
    var onPan: ((CGFloat, CGFloat) -> Void)?
    /// 이벤트를 받아들일 캔버스 영역. 윈도우 좌표계(좌상단 원점) 기준.
    var canvasFrame: CGRect = .zero

    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let point = canvasPoint(of: event) else { return false }

        switch event.type {
        case .magnify:
            // 핀치는 항상 확대/축소. magnification은 -1~1 범위의 증분이다.
            guard event.magnification != 0 else { return true }
            onZoom?(point, 1 + event.magnification)
            return true

        case .scrollWheel:
            let precise = event.hasPreciseScrollingDeltas
            let commandHeld = event.modifierFlags.contains(.command)

            // 트랙패드 두 손가락 스크롤은 이동, 마우스 휠은 확대가 관례다.
            // ⌘를 누르면 어느 쪽이든 확대로 통일한다.
            if precise && !commandHeld {
                guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return true }
                onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
                return true
            }

            let delta = precise ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            guard delta != 0 else { return true }
            onZoom?(point, 1 + max(-0.4, min(0.4, delta)))
            return true

        default:
            return false
        }
    }

    /// `locationInWindow`(좌하단 원점)를 SwiftUI 캔버스 좌표(좌상단 원점)로 옮긴다.
    /// 캔버스 밖에서 발생한 이벤트는 nil을 돌려 사이드바 스크롤을 막지 않는다.
    private func canvasPoint(of event: NSEvent) -> CGPoint? {
        guard canvasFrame.width > 1, canvasFrame.height > 1,
              let height = event.window?.contentView?.bounds.height else { return nil }

        let inWindow = CGPoint(x: event.locationInWindow.x,
                               y: height - event.locationInWindow.y)
        guard canvasFrame.contains(inWindow) else { return nil }

        return CGPoint(x: inWindow.x - canvasFrame.minX,
                       y: inWindow.y - canvasFrame.minY)
    }
}
