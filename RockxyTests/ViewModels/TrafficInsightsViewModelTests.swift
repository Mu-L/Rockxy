import Foundation
@testable import Rockxy
import Testing

// Regression tests for the Traffic Insights view model and coordinator handoffs.

// MARK: - TrafficInsightsViewModelTests

@MainActor
struct TrafficInsightsViewModelTests {
    // MARK: Internal

    @Test("Attaching builds a report from the coordinator's transactions")
    func attachBuildsReport() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com", "a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))

        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()

        #expect(viewModel.hasReport)
        #expect(viewModel.report.totals.requestCount == 3)
        #expect(viewModel.report.topHosts.first?.name == "a.example.com")
        #expect(viewModel.completedRunCount >= 1)
        viewModel.detach()
    }

    @Test("Visible scope follows the workspace filters while All Traffic ignores them")
    func scopeFollowsFilters() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com", "a.example.com"])
        coordinator.selectSidebarItem(.domainNode(domain: "b.example.com"))
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)

        viewModel.scope = .visibleTraffic
        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 1)
        #expect(viewModel.scopedTransactionCount == 1)

        viewModel.scope = .allTraffic
        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 3)
        viewModel.detach()
    }

    @Test("Time window changes rebuild with the new window")
    func timeWindowChangesRebuild() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)

        viewModel.timeWindow = .lastFiveMinutes
        await viewModel.refreshAndWait()

        #expect(viewModel.report.timeWindow == .lastFiveMinutes)
        viewModel.detach()
    }

    @Test("Paused report ignores source changes until refreshed or resumed")
    func pausedReportFreezes() async throws {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 1)

        viewModel.isLive = false
        coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://c.example.com/x"))
        coordinator.recomputeFilteredTransactions()
        viewModel.sourceDidChange(coordinator.trafficInsightsSourceToken)
        try await Task.sleep(for: .milliseconds(60))
        #expect(viewModel.report.totals.requestCount == 1)

        viewModel.refreshNow()
        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 2)

        coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://d.example.com/x"))
        coordinator.recomputeFilteredTransactions()
        viewModel.sourceDidChange(coordinator.trafficInsightsSourceToken)
        try await Task.sleep(for: .milliseconds(60))
        #expect(viewModel.report.totals.requestCount == 2)

        viewModel.isLive = true
        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 3)
        viewModel.detach()
    }

    @Test("Returning to a paused report preserves its snapshot until refresh")
    func pausedReportSurvivesNavigation() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()
        viewModel.isLive = false
        viewModel.detach()

        coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://b.example.com/x"))
        coordinator.recomputeFilteredTransactions()
        viewModel.attach(to: coordinator)
        #expect(viewModel.report.totals.requestCount == 1)

        await viewModel.refreshAndWait()
        #expect(viewModel.report.totals.requestCount == 2)
        viewModel.detach()
    }

    @Test("Live report picks up debounced source changes")
    func liveReportFollowsSourceChanges() async throws {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()

        coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://c.example.com/x"))
        coordinator.recomputeFilteredTransactions()
        viewModel.sourceDidChange(coordinator.trafficInsightsSourceToken)

        var attempts = 0
        while viewModel.report.totals.requestCount != 2, attempts < 100 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(viewModel.report.totals.requestCount == 2)
        viewModel.detach()
    }

    @Test("Live source changes coalesce into one throttled rebuild instead of one per batch")
    func liveSourceChangesCoalesce() async throws {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(40), minimumLiveInterval: .milliseconds(40))
        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()
        let runsBefore = viewModel.completedRunCount

        // Ten batches inside one debounce window, like the 100 ms capture batches.
        for index in 0 ..< 10 {
            coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://c.example.com/\(index)"))
            coordinator.recomputeFilteredTransactions()
            viewModel.sourceDidChange(coordinator.trafficInsightsSourceToken)
        }

        var attempts = 0
        while viewModel.report.totals.requestCount != 11, attempts < 200 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(viewModel.report.totals.requestCount == 11)
        #expect(viewModel.completedRunCount == runsBefore + 1)
        viewModel.detach()
    }

    @Test("Live rebuild spacing grows with the measured build time and stays bounded")
    func liveIntervalScalesWithBuildTime() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(
            debounce: .milliseconds(350),
            minimumLiveInterval: .seconds(1),
            maximumLiveInterval: .seconds(5)
        )
        // Before any build the live floor applies.
        #expect(viewModel.liveRefreshInterval == .seconds(1))

        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()
        // The interval is three builds long, but never shorter than the floor nor longer than
        // the cap, whatever a loaded test host makes the build take.
        let scaled = viewModel.lastBuildDuration * TrafficInsightsViewModel.liveIntervalBuildMultiplier
        #expect(viewModel.lastBuildDuration > .zero)
        #expect(viewModel.liveRefreshInterval == min(max(scaled, .seconds(1)), .seconds(5)))
        #expect(viewModel.liveRefreshInterval >= .seconds(1))
        #expect(viewModel.liveRefreshInterval <= .seconds(5))
        viewModel.detach()
    }

    @Test("A cancelled build stops between passes and applies nothing")
    func cancelledBuildStopsEarly() {
        let samples = (0 ..< 200).map { index in
            TrafficInsightsSample(transaction: TestFixtures.makeTransaction(url: "https://h\(index % 7).example.com/\(index)"))
        }
        var checks = 0
        let output = TrafficInsightsEngine.buildReport(samples: samples) {
            checks += 1
            return checks >= 2
        }
        #expect(output == nil)
        #expect(checks == 2)
        #expect(TrafficInsightsEngine.buildReport(samples: samples) { false }?.report.totals.requestCount == 200)
    }

    @Test("Detaching cancels in-flight work so no result is applied afterwards")
    func detachCancelsWork() async throws {
        let coordinator = makeCoordinator(hosts: (0 ..< 200).map { "host-\($0).example.com" })
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)
        viewModel.detach()
        try await Task.sleep(for: .milliseconds(80))

        #expect(!viewModel.isComputing)
        #expect(viewModel.completedRunCount == 0)
    }

    @Test("Markdown export reflects the coordinator's project and tab names")
    func markdownUsesCoordinatorNames() async {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let viewModel = TrafficInsightsViewModel(debounce: .milliseconds(5))
        viewModel.attach(to: coordinator)
        await viewModel.refreshAndWait()

        let markdown = viewModel.markdownReport()

        #expect(markdown.contains("- Project: \(coordinator.trafficInsightsProjectName)"))
        #expect(markdown.contains("- Traffic Tab: \(coordinator.trafficInsightsTrafficTabName)"))
        #expect(markdown.contains("| Requests | 1 |"))
        viewModel.detach()
    }

    @Test("Source token changes on append, filter recompute, and session generation")
    func sourceTokenTracksCoordinatorState() {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let initial = coordinator.trafficInsightsSourceToken

        coordinator.transactions.append(TestFixtures.makeTransaction(url: "https://b.example.com/x"))
        let afterAppend = coordinator.trafficInsightsSourceToken
        #expect(afterAppend != initial)

        coordinator.recomputeFilteredTransactions()
        let afterRecompute = coordinator.trafficInsightsSourceToken
        #expect(afterRecompute != afterAppend)

        coordinator.sessionGeneration &+= 1
        #expect(coordinator.trafficInsightsSourceToken != afterRecompute)
    }

    @Test("Samples snapshot the requested scope with bytes and lifecycle fields")
    func samplesSnapshotScope() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com"])
        coordinator.selectSidebarItem(.domainNode(domain: "a.example.com"))

        let all = coordinator.trafficInsightsSamples(scope: .allTraffic)
        let visible = coordinator.trafficInsightsSamples(scope: .visibleTraffic)

        #expect(all.count == 2)
        #expect(visible.count == 1)
        #expect(visible.first?.host == "a.example.com")
        #expect(all.allSatisfy { $0.statusClass == .success })
    }

    @Test("Selecting the Insights row switches the center content and clears the sidebar scope")
    func insightsSelectionSwitchesMainTab() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com"])
        coordinator.selectSidebarItem(.domainNode(domain: "a.example.com"))
        #expect(coordinator.filteredTransactions.count == 1)

        coordinator.selectSidebarItem(.insights)

        #expect(coordinator.activeMainTab == .insights)
        #expect(coordinator.isShowingTrafficInsights)
        #expect(coordinator.sidebarSelection == .insights)
        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.filteredTransactions.count == 2)

        coordinator.selectSidebarItem(.domainNode(domain: "b.example.com"))
        #expect(coordinator.activeMainTab == .traffic)
        #expect(coordinator.filteredTransactions.count == 1)
    }

    @Test("Show, hide, and toggle route through the sidebar selection")
    func showHideToggleInsights() {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])

        coordinator.showTrafficInsights()
        #expect(coordinator.activeMainTab == .insights)
        #expect(coordinator.sidebarSelection == .insights)

        coordinator.toggleTrafficInsights()
        #expect(coordinator.activeMainTab == .traffic)
        #expect(coordinator.sidebarSelection == .allApps)

        coordinator.toggleTrafficInsights()
        #expect(coordinator.activeMainTab == .insights)

        coordinator.hideTrafficInsights()
        #expect(coordinator.activeMainTab == .traffic)
        #expect(coordinator.sidebarSelection == .allApps)
        coordinator.hideTrafficInsights()
        #expect(coordinator.activeMainTab == .traffic)
    }

    @Test("Insights selection survives sidebar pruning and snapshot hydration")
    func insightsSelectionPersists() {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        coordinator.selectSidebarItem(.insights)
        coordinator.pruneSidebarSelectionIfNeeded(in: coordinator.activeWorkspace)
        #expect(coordinator.sidebarSelection == .insights)

        let snapshot = ProjectTabSnapshot(capturing: coordinator.activeWorkspace)
        let restored = snapshot.hydrateWorkspaceState()
        #expect(restored.activeMainTab == .insights)
        #expect(restored.sidebarSelection == .insights)
    }

    @Test("Each Traffic Tab owns its own insights state")
    func insightsStateIsPerWorkspace() {
        let coordinator = makeCoordinator(hosts: ["a.example.com"])
        let first = coordinator.activeWorkspace.trafficInsights
        first.timeWindow = .lastHour
        first.scope = .allTraffic

        let second = WorkspaceState(title: "Second")
        #expect(second.trafficInsights !== first)
        #expect(second.trafficInsights.timeWindow == .entireSession)
        #expect(second.trafficInsights.scope == .visibleTraffic)
        #expect(first.timeWindow == .lastHour)
    }

    @Test("A tab keeps its Live choice when another tab changes the saved default")
    func livePreferenceIsOnlyAnInitialDefault() {
        let first = TrafficInsightsViewModel()
        let second = TrafficInsightsViewModel()
        first.configureInitialLivePreference(false)
        second.configureInitialLivePreference(true)
        first.configureInitialLivePreference(true)

        #expect(!first.isLive)
        #expect(second.isLive)
    }

    @Test("Drill-downs toggle the same pill, method, and signal filters the list uses")
    func drillDownsToggleListFilters() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com"])
        coordinator.transactions[0].response = TestFixtures.makeResponse(statusCode: 500)
        coordinator.recomputeFilteredTransactions()

        let status = TrafficInsightsDrillDown.protocolFilter(.status5xx)
        #expect(!coordinator.isTrafficInsightsDrillDownActive(status))
        coordinator.toggleTrafficInsightsDrillDown(status)
        #expect(coordinator.isTrafficInsightsDrillDownActive(status))
        #expect(coordinator.filteredTransactions.count == 1)
        coordinator.toggleTrafficInsightsDrillDown(status)
        #expect(!coordinator.isTrafficInsightsDrillDownActive(status))
        #expect(coordinator.filteredTransactions.count == 2)

        let method = TrafficInsightsDrillDown.method("POST")
        coordinator.toggleTrafficInsightsDrillDown(method)
        #expect(coordinator.isTrafficInsightsDrillDownActive(method))
        #expect(coordinator.isFilterBarVisible)
        #expect(coordinator.filterRules.contains { $0.field == .method && $0.value == "POST" && $0.isEnabled })
        #expect(coordinator.filteredTransactions.isEmpty)
        coordinator.toggleTrafficInsightsDrillDown(method)
        #expect(!coordinator.isTrafficInsightsDrillDownActive(method))
        #expect(!coordinator.isFilterBarVisible)
        #expect(coordinator.filteredTransactions.count == 2)

        let signal = TrafficInsightsDrillDown.trafficSignal(.errors)
        coordinator.toggleTrafficInsightsDrillDown(signal)
        #expect(coordinator.activeWorkspace.activeTrafficSignal == .errors)
        #expect(coordinator.filteredTransactions.count == 1)
        coordinator.toggleTrafficInsightsDrillDown(signal)
        #expect(coordinator.activeWorkspace.activeTrafficSignal == nil)
    }

    @Test("Revealing a timeline bin selects exactly its transactions")
    func revealBinSelectsTransactions() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com", "c.example.com"])
        let ids = [coordinator.transactions[0].id, coordinator.transactions[2].id]
        let bin = TrafficInsightsTimelineBin(
            start: Date(),
            sentBytes: 0,
            receivedBytes: 0,
            requestCount: 2,
            countsByStatusClass: [:],
            medianDuration: nil,
            tailDuration: nil,
            transactionIDs: ids
        )

        coordinator.revealTrafficInsightsBin(bin)

        #expect(coordinator.selectedTransactionIDs == Set(ids))
        #expect(coordinator.selectedTransaction?.id == ids[0])
        #expect(coordinator.activeMainTab == .traffic)
        #expect(coordinator.trafficRevealRequest?.transactionID == ids[0])
    }

    @Test("Reveal drops advanced rules only when they would hide a requested row")
    func revealClearsRulesOnlyWhenNeeded() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com"])
        coordinator.transactions[1].response = TestFixtures.makeResponse(statusCode: 500)
        coordinator.recomputeFilteredTransactions()
        coordinator.toggleTrafficInsightsDrillDown(.method("GET"))
        #expect(coordinator.isFilterBarVisible)

        // Both rows are GET, so the visible rule survives the reveal.
        coordinator.revealTrafficInsightsTransactions([coordinator.transactions[0].id])
        #expect(coordinator.isFilterBarVisible)
        #expect(coordinator.selectedTransaction?.id == coordinator.transactions[0].id)

        // A rule that hides the target is cleared so the selection is guaranteed visible.
        coordinator.toggleTrafficInsightsDrillDown(.method("GET"))
        coordinator.toggleTrafficInsightsDrillDown(.method("POST"))
        #expect(coordinator.filteredTransactions.isEmpty)
        coordinator.revealTrafficInsightsTransactions([coordinator.transactions[1].id])
        #expect(!coordinator.isFilterBarVisible)
        #expect(coordinator.filteredTransactions.count == 2)
        #expect(coordinator.selectedTransaction?.id == coordinator.transactions[1].id)
    }

    @Test("Host and app handoffs drive the sidebar scope like a sidebar click")
    func handoffsFocusSidebarScope() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com"])
        coordinator.transactions[0].clientApp = "Safari"

        coordinator.focusTrafficInsights(onHost: "b.example.com")
        #expect(coordinator.filterCriteria.sidebarDomain == "b.example.com")
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.activeMainTab == .traffic)

        coordinator.focusTrafficInsights(onApp: "Safari")
        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.filterCriteria.sidebarApp == "Safari")
        #expect(coordinator.filteredTransactions.count == 1)

        coordinator.focusTrafficInsights(onHost: "   ")
        #expect(coordinator.filterCriteria.sidebarApp == "Safari")
    }

    @Test("Reveal handoff clears filters and selects every still-present transaction")
    func revealSelectsTransactions() {
        let coordinator = makeCoordinator(hosts: ["a.example.com", "b.example.com", "c.example.com"])
        coordinator.selectSidebarItem(.domainNode(domain: "a.example.com"))
        let ids = [coordinator.transactions[1].id, coordinator.transactions[2].id, UUID()]

        coordinator.revealTrafficInsightsTransactions(ids)

        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.filteredTransactions.count == 3)
        #expect(coordinator.selectedTransactionIDs == Set(ids.prefix(2)))
        #expect(coordinator.selectedTransaction?.id == ids[0])
        #expect(coordinator.trafficRevealRequest?.transactionID == ids[0])

        coordinator.revealTrafficInsightsTransactions([coordinator.transactions[0].id])
        #expect(coordinator.selectedTransaction?.id == coordinator.transactions[0].id)

        coordinator.revealTrafficInsightsTransactions([UUID()])
        #expect(coordinator.selectedTransaction?.id == coordinator.transactions[0].id)
    }

    // MARK: Private

    private func makeCoordinator(hosts: [String]) -> MainContentCoordinator {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = hosts.enumerated().map { index, host in
            let transaction = TestFixtures.makeTransaction(url: "https://\(host)/path/\(index)")
            transaction.response?.body = Data(repeating: 0x01, count: 10 * (index + 1))
            return transaction
        }
        coordinator.recomputeFilteredTransactions()
        return coordinator
    }
}
