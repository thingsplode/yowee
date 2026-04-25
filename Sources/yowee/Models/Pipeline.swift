import Foundation

@Observable
final class Pipeline: Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var steps: [PromptStep]

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = Date(), steps: [PromptStep] = []) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.steps = steps
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
