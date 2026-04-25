import Cocoa
import SwiftUI

@MainActor
final class LoadingHUD {
    private var panel: NSPanel?

    func show(near point: NSPoint) {
        let hosting = NSHostingView(rootView: LoadingHUDView())
        hosting.frame = NSRect(x: 0, y: 0, width: 140, height: 36)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .popUpMenu
        p.ignoresMouseEvents = true
        p.positionNear(point, width: 140, height: 36)
        p.orderFrontRegardless()
        self.panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct LoadingHUDView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
            Text("Processing…")
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
