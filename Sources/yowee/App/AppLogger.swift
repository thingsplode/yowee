import Foundation
import os

/// Centralised logger for the Yowee app.
///
/// Writes every message to two sinks:
///   1. OSLog unified log (Console.app, crash reporters, `log stream`; thread-safe; zero-overhead
///      when not capturing; persistent across reboots).
///   2. /tmp/yowee_debug.log for the in-app LogView tab (async, serialised via a Swift actor
///      so concurrent callers never interleave mid-line).
enum AppLogger {
    enum LogLevel {
        case debug, info, warning, error

        fileprivate var tag: String {
            switch self {
            case .debug: "DEBG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERRR"
            }
        }
    }

    private static let subsystem = "com.yowee.app"

    /// One Logger per category, allocated once.
    private static let loggers: [String: Logger] = Dictionary(uniqueKeysWithValues:
        [
            "Voice",
            "Whisper",
            "Orchestrator",
            "Runner",
            "TextReplacer",
            "ErrorBanner",
            "AudioRecorder",
            "StatusBar",
        ]
        .map { ($0, Logger(subsystem: subsystem, category: $0)) }
    )

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static let logFileURL = URL(fileURLWithPath: "/tmp/yowee_debug.log")

    /// Actor serialises all file writes — equivalent to a serial DispatchQueue but
    /// expressed in Swift structured concurrency, avoiding raw thread primitives.
    private actor LogWriter {
        private let url: URL
        init(url: URL) {
            self.url = url
        }

        func write(_ line: String) {
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path),
               let fh = try? FileHandle(forWritingTo: url)
            {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static let writer = LogWriter(url: logFileURL)

    /// Write `message` tagged with `category` and `level` to both sinks.
    static func log(_ message: String, category: String, level: LogLevel = .debug) {
        let logger = loggers[category] ?? Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }

        let timestamp = timestampFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.tag)] [\(category)] \(message)\n"
        Task {
            await writer.write(line)
        }
    }
}
