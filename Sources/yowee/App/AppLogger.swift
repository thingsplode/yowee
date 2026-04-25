import Foundation
import os

/// Centralised logger for the Yowee app.
///
/// Writes every message to two sinks:
///   1. OSLog unified log (Console.app, crash reporters, `log stream`; thread-safe; zero-overhead
///      when not capturing; persistent across reboots).
///   2. /tmp/yowee_debug.log for the in-app LogView tab (async, serialised to a background queue
///      so concurrent callers never interleave mid-line).
enum AppLogger {
    private static let subsystem = "com.yowee.app"

    // One Logger per category, allocated once.
    private static let loggers: [String: Logger] = Dictionary(uniqueKeysWithValues:
        ["Voice", "Whisper", "Orchestrator", "TextReplacer",
         "ErrorBanner", "AudioRecorder", "StatusBar"]
            .map { ($0, Logger(subsystem: subsystem, category: $0)) }
    )

    // Serial queue: all file writes happen here in arrival order, never concurrently.
    private static let fileQueue = DispatchQueue(label: "com.yowee.app.logger", qos: .utility)
    static let logFileURL = URL(fileURLWithPath: "/tmp/yowee_debug.log")

    /// Write `message` tagged with `category` to both sinks.
    static func log(_ message: String, category: String) {
        let logger = loggers[category] ?? Logger(subsystem: subsystem, category: category)
        logger.debug("\(message, privacy: .public)")

        let line = "[\(category)] \(message)\n"
        fileQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if fm.fileExists(atPath: logFileURL.path),
               let fh = try? FileHandle(forWritingTo: logFileURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
