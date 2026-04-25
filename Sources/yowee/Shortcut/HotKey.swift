import AppKit
import Carbon.HIToolbox
import Foundation

struct HotKey: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon mask: cmdKey=256, shiftKey=512, optionKey=2048, controlKey=4096

    // ⌥Space — trigger text pipeline
    static let defaultYoweeTrigger = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    // ⌥R — push-to-talk voice recording
    static let defaultVoiceTrigger = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: - CGEvent modifier conversion

    /// Returns the CGEventFlags corresponding to this hotkey's Carbon modifier mask.
    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if modifiers & UInt32(cmdKey)     != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(shiftKey)   != 0 { flags.insert(.maskShift) }
        if modifiers & UInt32(optionKey)  != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        return flags
    }

    // MARK: - NSEvent → Carbon conversion

    static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.option)  { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: - Display

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
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
    case kVK_Space:   return "Space"
    case kVK_Return:  return "↩"
    case kVK_Tab:     return "⇥"
    case kVK_Delete:  return "⌫"
    case kVK_Escape:  return "⎋"
    case kVK_ANSI_A:  return "A"
    case kVK_ANSI_B:  return "B"
    case kVK_ANSI_C:  return "C"
    case kVK_ANSI_D:  return "D"
    case kVK_ANSI_E:  return "E"
    case kVK_ANSI_F:  return "F"
    case kVK_ANSI_G:  return "G"
    case kVK_ANSI_H:  return "H"
    case kVK_ANSI_I:  return "I"
    case kVK_ANSI_J:  return "J"
    case kVK_ANSI_K:  return "K"
    case kVK_ANSI_L:  return "L"
    case kVK_ANSI_M:  return "M"
    case kVK_ANSI_N:  return "N"
    case kVK_ANSI_O:  return "O"
    case kVK_ANSI_P:  return "P"
    case kVK_ANSI_Q:  return "Q"
    case kVK_ANSI_R:  return "R"
    case kVK_ANSI_S:  return "S"
    case kVK_ANSI_T:  return "T"
    case kVK_ANSI_U:  return "U"
    case kVK_ANSI_V:  return "V"
    case kVK_ANSI_W:  return "W"
    case kVK_ANSI_X:  return "X"
    case kVK_ANSI_Y:  return "Y"
    case kVK_ANSI_Z:  return "Z"
    default:          return "Key(\(keyCode))"
    }
}
