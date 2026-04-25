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
        AppLogger.log("pipelines loaded from \(PipelineStore.pipelinesURL.path)", category: "Orchestrator")

        shortcuts.load()
        AppLogger.log("shortcuts loaded: yowee=\(shortcuts.yoweeTrigger.displayString) voice=\(shortcuts.voiceTrigger.displayString)", category: "Orchestrator")

        statusBarController = StatusBarController(store: store, shortcuts: shortcuts)
        orchestrator = YoweeOrchestrator(store: store)

        voiceCoordinator = VoiceInputCoordinator(store: store, shortcuts: shortcuts)
        voiceCoordinator?.setup()

        GlobalShortcutManager.shared.registerYoweeTrigger(shortcuts.yoweeTrigger)
        AccessibilityPermissionGuard.checkAndPromptIfNeeded()
        warmUpKeychain()
    }

    private func warmUpKeychain() {
        for provider in LLMProvider.allCases where provider.requiresAPIKey {
            _ = KeychainStore.load(for: provider.keychainKey)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        shortcuts.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
