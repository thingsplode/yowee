import SwiftUI

// MARK: - State enum

enum VoiceState: Equatable {
    /// No session active; panel is not shown.
    case idle
    case recording
    case modelLoading                               // first-use WhisperKit download
    case transcribing
    case pipelineSelection(transcribedText: String) // waiting for pipeline choice + ↩
    case processingPipeline(name: String)
    case error(String)

    static func == (lhs: VoiceState, rhs: VoiceState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.modelLoading, .modelLoading),
             (.transcribing, .transcribing):
            return true
        case (.pipelineSelection(let a), .pipelineSelection(let b)):
            return a == b
        case (.processingPipeline(let a), .processingPipeline(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Observable state

/// Observable source of truth for the voice recording panel.
/// Owned by VoiceInputCoordinator; observed directly by VoiceRecordingView via @Bindable.
@Observable
@MainActor
final class VoiceSessionState {
    var voiceState: VoiceState = .idle
    var audioLevel: Float = 0
    var selectedPipelineID: UUID? = nil
    /// Download progress 0–1 while the speech model is downloading; nil otherwise.
    var loadingProgress: Double? = nil
}
