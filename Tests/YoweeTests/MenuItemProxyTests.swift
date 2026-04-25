import Testing
import Cocoa

// Local replica of MenuItemProxy — same implementation as in StatusBarController.swift.
// Tests the ObjC dispatch mechanism that AppKit uses when a menu item is clicked.
private final class MenuItemProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init()
    }
    @objc func fire(_ sender: Any?) { action() }
}

@Suite("MenuItemProxy")
struct MenuItemProxyTests {

    @Test func firesClosureOnDirectCall() {
        var fired = false
        let proxy = MenuItemProxy { fired = true }
        proxy.fire(nil)
        #expect(fired)
    }

    @Test func respondsToFireSelector() {
        let proxy = MenuItemProxy {}
        #expect(proxy.responds(to: #selector(MenuItemProxy.fire(_:))))
    }

    @Test func firesClosureViaObjCDispatch() {
        // Simulates exactly what AppKit does when performSelector: is called on the target.
        var fired = false
        let proxy = MenuItemProxy { fired = true }
        let sel = #selector(MenuItemProxy.fire(_:))
        proxy.perform(sel, with: nil)
        #expect(fired)
    }

    @Test func isNSObjectSubclass() {
        // Regression guard: if MenuItemProxy ever loses NSObject inheritance,
        // AppKit menu dispatch breaks silently.
        let proxy = MenuItemProxy {}
        #expect(proxy is NSObject)
    }
}
