import WhisperKit
import Foundation
import os

/// Wraps WhisperKit with a two-phase load: download first (with real progress), then load into memory.
actor WhisperTranscriber {
    static let shared = WhisperTranscriber()

    private enum LoadState {
        case unloaded
        case loading
        case ready(WhisperKit)
    }

    private var state: LoadState = .unloaded

    // Callers that arrive while a load is in progress wait here instead of spinning.
    private var waiters: [CheckedContinuation<Void, Error>] = []

    // MARK: - Thread-safe progress

    // The WhisperKit progress callback fires on an arbitrary background thread while the
    // actor executor is suspended. OSAllocatedUnfairLock makes reads from any actor safe.
    nonisolated private let progressLock = OSAllocatedUnfairLock<Double?>(initialState: nil)

    /// 0–1 while downloading the model; nil when not downloading (cached or loading into memory).
    nonisolated var downloadProgress: Double? {
        progressLock.withLock { $0 }
    }

    // MARK: - API

    func prepare() async throws {
        switch state {
        case .ready: return
        case .loading:
            // Join the in-progress load instead of spinning independently.
            log("prepare: waiting for in-progress load")
            try await withCheckedThrowingContinuation { waiters.append($0) }
            return
        case .unloaded: break
        }

        let modelName = WhisperKit.recommendedModels().default
        log("prepare: starting — model=\(modelName)")
        state = .loading

        do {
            // Phase 1: Download (skipped when already cached). Real progress reported.
            progressLock.withLock { $0 = 0.0 }
            log("prepare: downloading")

            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { [weak self] progress in
                    self?.progressLock.withLock { $0 = progress.fractionCompleted }
                }
            )
            progressLock.withLock { $0 = nil }
            log("prepare: download done, loading into memory")

            // Phase 2: Load CoreML models into memory (takes a few seconds on first run).
            let kit = try await WhisperKit(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            state = .ready(kit)
            log("prepare: ready")

            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }

        } catch {
            progressLock.withLock { $0 = nil }
            // Reset to .unloaded so the next transcribe() call can retry (e.g. after a transient
            // network error during model download). Previously this was .failed and permanent.
            state = .unloaded
            log("prepare: failed — \(error)")

            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume(throwing: error) }

            throw error
        }
    }

    /// Transcribes audio at `url`. Calls `prepare()` first if needed.
    func transcribe(audioURL: URL) async throws -> String {
        log("transcribe: starting (\(audioURL.lastPathComponent))")
        try await prepare()
        guard case .ready(let kit) = state else {
            throw TranscriptionError.modelNotLoaded
        }
        log("transcribe: running")
        let results = try await kit.transcribe(audioPath: audioURL.path)
        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        log("transcribe: done — \(text.count) chars")
        return text
    }

    // MARK: - Warm-up

    /// Call at launch to pre-load the model so first use is instant.
    func warmUp() {
        log("warmUp: triggered")
        Task {
            do { try await prepare() }
            catch { log("warmUp: failed — \(error)") }
        }
    }

    // MARK: - Logging

    nonisolated private func log(_ msg: String) {
        AppLogger.log(msg, category: "Whisper")
    }
}

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded

    var errorDescription: String? { "Speech model failed to load." }
}
