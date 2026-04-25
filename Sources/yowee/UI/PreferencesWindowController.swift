import AppKit
import SwiftUI
import YoweeCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(store: PipelineStore, shortcuts: ShortcutStore) {
        let rootView = PreferencesView()
            .environment(store)
            .environment(shortcuts)

        let hostVC = NSHostingController(rootView: rootView)
        // Prevent SwiftUI content size changes from resizing the window.
        hostVC.sizingOptions = []

        let window = NSWindow(contentViewController: hostVC)
        window.title = "Yowee Configuration"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 720, height: 480)
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
