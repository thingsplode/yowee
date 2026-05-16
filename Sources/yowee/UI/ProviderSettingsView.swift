import SwiftUI
import YoweeCore

struct ProviderSettingsView: View {
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var openAIBaseURL = ""
    @State private var ollamaURL = ""
    @State private var tavilyKey = ""

    @State private var hasAnthropicKey = false
    @State private var hasOpenAIKey = false
    @State private var hasTavilyKey = false

    @State private var savedProvider: LLMProvider?
    @State private var savedTavily = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .onSubmit { saveAnthropicKey() }
                    .textContentType(.password)
                if hasAnthropicKey {
                    Text("A key is saved — enter a new value to replace it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save Anthropic Key") { saveAnthropicKey() }
                    .disabled(anthropicKey.isEmpty)
            } header: {
                Label("Anthropic (Claude)", systemImage: "brain")
            }

            Section {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .onSubmit { saveOpenAIKey() }
                    .textContentType(.password)
                if hasOpenAIKey {
                    Text("A key is saved — enter a new value to replace it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save OpenAI Key") { saveOpenAIKey() }
                    .disabled(openAIKey.isEmpty)

                TextField("Base URL", text: $openAIBaseURL,
                          prompt: Text("https://api.openai.com"))
                    .onSubmit { saveOpenAIBaseURL() }
                Button("Save OpenAI Base URL") { saveOpenAIBaseURL() }
            } header: {
                Label("OpenAI (GPT)", systemImage: "brain.filled.head.profile")
            } footer: {
                Text("Set Base URL for Azure OpenAI or compatible endpoints.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Base URL", text: $ollamaURL, prompt: Text("http://localhost:11434"))
                    .onSubmit { saveOllamaURL() }
                Button("Save Ollama URL") { saveOllamaURL() }
            } header: {
                Label("Ollama (Local)", systemImage: "server.rack")
            } footer: {
                Text("Ollama runs locally and doesn't require an API key.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SecureField("Tavily API Key", text: $tavilyKey)
                    .onSubmit { saveTavilyKey() }
                    .textContentType(.password)
                if hasTavilyKey {
                    Text("A key is saved — enter a new value to replace it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save Tavily Key") { saveTavilyKey() }
                    .disabled(tavilyKey.isEmpty)
            } header: {
                Label("Tavily (Web Search)", systemImage: "magnifyingglass")
            } footer: {
                Text("Required for Research steps. Get a free API key at app.tavily.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if savedTavily {
                Label("Tavily key saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            }
            if let provider = savedProvider {
                Label("\(provider.displayName) settings saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            }
            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: loadExistingState)
    }

    private func loadExistingState() {
        hasAnthropicKey = KeychainStore.load(for: LLMProvider.anthropic.keychainKey) != nil
        hasOpenAIKey    = KeychainStore.load(for: LLMProvider.openai.keychainKey) != nil
        hasTavilyKey    = KeychainStore.load(for: Credentials.tavilyKeychainKey) != nil
        ollamaURL    = UserDefaults.standard.string(forKey: "yowee.ollama.baseURL") ?? ""
        openAIBaseURL = UserDefaults.standard.string(forKey: "yowee.openai.baseURL") ?? ""
    }

    private func saveAnthropicKey() {
        guard !anthropicKey.isEmpty else { return }
        do {
            try KeychainStore.save(anthropicKey, for: LLMProvider.anthropic.keychainKey)
            anthropicKey = ""
            hasAnthropicKey = true
            saveError = nil
            withAnimation { savedProvider = .anthropic }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
        } catch {
            withAnimation { saveError = "Failed to save Anthropic key: \(error.localizedDescription)" }
        }
    }

    private func saveOpenAIKey() {
        guard !openAIKey.isEmpty else { return }
        do {
            try KeychainStore.save(openAIKey, for: LLMProvider.openai.keychainKey)
            ModelFetcherService.shared.invalidate(for: .openai)
            openAIKey = ""
            hasOpenAIKey = true
            saveError = nil
            withAnimation { savedProvider = .openai }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
        } catch {
            withAnimation { saveError = "Failed to save OpenAI key: \(error.localizedDescription)" }
        }
    }

    private func saveOpenAIBaseURL() {
        let url = openAIBaseURL.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(url.isEmpty ? nil : url, forKey: "yowee.openai.baseURL")
        ModelFetcherService.shared.invalidate(for: .openai)
        withAnimation { savedProvider = .openai }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }

    private func saveOllamaURL() {
        let url = ollamaURL.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(url.isEmpty ? nil : url, forKey: "yowee.ollama.baseURL")
        ModelFetcherService.shared.invalidate(for: .ollama)
        withAnimation { savedProvider = .ollama }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedProvider = nil }
    }

    private func saveTavilyKey() {
        guard !tavilyKey.isEmpty else { return }
        do {
            try KeychainStore.save(tavilyKey, for: Credentials.tavilyKeychainKey)
            tavilyKey = ""
            hasTavilyKey = true
            saveError = nil
            withAnimation { savedTavily = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedTavily = false }
        } catch {
            withAnimation { saveError = "Failed to save Tavily key: \(error.localizedDescription)" }
        }
    }
}
