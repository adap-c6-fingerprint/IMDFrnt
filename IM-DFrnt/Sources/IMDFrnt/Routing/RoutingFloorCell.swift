import AppKit
import SwiftUI

/// A full-cell click target with a native, explicitly red deletion menu.
struct RoutingFloorCell: NSViewRepresentable {
    let floor: RoutingFloor
    let nodeCount: Int
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onDelete: @MainActor () -> Void
    let onMenuTracking: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> CellView {
        let view = CellView(rootView: label)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CellView, context: Context) {
        view.rootView = label
        view.cellLabel = "\(floor.name), 노드 \(nodeCount)개 · \(floor.svg.isEmpty ? "도면 없음" : floor.sourceName)"
        view.onSelect = onSelect
        view.onDelete = onDelete
        view.onMenuTracking = onMenuTracking
    }

    private var label: CellLabel {
        CellLabel(name: floor.name,
                  detail: "노드 \(nodeCount)개 · \(floor.svg.isEmpty ? "도면 없음" : floor.sourceName)",
                  isSelected: isSelected)
    }

    struct CellLabel: View {
        let name: String
        let detail: String
        let isSelected: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.semibold))
                Text(detail).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }

    final class CellView: NSHostingView<CellLabel> {
        var cellLabel = ""
        var onSelect: (@MainActor () -> Void)?
        var onDelete: (@MainActor () -> Void)?
        var onMenuTracking: (@MainActor (Bool) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
            else {
                window?.makeFirstResponder(nil)
                onSelect?()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onMenuTracking?(true)
            defer { onMenuTracking?(false) }
            NSMenu.popUpContextMenu(deletionMenu(), with: event, for: self)
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { cellLabel }
        override func accessibilityChildren() -> [Any]? { [] }
        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            [NSAccessibilityCustomAction(name: "층 메뉴", target: self, selector: #selector(showFloorMenu))]
        }

        override func accessibilityPerformPress() -> Bool {
            window?.makeFirstResponder(nil)
            onSelect?()
            return true
        }

        override func accessibilityPerformShowMenu() -> Bool {
            Task { @MainActor [weak self] in
                guard let self else { return }
                onMenuTracking?(true)
                defer { onMenuTracking?(false) }
                deletionMenu().popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
            }
            return true
        }

        @objc private func showFloorMenu() -> Bool { accessibilityPerformShowMenu() }

        private func deletionMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let title = "층 삭제"
            let item = NSMenuItem(title: title, action: #selector(deleteFloor), keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: title)?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            item.target = self
            item.isEnabled = onDelete != nil
            menu.addItem(item)
            return menu
        }

        @objc private func deleteFloor() { onDelete?() }
    }
}
