import Foundation
import YoweeCore

/// Owns the in-memory pipeline list and persists it to ~/.config/yowee/pipelines.json.
@Observable
@MainActor
final class PipelineStore {
    var pipelines: [Pipeline] = []

    /// Current storage schema version. Bump when PipelineRecord or StepRecord fields change.
    static let storageVersion = 2

    private static var configDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/yowee")
    }

    static var pipelinesURL: URL {
        configDir.appendingPathComponent("pipelines.json")
    }

    // MARK: - Mutations (each calls save() so callers don't have to)

    func addPipeline(name: String = "New Pipeline") -> Pipeline {
        let pipeline = Pipeline(name: name, sortOrder: pipelines.count)
        pipelines.append(pipeline)
        save()
        return pipeline
    }

    func deletePipeline(id: UUID) {
        pipelines.removeAll { $0.id == id }
        save()
    }

    func movePipelines(from source: IndexSet, to destination: Int, in sorted: [Pipeline]) {
        var reordered = sorted
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, pipeline) in reordered.enumerated() {
            pipeline.sortOrder = index
        }
        save()
    }

    func addStep(to pipeline: Pipeline) -> PromptStep {
        let defaultProvider = LLMProvider.openai
        let step = PromptStep(
            name: "Step \(pipeline.steps.count + 1)",
            userTemplate: "{{input}}",
            provider: defaultProvider,
            modelID: defaultProvider.defaultModelID,
            sortOrder: pipeline.steps.count
        )
        pipeline.steps.append(step)
        save()
        return step
    }

    func deleteStep(id: UUID, from pipeline: Pipeline) {
        pipeline.steps.removeAll { $0.id == id }
        save()
    }

    func moveSteps(from source: IndexSet, to destination: Int, in sorted: [PromptStep], pipeline: Pipeline) {
        var reordered = sorted
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, step) in reordered.enumerated() {
            step.sortOrder = index
        }
        save()
    }

    // MARK: - Sorted access (single source of truth; replaces per-call sort at each call site)

    var sortedPipelines: [Pipeline] {
        pipelines.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
    }

    // MARK: - Persistence

    func load() {
        let dir = Self.configDir
        let file = Self.pipelinesURL
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file)
        {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let records = try? decoder.decode([PipelineRecord].self, from: data) {
                pipelines = records.map(Pipeline.init(record:))
                    .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
                return
            }
        }

        // First launch or unreadable file — seed defaults and write.
        pipelines = makeDefaultPipelines()
        saveQuietly()
    }

    func save() {
        saveQuietly()
        NotificationCenter.default.post(name: .yoweePipelinesChanged, object: nil)
    }

    /// Adds any missing default pipelines without touching existing ones.
    func restoreDefaults() {
        let existing = Set(pipelines.map(\.name))
        let missing = makeDefaultPipelines().filter { !existing.contains($0.name) }
        guard !missing.isEmpty else { return }
        let nextOrder = (pipelines.map(\.sortOrder).max() ?? -1) + 1
        for (i, pipeline) in missing.enumerated() {
            pipeline.sortOrder = nextOrder + i
            pipelines.append(pipeline)
        }
        save()
    }

    // MARK: - Private

    private func saveQuietly() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let records = pipelines.map(PipelineRecord.init(pipeline:))
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: Self.pipelinesURL, options: .atomic)
    }

    private func makeDefaultPipelines() -> [Pipeline] {
        [
            Pipeline(name: "Improve Grammar", sortOrder: 0, steps: [
                PromptStep(
                    name: "Fix Grammar",
                    userTemplate: "Improve the grammar and clarity of the following text:\n\n{{input}}",
                    systemPrompt: "You are a writing assistant. Return only the corrected text with no explanation.",
                    provider: .anthropic,
                    modelID: "claude-sonnet-4-6",
                    sortOrder: 0
                ),
            ]),
            Pipeline(name: "Make Concise", sortOrder: 1, steps: [
                PromptStep(
                    name: "Condense",
                    userTemplate: "Rewrite the following text to be more concise. Return only the rewritten text:\n\n{{input}}",
                    provider: .anthropic,
                    modelID: "claude-sonnet-4-6",
                    sortOrder: 0
                ),
            ]),
            Pipeline(name: "Translate to English", sortOrder: 2, steps: [
                PromptStep(
                    name: "Translate",
                    userTemplate: "Translate the following text to English. Return only the translation:\n\n{{input}}",
                    provider: .anthropic,
                    modelID: "claude-sonnet-4-6",
                    sortOrder: 0
                ),
            ]),
            Pipeline(name: "Change Tone: Professional", sortOrder: 3, steps: [
                PromptStep(
                    name: "Professionalize",
                    userTemplate: "Rewrite the following text in a professional tone. Return only the rewritten text:\n\n{{input}}",
                    provider: .anthropic,
                    modelID: "claude-sonnet-4-6",
                    sortOrder: 0
                ),
            ]),
        ]
    }
}

// MARK: - JSON DTOs

private struct PipelineRecord: Codable {
    let version: Int
    let id: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let steps: [StepRecord]

    init(pipeline p: Pipeline) {
        version = PipelineStore.storageVersion
        id = p.id
        name = p.name
        sortOrder = p.sortOrder
        createdAt = p.createdAt
        steps = p.steps.map(StepRecord.init(step:))
    }

    /// Custom decoder: `version` defaults to 0 so existing files without the field still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 0
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        steps = try c.decode([StepRecord].self, forKey: .steps)
    }
}

private struct StepRecord: Codable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let systemPrompt: String?
    let userTemplate: String
    let providerRaw: String
    let modelID: String
    let ollamaThinkingDisabled: Bool
    let stepKindRaw: String
    let queryTemplate: String
    let tavilyMaxResults: Int
    let tavilySearchDepth: String

    init(step s: PromptStep) {
        id = s.id
        name = s.name
        sortOrder = s.sortOrder
        systemPrompt = s.systemPrompt
        userTemplate = s.userTemplate
        providerRaw = s.providerRaw
        modelID = s.modelID
        ollamaThinkingDisabled = s.ollamaThinkingDisabled
        stepKindRaw = s.stepKind.rawValue
        queryTemplate = s.queryTemplate
        tavilyMaxResults = s.tavilyMaxResults
        tavilySearchDepth = s.tavilySearchDepth
    }

    /// Custom decoder: new fields default gracefully so existing JSON (schema v1) still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        systemPrompt = try? c.decode(String.self, forKey: .systemPrompt)
        userTemplate = try c.decode(String.self, forKey: .userTemplate)
        providerRaw = try c.decode(String.self, forKey: .providerRaw)
        modelID = try c.decode(String.self, forKey: .modelID)
        ollamaThinkingDisabled = (try? c.decode(Bool.self, forKey: .ollamaThinkingDisabled)) ?? false
        stepKindRaw = (try? c.decode(String.self, forKey: .stepKindRaw)) ?? "prompt"
        queryTemplate = (try? c.decode(String.self, forKey: .queryTemplate)) ?? "{{input}}"
        tavilyMaxResults = (try? c.decode(Int.self, forKey: .tavilyMaxResults)) ?? 5
        tavilySearchDepth = (try? c.decode(String.self, forKey: .tavilySearchDepth)) ?? "basic"
    }
}

private extension Pipeline {
    convenience init(record r: PipelineRecord) {
        let steps = r.steps.map { s in
            PromptStep(
                id: s.id,
                name: s.name,
                userTemplate: s.userTemplate,
                systemPrompt: s.systemPrompt,
                provider: LLMProvider(rawValue: s.providerRaw) ?? .anthropic,
                modelID: s.modelID,
                sortOrder: s.sortOrder,
                ollamaThinkingDisabled: s.ollamaThinkingDisabled,
                stepKind: StepKind(rawValue: s.stepKindRaw) ?? .prompt,
                queryTemplate: s.queryTemplate,
                tavilyMaxResults: s.tavilyMaxResults,
                tavilySearchDepth: s.tavilySearchDepth
            )
        }
        self.init(id: r.id, name: r.name, sortOrder: r.sortOrder, createdAt: r.createdAt, steps: steps)
    }
}
