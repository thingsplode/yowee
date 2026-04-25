import SwiftUI

struct LogView: View {
    @State private var content = ""
    @State private var autoScroll = true

    private let logURL = URL(fileURLWithPath: "/tmp/yowee_debug.log")

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(content.isEmpty ? "No log entries yet." : content)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("logBottom")
                }
                .onChange(of: content) { _, _ in
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
                    content = ""
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
        let fresh = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if fresh != content { content = fresh }
    }
}
