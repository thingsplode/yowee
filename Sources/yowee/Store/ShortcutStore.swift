import Foundation

/// Persists both keyboard shortcuts to ~/.config/yowee/shortcuts.json.
/// Replaces the old UserDefaults-based HotKey persistence.
@Observable
@MainActor
final class ShortcutStore {
    var yoweeTrigger: HotKey = .defaultYoweeTrigger
    var voiceTrigger: HotKey = .defaultVoiceTrigger
    var voiceStopTrigger: HotKey = .defaultVoiceStopTrigger
    var voiceCancelTrigger: HotKey = .defaultVoiceCancelTrigger

    private static var shortcutsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/yowee/shortcuts.json")
    }

    func load() {
        let fm = FileManager.default

        // Migrate from legacy UserDefaults if shortcuts.json doesn't exist yet.
        if !fm.fileExists(atPath: Self.shortcutsURL.path) {
            let legacy = HotKey.loadLegacy()
            if let saved = legacy { yoweeTrigger = saved }
            voiceTrigger = .defaultVoiceTrigger
            save()
            return
        }

        do {
            let data = try Data(contentsOf: Self.shortcutsURL)
            let record = try JSONDecoder().decode(ShortcutRecord.self, from: data)
            yoweeTrigger = record.yoweeTrigger
            voiceTrigger = record.voiceTrigger
            voiceStopTrigger = record.voiceStopTrigger
            voiceCancelTrigger = record.voiceCancelTrigger
        } catch {
            // Corrupt file — back it up, then persist current defaults so next launch is clean.
            AppLogger.log("shortcuts load failed (\(error)) — backing up corrupt file", category: "ShortcutStore")
            let stamp = backupTimestamp()
            let backup = Self.shortcutsURL.deletingLastPathComponent()
                .appendingPathComponent("shortcuts.json.backup-\(stamp)")
            try? fm.copyItem(at: Self.shortcutsURL, to: backup)
            // Property initializers already set sensible defaults; just persist them.
            save()
        }
    }

    func save() {
        let record = ShortcutRecord(
            yoweeTrigger: yoweeTrigger,
            voiceTrigger: voiceTrigger,
            voiceStopTrigger: voiceStopTrigger,
            voiceCancelTrigger: voiceCancelTrigger
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(record)
            try data.write(to: Self.shortcutsURL, options: .atomic)
        } catch {
            AppLogger.log("shortcuts save failed: \(error)", category: "ShortcutStore")
        }
        NotificationCenter.default.post(name: .yoweeShortcutsChanged, object: nil)
    }

    private func backupTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: Date())
    }
}

private struct ShortcutRecord: Codable {
    let yoweeTrigger: HotKey
    let voiceTrigger: HotKey
    let voiceStopTrigger: HotKey
    let voiceCancelTrigger: HotKey

    /// Custom decoder: new fields default gracefully so existing JSON files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yoweeTrigger = try c.decode(HotKey.self, forKey: .yoweeTrigger)
        voiceTrigger = try c.decode(HotKey.self, forKey: .voiceTrigger)
        voiceStopTrigger = (try? c.decode(HotKey.self, forKey: .voiceStopTrigger)) ?? .defaultVoiceStopTrigger
        voiceCancelTrigger = (try? c.decode(HotKey.self, forKey: .voiceCancelTrigger)) ?? .defaultVoiceCancelTrigger
    }

    init(yoweeTrigger: HotKey, voiceTrigger: HotKey, voiceStopTrigger: HotKey, voiceCancelTrigger: HotKey) {
        self.yoweeTrigger = yoweeTrigger
        self.voiceTrigger = voiceTrigger
        self.voiceStopTrigger = voiceStopTrigger
        self.voiceCancelTrigger = voiceCancelTrigger
    }
}

extension NSNotification.Name {
    static let yoweeShortcutsChanged = NSNotification.Name("YoweeShortcutsChanged")
}
