import Foundation
import Observation

// Owns the Traffic Insights report state: scope, live refresh, and the current report.

// MARK: - TrafficInsightsViewModel

/// Main-actor state owner for the Insights report of one Traffic Tab.
///
/// The view model snapshots the coordinator's transactions on the main actor, runs the engine
/// on a detached task, and applies the result only when the run is still the latest one. Every
/// scope, window, or source change increments the run generation so a slower, older computation
/// can never overwrite a newer report.
@MainActor @Observable
final class TrafficInsightsViewModel {
    // MARK: Lifecycle

    init(
        debounce: Duration = .milliseconds(350),
        livePollInterval: Duration = .seconds(2)
    ) {
        self.debounce = debounce
        self.livePollInterval = livePollInterval
    }

    // MARK: Internal

    static let liveStorageKey = RockxyIdentity.current.defaultsKey("trafficInsights.isLive")

    private(set) var report: TrafficInsightsReport = .empty
    private(set) var hasReport = false
    private(set) var isComputing = false
    private(set) var lastRefreshedAt: Date?
    private(set) var completedRunCount = 0

    var timelineMetric: TrafficInsightsTimelineMetric = .bytes
    var protocolShareBasis: TrafficInsightsShareBasis = .requests

    /// Whether the report follows live traffic. Pausing freezes the current report so a user can
    /// read a busy session without the numbers moving underneath the pointer.
    var isLive = true {
        didSet {
            guard oldValue != isLive else {
                return
            }
            if isLive {
                requestRefresh(immediate: true)
            }
        }
    }

    var scope: TrafficInsightsScope = .visibleTraffic {
        didSet {
            guard oldValue != scope else {
                return
            }
            requestRefresh(immediate: true, force: true)
        }
    }

    var timeWindow: TrafficInsightsTimeWindow = .entireSession {
        didSet {
            guard oldValue != timeWindow else {
                return
            }
            requestRefresh(immediate: true, force: true)
        }
    }

    var projectName: String {
        coordinator?.trafficInsightsProjectName ?? ""
    }

    var trafficTabName: String {
        coordinator?.trafficInsightsTrafficTabName ?? ""
    }

    var isCaptureRunning: Bool {
        coordinator?.isProxyRunning ?? false
    }

    var isCoordinatorAttached: Bool {
        coordinator != nil
    }

    /// Number of transactions in the selected scope before the time window is applied.
    var scopedTransactionCount: Int {
        guard let coordinator else {
            return 0
        }
        return switch scope {
        case .allTraffic: coordinator.transactions.count
        case .visibleTraffic: coordinator.filteredTransactions.count
        }
    }

    func attach(to coordinator: MainContentCoordinator) {
        if self.coordinator !== coordinator {
            self.coordinator = coordinator
            cache = .empty
        }
        lastSourceToken = coordinator.trafficInsightsSourceToken
        requestRefresh(immediate: true, force: true)
        startLivePollingIfNeeded()
    }

    func detach() {
        refreshTask?.cancel()
        refreshTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        runGeneration &+= 1
        isComputing = false
    }

    /// Called by the report view whenever the coordinator source token changes.
    func sourceDidChange(_ token: TrafficInsightsSourceToken) {
        guard token != lastSourceToken else {
            return
        }
        let workspaceChanged = token.workspaceID != lastSourceToken?.workspaceID
        let sessionChanged = token.sessionGeneration != lastSourceToken?.sessionGeneration
        lastSourceToken = token
        if workspaceChanged || sessionChanged {
            cache = .empty
            requestRefresh(immediate: true, force: true)
        } else {
            requestRefresh(immediate: false)
        }
    }

    /// Manual refresh; also the action behind the Refresh button while paused.
    func refreshNow() {
        requestRefresh(immediate: true, force: true)
    }

    func markdownReport() -> String {
        TrafficInsightsReportFormatter.markdown(
            for: report,
            context: TrafficInsightsReportFormatter.Context(
                projectName: projectName,
                trafficTabName: trafficTabName,
                generatedAt: report.generatedAt == .distantPast ? Date() : report.generatedAt
            )
        )
    }

    // MARK: - Handoffs

    func focus(onHost host: String) {
        coordinator?.focusTrafficInsights(onHost: host)
    }

    func focus(onApp app: String) {
        coordinator?.focusTrafficInsights(onApp: app)
    }

    func reveal(_ ids: [UUID]) {
        coordinator?.revealTrafficInsightsTransactions(ids)
    }

    func reveal(_ reference: TrafficInsightsTransactionRef) {
        coordinator?.revealTrafficInsightsTransactions([reference.id])
    }

    func reveal(_ bin: TrafficInsightsTimelineBin) {
        coordinator?.revealTrafficInsightsBin(bin)
    }

    func toggleDrillDown(_ drillDown: TrafficInsightsDrillDown) {
        coordinator?.toggleTrafficInsightsDrillDown(drillDown)
    }

    func isDrillDownActive(_ drillDown: TrafficInsightsDrillDown) -> Bool {
        coordinator?.isTrafficInsightsDrillDownActive(drillDown) ?? false
    }

    /// Runs a computation immediately and waits for it. Intended for tests and for the export
    /// path, which must never write a stale report.
    func refreshAndWait() async {
        refreshTask?.cancel()
        refreshTask = nil
        await performRefresh()
    }

    // MARK: Private

    private let debounce: Duration
    private let livePollInterval: Duration

    @ObservationIgnored private weak var coordinator: MainContentCoordinator?
    @ObservationIgnored private var runGeneration: UInt = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var cache: TrafficInsightsProtocolCache = .empty
    @ObservationIgnored private var lastSourceToken: TrafficInsightsSourceToken?

    private func requestRefresh(immediate: Bool, force: Bool = false) {
        guard force || isLive else {
            return
        }
        refreshTask?.cancel()
        let delay = immediate ? Duration.zero : debounce
        refreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        guard let coordinator else {
            report = .empty
            hasReport = true
            return
        }
        runGeneration &+= 1
        let generation = runGeneration
        let samples = coordinator.trafficInsightsSamples(scope: scope)
        var options = TrafficInsightsOptions()
        options.scope = scope
        options.timeWindow = timeWindow
        let cache = cache
        isComputing = true

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let output = TrafficInsightsEngine.buildReport(samples: samples, options: options, cache: cache)
            try Task.checkCancellation()
            return output
        }
        let output: TrafficInsightsEngine.Output?
        do {
            output = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        } catch {
            output = nil
        }

        guard generation == runGeneration else {
            return
        }
        isComputing = false
        guard let output else {
            return
        }
        self.cache = output.cache
        report = output.report
        hasReport = true
        lastRefreshedAt = output.report.generatedAt
        completedRunCount += 1
    }

    private func startLivePollingIfNeeded() {
        guard pollingTask == nil else {
            return
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.livePollInterval ?? .seconds(2))
                guard !Task.isCancelled, let self else {
                    return
                }
                // In-flight responses complete in place without a new batch, so a live report
                // re-reads the scope while anything is still pending.
                if isLive, report.totals.inFlightCount > 0, !isComputing {
                    requestRefresh(immediate: true)
                }
            }
        }
    }
}
