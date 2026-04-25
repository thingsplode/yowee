import SwiftUI
import YoweeCore

struct ProviderSettingsView: View {
    @State private var anthropicKey: String = ""
    @State private var openAIKey: String = ""
    @State private var ollamaURL: String = ""
    @State private var savedProvider: LLMProvider?

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .onSubmit { saveAnthropicKey() }
                    .textContentType(.password)

                Button("Save Anthropic Key") { saveAnthropicKey() }
                    .disabled(anthropicKey.isEmpty)
            } header: {
                Label("Anthropic (Claude)", systemImage: "brain")
            }

            Section {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .onSubmit { saveOpenAIKey() }
                    .textContentType(.password)

                Button("Save OpenAI Key") { saveOpenAIKey() }
                    .disabled(openAIKey.isEmpty)
            } header: {
                Label("OpenAI (GPT)", systemImage: "brain.filled.head.profile")
            }

            Section {
                TextField("Base URL", text: $ollamaURL, prompt: Text("http://localhost:11434"))
                    .onSubmit { saveOllamaURL() }

                Button("Save Ollama URL") { saveOllamaURL() }
            } header: {
                Label("Ollama (Local)", systemImage: "server.rack")
            } footer: {
                Text("Ollama runs locally and doesn't require an API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let provider = savedProvider {
                Label("\(provider.displayName) settings saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: loadExistingKeys)
    }

    private func loadExistingKeys() {
        if let key = KeychainStore.load(for: LLMProvider.anthropic.keychainKey) {
            anthropicKey = String(repeating: "•", count: min(key.count, 20))
        }
        if let key = KeychainStore.load(for: LLMProvider.openai.keychainKey) {
            openAIKey = String(repeating: "•", count: min(key.count, 20))
        }
        ollamaURL = UserDefaults.standard.string(forKey: "yowee.ollama.baseURL") ?? ""
    }

    private func saveAnthropicKey() {
        guard !anthropicKey.isEmpty, !anthropicKey.hasPrefix("•") else { return }
        try? KeychainStore.save(anthropicKey, for: LLMProvider.anthropic.keychainKey)
        withAnimation { savedProvider = .anthropic }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }

    private func saveOpenAIKey() {
        guard !openAIKey.isEmpty, !openAIKey.hasPrefix("•") else { return }
        try? KeychainStore.save(openAIKey, for: LLMProvider.openai.keychainKey)
        withAnimation { savedProvider = .openai }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }

    private func saveOllamaURL() {
        let url = ollamaURL.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(url.isEmpty ? nil : url, forKey: "yowee.ollama.baseURL")
        withAnimation { savedProvider = .ollama }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }
}
