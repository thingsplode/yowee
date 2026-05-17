import SwiftUI
import UniformTypeIdentifiers
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
            if step.stepKind == .prompt, !step.userTemplate.contains("{{input}}") {
                return "Step '\(step.name.isEmpty ? step.modelID : step.name)' template must contain {{input}}."
            }
            if step.stepKind == .research, !step.queryTemplate.contains("{{input}}") {
                return "Step '\(step.name)' query template must contain {{input}}."
            }
            if step.stepKind == .prompt, step.modelID.trimmingCharacters(in: .whitespaces).isEmpty {
                return "All prompt steps must have a model ID."
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
            .frame(minWidth: 120, maxWidth: 220)

            VStack(alignment: .leading, spacing: 0) {
                // Pipeline Name — pinned so it stays visible when step content scrolls.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pipeline Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Name", text: $pipeline.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: pipeline.name) { _, _ in store.save() }
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

                ContextFileRow(pipeline: pipeline)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Divider()

                // Step editor — scrollable so content never pushes the tab bar or header off-screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let step = selectedStep {
                            StepEditorView(step: step)
                        } else {
                            ContentUnavailableView(
                                "Select a Step",
                                systemImage: "chevron.right.circle",
                                description: Text("Choose a step to edit its prompt.")
                            )
                            .frame(maxWidth: .infinity)
                        }

                        if let error = validationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 200)
        }
        .navigationTitle("Yowee Configuration")
        .onChange(of: pipeline.id, initial: true) {
            selectedStep = pipeline.sortedSteps.first
        }
    }

    private func addStep() {
        selectedStep = store.addStep(to: pipeline)
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
            store.deleteStep(id: sorted[index].id, from: pipeline)
        }
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        store.moveSteps(from: source, to: destination, in: pipeline.sortedSteps, pipeline: pipeline)
    }
}

// MARK: - Context file drop zone

private struct ContextFileRow: View {
    @Bindable var pipeline: Pipeline
    @Environment(PipelineStore.self) private var store
    @State private var isTargeted = false

    private static let acceptedExtensions: Set<String> = ["txt", "md"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Context File").font(.caption).foregroundStyle(.secondary)
            Group {
                if let path = pipeline.contextFilePath {
                    // File is set — show name with clear button.
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            pipeline.contextFilePath = nil
                            store.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove context file")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    // Drop zone.
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.doc")
                                .font(.caption)
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                            Text("Drop a .txt or .md file here")
                                .font(.caption2)
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color(nsColor: .separatorColor) as Color,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
                    .background(
                        isTargeted ? Color.accentColor.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)

            Text("Content is available as {{context}} in prompt templates.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  Self.acceptedExtensions.contains(url.pathExtension.lowercased())
            else { return }
            DispatchQueue.main.async {
                pipeline.contextFilePath = url.path
                store.save()
            }
        }
        return true
    }
}
