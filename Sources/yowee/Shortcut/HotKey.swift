import AppKit
import Carbon.HIToolbox
import Foundation

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon mask: cmdKey=256, shiftKey=512, optionKey=2048, controlKey=4096

    /// ⌥Space — trigger text pipeline
    static let defaultYoweeTrigger = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    /// ⌥R — push-to-talk voice recording start
    static let defaultVoiceTrigger = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))
    /// ⌥S — voice recording stop
    static let defaultVoiceStopTrigger = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))
    /// ⌥⎋ — cancel recording and close panel
    static let defaultVoiceCancelTrigger = HotKey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey))

    // MARK: - CGEvent modifier conversion

    /// Returns the CGEventFlags corresponding to this hotkey's Carbon modifier mask.
    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        return flags
    }

    // MARK: - NSEvent → Carbon conversion

    static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: - Display

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeDisplayName(keyCode))
        return parts.joined()
    }

    // MARK: - Legacy UserDefaults migration

    /// Reads the shortcut saved by the old UserDefaults-based system (yowee.shortcut.*).
    /// Returns nil if nothing was saved there.
    static func loadLegacy() -> HotKey? {
        guard UserDefaults.standard.object(forKey: "yowee.shortcut.keyCode") != nil else { return nil }
        return HotKey(
            keyCode: UInt32(UserDefaults.standard.integer(forKey: "yowee.shortcut.keyCode")),
            modifiers: UInt32(UserDefaults.standard.integer(forKey: "yowee.shortcut.modifiers"))
        )
    }
}

private func keyCodeDisplayName(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_Space: "Space"
    case kVK_Return: "↩"
    case kVK_Tab: "⇥"
    case kVK_Delete: "⌫"
    case kVK_Escape: "⎋"
    case kVK_ANSI_A: "A"
    case kVK_ANSI_B: "B"
    case kVK_ANSI_C: "C"
    case kVK_ANSI_D: "D"
    case kVK_ANSI_E: "E"
    case kVK_ANSI_F: "F"
    case kVK_ANSI_G: "G"
    case kVK_ANSI_H: "H"
    case kVK_ANSI_I: "I"
    case kVK_ANSI_J: "J"
    case kVK_ANSI_K: "K"
    case kVK_ANSI_L: "L"
    case kVK_ANSI_M: "M"
    case kVK_ANSI_N: "N"
    case kVK_ANSI_O: "O"
    case kVK_ANSI_P: "P"
    case kVK_ANSI_Q: "Q"
    case kVK_ANSI_R: "R"
    case kVK_ANSI_S: "S"
    case kVK_ANSI_T: "T"
    case kVK_ANSI_U: "U"
    case kVK_ANSI_V: "V"
    case kVK_ANSI_W: "W"
    case kVK_ANSI_X: "X"
    case kVK_ANSI_Y: "Y"
    case kVK_ANSI_Z: "Z"
    default: "Key(\(keyCode))"
    }
}
