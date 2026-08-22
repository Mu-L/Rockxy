import Foundation
@testable import Rockxy
import Testing

/// Coverage for the non-visual traffic navigation-state lane: Jump-to-First/Last resolving from the
/// display order, one-shot reveal requests, and the invariant that jumping never mutates Follow Live.
@MainActor
struct TrafficNavigationStateTests {
    // MARK: - Display-order endpoints

    @Test("Jump to First/Last resolves endpoints from the display order, not chronological order")
    func jumpUsesDisplayOrder() {
        let coordinator = MainContentCoordinator()
        // Received (chronological) order differs from the URL-sorted display order.
        let beta = TestFixtures.makeTransaction(url: "https://beta.example.com/1")
        let gamma = TestFixtures.makeTransaction(url: "https://gamma.example.com/2")
        let alpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/3")
        coordinator.transactions = [beta, gamma, alpha]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        // Sanity: display order is alpha, beta, gamma; chronological is beta, gamma, alpha.
        #expect(coordinator.filteredRows.map(\.host) == ["alpha.example.com", "beta.example.com", "gamma.example.com"])
        #expect(coordinator.filteredTransactions.first?.id == beta.id)
        #expect(coordinator.filteredTransactions.last?.id == alpha.id)

        coordinator.selectFirstFilteredTransaction()
        #expect(coordinator.selectedTransaction?.id == alpha.id)
        #expect(coordinator.selectedTransactionIDs == [alpha.id])

        coordinator.selectLastFilteredTransaction()
        #expect(coordinator.selectedTransaction?.id == gamma.id)
        #expect(coordinator.selectedTransactionIDs == [gamma.id])
    }

    @Test("Endpoints resolve the correct transaction through the selection index")
    func endpointsResolveThroughSelectionIndex() {
        let coordinator = MainContentCoordinator()
        let first = TestFixtures.makeTransaction(url: "https://alpha.example.com/1")
        let last = TestFixtures.makeTransaction(url: "https://zeta.example.com/9")
        coordinator.transactions = [first, last]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        coordinator.selectFirstFilteredTransaction()
        #expect(coordinator.selectedTransaction === first)

        coordinator.selectLastFilteredTransaction()
        #expect(coordinator.selectedTransaction === last)
    }

    // MARK: - Reveal request publication

    @Test("Jump publishes a reveal request carrying the target transaction and a fresh generation")
    func jumpPublishesRevealRequest() {
        let coordinator = MainContentCoordinator()
        let alpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/1")
        let zeta = TestFixtures.makeTransaction(url: "https://zeta.example.com/9")
        coordinator.transactions = [alpha, zeta]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.trafficRevealRequest == nil)

        coordinator.selectFirstFilteredTransaction()
        let firstReveal = coordinator.trafficRevealRequest
        #expect(firstReveal?.transactionID == alpha.id)

        coordinator.selectLastFilteredTransaction()
        let lastReveal = coordinator.trafficRevealRequest
        #expect(lastReveal?.transactionID == zeta.id)
        // Generation strictly advances between distinct endpoints.
        #expect((lastReveal?.generation ?? 0) > (firstReveal?.generation ?? 0))
    }

    @Test("Repeated jump to the same endpoint still publishes a fresh reveal generation")
    func repeatedSameEndpointAdvancesGeneration() {
        let coordinator = MainContentCoordinator()
        let only = TestFixtures.makeTransaction(url: "https://only.example.com/1")
        coordinator.transactions = [only]
        coordinator.recomputeFilteredTransactions()

        coordinator.selectLastFilteredTransaction()
        let firstReveal = coordinator.trafficRevealRequest
        coordinator.selectLastFilteredTransaction()
        let secondReveal = coordinator.trafficRevealRequest

        #expect(firstReveal?.transactionID == only.id)
        #expect(secondReveal?.transactionID == only.id)
        #expect(firstReveal != secondReveal)
        #expect((secondReveal?.generation ?? 0) > (firstReveal?.generation ?? 0))
    }

    // MARK: - Fail-safe inputs

    @Test("Jump on an empty view changes nothing and publishes no reveal request")
    func jumpOnEmptyViewIsNoOp() {
        let coordinator = MainContentCoordinator()
        coordinator.recomputeFilteredTransactions()

        coordinator.selectFirstFilteredTransaction()
        coordinator.selectLastFilteredTransaction()

        #expect(coordinator.selectedTransaction == nil)
        #expect(coordinator.selectedTransactionIDs.isEmpty)
        #expect(coordinator.trafficRevealRequest == nil)
    }

    @Test("A stale or missing selection-index entry fails safely without selecting or revealing")
    func staleSelectionIndexFailsSafely() {
        let coordinator = MainContentCoordinator()
        let alpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/1")
        let zeta = TestFixtures.makeTransaction(url: "https://zeta.example.com/9")
        coordinator.transactions = [alpha, zeta]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        // Drop the last displayed row's index entry to simulate a stale/missing lookup.
        guard let lastRowID = coordinator.filteredRows.last?.id else {
            Issue.record("Expected a last row after recompute")
            return
        }
        coordinator.activeWorkspace.trafficSelectionIndex[lastRowID] = nil

        coordinator.selectLastFilteredTransaction()

        #expect(coordinator.selectedTransaction == nil)
        #expect(coordinator.selectedTransactionIDs.isEmpty)
        #expect(coordinator.trafficRevealRequest == nil)
    }

    // MARK: - Follow Live isolation

    @Test("Jump never enables Follow Live")
    func jumpDoesNotEnableFollowLive() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction(url: "https://alpha.example.com/1")]
        coordinator.recomputeFilteredTransactions()

        #expect(!coordinator.isFollowingLiveTraffic)
        coordinator.selectFirstFilteredTransaction()
        coordinator.selectLastFilteredTransaction()
        #expect(!coordinator.isFollowingLiveTraffic)
    }

    @Test("Jump never disables an already-armed Follow Live")
    func jumpDoesNotDisableFollowLive() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction(url: "https://alpha.example.com/1")]
        coordinator.recomputeFilteredTransactions()
        coordinator.setFollowingLiveTraffic(true)

        coordinator.selectFirstFilteredTransaction()
        coordinator.selectLastFilteredTransaction()

        #expect(coordinator.isFollowingLiveTraffic)
    }

    // MARK: - Workspace scoping

    @Test("Reveal requests are scoped to the active workspace")
    func revealRequestIsWorkspaceScoped() {
        let coordinator = MainContentCoordinator()
        let first = coordinator.activeWorkspace
        coordinator.transactions = [TestFixtures.makeTransaction(url: "https://alpha.example.com/1")]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectLastFilteredTransaction()

        let second = coordinator.workspaceStore.createWorkspace(title: "Second")

        #expect(first.trafficRevealRequest != nil)
        #expect(second.trafficRevealRequest == nil)
    }

    @Test("Reset clears the workspace reveal request alongside selection state")
    func resetClearsRevealRequest() {
        let workspace = WorkspaceState()
        workspace.publishTrafficRevealRequest(for: UUID())
        #expect(workspace.trafficRevealRequest != nil)

        workspace.reset()

        #expect(workspace.trafficRevealRequest == nil)
    }

    @Test("Reveal generation stays monotonic across a reset")
    func revealGenerationMonotonicAcrossReset() {
        let workspace = WorkspaceState()
        let target = UUID()
        workspace.publishTrafficRevealRequest(for: target)
        let beforeReset = workspace.trafficRevealRequest?.generation ?? 0

        workspace.reset()
        workspace.publishTrafficRevealRequest(for: target)
        let afterReset = workspace.trafficRevealRequest?.generation ?? 0

        #expect(afterReset > beforeReset)
    }
}
