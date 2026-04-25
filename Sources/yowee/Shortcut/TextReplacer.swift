import Cocoa
import ApplicationServices

@MainActor
enum TextReplacer {
    /// Replaces text in the given AX element. Falls back to Cmd+V paste if AX write is unsupported.
    static func replace(in element: AXUIElement, range: CFRange, with text: String) {
        // Step 1: Explicitly focus the element.
        // After Yowee's pipeline menu steals keyboard focus, the original text element is
        // defocused. Without this, range restore and AX writes silently fail or target nothing.
        let focusResult = AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, true as CFTypeRef
        )
        log("element focus: \(focusResult.rawValue)")

        // Step 2: Restore the original selection range.
        var mutableRange = range
        if let axRange = AXValueCreate(.cfRange, &mutableRange) {
            let rangeResult = AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, axRange
            )
            log("range restore: \(rangeResult.rawValue)")
        }

        // Step 3: Snapshot selected text before write.
        // After a real replacement the selection collapses (→ ""), which differs from the
        // original text. If an app silently ignores the write (e.g. Notes), the selected
        // text stays the same — we detect this and fall back to Cmd+V.
        var beforeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &beforeRef)
        let textBefore = beforeRef as? String
        log("selected before write: \"\(textBefore?.prefix(40) ?? "nil")\"")

        // Step 4: Try direct AX write (instant, no clipboard side-effects).
        let axResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        log("AX write: \(axResult.rawValue)")

        if axResult == .success {
            var afterRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &afterRef)
            let textAfter = afterRef as? String
            log("selected after write: \"\(textAfter?.prefix(40) ?? "nil")\"")

            if textAfter != textBefore {
                log("AX write verified (selection changed)")
                return
            }
            // Same text as before write → app accepted the call but did nothing (e.g. Notes).
            log("AX write silently ignored — using Cmd+V")
        } else {
            log("AX write failed — using Cmd+V")
        }

        pasteViaCmdV(text)
    }

    private static func log(_ msg: String) {
        AppLogger.log(msg, category: "TextReplacer")
    }

    /// Writes `text` to the general pasteboard, sends Cmd+V to the frontmost app,
    /// then restores the previous clipboard contents after 500 ms.
    /// Internal so VoiceInputCoordinator can share this implementation.
    static func pasteViaCmdV(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateCmdV()

        // Restore previous clipboard contents after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let prev = previous {
                pasteboard.setString(prev, forType: .string)
            }
        }
    }

    private static func simulateCmdV() {  // called only by pasteViaCmdV
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        // .cgSessionEventTap delivers to the frontmost app, not Yowee's own process.
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
