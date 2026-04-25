import Cocoa
import SwiftUI

@MainActor
final class ErrorBanner {
    private static var currentPanel: NSPanel?

    static func show(message: String, near point: NSPoint = NSEvent.mouseLocation) {
        currentPanel?.orderOut(nil)

        let width: CGFloat = 560

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        currentPanel = p

        let close = {
            p.orderOut(nil)
            if currentPanel === p { currentPanel = nil }
        }

        // Force SwiftUI layout with a tall frame so fittingSize returns the real height,
        // not a pre-layout estimate (which is often 0 and causes the panel to appear off-screen).
        let hosting = NSHostingView(rootView: ErrorBannerView(message: message, onClose: close))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        let naturalHeight = max(72, min(hosting.fittingSize.height + 16, 400))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: naturalHeight)

        p.setContentSize(NSSize(width: width, height: naturalHeight))
        p.contentView = hosting
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        // .popUpMenu (101) ensures the banner appears above any frontmost app window.
        p.level = .popUpMenu
        p.ignoresMouseEvents = false

        p.positionNear(point, width: width, height: naturalHeight)
        AppLogger.log("showing at cursor (\(Int(point.x)),\(Int(point.y))) h=\(Int(naturalHeight))", category: "ErrorBanner")
        // orderFrontRegardless bypasses application activation state so the banner
        // appears even when yowee runs as a .accessory (menu-bar-only) app.
        p.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { close() }
    }
}

private struct ErrorBannerView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.trailing, 28)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        // Solid background — NSVisualEffectView materials require an active/key window
        // to render their blur; a non-activating floating panel won't qualify.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
        )
    }
}
