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

    func showProcessing(near point: NSPoint) {
        hud.show(near: point)
    }

    func hideProcessing() {
        hud.hide()
    }

    func showError(_ message: String) {
        ErrorBanner.show(message: message)
    }
}
