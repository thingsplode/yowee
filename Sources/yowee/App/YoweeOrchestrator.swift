import Cocoa
import YoweeCore

/// Wires together the shortcut trigger, pipeline picker, runner, and text replacement.
@MainActor
final class YoweeOrchestrator {
    private let store: PipelineStore
    private let runner = PipelineRunner(log: { AppLogger.log($0, category: "Ollama") })
    private let loadingHUD = LoadingHUD()
    private let flowMenu = YoweeMenu()

    // Tracked to prevent re-entrant triggers and to support future cancellation.
    private var pipelineTask: Task<Void, Never>?

    init(store: PipelineStore) {
        self.store = store
        GlobalShortcutManager.shared.onTrigger = { [weak self] in
            self?.handleTrigger()
        }
    }

    private func handleTrigger() {
        // Re-entrancy guard: if a pipeline is already running, ignore the second trigger.
        // This prevents two concurrent runs racing to write to the same text element.
        guard pipelineTask == nil else {
            log("handleTrigger: pipeline already running, ignoring")
            return
        }

        log("handleTrigger fired")

        guard AccessibilityPermissionGuard.isTrusted else {
            log("FAIL: not trusted")
            ErrorBanner.show(message: "yowee needs Accessibility permission. Open Configure yowee… or check System Settings → Privacy & Security → Accessibility.")
            return
        }
        log("accessibility trusted")

        let originalApp = NSWorkspace.shared.frontmostApplication
        log("original app: \(originalApp?.localizedName ?? "unknown")")

        guard let (text, element, selectionRange) = AccessibilityReader.selectedText() else {
            log("FAIL: no selected text")
            ErrorBanner.show(message: "No text selected — select some text first.")
            return
        }
        log("got text (\(text.count) chars, range loc=\(selectionRange.location) len=\(selectionRange.length))")

        let pipelines = store.sortedPipelines
        guard !pipelines.isEmpty else {
            ErrorBanner.show(message: "No pipelines configured. Open Configure yowee… to add one.")
            return
        }

        let pipelineList = pipelines.map { (id: $0.id, name: $0.name) }
        let cursorPoint = NSEvent.mouseLocation

        NSApp.activate(ignoringOtherApps: true)

        guard let selectedID = flowMenu.show(pipelines: pipelineList, at: cursorPoint) else {
            log("menu dismissed without selection")
            originalApp?.activate(options: [])
            return
        }
        guard let pipeline = pipelines.first(where: { $0.id == selectedID }) else { return }

        let steps = pipeline.sortedSteps.map(StepData.init)
        loadingHUD.show(near: cursorPoint)

        pipelineTask = Task {
            // The Task inherits @MainActor from the enclosing scope, so clearing
            // pipelineTask in defer is safe — it runs on the main actor when the Task body exits.
            defer { self.pipelineTask = nil }
            do {
                let result = try await runner.run(steps: steps, input: text)
                log("pipeline result: \(result.prefix(80))…")
                await MainActor.run {
                    loadingHUD.hide()
                    originalApp?.activate(options: [.activateIgnoringOtherApps])
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    TextReplacer.replace(in: element, range: selectionRange, with: result)
                    log("replace done")
                }
            } catch {
                await MainActor.run {
                    loadingHUD.hide()
                    ErrorBanner.show(message: error.localizedDescription)
                    log("pipeline error: \(error)")
                }
            }
        }
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        AppLogger.log(msg, category: "Orchestrator")
    }
}
