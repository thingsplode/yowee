import SwiftUI
import YoweeCore

struct ProviderSettingsView: View {
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var ollamaURL = ""
    @State private var savedProvider: LLMProvider?
    @State private var saveError: String?

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
            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
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
        do {
            try KeychainStore.save(anthropicKey, for: LLMProvider.anthropic.keychainKey)
            saveError = nil
            withAnimation { savedProvider = .anthropic }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
        } catch {
            withAnimation { saveError = "Failed to save Anthropic key: \(error.localizedDescription)" }
        }
    }

    private func saveOpenAIKey() {
        guard !openAIKey.isEmpty, !openAIKey.hasPrefix("•") else { return }
        do {
            try KeychainStore.save(openAIKey, for: LLMProvider.openai.keychainKey)
            saveError = nil
            withAnimation { savedProvider = .openai }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
        } catch {
            withAnimation { saveError = "Failed to save OpenAI key: \(error.localizedDescription)" }
        }
    }

    private func saveOllamaURL() {
        let url = ollamaURL.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(url.isEmpty ? nil : url, forKey: "yowee.ollama.baseURL")
        withAnimation { savedProvider = .ollama }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }
}
