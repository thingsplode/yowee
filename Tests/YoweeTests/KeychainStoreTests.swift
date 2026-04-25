import Testing
@testable import YoweeCore

struct KeychainStoreTests {
    private static let base = "yowee.test.key"

    @Test func saveAndLoad() throws {
        let key = "\(Self.base).saveAndLoad"
        defer { KeychainStore.delete(for: key) }
        try KeychainStore.save("test-api-key-123", for: key)
        let loaded = KeychainStore.load(for: key)
        #expect(loaded == "test-api-key-123")
    }

    @Test func loadReturnsNilForMissingKey() {
        let result = KeychainStore.load(for: "\(Self.base).nonexistent.xyzzy")
        #expect(result == nil)
    }

    @Test func deleteRemovesKey() throws {
        let key = "\(Self.base).deleteRemovesKey"
        defer { KeychainStore.delete(for: key) }
        try KeychainStore.save("to-be-deleted", for: key)
        KeychainStore.delete(for: key)
        #expect(KeychainStore.load(for: key) == nil)
    }

    @Test func overwriteExistingKey() throws {
        let key = "\(Self.base).overwriteExistingKey"
        defer { KeychainStore.delete(for: key) }
        try KeychainStore.save("first-value", for: key)
        try KeychainStore.save("second-value", for: key)
        #expect(KeychainStore.load(for: key) == "second-value")
    }
}
