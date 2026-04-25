import YoweeCore
import SwiftUI

struct StepEditorView: View {
    @Bindable var step: PromptStep
    @Environment(PipelineStore.self) private var store

    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false

    private var templateIsValid: Bool {
        step.userTemplate.contains("{{input}}")
    }

    private var pickerModels: [String] {
        var models = fetchedModels.isEmpty ? step.provider.defaultModels : fetchedModels
        if !models.contains(step.modelID) { models.insert(step.modelID, at: 0) }
        return models
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Step Name").font(.caption).foregroundStyle(.secondary)
                TextField("Step Name", text: $step.name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider").font(.caption).foregroundStyle(.secondary)
                    Picker("Provider", selection: $step.provider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: step.provider) { _, newProvider in
                        step.modelID = newProvider.defaultModelID
                        store.save()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Model").font(.caption).foregroundStyle(.secondary)
                        if isFetchingModels {
                            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        }
                    }
                    Picker("Model", selection: $step.modelID) {
                        ForEach(pickerModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: step.modelID) { _, _ in store.save() }
                }
            }

            if step.provider == .ollama {
                Toggle(isOn: $step.ollamaThinkingDisabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Disable thinking").font(.caption)
                        Text("Passes think: false — speeds up reasoning models (deepseek-r1, qwq)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: step.ollamaThinkingDisabled) { _, _ in store.save() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System Prompt (optional)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { step.systemPrompt ?? "" },
                    set: { step.systemPrompt = $0.isEmpty ? nil : $0 }
                ))
                .font(.body)
                .frame(minHeight: 60, maxHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt Template").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !templateIsValid {
                        Label("Must contain {{input}}", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                TextEditor(text: $step.userTemplate)
                    .font(.body.monospaced())
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(templateIsValid ? Color(nsColor: .separatorColor) : Color.orange)
                    )
            }

            Text("Use {{input}} where the selected text (or previous step's output) should be inserted.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onChange(of: step.name) { _, _ in store.save() }
        .onChange(of: step.userTemplate) { _, _ in store.save() }
        .onChange(of: step.systemPrompt) { _, _ in store.save() }
        .task(id: step.provider) { await fetchModelsIfNeeded() }
    }

    private func fetchModelsIfNeeded() async {
        switch step.provider {
        case .openai:
            guard let apiKey = KeychainStore.load(for: LLMProvider.openai.keychainKey),
                  !apiKey.isEmpty else {
                fetchedModels = []
                return
            }
            isFetchingModels = true
            defer { isFetchingModels = false }
            fetchedModels = (try? await OpenAIClient(apiKey: apiKey).fetchModels()) ?? []
        case .ollama:
            isFetchingModels = true
            defer { isFetchingModels = false }
            fetchedModels = (try? await OllamaClient().fetchModels()) ?? []
        default:
            fetchedModels = []
        }
    }
}
