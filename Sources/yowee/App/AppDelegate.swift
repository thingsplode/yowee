import Cocoa
import YoweeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = PipelineStore()
    let shortcuts = ShortcutStore()
    private var statusBarController: StatusBarController?
    private var orchestrator: YoweeOrchestrator?
    private var voiceCoordinator: VoiceInputCoordinator?

    override init() {
        super.init()
        AppLogger.log("AppDelegate.init() complete", category: "Orchestrator")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.log("applicationDidFinishLaunching", category: "Orchestrator")
        NSApp.setActivationPolicy(.accessory)

        store.load()

        shortcuts.load()
        AppLogger.log(
            "shortcuts loaded: yowee=\(shortcuts.yoweeTrigger.displayString) voice=\(shortcuts.voiceTrigger.displayString)",
            category: "Orchestrator"
        )

        statusBarController = StatusBarController(store: store, shortcuts: shortcuts)
        orchestrator = YoweeOrchestrator(store: store)

        voiceCoordinator = VoiceInputCoordinator(store: store, shortcuts: shortcuts)
        voiceCoordinator?.setup()

        GlobalShortcutManager.shared.registerYoweeTrigger(shortcuts.yoweeTrigger)
        AccessibilityPermissionGuard.checkAndPromptIfNeeded()
        warmUpKeychain()
    }

    private func warmUpKeychain() {
        // Run on a background task so the security daemon round-trip doesn't stall launch.
        Task.detached(priority: .background) {
            for provider in LLMProvider.allCases where provider.requiresAPIKey {
                _ = KeychainStore.load(for: provider.keychainKey)
            }
            _ = KeychainStore.load(for: Credentials.tavilyKeychainKey)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        shortcuts.save()
        AppLogger.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
