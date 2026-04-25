import Cocoa
import SwiftUI

// VoiceState and VoiceSessionState are defined in VoiceSessionState.swift.
// VoiceRecordingView and WaveformView are defined in VoiceRecordingView.swift.

// MARK: - NSPanel wrapper

@MainActor
final class VoiceRecordingPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<VoiceRecordingView>?
    private var eventMonitor: Any?

    // Retained for the keyboard event handler (set/read on main thread only).
    private var session: VoiceSessionState?
    private var pipelineIDs: [UUID?] = []  // [nil, id1, id2, …] mirrors Picker order
    private var onCancel: (() -> Void)?
    private var onConfirm: (() -> Void)?

    func show(
        near point: NSPoint,
        session: VoiceSessionState,
        pipelines: [Pipeline],
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        dismiss()

        self.session = session
        self.pipelineIDs = [nil] + pipelines.map { Optional($0.id) }
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let width: CGFloat = 340

        let content = VoiceRecordingView(
            session: session,
            pipelines: pipelines,
            onCancel: onCancel,
            onConfirm: onConfirm
        )

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        let naturalHeight = max(120, min(hosting.fittingSize.height + 16, 400))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: naturalHeight)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: naturalHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .popUpMenu
        p.ignoresMouseEvents = false
        p.isMovableByWindowBackground = true

        p.positionNear(point, width: width, height: naturalHeight)
        p.orderFrontRegardless()

        panel = p
        hostingView = hosting

        // Local monitor intercepts key events in our app before they reach any window.
        // NSEvent monitors always fire on the main thread; MainActor.assumeIsolated is safe.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleKeyEvent(event) }
        }
    }

    func dismiss() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        session = nil
        pipelineIDs = []
        onCancel = nil
        onConfirm = nil
    }

    /// Makes the panel the key window so keyboard shortcuts fire.
    func activateForSelection() {
        guard let p = panel else { return }
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Reflows the panel height when content size changes between states.
    func reflow() {
        guard let hosting = hostingView, let p = panel else { return }
        let width = p.frame.width
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        let naturalHeight = max(120, min(hosting.fittingSize.height + 16, 400))
        var frame = p.frame
        frame.origin.y += frame.height - naturalHeight  // keep top edge fixed
        frame.size.height = naturalHeight
        p.setFrame(frame, display: true, animate: false)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: naturalHeight)
    }

    // MARK: - Keyboard handling

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Esc or ⌥Esc → cancel (works in all active states whenever the app has key focus)
        if event.keyCode == 53 /* Escape */ && (flags.isEmpty || flags == .option) {
            // Defer past the current event-dispatch cycle so that window activation
            // in cancel() fires after the system finishes processing this key event.
            Task { @MainActor [weak self] in self?.onCancel?() }
            return nil
        }

        guard let session, case .pipelineSelection = session.voiceState else { return event }

        // Return (no modifiers) → confirm.
        if event.keyCode == 36 /* Return */ && flags.isEmpty {
            Task { @MainActor [weak self] in self?.onConfirm?() }
            return nil
        }

        // ⌥↓ / ⌥↑ → cycle pipeline selection (pure state update, no activation needed)
        if event.keyCode == 125 /* ↓ */ && flags == .option {
            cycleSelection(forward: true)
            return nil
        }
        if event.keyCode == 126 /* ↑ */ && flags == .option {
            cycleSelection(forward: false)
            return nil
        }

        return event
    }

    private func cycleSelection(forward: Bool) {
        guard let session else { return }
        let ids = pipelineIDs
        guard !ids.isEmpty else { return }
        let current = session.selectedPipelineID
        let idx = ids.firstIndex(where: { $0 == current }) ?? 0
        let next = forward ? (idx + 1) % ids.count : (idx - 1 + ids.count) % ids.count
        session.selectedPipelineID = ids[next]
    }
}
