import Foundation
@testable import Rockxy
import Testing

// Regression tests for the Library > Notes collection: navigation scope, filtering,
// persisted-only rows, the coordinator note mutation/normalization seam, and UI contracts.

// MARK: - NotesCollectionTests

@MainActor
struct NotesCollectionTests {
    // MARK: - Aggregate & Single Selection

    @Test("allNotes scope shows only note-bearing transactions")
    func allNotesShowsNotedOnly() {
        let coordinator = MainContentCoordinator()
        let plain = TestFixtures.makeTransaction()
        let noted = TestFixtures.makeTransaction()
        noted.comment = "Investigate this 500"
        let pinnedOnly = TestFixtures.makeTransaction()
        pinnedOnly.isPinned = true
        coordinator.transactions = [plain, noted, pinnedOnly]

        coordinator.selectSidebarItem(.allNotes)

        #expect(coordinator.filterCriteria.sidebarScope == .notes)
        #expect(coordinator.filteredTransactions.map(\.id) == [noted.id])
    }

    @Test("Whitespace-only comment is not treated as a note")
    func whitespaceCommentIsNotNote() {
        let coordinator = MainContentCoordinator()
        let blankNote = TestFixtures.makeTransaction()
        blankNote.comment = "   \n\t"
        coordinator.transactions = [blankNote]

        coordinator.selectSidebarItem(.allNotes)

        #expect(coordinator.filteredTransactions.isEmpty)
        #expect(coordinator.allNotesTransactions.isEmpty)
    }

    @Test("Selecting a note transaction scopes to notes and selects it")
    func noteTransactionSelectionSelectsExact() {
        let coordinator = MainContentCoordinator()
        let notedA = TestFixtures.makeTransaction(url: "https://api.example.com/a")
        notedA.comment = "note A"
        let notedB = TestFixtures.makeTransaction(url: "https://api.example.com/b")
        notedB.comment = "note B"
        coordinator.transactions = [notedA, notedB]

        coordinator.selectSidebarItem(.noteTransaction(id: notedB.id))

        #expect(coordinator.filterCriteria.sidebarScope == .notes)
        #expect(coordinator.selectedTransaction?.id == notedB.id)
        #expect(Set(coordinator.filteredTransactions.map(\.id)) == [notedA.id, notedB.id])
    }

    @Test("Switching away from notes resets scope to allTraffic")
    func switchingAwayResetsScope() {
        let coordinator = MainContentCoordinator()
        let noted = TestFixtures.makeTransaction()
        noted.comment = "note"
        let plain = TestFixtures.makeTransaction()
        coordinator.transactions = [noted, plain]

        coordinator.selectSidebarItem(.allNotes)
        #expect(coordinator.filterCriteria.sidebarScope == .notes)

        coordinator.selectSidebarItem(.allApps)
        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    // MARK: - Search & Persisted-Only Filtering

    @Test("Notes scope respects search text")
    func notesScopeRespectsSearch() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/users/1")
        match.comment = "note"
        let noMatch = TestFixtures.makeTransaction(url: "https://api.example.com/posts/1")
        noMatch.comment = "note"
        coordinator.transactions = [match, noMatch]

        coordinator.selectSidebarItem(.allNotes)
        coordinator.filterCriteria.searchText = "users"
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
    }

    @Test("Notes collection includes persisted-only rows deduplicated with live rows")
    func notesIncludesPersistedOnlyRows() {
        let coordinator = MainContentCoordinator()
        let live = TestFixtures.makeTransaction(url: "https://api.example.com/live")
        live.comment = "live note"
        let persisted = TestFixtures.makeTransaction(url: "https://api.example.com/persisted")
        persisted.comment = "persisted note"
        coordinator.transactions = [live]
        coordinator.persistedFavorites = [persisted]

        let notes = coordinator.allNotesTransactions
        #expect(Set(notes.map(\.id)) == [live.id, persisted.id])

        coordinator.selectSidebarItem(.allNotes)
        #expect(Set(coordinator.filteredTransactions.map(\.id)) == [live.id, persisted.id])
    }

    @Test("A live row that is also persisted appears once in the notes collection")
    func notesDeduplicatesLiveAndPersisted() {
        let coordinator = MainContentCoordinator()
        let shared = TestFixtures.makeTransaction(url: "https://api.example.com/shared")
        shared.comment = "shared note"
        coordinator.transactions = [shared]
        coordinator.persistedFavorites = [shared]

        #expect(coordinator.allNotesTransactions.map(\.id) == [shared.id])
    }

    // MARK: - Mutation, Normalization & Removal Seam

    @Test("normalizedNote trims and collapses whitespace-only input to nil")
    func normalizedNoteContract() {
        #expect(MainContentCoordinator.normalizedNote(nil) == nil)
        #expect(MainContentCoordinator.normalizedNote("") == nil)
        #expect(MainContentCoordinator.normalizedNote("   \n\t ") == nil)
        #expect(MainContentCoordinator.normalizedNote("  keep me  ") == "keep me")
    }

    @Test("setNote adds a transaction to the notes collection")
    func setNoteAddsToNotes() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        coordinator.transactions = [transaction]

        coordinator.setNote("  needs review  ", for: transaction)

        #expect(transaction.comment == "needs review")
        #expect(coordinator.allNotesTransactions.map(\.id) == [transaction.id])
    }

    @Test("setNote with whitespace-only input stores nil and stays out of notes")
    func setNoteWhitespaceNormalizesToNil() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        coordinator.transactions = [transaction]

        coordinator.setNote("   ", for: transaction)

        #expect(transaction.comment == nil)
        #expect(coordinator.allNotesTransactions.isEmpty)
    }

    @Test("Removing the last note drops the row from notes scope")
    func removingLastNoteDropsFromScope() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        coordinator.transactions = [transaction]

        coordinator.setNote("temporary", for: transaction)
        coordinator.selectSidebarItem(.allNotes)
        #expect(coordinator.filteredTransactions.map(\.id) == [transaction.id])

        coordinator.updateNoteDraft("", for: transaction)

        #expect(transaction.hasNote == false)
        #expect(coordinator.allNotesTransactions.isEmpty)
        #expect(coordinator.filteredTransactions.isEmpty)
    }

    @Test("Removing a note from the selected child returns selection to all Notes")
    func removingSelectedChildFallsBackToAllNotes() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.comment = "temporary"
        coordinator.transactions = [transaction]
        coordinator.selectSidebarItem(.noteTransaction(id: transaction.id))

        coordinator.updateNoteDraft(nil, for: transaction)

        #expect(coordinator.sidebarSelection == .allNotes)
        #expect(coordinator.selectedTransaction == nil)
        #expect(coordinator.filteredTransactions.isEmpty)
    }

    @Test("Editing note text recomputes an active Note search")
    func editingNoteRecomputesNoteSearch() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.comment = "alpha"
        coordinator.transactions = [transaction]
        coordinator.filterCriteria.searchField = .comment
        coordinator.filterCriteria.searchText = "alpha"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [transaction.id])

        coordinator.updateNoteDraft("beta", for: transaction)

        #expect(coordinator.filteredTransactions.isEmpty)
    }

    @Test("Removing a note retains the row when it is also pinned")
    func removingNoteRetainsPinnedRow() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.isPinned = true
        coordinator.persistedFavorites = [transaction]
        coordinator.setNote("a note", for: transaction)

        coordinator.setNote(nil, for: transaction)

        #expect(transaction.comment == nil)
        #expect(coordinator.allNotesTransactions.isEmpty)
        #expect(coordinator.allPinnedTransactions.map(\.id) == [transaction.id])
        #expect(coordinator.persistedFavorites.map(\.id) == [transaction.id])
    }

    @Test("Remove-note context action clears the note but keeps a saved row")
    func removeFavoriteNoteKeepsSaved() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.isSaved = true
        transaction.comment = "note text"
        coordinator.transactions = [transaction]

        coordinator.removeFavoriteTransaction(transaction, from: .notes)

        #expect(transaction.comment == nil)
        #expect(transaction.isSaved == true)
        #expect(coordinator.allNotesTransactions.isEmpty)
        #expect(coordinator.allSavedTransactions.map(\.id) == [transaction.id])
    }

    @Test("Open note in new tab scopes the workspace to the exact request")
    func openNoteInNewTabScopesExact() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/persisted-note")
        transaction.comment = "persisted note"
        coordinator.persistedFavorites = [transaction]

        coordinator.openFavoriteTransactionInNewTab(transaction, from: .notes)

        let workspace = coordinator.workspaceStore.workspaces[1]
        #expect(workspace.filterCriteria.sidebarScope == .notes)
        #expect(workspace.filterCriteria.exactTransactionID == transaction.id)
        #expect(workspace.filteredTransactions.map(\.id) == [transaction.id])
    }

    // MARK: - Active Filter Lifecycle

    @Test("Notes scope counts as an active filter")
    func notesScopeCountsAsActiveFilter() {
        var criteria = FilterCriteria.empty
        #expect(criteria.isEmpty)
        #expect(criteria.activeFilterCount == 0)

        criteria.sidebarScope = .notes

        #expect(!criteria.isEmpty)
        #expect(criteria.activeFilterCount == 1)
    }

    @Test("Clearing the Notes scope restores All Traffic and selection, mirroring Saved/Pinned")
    func clearingNotesScopeRestoresAllTraffic() {
        let coordinator = MainContentCoordinator()
        let noted = TestFixtures.makeTransaction()
        noted.comment = "keep"
        let plain = TestFixtures.makeTransaction()
        coordinator.transactions = [noted, plain]

        coordinator.selectSidebarItem(.allNotes)
        #expect(coordinator.filterCriteria.sidebarScope == .notes)
        #expect(coordinator.sidebarSelection == .allNotes)

        // Mirror the ActiveFilterSummaryBar Notes chip removal action.
        coordinator.filterCriteria.sidebarScope = .allTraffic
        coordinator.filterCriteria.exactTransactionID = nil
        coordinator.sidebarSelection = nil
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filterCriteria.exactTransactionID == nil)
        #expect(coordinator.sidebarSelection == nil)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    // MARK: - UI / Source Contracts

    @Test("Notes section maps to the correct sidebar items")
    func notesSectionSidebarContract() {
        let id = UUID()
        #expect(FavoriteTransactionSection.notes.displayName == "Notes")
        #expect(FavoriteTransactionSection.notes.sidebarItem(for: id) == .noteTransaction(id: id))
        #expect(FavoriteTransactionSection.notes.fallbackSidebarItem == .allNotes)
    }

    @Test("Annotation workflow labels read as Note/Notes")
    func annotationLabelsUseNoteNaming() {
        #expect(RequestInspectorTab.comments.displayName == "Notes")
        #expect(FilterField.comment.displayName == "Note")
    }
}
