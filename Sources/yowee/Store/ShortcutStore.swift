import Foundation

/// Persists both keyboard shortcuts to ~/.config/yowee/shortcuts.json.
/// Replaces the old UserDefaults-based HotKey persistence.
@Observable
@MainActor
final class ShortcutStore {
    var yoweeTrigger: HotKey = .defaultYoweeTrigger
    var voiceTrigger: HotKey = .defaultVoiceTrigger
    var voiceStopTrigger: HotKey = .defaultVoiceStopTrigger

    private static var shortcutsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/yowee/shortcuts.json")
    }

    func load() {
        // Migrate from legacy UserDefaults if shortcuts.json doesn't exist yet.
        if !FileManager.default.fileExists(atPath: Self.shortcutsURL.path) {
            let legacy = HotKey.loadLegacy()
            if let saved = legacy { yoweeTrigger = saved }
            voiceTrigger = .defaultVoiceTrigger
            save()
            return
        }

        guard let data = try? Data(contentsOf: Self.shortcutsURL),
              let record = try? JSONDecoder().decode(ShortcutRecord.self, from: data)
        else { return }

        yoweeTrigger = record.yoweeTrigger
        voiceTrigger = record.voiceTrigger
        voiceStopTrigger = record.voiceStopTrigger
    }

    func save() {
        let record = ShortcutRecord(yoweeTrigger: yoweeTrigger, voiceTrigger: voiceTrigger, voiceStopTrigger: voiceStopTrigger)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: Self.shortcutsURL, options: .atomic)
        NotificationCenter.default.post(name: .yoweeShortcutsChanged, object: nil)
    }
}

private struct ShortcutRecord: Codable {
    let yoweeTrigger: HotKey
    let voiceTrigger: HotKey
    let voiceStopTrigger: HotKey

    /// Custom decoder: `voiceStopTrigger` defaults to ⌥S so existing JSON files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yoweeTrigger = try c.decode(HotKey.self, forKey: .yoweeTrigger)
        voiceTrigger = try c.decode(HotKey.self, forKey: .voiceTrigger)
        voiceStopTrigger = (try? c.decode(HotKey.self, forKey: .voiceStopTrigger)) ?? .defaultVoiceStopTrigger
    }

    init(yoweeTrigger: HotKey, voiceTrigger: HotKey, voiceStopTrigger: HotKey) {
        self.yoweeTrigger = yoweeTrigger
        self.voiceTrigger = voiceTrigger
        self.voiceStopTrigger = voiceStopTrigger
    }
}

extension NSNotification.Name {
    static let yoweeShortcutsChanged = NSNotification.Name("YoweeShortcutsChanged")
}
