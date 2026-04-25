import Cocoa

extension NSPanel {
    /// Positions the panel near `point`, keeping it fully inside the visible screen area.
    /// The panel appears below the point when space allows; above it when near the bottom edge.
    func positionNear(_ point: NSPoint, width: CGFloat, height: CGFloat) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let x = max(screen.minX + 8, min(point.x - width / 2, screen.maxX - width - 8))
        let belowY = point.y - height - 8
        let aboveY = point.y + 8
        let y = belowY >= screen.minY + 8 ? belowY : min(aboveY, screen.maxY - height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
