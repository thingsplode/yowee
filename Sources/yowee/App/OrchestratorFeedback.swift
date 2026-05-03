import AppKit

/// Abstracts the UI feedback channel for pipeline processing.
/// Injecting this protocol allows unit tests to verify orchestrator logic
/// without spinning up real NSPanel instances.
@MainActor
protocol OrchestratorFeedback: AnyObject {
    func showProcessing(near point: NSPoint)
    func hideProcessing()
    func showError(_ message: String)
}

/// Production implementation backed by LoadingHUD and ErrorBanner.
@MainActor
final class DefaultOrchestratorFeedback: OrchestratorFeedback {
    private let hud = LoadingHUD()
    // Retain the trigger point so errors anchor near where the user initiated the action,
    // not wherever the cursor drifted during the async pipeline run.
    private var triggerPoint: NSPoint = .zero

    func showProcessing(near point: NSPoint) {
        triggerPoint = point
        hud.show(near: point)
    }

    func hideProcessing() {
        hud.hide()
    }

    func showError(_ message: String) {
        let point = triggerPoint != .zero ? triggerPoint : NSEvent.mouseLocation
        ErrorBanner.show(message: message, near: point)
    }
}
