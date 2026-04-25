import Cocoa

/// Shows a floating pipeline picker at the cursor position.
/// Uses NSMenu.popUp (synchronous modal loop) — returns the selected pipeline's UUID or nil.
@MainActor
final class YoweeMenu: NSObject {
    private var selectedID: UUID?

    /// Displays the pipeline picker near `point` (screen coordinates).
    /// Returns the selected pipeline UUID, or nil if dismissed.
    func show(pipelines: [(id: UUID, name: String)], at point: NSPoint) -> UUID? {
        selectedID = nil

        let menu = NSMenu()
        menu.font = .systemFont(ofSize: NSFont.systemFontSize)

        let header = NSMenuItem(title: "yowee", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if pipelines.isEmpty {
            let empty = NSMenuItem(title: "No pipelines — open Configure yowee…", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for pipeline in pipelines {
                let item = NSMenuItem(
                    title: pipeline.name,
                    action: #selector(itemSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = pipeline.id.uuidString
                menu.addItem(item)
            }
        }

        // popUp runs a nested event loop; returns true if an item was selected.
        menu.popUp(positioning: nil, at: point, in: nil)
        return selectedID
    }

    @objc private func itemSelected(_ sender: NSMenuItem) {
        guard let str = sender.representedObject as? String else { return }
        selectedID = UUID(uuidString: str)
    }
}
