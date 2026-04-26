import SwiftUI

struct LogView: View {
    @State private var lines: [LogLine] = []
    @State private var autoScroll = true

    private let logURL = URL(fileURLWithPath: "/tmp/yowee_debug.log")

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if lines.isEmpty {
                        Text("No log entries yet.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 1)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Color.clear.frame(height: 1).id("logBottom")
                }
                .onChange(of: lines.count) { _, _ in
                    if autoScroll {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Text("· refreshes every 1.5s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Clear") {
                    try? "".write(to: logURL, atomically: true, encoding: .utf8)
                    lines = []
                }
                .buttonStyle(.borderless)
                Button("Refresh") { reload() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .task {
            reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                reload()
            }
        }
    }

    private func reload() {
        let raw = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let parsed = raw
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map(LogLine.init)
        if parsed.map(\.text) != lines.map(\.text) { lines = parsed }
    }
}

private struct LogLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color

    init(_ text: String) {
        self.text = text
        if text.contains("[WARN]") {
            color = Color(red: 0.85, green: 0.62, blue: 0.0)
        } else if text.contains("[ERRR]") {
            color = Color(red: 0.90, green: 0.38, blue: 0.0)
        } else {
            color = Color.primary
        }
    }
}
