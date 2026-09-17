import Foundation

// Extends `MainContentCoordinator` with Traffic Insights snapshots, navigation, and handoffs.

// MARK: - MainContentCoordinator + TrafficInsights

extension MainContentCoordinator {
    /// Changes whenever the transactions Traffic Insights reads could have changed: a new batch,
    /// a filter recompute, a session reset, or a Traffic Tab switch.
    var trafficInsightsSourceToken: TrafficInsightsSourceToken {
        TrafficInsightsSourceToken(
            workspaceID: activeWorkspace.id,
            sessionGeneration: sessionGeneration,
            transactionCount: transactions.count,
            filteredCount: filteredTransactions.count,
            refreshToken: refreshToken
        )
    }

    var trafficInsightsProjectName: String {
        projectStore.activeProject.name
    }

    var trafficInsightsTrafficTabName: String {
        activeWorkspace.title
    }

    var isShowingTrafficInsights: Bool {
        activeMainTab == .insights
    }

    /// Snapshots the requested scope into `Sendable` samples so the engine can aggregate off the
    /// main actor without touching live transactions.
    func trafficInsightsSamples(scope: TrafficInsightsScope) -> [TrafficInsightsSample] {
        let source: [HTTPTransaction] = switch scope {
        case .allTraffic: transactions
        case .visibleTraffic: filteredTransactions
        }
        return source.map(TrafficInsightsSample.init(transaction:))
    }

    // MARK: - Navigation

    /// Shows the Insights report in the center content through the same sidebar path a click
    /// on the Insights row uses, so selection, filters, and persistence stay in one place.
    func showTrafficInsights() {
        guard sidebarSelection != .insights || activeMainTab != .insights else {
            return
        }
        selectSidebarItem(.insights)
    }

    /// Returns to the request list. The sidebar scope was already cleared when Insights was
    /// selected, so "All Traffic" is the honest destination.
    func hideTrafficInsights() {
        guard activeMainTab == .insights else {
            return
        }
        selectSidebarItem(nil)
    }

    func toggleTrafficInsights() {
        if activeMainTab == .insights {
            hideTrafficInsights()
        } else {
            showTrafficInsights()
        }
    }

    // MARK: - Drill-down filters

    /// Whether a report drill-down is currently applied to the Traffic Tab's filters.
    func isTrafficInsightsDrillDownActive(_ drillDown: TrafficInsightsDrillDown) -> Bool {
        switch drillDown {
        case let .protocolFilter(filter):
            filterCriteria.activeProtocolFilters.contains(filter)
        case let .method(method):
            methodFilterRuleIndex(for: method) != nil
        case let .trafficSignal(signal):
            activeWorkspace.activeTrafficSignal == signal
        }
    }

    /// Toggles a report drill-down through the same filter state the pill bar, method filter, and
    /// Signals use, so the report re-scopes itself and the request list agrees when the user
    /// returns to it.
    func toggleTrafficInsightsDrillDown(_ drillDown: TrafficInsightsDrillDown) {
        switch drillDown {
        case let .protocolFilter(filter):
            if filterCriteria.activeProtocolFilters.contains(filter) {
                filterCriteria.activeProtocolFilters.remove(filter)
            } else {
                filterCriteria.activeProtocolFilters.insert(filter)
            }
            recomputeFilteredTransactions()
        case let .method(method):
            // Methods go through the visible advanced-filter rule (like the table's context
            // menu) so the filter stays discoverable and removable after leaving the report.
            if let index = methodFilterRuleIndex(for: method) {
                filterRules.remove(at: index)
                if filterRules.isEmpty {
                    filterRules = [FilterRule()]
                    isFilterBarVisible = false
                }
                recomputeFilteredTransactions()
            } else {
                applyContextFilter(ContextFilterSuggestion(
                    field: .method,
                    value: method,
                    includeOperator: .is,
                    excludeOperator: .notEqual
                ))
            }
        case let .trafficSignal(signal):
            toggleTrafficSignal(signal)
        }
    }

    private func methodFilterRuleIndex(for method: String) -> Int? {
        guard isFilterBarVisible else {
            return nil
        }
        return filterRules.firstIndex { rule in
            rule.isEnabled
                && rule.field == .method
                && rule.filterOperator == .is
                && rule.value.caseInsensitiveCompare(method) == .orderedSame
        }
    }

    /// Selects the transactions captured in one timeline bin without leaving the report scope
    /// behind: filters are cleared like every other reveal so each row is guaranteed visible.
    func revealTrafficInsightsBin(_ bin: TrafficInsightsTimelineBin) {
        revealTrafficInsightsTransactions(bin.transactionIDs)
    }

    // MARK: - Handoffs

    /// Focuses the request list on one host through the same sidebar path a domain click uses,
    /// so the Focus Navigator, request list, and status bar all agree on the active scope.
    func focusTrafficInsights(onHost host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        selectSidebarItem(.domainNode(domain: trimmed))
    }

    func focusTrafficInsights(onApp app: String) {
        let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        selectSidebarItem(.app(name: trimmed, bundleId: observedApplicationIdentity(named: trimmed)?.bundleIdentifier))
    }

    /// Reveals a set of transactions in the request list. Sidebar scope and filters are cleared
    /// exactly as `revealTransaction(id:)` does, then every still-present transaction is selected
    /// with the first one as the primary row.
    func revealTrafficInsightsTransactions(_ ids: [UUID]) {
        let present = ids.filter { transaction(for: $0) != nil }
        guard let primary = present.first else {
            return
        }
        filterCriteria = .empty
        sidebarSelection = nil
        activeMainTab = .traffic
        recomputeFilteredTransactions()
        // Advanced rules, Signals, Focus Sets, and muted sources survive a plain reveal; drop
        // them only when they would hide one of the rows the user asked to see.
        if present.contains(where: { activeWorkspace.trafficSelectionIndex[$0] == nil }) {
            clearAllWorkspaceFilters()
        }
        if present.count == 1 {
            selectTransaction(transaction(for: primary))
        } else {
            selectTransactions(Set(present), primaryID: primary)
        }
    }
}

// MARK: - TrafficInsightsDrillDown

/// A report row that maps onto an existing Traffic Tab filter.
enum TrafficInsightsDrillDown: Equatable, Sendable {
    case protocolFilter(ProtocolFilter)
    case method(String)
    case trafficSignal(TrafficSignal)
}

// MARK: - TrafficInsightsSourceToken

/// Equatable identity of the coordinator state Traffic Insights depends on. Comparing tokens is
/// cheaper than diffing transaction arrays and lets the report debounce refreshes precisely.
struct TrafficInsightsSourceToken: Equatable, Sendable {
    let workspaceID: UUID
    let sessionGeneration: UInt
    let transactionCount: Int
    let filteredCount: Int
    let refreshToken: Int
}
