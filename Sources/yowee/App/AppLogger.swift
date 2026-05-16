import Foundation
import os

/// Centralised logger for the Yowee app.
///
/// Writes every message to two sinks:
///   1. OSLog unified log (Console.app, crash reporters, `log stream`).
///   2. A file in ~/Library/Logs/yowee/ for the in-app LogView tab.
///
/// File writes are serialised inside a Swift actor so concurrent callers never
/// interleave mid-line. The FileHandle stays open for the app lifetime (closed in
/// applicationWillTerminate via `AppLogger.close()`). The file is rotated at 5 MB,
/// keeping one backup (.bak).
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

    private static let loggers: [String: Logger] = Dictionary(uniqueKeysWithValues:
        ["Voice", "Whisper", "Orchestrator", "Runner", "TextReplacer", "ErrorBanner",
         "AudioRecorder", "StatusBar", "PipelineStore", "ShortcutStore", "AXReader"]
            .map { ($0, Logger(subsystem: subsystem, category: $0)) }
    )

    static var logFileURL: URL {
        let logs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/yowee")
        return logs.appendingPathComponent("yowee.log")
    }

    private static let writer = LogWriter(url: logFileURL)

    // MARK: - Public API

    static func log(_ message: String, category: String, level: LogLevel = .debug) {
        let logger = loggers[category] ?? Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug:   logger.debug("\(message, privacy: .public)")
        case .info:    logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error:   logger.error("\(message, privacy: .public)")
        }
        // Capture timestamp before the actor hop — Date() is thread-safe.
        // Formatting happens inside the actor (serialised) to avoid racing on DateFormatter.
        let now = Date()
        Task { await writer.write(message, category: category, level: level, at: now) }
    }

    /// Call from applicationWillTerminate to flush and close the log file cleanly.
    static func close() {
        Task { await writer.close() }
    }
}

// MARK: - Actor

private actor LogWriter {
    private let url: URL
    private var handle: FileHandle?

    // DateFormatter is not thread-safe; using it exclusively inside the actor is safe.
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let maxBytes: UInt64 = 5 * 1024 * 1024  // 5 MB

    init(url: URL) {
        self.url = url
        // Inline the open logic — cannot call actor-isolated methods from init.
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }

    func write(_ message: String, category: String, level: AppLogger.LogLevel, at date: Date) {
        rotateIfNeeded()
        let timestamp = formatter.string(from: date)
        let line = "\(timestamp) [\(level.tag)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        handle?.write(data)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    // MARK: - Private

    private func openHandle() {
        let fm = FileManager.default
        // Create the log directory if it doesn't exist yet.
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size >= Self.maxBytes
        else { return }

        try? handle?.close()
        handle = nil

        let bak = url.deletingPathExtension().appendingPathExtension("bak")
        let fm = FileManager.default
        try? fm.removeItem(at: bak)
        try? fm.moveItem(at: url, to: bak)

        openHandle()
    }
}
