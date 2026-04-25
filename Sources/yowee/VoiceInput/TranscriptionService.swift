import Foundation

/// Protocol for speech-to-text transcription, enabling injection of mocks in tests.
@MainActor
protocol TranscriptionService: AnyObject {
    /// 0–1 while the model is downloading; nil when idle or transcribing.
    var modelDownloadProgress: Double? { get }
    func transcribe(audioURL: URL) async throws -> String
    func warmUp()
}

/// Production implementation that delegates to the shared WhisperTranscriber actor.
@MainActor
final class WhisperTranscriptionService: TranscriptionService {
    static let shared = WhisperTranscriptionService()
    private init() {}

    var modelDownloadProgress: Double? {
        WhisperTranscriber.shared.downloadProgress
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await WhisperTranscriber.shared.transcribe(audioURL: audioURL)
    }

    func warmUp() {
        Task { await WhisperTranscriber.shared.warmUp() }
    }
}
