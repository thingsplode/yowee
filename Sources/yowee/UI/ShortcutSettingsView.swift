import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(ShortcutStore.self) private var store

    @State private var yoweeKey: HotKey = .defaultYoweeTrigger
    @State private var voiceKey: HotKey = .defaultVoiceTrigger
    @State private var yoweeRecording = false
    @State private var voiceRecording = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Text Pipeline Trigger")
                    Spacer()
                    ShortcutRecorderButton(hotKey: $yoweeKey, isRecording: $yoweeRecording)
                }
                Button("Reset to ⌥Space") {
                    yoweeKey = .defaultYoweeTrigger
                }
                .foregroundStyle(.secondary)
                Text("With text selected in any app, press this shortcut to open the yowee pipeline picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }

            Section {
                HStack {
                    Text("Voice Recording")
                    Spacer()
                    ShortcutRecorderButton(hotKey: $voiceKey, isRecording: $voiceRecording)
                }
                Button("Reset to ⌥R") {
                    voiceKey = .defaultVoiceTrigger
                }
                .foregroundStyle(.secondary)
                Text("Hold this shortcut to record voice. Release to stop recording and begin transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            yoweeKey = store.yoweeTrigger
            voiceKey = store.voiceTrigger
        }
        .onChange(of: yoweeKey) { _, newValue in
            store.yoweeTrigger = newValue
            store.save()
            GlobalShortcutManager.shared.updateYoweeTrigger(newValue)
        }
        .onChange(of: voiceKey) { _, newValue in
            store.voiceTrigger = newValue
            store.save()
            // ShortcutStore.save() posts .yoweeShortcutsChanged — VoiceInputCoordinator handles it.
        }
    }
}

// MARK: - Recorder button (NSViewRepresentable)

private struct ShortcutRecorderButton: NSViewRepresentable {
    @Binding var hotKey: HotKey
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderNSButton {
        let button = RecorderNSButton()
        button.coordinator = context.coordinator
        return button
    }

    func updateNSView(_ button: RecorderNSButton, context: Context) {
        button.hotKey = hotKey
        button.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator {
        var parent: ShortcutRecorderButton
        init(_ parent: ShortcutRecorderButton) {
            self.parent = parent
        }

        func hotKeyChanged(_ hotKey: HotKey) {
            parent.hotKey = hotKey
        }

        func recordingChanged(_ value: Bool) {
            parent.isRecording = value
        }
    }
}

final class RecorderNSButton: NSButton {
    fileprivate var coordinator: ShortcutRecorderButton.Coordinator?
    private var monitor: Any?

    var hotKey: HotKey = .defaultYoweeTrigger {
        didSet { updateTitle() }
    }

    var isRecording = false {
        didSet { updateTitle() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        updateTitle()
        target = self
        action = #selector(clicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        // Remove the monitor if the view is deallocated while recording is in progress
        // (e.g., user switches tabs before pressing a key).
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    @objc private func clicked() {
        isRecording = true
        coordinator?.recordingChanged(true)
        installMonitor()
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = HotKey.carbonModifiers(from: event.modifierFlags)
            guard mods != 0, mods != UInt32(shiftKey) else { return event }
            let newKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: mods)
            hotKey = newKey
            coordinator?.hotKeyChanged(newKey)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
        coordinator?.recordingChanged(false)
    }

    private func updateTitle() {
        title = isRecording ? "Press shortcut…" : hotKey.displayString
    }
}
