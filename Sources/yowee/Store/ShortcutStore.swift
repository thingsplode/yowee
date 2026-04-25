import Foundation

/// Persists both keyboard shortcuts to ~/.config/yowee/shortcuts.json.
/// Replaces the old UserDefaults-based HotKey persistence.
@Observable
@MainActor
final class ShortcutStore {
    var yoweeTrigger: HotKey = .defaultYoweeTrigger
    var voiceTrigger: HotKey = .defaultVoiceTrigger

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

        yoweeTrigger  = record.yoweeTrigger
        voiceTrigger = record.voiceTrigger
    }

    func save() {
        let record = ShortcutRecord(yoweeTrigger: yoweeTrigger, voiceTrigger: voiceTrigger)
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
}

extension NSNotification.Name {
    static let yoweeShortcutsChanged = NSNotification.Name("YoweeShortcutsChanged")
}
