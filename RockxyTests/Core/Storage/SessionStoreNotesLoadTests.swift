import Foundation
@testable import Rockxy
import Testing

// Regression tests for note-only transaction persistence in `SessionStore`.
// A transaction that is neither pinned nor saved must still survive a restart when it carries a note.

struct SessionStoreNotesLoadTests {
    // MARK: Internal

    @Test("Note-only transaction is reloaded by the Library startup query")
    func noteOnlyTransactionSurvivesReload() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let noteOnly = TestFixtures.makeTransaction(url: "https://api.example.com/note-only")
        noteOnly.comment = "Investigate later"
        try await store.saveTransaction(noteOnly)

        let reloaded = try SessionStore(directory: dir)
        let loaded = try await reloaded.loadPinnedAndSavedTransactions()

        let match = try #require(loaded.first { $0.id == noteOnly.id })
        #expect(match.isPinned == false)
        #expect(match.isSaved == false)
        #expect(match.comment == "Investigate later")
    }

    @Test("Startup query still excludes plain transactions and keeps pinned/saved")
    func startupQueryScopesCorrectly() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let plain = TestFixtures.makeTransaction(url: "https://api.example.com/plain")
        let pinned = TestFixtures.makeTransaction(url: "https://api.example.com/pinned")
        pinned.isPinned = true
        let saved = TestFixtures.makeTransaction(url: "https://api.example.com/saved")
        saved.isSaved = true
        let noted = TestFixtures.makeTransaction(url: "https://api.example.com/noted")
        noted.comment = "note"
        for transaction in [plain, pinned, saved, noted] {
            try await store.saveTransaction(transaction)
        }

        let loaded = try await store.loadPinnedAndSavedTransactions()
        let ids = Set(loaded.map(\.id))

        #expect(ids == [pinned.id, saved.id, noted.id])
        #expect(!ids.contains(plain.id))
    }

    // MARK: Private

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
