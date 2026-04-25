import Cocoa
import ApplicationServices

@MainActor
enum AccessibilityReader {
    /// Returns the selected text, the element it belongs to, and the selection range.
    /// The range is needed to restore selection after Yowee steals focus during the menu.
    static func selectedText() -> (text: String, element: AXUIElement, range: CFRange)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else { return nil }

        let element = focusedRef as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &valueRef
        ) == .success else { return nil }

        guard let text = valueRef as? String, !text.isEmpty else { return nil }

        // Capture the selection range so we can restore it later.
        var rangeRef: CFTypeRef?
        var range = CFRange(location: 0, length: (text as NSString).length)
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success {
            AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        }

        return (text, element, range)
    }
}
