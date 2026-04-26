import SwiftUI
import YoweeCore

struct StepEditorView: View {
    @Bindable var step: PromptStep
    @Environment(PipelineStore.self) private var store

    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false

    private var templateIsValid: Bool {
        step.stepKind == .research || step.userTemplate.contains("{{input}}")
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
                    Text("Step Type").font(.caption).foregroundStyle(.secondary)
                    Picker("Step Type", selection: $step.stepKind) {
                        Text("Prompt").tag(StepKind.prompt)
                        Text("Research").tag(StepKind.research)
                    }
                    .labelsHidden()
                    .onChange(of: step.stepKind) { _, _ in store.save() }
                }
            }

            if step.stepKind == .research {
                researchConfig
            } else {
                promptConfig
            }
        }
        .onChange(of: step.name) { _, _ in store.save() }
        .onChange(of: step.userTemplate) { _, _ in store.save() }
        .onChange(of: step.systemPrompt) { _, _ in store.save() }
        .task(id: step.provider) { await fetchModelsIfNeeded() }
    }

    private var queryTemplateIsValid: Bool {
        step.queryTemplate.contains("{{input}}")
    }

    private var researchConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Query Template").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !queryTemplateIsValid {
                        Label("Must contain {{input}}", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                TextEditor(text: $step.queryTemplate)
                    .font(.body.monospaced())
                    .frame(minHeight: 50, maxHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(queryTemplateIsValid ? Color(nsColor: .separatorColor) : Color.orange)
                    )
                    .onChange(of: step.queryTemplate) { _, _ in store.save() }
                Text("Use {{input}} where the search topic should appear.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Stepper(
                "Max results: \(step.tavilyMaxResults)",
                value: $step.tavilyMaxResults,
                in: 1 ... 10
            )
            .onChange(of: step.tavilyMaxResults) { _, _ in store.save() }

            HStack(spacing: 8) {
                Text("Search depth").font(.caption).foregroundStyle(.secondary)
                Picker("Search Depth", selection: $step.tavilySearchDepth) {
                    Text("Fast (snippets, 1 credit)").tag("basic")
                    Text("Deep (full content, 2 credits)").tag("advanced")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: step.tavilySearchDepth) { _, _ in store.save() }
            }

            Text("Searches the web via Tavily and Jina Reader, then outputs Markdown for the next step to summarize.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var promptConfig: some View {
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

    private func fetchModelsIfNeeded() async {
        guard step.provider == .openai || step.provider == .ollama else {
            fetchedModels = []
            return
        }
        isFetchingModels = true
        defer { isFetchingModels = false }
        fetchedModels = await (try? ModelFetcherService.shared.fetchModels(for: step.provider)) ?? []
    }
}
