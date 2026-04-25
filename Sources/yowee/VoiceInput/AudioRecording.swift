import Foundation

/// Protocol for the microphone recording interface, enabling injection of mocks in tests.
@MainActor
protocol AudioRecording: AnyObject {
    var audioLevel: Float { get }
    func startRecording() throws -> URL
    func stopRecording() -> URL?
    func cleanUp(url: URL)
}
