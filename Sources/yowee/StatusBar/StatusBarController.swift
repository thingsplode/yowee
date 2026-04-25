import Cocoa
import YoweeCore

/// Bridges an AppKit menu item action (ObjC selector dispatch) to a Swift closure.
/// Using a dedicated NSObject target removes any uncertainty about @MainActor
/// class dispatch when AppKit calls performSelector: on the menu item target.
final class MenuItemProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func fire(_ sender: Any?) {
        action()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let store: PipelineStore
    private let shortcuts: ShortcutStore
    private var settingsWindowController: PreferencesWindowController?
    private var configProxy: MenuItemProxy?

    deinit {
        AppLogger.log("WARNING: StatusBarController deinit — controller was deallocated!", category: "StatusBar")
    }

    init(store: PipelineStore, shortcuts: ShortcutStore) {
        self.store = store
        self.shortcuts = shortcuts
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.isVisible = true
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: "yowee") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⟡"
            }
        }

        buildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pipelinesChanged),
            name: .yoweePipelinesChanged,
            object: nil
        )
    }

    func buildMenu() {
        let menu = NSMenu()

        let pipelines = store.sortedPipelines
        if pipelines.isEmpty {
            let empty = NSMenuItem(title: "No pipelines configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Pipelines  (⌥Space)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for pipeline in pipelines {
                let item = NSMenuItem(title: pipeline.name, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let proxy = MenuItemProxy { [weak self] in
            Task { @MainActor in self?.openSettings() }
        }
        configProxy = proxy
        let config = NSMenuItem(title: "Configure yowee…", action: #selector(MenuItemProxy.fire(_:)), keyEquivalent: ",")
        config.target = proxy
        config.isEnabled = true
        config.keyEquivalentModifierMask = .command
        menu.addItem(config)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit yowee", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func pipelinesChanged() {
        buildMenu()
    }

    @objc private func openSettings() {
        AppLogger.log("openSettings called, existing controller: \(settingsWindowController != nil)", category: "StatusBar")
        if settingsWindowController == nil {
            let prefsController = PreferencesWindowController(store: store, shortcuts: shortcuts)
            settingsWindowController = prefsController
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: prefsController.window
            )
            AppLogger.log("settings window created", category: "StatusBar")
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.log("window shown, visible: \(settingsWindowController?.window?.isVisible ?? false)", category: "StatusBar")
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

extension NSNotification.Name {
    static let yoweePipelinesChanged = NSNotification.Name("YoweePipelinesChanged")
}
