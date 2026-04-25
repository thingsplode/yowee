import Testing
@testable import YoweeCore

@Suite("PromptRenderer — edge cases")
struct PromptRendererEdgeCaseTests {

    @Test func emptyInputProducesEmptySubstitution() throws {
        let result = try PromptRenderer.render(template: "Process: {{input}}", input: "")
        #expect(result == "Process: ")
    }

    @Test func templateConsistingOnlyOfPlaceholder() throws {
        let result = try PromptRenderer.render(template: "{{input}}", input: "hello")
        #expect(result == "hello")
    }

    @Test func placeholderAtStart() throws {
        let result = try PromptRenderer.render(template: "{{input}} is the input", input: "foo")
        #expect(result == "foo is the input")
    }

    @Test func placeholderAtEnd() throws {
        let result = try PromptRenderer.render(template: "Translate: {{input}}", input: "bar")
        #expect(result == "Translate: bar")
    }

    @Test func inputContainingPlaceholderString() throws {
        // If the input itself contains {{input}}, the result should include the literal
        // substituted string — there should be no second-pass replacement.
        let result = try PromptRenderer.render(template: "Got: {{input}}", input: "{{input}}")
        // After first replacement: "Got: {{input}}" — the inserted literal must not be replaced again
        // Swift's replacingOccurrences does a single pass, so this is deterministic.
        #expect(result.contains("{{input}}"))
    }

    @Test func multilineTemplatePreservesNewlines() throws {
        let template = "Line 1\n{{input}}\nLine 3"
        let result = try PromptRenderer.render(template: template, input: "Line 2")
        #expect(result == "Line 1\nLine 2\nLine 3")
    }

    @Test func unicodeInputHandledCorrectly() throws {
        let result = try PromptRenderer.render(template: "{{input}}", input: "Héllo Wörld 🌍")
        #expect(result == "Héllo Wörld 🌍")
    }

    @Test func veryLongInputIsSubstituted() throws {
        let longInput = String(repeating: "A", count: 100_000)
        let result = try PromptRenderer.render(template: "START {{input}} END", input: longInput)
        #expect(result.hasPrefix("START "))
        #expect(result.hasSuffix(" END"))
        #expect(result.count == longInput.count + "START  END".count)
    }

    @Test func templateWithNoPlaceholderThrows() {
        #expect(throws: (any Error).self) {
            try PromptRenderer.render(template: "No placeholder here", input: "anything")
        }
    }

    @Test func templateWithWrongPlaceholderThrows() {
        #expect(throws: (any Error).self) {
            try PromptRenderer.render(template: "Use {input} not the right one", input: "x")
        }
    }
}
