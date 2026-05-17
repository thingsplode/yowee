import Foundation

@Observable
final class Pipeline: Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var steps: [PromptStep]
    /// Path to an optional .txt or .md file whose content is injected as {{context}}
    /// in every step's prompt template when this pipeline runs.
    var contextFilePath: String?

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        steps: [PromptStep] = [],
        contextFilePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.steps = steps
        self.contextFilePath = contextFilePath
    }

    var sortedSteps: [PromptStep] {
        steps.sorted { $0.sortOrder < $1.sortOrder }
    }
}

extension Pipeline: Hashable {
    static func == (lhs: Pipeline, rhs: Pipeline) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
