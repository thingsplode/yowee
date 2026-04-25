import ApplicationServices
import Cocoa

@MainActor
enum AccessibilityPermissionGuard {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func checkAndPromptIfNeeded() {
        guard !isTrusted else { return }
        // Passing prompt:true causes macOS to open System Settings and auto-add
        // the current binary to the Accessibility list so the user just toggles it on.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
