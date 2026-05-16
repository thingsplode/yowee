import Cocoa
import YoweeCore

/// Wires together the shortcut trigger, pipeline picker, runner, and text replacement.
@MainActor
final class YoweeOrchestrator {
    private let store: PipelineStore
    private let runner = PipelineRunner(log: { AppLogger.log($0, category: "Runner") })
    private let feedback: any OrchestratorFeedback
    private let flowMenu = YoweeMenu()

    /// Tracked to prevent re-entrant triggers and to support future cancellation.
    private var pipelineTask: Task<Void, Never>?

    init(store: PipelineStore) {
        self.store = store
        feedback = DefaultOrchestratorFeedback()
        GlobalShortcutManager.shared.onTrigger = { [weak self] in
            self?.handleTrigger()
        }
    }

    /// Designated initialiser for tests — inject a custom feedback implementation.
    init(store: PipelineStore, feedback: any OrchestratorFeedback) {
        self.store = store
        self.feedback = feedback
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
            let msg = "yowee needs Accessibility permission. Go to System Settings → Privacy & Security → Accessibility, find yowee, and toggle it on (or off then on again if already listed)."
            log("FAIL: not trusted — \(msg)")
            feedback.showError(msg)
            return
        }
        log("accessibility trusted")

        let originalApp = NSWorkspace.shared.frontmostApplication
        log("original app: \(originalApp?.localizedName ?? "unknown")")

        // Read selected text synchronously before starting the task — the AX selection
        // window is very short in some apps (e.g. Slack) and an extra run-loop hop loses it.
        guard let (text, element, selectionRange) = AccessibilityReader.selectedText() else {
            log("FAIL: no selected text")
            feedback.showError("No text selected — select some text first.")
            return
        }
        log("got text (\(text.count) chars, range loc=\(selectionRange.location) len=\(selectionRange.length))")

        let pipelines = store.sortedPipelines
        guard !pipelines.isEmpty else {
            feedback.showError("No pipelines configured. Open Configure yowee… to add one.")
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

        let credentials = Credentials.load()
        let steps = pipeline.sortedSteps.map { StepData(from: $0, credentials: credentials) }
        feedback.showProcessing(near: cursorPoint)

        pipelineTask = Task {
            // The Task inherits @MainActor from the enclosing scope, so clearing
            // pipelineTask in defer is safe — it runs on the main actor when the Task body exits.
            defer { self.pipelineTask = nil }
            do {
                let result = try await runner.run(steps: steps, input: text)
                log("pipeline result: \(result.prefix(80))…")
                // Task body already runs on @MainActor (inherited from enclosing scope).
                // MainActor.run {} hops are redundant — call directly.
                feedback.hideProcessing()
                originalApp?.activate(options: [.activateIgnoringOtherApps])
                try? await Task.sleep(nanoseconds: 300_000_000)
                TextReplacer.replace(in: element, range: selectionRange, with: result)
                log("replace done")
            } catch {
                feedback.hideProcessing()
                feedback.showError(error.localizedDescription)
                log("pipeline error: \(error)")
            }
        }
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        AppLogger.log(msg, category: "Orchestrator")
    }
}
