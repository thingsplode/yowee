import SwiftUI

// MARK: - Root view

struct VoiceRecordingView: View {
    @Bindable var session: VoiceSessionState
    let pipelines: [Pipeline]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var pickerFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            stateContent
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .padding(.trailing, 30)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - State content

    @ViewBuilder
    private var stateContent: some View {
        switch session.voiceState {
        case .idle:
            EmptyView()
        case .recording:
            recordingView
        case .modelLoading:
            progressRow(
                icon: "arrow.down.circle.fill",
                label: "Downloading speech model…",
                sublabel: "First use only — this may take a few minutes",
                progress: session.loadingProgress
            )
        case .transcribing:
            progressRow(icon: "waveform", label: "Transcribing…")
        case .pipelineSelection(let text):
            selectionView(transcribedText: text)
        case .processingPipeline(let name):
            progressRow(icon: "gearshape.2.fill", label: "Running \"\(name)\"…")
        case .error(let msg):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sub-views

    private var recordingView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text("Recording")
                    .font(.headline)
            }
            WaveformView(level: session.audioLevel)
            Text("Press ⌥S to stop · Esc to cancel")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionView(transcribedText: String) -> some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.headline)
            }
            Picker("Pipeline", selection: $session.selectedPipelineID) {
                Text("Direct (no LLM)").tag(Optional<UUID>.none)
                if !pipelines.isEmpty { Divider() }
                ForEach(pipelines) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .focused($pickerFocused)
            Button(action: onConfirm) {
                Text("Process")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .onAppear { pickerFocused = true }
    }

    /// Linear progress row. Pass `progress` (0–1) for a determinate bar, nil for indeterminate.
    private func progressRow(
        icon: String? = nil,
        label: String,
        sublabel: String? = nil,
        progress: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.headline)
                Spacer()
                if let progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if let sublabel {
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let level: Float

    private let barCount = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: barHeight(index: i, t: t))
                }
            }
            .frame(height: 36)
            // Removed: .animation(.easeInOut(duration: 0.05), value: level)
            // TimelineView redraws at 20 Hz; a 50ms ease-in-out is always superseded
            // by the next redraw before it completes, making the modifier a no-op.
        }
    }

    private func barHeight(index: Int, t: Double) -> CGFloat {
        let amplitude = max(0.08, CGFloat(level))
        let offset = Double(index) * 0.8
        let wave = (sin(t * 6 + offset) + 1) / 2   // 0…1, oscillates at ~1 Hz
        return 4 + amplitude * 32 * CGFloat(wave)
    }
}
