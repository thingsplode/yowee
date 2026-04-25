import SwiftUI
import YoweeCore

struct PipelineEditorView: View {
    @Bindable var pipeline: Pipeline
    @Environment(PipelineStore.self) private var store
    @State private var selectedStep: PromptStep?

    private var validationError: String? {
        if pipeline.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Pipeline name cannot be empty."
        }
        if pipeline.steps.isEmpty {
            return "Add at least one step."
        }
        for step in pipeline.steps {
            if !step.userTemplate.contains("{{input}}") {
                return "Step '\(step.modelID)' template must contain {{input}}."
            }
            if step.modelID.trimmingCharacters(in: .whitespaces).isEmpty {
                return "All steps must have a model ID."
            }
        }
        return nil
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Steps").font(.headline)
                    Spacer()
                    HStack(spacing: 0) {
                        Button(action: addStep) {
                            Image(systemName: "plus")
                        }
                        .help("Add Step")
                        Divider().frame(height: 14)
                        Button(action: deleteSelectedStep) {
                            Image(systemName: "minus")
                        }
                        .help("Delete Step")
                        .disabled(selectedStep == nil)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 6)

                List(selection: $selectedStep) {
                    ForEach(pipeline.sortedSteps) { step in
                        HStack {
                            Image(systemName: "chevron.right.circle")
                                .foregroundStyle(.secondary)
                            Text(step.name.isEmpty ? step.modelID : step.name)
                                .lineLimit(1)
                        }
                        .tag(step)
                    }
                    .onMove(perform: moveSteps)
                    .onDelete(perform: deleteSteps)
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 180, maxWidth: 220)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pipeline Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Name", text: $pipeline.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: pipeline.name) { _, _ in store.save() }
                }

                if let step = selectedStep {
                    Divider()
                    StepEditorView(step: step)
                } else {
                    ContentUnavailableView(
                        "Select a Step",
                        systemImage: "chevron.right.circle",
                        description: Text("Choose a step to edit its prompt.")
                    )
                }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 360)
        }
        .navigationTitle(pipeline.name)
    }

    private func addStep() {
        let order = pipeline.steps.count
        let defaultProvider = LLMProvider.openai
        let step = PromptStep(
            name: "Step \(order + 1)",
            userTemplate: "{{input}}",
            provider: defaultProvider,
            modelID: defaultProvider.defaultModelID,
            sortOrder: order
        )
        pipeline.steps.append(step)
        store.save()
        selectedStep = step
    }

    private func deleteSelectedStep() {
        guard let step = selectedStep,
              let index = pipeline.sortedSteps.firstIndex(where: { $0.id == step.id }) else { return }
        selectedStep = nil
        deleteSteps(at: IndexSet([index]))
    }

    private func deleteSteps(at offsets: IndexSet) {
        let sorted = pipeline.sortedSteps
        for index in offsets {
            pipeline.steps.removeAll { $0.id == sorted[index].id }
        }
        store.save()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var reordered = pipeline.sortedSteps
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, step) in reordered.enumerated() {
            step.sortOrder = index
        }
        store.save()
    }
}
