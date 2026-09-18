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
///
/// Live traffic is throttled rather than debounced: source changes coalesce into one rebuild,
/// a rebuild never starts while another is running, and the interval between live rebuilds
/// grows with the measured build time so a session with tens of thousands of requests neither
/// starves the report during sustained capture nor keeps a core busy rebuilding it.
@MainActor @Observable
final class TrafficInsightsViewModel {
    // MARK: Lifecycle

    init(
        debounce: Duration = .milliseconds(350),
        livePollInterval: Duration = .seconds(2),
        minimumLiveInterval: Duration = .seconds(1),
        maximumLiveInterval: Duration = .seconds(5)
    ) {
        self.debounce = debounce
        self.livePollInterval = livePollInterval
        self.minimumLiveInterval = minimumLiveInterval
        self.maximumLiveInterval = maximumLiveInterval
    }

    // MARK: Internal

    static let liveStorageKey = RockxyIdentity.current.defaultsKey("trafficInsights.isLive")

    /// Live rebuilds wait at least this many build durations between starts.
    static let liveIntervalBuildMultiplier = 3

    private(set) var report: TrafficInsightsReport = .empty
    private(set) var hasReport = false
    private(set) var isComputing = false
    private(set) var lastRefreshedAt: Date?
    private(set) var completedRunCount = 0
    /// Wall-clock duration of the most recent completed build, including the snapshot.
    private(set) var lastBuildDuration: Duration = .zero

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

    /// Minimum spacing between live rebuild starts: never below the live floor (a dashboard
    /// that redraws every card more than once a second only costs frames), never above the
    /// maximum, and otherwise a multiple of the last build so heavy sessions refresh less often.
    var liveRefreshInterval: Duration {
        let scaled = lastBuildDuration * Self.liveIntervalBuildMultiplier
        return min(max(scaled, minimumLiveInterval, debounce), maximumLiveInterval)
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
        hasPendingLiveRefresh = false
        isBuildInFlight = false
        isComputing = false
    }

    /// Called whenever the coordinator source token changes.
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
        hasPendingLiveRefresh = false
        await performRefresh(priority: .userInitiated)
    }

    // MARK: Private

    private let debounce: Duration
    private let livePollInterval: Duration
    private let minimumLiveInterval: Duration
    private let maximumLiveInterval: Duration

    @ObservationIgnored private weak var coordinator: MainContentCoordinator?
    @ObservationIgnored private var runGeneration: UInt = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var cache: TrafficInsightsProtocolCache = .empty
    @ObservationIgnored private var lastSourceToken: TrafficInsightsSourceToken?
    /// A live source change arrived while a build was running; rebuild once it finishes.
    @ObservationIgnored private var hasPendingLiveRefresh = false
    @ObservationIgnored private var lastRefreshStart: ContinuousClock.Instant?
    @ObservationIgnored private var isBuildInFlight = false

    /// `force` runs regardless of the live switch and supersedes any build in flight; it is the
    /// path for scope, window, session, and manual refreshes. Live refreshes coalesce instead.
    private func requestRefresh(immediate: Bool, force: Bool = false) {
        guard force || isLive else {
            return
        }
        if force {
            hasPendingLiveRefresh = false
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                guard !Task.isCancelled else {
                    return
                }
                await self?.performRefresh(priority: .userInitiated)
            }
            return
        }
        if isBuildInFlight {
            hasPendingLiveRefresh = true
            return
        }
        // A scheduled live refresh already covers this change.
        guard refreshTask == nil else {
            return
        }
        let delay = liveRefreshDelay(immediate: immediate)
        refreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.performRefresh(priority: .utility)
        }
    }

    private func liveRefreshDelay(immediate: Bool) -> Duration {
        let floor = immediate ? Duration.zero : debounce
        guard let lastRefreshStart else {
            return floor
        }
        let elapsed = ContinuousClock.now - lastRefreshStart
        return max(floor, liveRefreshInterval - elapsed)
    }

    private func performRefresh(priority: TaskPriority) async {
        guard let coordinator else {
            report = .empty
            hasReport = true
            refreshTask = nil
            return
        }
        runGeneration &+= 1
        let generation = runGeneration
        let startedAt = ContinuousClock.now
        lastRefreshStart = startedAt
        let samples = coordinator.trafficInsightsSamples(scope: scope)
        var options = TrafficInsightsOptions()
        options.scope = scope
        options.timeWindow = timeWindow
        let cache = cache
        isComputing = true
        isBuildInFlight = true

        let worker = Task.detached(priority: priority) {
            TrafficInsightsEngine.buildReport(samples: samples, options: options, cache: cache) {
                Task.isCancelled
            }
        }
        let output = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard generation == runGeneration else {
            return
        }
        isBuildInFlight = false
        isComputing = false
        refreshTask = nil
        defer { resumePendingLiveRefreshIfNeeded() }
        guard let output else {
            return
        }
        lastBuildDuration = ContinuousClock.now - startedAt
        self.cache = output.cache
        report = output.report
        hasReport = true
        lastRefreshedAt = output.report.generatedAt
        completedRunCount += 1
    }

    private func resumePendingLiveRefreshIfNeeded() {
        guard hasPendingLiveRefresh else {
            return
        }
        hasPendingLiveRefresh = false
        requestRefresh(immediate: true)
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
