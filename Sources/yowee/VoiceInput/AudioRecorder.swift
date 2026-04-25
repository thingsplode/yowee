import AVFoundation
import Foundation

/// Records microphone audio to a temporary M4A file.
/// Exposes `audioLevel` (0–1, normalized from dB) updated at 20 Hz.
@MainActor
final class AudioRecorder: NSObject {
    /// Normalized audio level: 0 = silence, 1 = peak.
    private(set) var audioLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var levelTimer: Timer?

    // MARK: - Permissions

    static func isAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Recording

    /// Starts recording. Returns the URL where audio will be written.
    func startRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yowee_voice_\(UUID().uuidString).m4a")

        // 16 kHz mono M4A — optimal input format for Whisper.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.record()

        recorder = rec
        outputURL = url

        // AudioRecorder is @MainActor and the Timer is scheduled on the main run loop,
        // so the closure already executes on the main thread — no Task hop needed.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLevel() }
        }

        return url
    }

    /// Stops recording and returns the URL of the completed audio file.
    /// Returns nil if recording had already been stopped.
    /// Resets the stored URL so repeated calls return nil rather than a stale path.
    func stopRecording() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
        recorder?.stop()
        recorder = nil
        defer { outputURL = nil }
        return outputURL
    }

    // MARK: - Cleanup

    /// Deletes a temporary recording file after transcription is complete.
    func cleanUp(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func updateLevel() {
        recorder?.updateMeters()
        // averagePower returns dB in [-160, 0]; map [-60, 0] → [0, 1].
        let db = recorder?.averagePower(forChannel: 0) ?? -60
        audioLevel = max(0, min(1, (db + 60) / 60))
    }
}
