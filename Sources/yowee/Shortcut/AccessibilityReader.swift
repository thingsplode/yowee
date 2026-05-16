import ApplicationServices
import Cocoa

@MainActor
enum AccessibilityReader {
    /// Returns the selected text, the element it belongs to, and the selection range.
    /// The range is needed to restore selection after Yowee steals focus during the menu.
    static func selectedText() -> (text: String, element: AXUIElement, range: CFRange)? {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        AppLogger.log("selectedText: frontmost=\(frontApp)", category: "AXReader")

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusResult == .success else {
            AppLogger.log("selectedText: no focused element (AXError=\(focusResult.rawValue))", category: "AXReader")
            return nil
        }

        guard let element = focusedRef as! AXUIElement? else {
            AppLogger.log("selectedText: focused ref is not AXUIElement", category: "AXReader")
            return nil
        }

        var valueRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &valueRef
        )
        guard textResult == .success else {
            AppLogger.log("selectedText: kAXSelectedText failed (AXError=\(textResult.rawValue))", category: "AXReader")
            return nil
        }

        guard let text = valueRef as? String, !text.isEmpty else {
            AppLogger.log("selectedText: text empty or wrong type", category: "AXReader")
            return nil
        }

        // Capture the selection range so we can restore it later.
        var rangeRef: CFTypeRef?
        var range = CFRange(location: 0, length: (text as NSString).length)
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let axValue = rangeRef as! AXValue? {
            AXValueGetValue(axValue, .cfRange, &range)
        }

        return (text, element, range)
    }
}
