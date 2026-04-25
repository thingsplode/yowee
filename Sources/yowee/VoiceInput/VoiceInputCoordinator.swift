import Cocoa
import SwiftUI
import AVFoundation
import Carbon.HIToolbox
import YoweeCore

/// Orchestrates the full voice-input flow:
///   ⌥R → record → ⌥S → transcribe → pick pipeline → ↩ → insert at cursor
@MainActor
final class VoiceInputCoordinator: NSObject {
    private let store: PipelineStore
    private let shortcuts: ShortcutStore
    private let runner = PipelineRunner()
    private let recorder: any AudioRecording
    private let transcriber: any TranscriptionService
    private let panel = VoiceRecordingPanel()

    private let sessionState = VoiceSessionState()

    private var originalApp: NSRunningApplication?
    private var currentRecordingURL: URL?

    // Tracked so they can be cancelled when the session is aborted mid-flight.
    private var transcriptionTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?

    init(store: PipelineStore, shortcuts: ShortcutStore) {
        self.store = store
        self.shortcuts = shortcuts
        self.recorder = AudioRecorder()
        self.transcriber = WhisperTranscriptionService.shared
    }

    /// Designated initialiser for tests — inject mock recorder and transcriber.
    init(
        store: PipelineStore,
        shortcuts: ShortcutStore,
        recorder: any AudioRecording,
        transcriber: any TranscriptionService
    ) {
        self.store = store
        self.shortcuts = shortcuts
        self.recorder = recorder
        self.transcriber = transcriber
    }

    // MARK: - Lifecycle

    func setup() {
        GlobalShortcutManager.shared.onVoiceStart = { [weak self] in self?.beginRecording() }
        GlobalShortcutManager.shared.onVoiceStop  = { [weak self] in self?.endRecording() }

        let stopKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))
        GlobalShortcutManager.shared.registerVoice(start: shortcuts.voiceTrigger, stop: stopKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsChanged),
            name: .yoweeShortcutsChanged,
            object: nil
        )

        transcriber.warmUp()
    }

    @objc private func shortcutsChanged() {
        GlobalShortcutManager.shared.updateVoiceStart(shortcuts.voiceTrigger)
    }

    // MARK: - Recording phase

    private func beginRecording() {
        // Single source of truth: only .idle means no session is running.
        guard case .idle = sessionState.voiceState else {
            log("beginRecording: session already active (\(sessionState.voiceState)), ignoring")
            return
        }
        log("beginRecording: starting")

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        log("beginRecording: mic status = \(status.rawValue)")

        if status == .authorized {
            // Synchronous path avoids the race where ⌥S fires before the async Task
            // has a chance to set a non-idle voiceState.
            startRecordingSession()
        } else if status == .notDetermined {
            Task {
                guard await AudioRecorder.requestAccess() else {
                    log("beginRecording: mic permission denied")
                    ErrorBanner.show(message: "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.")
                    return
                }
                startRecordingSession()
            }
        } else {
            log("beginRecording: mic permission denied (status \(status.rawValue))")
            ErrorBanner.show(message: "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.")
        }
    }

    private func startRecordingSession() {
        originalApp = NSWorkspace.shared.frontmostApplication
        sessionState.voiceState = .recording
        sessionState.audioLevel = 0
        sessionState.selectedPipelineID = nil
        sessionState.loadingProgress = nil
        currentRecordingURL = nil

        let cursorPoint = NSEvent.mouseLocation
        log("startRecordingSession: cursorPoint=\(cursorPoint)")

        // Level polling loop — exits automatically when voiceState leaves .recording.
        Task {
            while case .recording = sessionState.voiceState {
                sessionState.audioLevel = recorder.audioLevel
                try? await Task.sleep(nanoseconds: 50_000_000)  // 20 Hz
            }
        }

        do {
            currentRecordingURL = try recorder.startRecording()
            log("startRecordingSession: recorder started, url=\(currentRecordingURL?.lastPathComponent ?? "nil")")
        } catch {
            log("startRecordingSession: recorder start failed: \(error)")
            finish(error: "Could not start microphone: \(error.localizedDescription)")
            return
        }

        panel.show(
            near: cursorPoint,
            session: sessionState,
            pipelines: store.sortedPipelines,
            onCancel: { [weak self] in self?.cancel() },
            onConfirm: { [weak self] in self?.confirmSelection() }
        )
        log("startRecordingSession: panel shown")
    }

    private func endRecording() {
        log("endRecording: voiceState=\(sessionState.voiceState)")
        guard case .recording = sessionState.voiceState else {
            log("endRecording: guard failed — not recording")
            return
        }
        guard let audioURL = recorder.stopRecording() else {
            log("endRecording: stopRecording returned nil")
            finish(error: "Recording produced no audio.")
            return
        }
        log("endRecording: audio at \(audioURL.lastPathComponent)")
        currentRecordingURL = audioURL
        beginTranscription(audioURL: audioURL)
    }

    // MARK: - Transcription phase

    private func beginTranscription(audioURL: URL) {
        let dp = transcriber.modelDownloadProgress
        sessionState.voiceState = dp != nil ? .modelLoading : .transcribing
        sessionState.loadingProgress = dp
        log("beginTranscription: initial state=\(sessionState.voiceState)")
        panel.reflow()

        transcriptionTask = Task {
            // Poll transcriber.modelDownloadProgress at 10 Hz and keep the voice state
            // and progress bar in sync while the model downloads / loads into memory.
            let poller = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    let dp = transcriber.modelDownloadProgress
                    if let dp {
                        if case .transcribing = sessionState.voiceState {
                            sessionState.voiceState = .modelLoading
                            panel.reflow()
                        }
                        sessionState.loadingProgress = dp
                    } else {
                        if case .modelLoading = sessionState.voiceState {
                            sessionState.voiceState = .transcribing
                            sessionState.loadingProgress = nil
                            panel.reflow()
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 10 Hz
                }
            }

            do {
                log("beginTranscription: calling transcribe()")
                let text = try await transcriber.transcribe(audioURL: audioURL)
                poller.cancel()
                sessionState.loadingProgress = nil
                log("beginTranscription: transcribed \(text.count) chars: \"\(text.prefix(80))\"")
                recorder.cleanUp(url: audioURL)
                currentRecordingURL = nil
                guard !text.isEmpty else {
                    log("beginTranscription: empty transcription")
                    finish(error: "No speech detected — try speaking more clearly.")
                    return
                }
                if !Task.isCancelled { handleTranscription(text) }
            } catch {
                poller.cancel()
                sessionState.loadingProgress = nil
                log("beginTranscription: transcription error: \(error)")
                if !Task.isCancelled { finish(error: friendlyTranscriptionError(error)) }
            }
        }
    }

    // MARK: - Pipeline selection phase

    private func handleTranscription(_ text: String) {
        guard sessionState.voiceState != .idle else {
            log("handleTranscription: session cancelled, discarding result")
            return
        }
        log("handleTranscription: showing picker for \"\(text.prefix(60))\"")
        sessionState.voiceState = .pipelineSelection(transcribedText: text)
        panel.reflow()
        panel.activateForSelection()
    }

    private func confirmSelection() {
        guard sessionState.voiceState != .idle else { return }
        log("confirmSelection: pipelineID=\(sessionState.selectedPipelineID?.uuidString ?? "none")")
        if let pipelineID = sessionState.selectedPipelineID,
           let pipeline = store.pipelines.first(where: { $0.id == pipelineID }) {
            runPipeline(pipeline, input: transcribedText())
        } else {
            insertText(transcribedText())
        }
    }

    // Extract the transcribed text from the current voiceState.
    private func transcribedText() -> String {
        if case .pipelineSelection(let text) = sessionState.voiceState { return text }
        return ""
    }

    // MARK: - Pipeline / insertion phase

    private func runPipeline(_ pipeline: Pipeline, input: String) {
        log("runPipeline: \(pipeline.name)")
        sessionState.voiceState = .processingPipeline(name: pipeline.name)
        panel.reflow()

        let steps = pipeline.sortedSteps.map(StepData.init)
        pipelineTask = Task {
            do {
                let result = try await runner.run(steps: steps, input: input)
                if !Task.isCancelled { insertText(result) }
            } catch {
                if !Task.isCancelled { finish(error: error.localizedDescription) }
            }
        }
    }

    private func insertText(_ text: String) {
        guard sessionState.voiceState != .idle else {
            log("insertText: skipped — session already idle")
            return
        }
        log("insertText: \(text.count) chars, activating \(originalApp?.localizedName ?? "nil")")
        sessionState.voiceState = .idle
        panel.dismiss()
        originalApp?.activate(options: [.activateIgnoringOtherApps])
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            // Shared implementation — same clipboard-save/restore + CGEvent path as the
            // text-pipeline fallback in TextReplacer. Avoids a duplicate code path.
            TextReplacer.pasteViaCmdV(text)
        }
    }

    // MARK: - Error / cancel

    private func finish(error message: String) {
        guard sessionState.voiceState != .idle else { return }
        log("finish(error:): \(message)")
        sessionState.voiceState = .error(message)
        panel.reflow()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            // Auto-dismiss only if still showing the error (user may have cancelled already).
            if case .error = sessionState.voiceState { cancel() }
        }
    }

    private func cancel() {
        guard sessionState.voiceState != .idle else { return }
        log("cancel: dismissing panel")

        transcriptionTask?.cancel()
        transcriptionTask = nil
        pipelineTask?.cancel()
        pipelineTask = nil

        sessionState.voiceState = .idle
        _ = recorder.stopRecording()
        if let url = currentRecordingURL { recorder.cleanUp(url: url) }
        currentRecordingURL = nil
        panel.dismiss()
        originalApp?.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - Error helpers

    private func friendlyTranscriptionError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.contains("modelsUnavailable") || raw.contains("Model not found") {
            return "Speech model could not be loaded. Check your internet connection and try again."
        }
        if raw.contains("modelNotLoaded") {
            return "Speech model is not ready yet. Please wait a moment and try again."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("URLError") {
            return "Network error while loading speech model. Check your connection and try again."
        }
        if let firstSentence = raw.split(separator: "\n").first.map(String.init),
           !firstSentence.contains("(\"") {
            return "Transcription failed: \(firstSentence)"
        }
        return "Transcription failed. Please try again."
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        AppLogger.log(msg, category: "Voice")
    }
}
