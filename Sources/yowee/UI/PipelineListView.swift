import SwiftUI

struct PipelineListView: View {
    @Environment(PipelineStore.self) private var store
    @State private var selectedPipeline: Pipeline?

    private var pipelines: [Pipeline] {
        store.sortedPipelines
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Pipelines").font(.headline)
                    Spacer()
                    HStack(spacing: 0) {
                        Button(action: addPipeline) {
                            Image(systemName: "plus")
                        }
                        .help("Add Pipeline")
                        Divider().frame(height: 14)
                        Button(action: deleteSelectedPipeline) {
                            Image(systemName: "minus")
                        }
                        .help("Delete Pipeline")
                        .disabled(selectedPipeline == nil)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List(selection: $selectedPipeline) {
                    ForEach(pipelines) { pipeline in
                        NavigationLink(value: pipeline) {
                            Label(pipeline.name, systemImage: "wand.and.sparkles")
                        }
                    }
                    .onMove(perform: movePipelines)
                    .onDelete(perform: deletePipelines)
                }
                .listStyle(.sidebar)

                Divider()

                Button(action: { store.restoreDefaults() }) {
                    Label("Restore Default Pipelines", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .help("Re-adds any default pipelines that have been deleted. Does not remove custom pipelines.")
            }
            // Pin sidebar width so column-width recalculation on detail changes can't shift it.
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            if let pipeline = selectedPipeline {
                PipelineEditorView(pipeline: pipeline)
            } else {
                ContentUnavailableView(
                    "Select a Pipeline",
                    systemImage: "wand.and.sparkles",
                    description: Text("Choose a pipeline to edit, or create a new one.")
                )
                .navigationTitle("Yowee Configuration")
            }
        }
    }

    private func addPipeline() {
        selectedPipeline = store.addPipeline()
    }

    private func deleteSelectedPipeline() {
        guard let pipeline = selectedPipeline else { return }
        selectedPipeline = nil
        store.deletePipeline(id: pipeline.id)
    }

    private func deletePipelines(at offsets: IndexSet) {
        let sorted = pipelines
        for index in offsets {
            store.deletePipeline(id: sorted[index].id)
        }
    }

    private func movePipelines(from source: IndexSet, to destination: Int) {
        store.movePipelines(from: source, to: destination, in: pipelines)
    }
}
