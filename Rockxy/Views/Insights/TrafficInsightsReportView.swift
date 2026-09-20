import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Renders the Traffic Insights report inside the main workspace.

// MARK: - TrafficInsightsReportView

/// Insights destination of the Focus Navigator. Header (scope, time window, live control,
/// export), then a scrolling report of headline tiles, findings, charts, breakdowns, ranked
/// lists, and outliers. Report state lives on the active `WorkspaceState`, so switching Traffic
/// Tabs or returning to the request list never loses the scope or the last report. Every row
/// that names a host, app, or request hands off to the request list instead of duplicating it.
struct TrafficInsightsReportView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        reportLayout
            .font(toolMetrics.font())
            .background {
                // Isolated so a 100 ms capture batch invalidates this zero-size view only; the
                // card tree re-renders when the report itself changes.
                TrafficInsightsSourceMonitor(coordinator: coordinator, viewModel: viewModel)
            }
            .onAppear {
                viewModel.configureInitialLivePreference(storedIsLive)
                viewModel.attach(to: coordinator)
            }
            .onDisappear {
                viewModel.detach()
            }
            .onChange(of: viewModel.isLive) { _, isLive in
                storedIsLive = isLive
            }
            .alert(
                String(localized: "Save Failed", bundle: RockxyLocalization.bundle),
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: {
                        if !$0 {
                            exportErrorMessage = nil
                        }
                    }
                )
            ) {
                Button(String(localized: "OK", bundle: RockxyLocalization.bundle), role: .cancel) {
                    exportErrorMessage = nil
                }
            } message: {
                if let exportErrorMessage {
                    Text(exportErrorMessage)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Traffic Insights", bundle: RockxyLocalization.bundle))
    }

    /// Filesystem-safe name that keeps the project and tab identifiable in a shared folder.
    static func suggestedFileName(projectName: String, trafficTabName: String, generatedAt: Date) -> String {
        let stamp = generatedAt.formatted(
            Date.FormatStyle(date: .numeric, time: .shortened)
                .year(.defaultDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
        let raw = ["Rockxy Insights", projectName, trafficTabName, stamp]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = raw.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }
        return String(cleaned) + ".md"
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow
    @AppStorage(TrafficInsightsViewModel.liveStorageKey) private var storedIsLive = true
    @State private var exportErrorMessage: String?

    private var viewModel: TrafficInsightsViewModel {
        coordinator.activeWorkspace.trafficInsights
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var report: TrafficInsightsReport {
        viewModel.report
    }

    private var timelineSubtitle: String {
        String(
            localized: "per \(TrafficInsightsReportFormatter.formatBinWidth(report.binWidth))",
            bundle: RockxyLocalization.bundle
        )
    }

    // MARK: - Layout

    /// On macOS 26 the header is a floating Liquid Glass functional bar and the report scrolls
    /// beneath it with the native scroll-edge effect. Older systems keep a static material bar
    /// and a divider, so the hierarchy stays identical while the material differs.
    @ViewBuilder private var reportLayout: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            reportBody
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .safeAreaBar(edge: .top, spacing: 0) {
                    header
                }
        } else {
            legacyReportLayout
        }
        #else
        legacyReportLayout
        #endif
    }

    private var legacyReportLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            reportBody
        }
    }

    // MARK: - Header

    private var header: some View {
        TrafficInsightsHeader(
            viewModel: viewModel,
            onShowTraffic: coordinator.hideTrafficInsights,
            onCopy: copyReport,
            onSave: saveReport
        )
    }

    // MARK: - Body

    @ViewBuilder private var reportBody: some View {
        if !viewModel.hasReport {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(String(localized: "Building report…", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if report.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Insights.cardSpacing) {
                    summaryRow
                    if !report.findings.isEmpty {
                        findingsCard
                    }
                    TrafficInsightsSplitRow(
                        secondaryWidth: Theme.Insights.protocolsCardWidth,
                        minimumPrimaryWidth: Theme.Insights.timelineMinimumWidth
                    ) {
                        timelineCard
                        protocolsCard
                    }
                    TrafficInsightsCardGrid(minimumColumnWidth: Theme.Insights.breakdownMinimumWidth) {
                        statusCard
                        contentCard
                        methodsCard
                        timingCard
                    }
                    // One grid for all four lists so a wide workspace shows them side by side
                    // and a narrow one wraps them 2 + 2, never a 3 + 1 orphan.
                    TrafficInsightsCardGrid(minimumColumnWidth: Theme.Insights.listMinimumWidth) {
                        topAppsCard
                        topHostsCard
                        slowestCard
                        largestCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, toolMetrics.contentHorizontalPadding)
            }
            .accessibilityLabel(String(localized: "Traffic Insights report", bundle: RockxyLocalization.bundle))
        }
    }

    @ViewBuilder private var emptyState: some View {
        if viewModel.scope == .visibleTraffic, viewModel.scopedTransactionCount == 0,
           coordinator.transactions.isEmpty == false
        {
            ContentUnavailableView {
                Label(
                    String(localized: "No Visible Traffic", bundle: RockxyLocalization.bundle),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } description: {
                Text(String(localized: "The current filters hide every request.", bundle: RockxyLocalization.bundle))
            } actions: {
                Button(String(localized: "Report All Traffic", bundle: RockxyLocalization.bundle)) {
                    viewModel.scope = .allTraffic
                }
            }
        } else if viewModel.isCaptureRunning {
            ContentUnavailableView {
                Label(
                    String(localized: "Waiting for Traffic", bundle: RockxyLocalization.bundle),
                    systemImage: "waveform.path.ecg"
                )
            } description: {
                Text(String(localized: "The report fills in as requests arrive.", bundle: RockxyLocalization.bundle))
            }
        } else {
            ContentUnavailableView {
                Label(
                    String(localized: "No Traffic Captured", bundle: RockxyLocalization.bundle),
                    systemImage: "chart.xyaxis.line"
                )
            } description: {
                Text(String(localized: "Start capture or open a session.", bundle: RockxyLocalization.bundle))
            } actions: {
                Button(String(localized: "Start Capture", bundle: RockxyLocalization.bundle)) {
                    coordinator.startProxy()
                }
                .disabled(!coordinator.canStartProxy)
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let totals = report.totals
        let rate = totals.averageRequestsPerSecond
        return TrafficInsightsCardGrid(
            minimumColumnWidth: Theme.Insights.tileMinimumWidth,
            fillsLastRow: true
        ) {
            TrafficInsightsStatTile(
                title: String(localized: "Requests", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.count(totals.requestCount),
                detail: requestsTileDetail(totals: totals, rate: rate),
                systemImage: "arrow.left.arrow.right",
                tint: .accentColor
            )
            .help(String(localized: "Requests in scope, average and peak rate", bundle: RockxyLocalization.bundle))
            TrafficInsightsStatTile(
                title: String(localized: "Received", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.bytes(totals.receivedBytes),
                detail: String(
                    localized: "↑ \(TrafficInsightsFormatting.bytes(totals.sentBytes)) sent",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "arrow.down.circle",
                tint: Theme.Insights.received
            )
            .help(String(
                localized: "Body bytes plus WebSocket frames, by direction",
                bundle: RockxyLocalization.bundle
            ))
            TrafficInsightsStatTile(
                title: String(localized: "Errors", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.percent(totals.errorRate),
                detail: String(
                    localized: "\(totals.errorCount) of \(totals.completedCount)",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: totals.errorCount > 0 ? "exclamationmark.triangle" : "checkmark.circle",
                tint: totals.errorCount > 0 ? Theme.StatusCode.clientError : Theme.StatusCode.success
            )
            .help(String(
                localized: "4xx, 5xx, and failed requests over completed ones",
                bundle: RockxyLocalization.bundle
            ))
            TrafficInsightsStatTile(
                title: String(localized: "Median Latency", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.duration(totals.medianDuration),
                detail: String(
                    localized: "p95 \(TrafficInsightsFormatting.duration(totals.p95Duration))",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "timer",
                tint: Theme.Insights.latencyMedian
            )
            .help(String(
                localized: "Half of the requests were faster than the median, 95 percent faster than p95",
                bundle: RockxyLocalization.bundle
            ))
            TrafficInsightsStatTile(
                title: String(localized: "Hosts", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.count(totals.hostCount),
                detail: TrafficInsightsText.inflected("^[\(totals.appCount) app](inflect: true)"),
                systemImage: "globe",
                tint: .secondary
            )
            .help(String(localized: "Distinct hosts and local apps in scope", bundle: RockxyLocalization.bundle))
        }
    }

    // MARK: - Cards

    private var findingsCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Findings", bundle: RockxyLocalization.bundle),
            accessory: {
                Text(TrafficInsightsFormatting.count(report.findings.count))
                    .font(toolMetrics.metadataFont(weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        ) {
            TrafficInsightsFindingsList(findings: report.findings) { finding in
                handle(finding.handoff)
            }
        }
    }

    private var timelineCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Traffic Over Time", bundle: RockxyLocalization.bundle),
            subtitle: timelineSubtitle,
            accessory: {
                Picker(
                    String(localized: "Metric", bundle: RockxyLocalization.bundle),
                    selection: Binding(
                        get: { viewModel.timelineMetric },
                        set: { viewModel.timelineMetric = $0 }
                    )
                ) {
                    ForEach(TrafficInsightsTimelineMetric.allCases, id: \.self) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    timelineLegend
                    Spacer(minLength: 0)
                }
                TrafficInsightsTimelineChart(
                    bins: report.bins,
                    binWidth: report.binWidth,
                    metric: viewModel.timelineMetric,
                    onSelectBin: { viewModel.reveal($0) }
                )
            }
        }
    }

    @ViewBuilder private var timelineLegend: some View {
        switch viewModel.timelineMetric {
        case .bytes:
            legendItem(
                color: Theme.Insights.sent,
                title: String(localized: "Sent", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.bytes(report.totals.sentBytes)
            )
            legendItem(
                color: Theme.Insights.received,
                title: String(localized: "Received", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.bytes(report.totals.receivedBytes)
            )
        case .requests:
            ForEach(report.statusClasses.prefix(4)) { share in
                legendItem(
                    color: Theme.Insights.statusClassColor(share.key),
                    title: share.key.shortDisplayName,
                    value: TrafficInsightsFormatting.count(share.requestCount)
                )
            }
        case .latency:
            legendItem(
                color: Theme.Insights.latencyMedian,
                title: String(localized: "Median", bundle: RockxyLocalization.bundle),
                value: TrafficInsightsFormatting.duration(report.totals.medianDuration)
            )
            legendItem(
                color: Theme.Insights.latencyTail,
                title: "p95",
                value: TrafficInsightsFormatting.duration(report.totals.p95Duration)
            )
        }
    }

    private var protocolsCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Protocols", bundle: RockxyLocalization.bundle),
            accessory: {
                Picker(
                    String(localized: "Basis", bundle: RockxyLocalization.bundle),
                    selection: Binding(
                        get: { viewModel.protocolShareBasis },
                        set: { viewModel.protocolShareBasis = $0 }
                    )
                ) {
                    ForEach(TrafficInsightsShareBasis.allCases, id: \.self) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
        ) {
            TrafficInsightsProtocolChart(
                shares: report.protocols,
                basis: viewModel.protocolShareBasis,
                isActive: { viewModel.isDrillDownActive($0) },
                onToggle: { viewModel.toggleDrillDown($0) }
            )
        }
    }

    private var statusCard: some View {
        TrafficInsightsCard(title: String(localized: "Outcomes", bundle: RockxyLocalization.bundle)) {
            TrafficInsightsBreakdownList(
                shares: report.statusClasses,
                total: report.totals.requestCount,
                name: { $0.shortDisplayName },
                color: { Theme.Insights.statusClassColor($0) },
                note: { statusCodeNote(for: $0) },
                help: { drillDownHelp(statusCodeNote(for: $0), hasFilter: $0.drillDown != nil) },
                drillDown: { $0.drillDown },
                isActive: { viewModel.isDrillDownActive($0) },
                onToggle: { viewModel.toggleDrillDown($0) },
                emptyMessage: String(localized: "No responses yet", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private var contentCard: some View {
        TrafficInsightsCard(title: String(localized: "Content Types", bundle: RockxyLocalization.bundle)) {
            TrafficInsightsBreakdownList(
                shares: report.contentCategories,
                total: report.contentCategories.reduce(0) { $0 + $1.requestCount },
                name: { $0.displayName },
                color: { _ in Color.accentColor },
                help: { category in
                    let bytes = report.contentCategories.first { $0.key == category }
                        .map { TrafficInsightsFormatting.bytes($0.bytes) }
                    return drillDownHelp(bytes, hasFilter: category.drillDown != nil)
                },
                drillDown: { $0.drillDown },
                isActive: { viewModel.isDrillDownActive($0) },
                onToggle: { viewModel.toggleDrillDown($0) },
                emptyMessage: String(localized: "No decrypted responses yet", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private var methodsCard: some View {
        TrafficInsightsCard(title: String(localized: "Methods", bundle: RockxyLocalization.bundle)) {
            TrafficInsightsBreakdownList(
                shares: report.methods,
                total: report.totals.requestCount,
                name: { $0 },
                color: { methodColor($0) },
                help: { _ in drillDownHelp(nil, hasFilter: true) },
                drillDown: { .method($0) },
                isActive: { viewModel.isDrillDownActive($0) },
                onToggle: { viewModel.toggleDrillDown($0) },
                emptyMessage: String(localized: "No requests yet", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private var timingCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Time per Request", bundle: RockxyLocalization.bundle),
            subtitle: report.timing.map { timing in
                TrafficInsightsText.inflected("avg of ^[\(timing.sampleCount) timed request](inflect: true)")
            }
        ) {
            if let timing = report.timing {
                TrafficInsightsTimingBar(timing: timing)
            } else {
                Text(String(localized: "No timed requests yet", bundle: RockxyLocalization.bundle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var topAppsCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Top Apps", bundle: RockxyLocalization.bundle),
            subtitle: String(localized: "by bytes", bundle: RockxyLocalization.bundle)
        ) {
            TrafficInsightsRankedList(
                kind: .apps,
                entries: report.topApps,
                totalBytes: report.totals.totalBytes,
                emptyMessage: String(localized: "No app attribution yet", bundle: RockxyLocalization.bundle),
                onFocus: { viewModel.focus(onApp: $0.name) }
            )
        }
    }

    private var topHostsCard: some View {
        TrafficInsightsCard(
            title: String(localized: "Top Hosts", bundle: RockxyLocalization.bundle),
            subtitle: String(localized: "by bytes", bundle: RockxyLocalization.bundle)
        ) {
            TrafficInsightsRankedList(
                kind: .hosts,
                entries: report.topHosts,
                totalBytes: report.totals.totalBytes,
                emptyMessage: String(localized: "No hosts yet", bundle: RockxyLocalization.bundle),
                onFocus: { viewModel.focus(onHost: $0.name) }
            )
        }
    }

    private var slowestCard: some View {
        TrafficInsightsCard(title: String(localized: "Slowest Requests", bundle: RockxyLocalization.bundle)) {
            TrafficInsightsOutlierList(
                kind: .slowest,
                entries: report.slowestRequests,
                emptyMessage: String(localized: "No timed requests yet", bundle: RockxyLocalization.bundle),
                onReveal: { viewModel.reveal($0) }
            )
        }
    }

    private var largestCard: some View {
        TrafficInsightsCard(title: String(localized: "Largest Responses", bundle: RockxyLocalization.bundle)) {
            TrafficInsightsOutlierList(
                kind: .largest,
                entries: report.largestResponses,
                emptyMessage: String(localized: "No response bodies yet", bundle: RockxyLocalization.bundle),
                onReveal: { viewModel.reveal($0) }
            )
        }
    }

    private func legendItem(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(toolMetrics.metadataFont(weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }

    /// Rates only mean something once the capture spans at least a second; a burst shorter than
    /// that reads better as its duration.
    private func requestsTileDetail(totals: TrafficInsightsTotals, rate: Double) -> String {
        if totals.inFlightCount > 0 {
            return String(localized: "\(totals.inFlightCount) in flight", bundle: RockxyLocalization.bundle)
        }
        guard totals.span >= 1 else {
            return String(
                localized: "in \(DurationFormatter.format(seconds: totals.span))",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "\(rate.formatted(.number.precision(.fractionLength(1))))/s · peak \(totals.peakRequestsPerSecond.formatted(.number.precision(.fractionLength(0))))/s",
            bundle: RockxyLocalization.bundle
        )
    }

    /// "401 ×6 · 404 ×6" for an outcome class, or `nil` when it has no status codes.
    private func statusCodeNote(for statusClass: TrafficInsightsStatusClass) -> String? {
        let codes = report.statusCodes.filter { share in
            TrafficInsightsStatusClass.classify(statusCode: share.key, state: .completed, isTLSFailure: false)
                == statusClass
        }
        guard !codes.isEmpty else {
            return nil
        }
        return codes.prefix(4).map { "\($0.key) ×\(TrafficInsightsFormatting.count($0.requestCount))" }
            .joined(separator: " · ")
    }

    private func drillDownHelp(_ detail: String?, hasFilter: Bool) -> String {
        let action = hasFilter
            ? String(localized: "Click to filter the request list", bundle: RockxyLocalization.bundle)
            : String(localized: "No matching list filter", bundle: RockxyLocalization.bundle)
        guard let detail, !detail.isEmpty else {
            return action
        }
        return "\(detail)\n\(action)"
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": Theme.Method.get
        case "POST": Theme.Method.post
        case "PUT": Theme.Method.put
        case "PATCH": Theme.Method.patch
        case "DELETE": Theme.Method.delete
        default: Color.secondary
        }
    }

    private func handle(_ handoff: TrafficInsightsFindingHandoff) {
        switch handoff {
        case let .focusHost(host):
            viewModel.focus(onHost: host)
        case let .focusApp(app):
            viewModel.focus(onApp: app)
        case let .revealTransactions(ids):
            viewModel.reveal(ids)
        case .openHTTPSDecryption:
            openWindow(id: "sslProxyingList")
        case .none:
            break
        }
    }

    private func copyReport() {
        let markdown = viewModel.markdownReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        // The menu closes on selection, so the confirmation lives in the workspace toast the
        // rest of the app uses for copy feedback rather than in a label nobody can see.
        coordinator.activeToast = ToastMessage(
            style: .success,
            text: String(localized: "Report copied as Markdown", bundle: RockxyLocalization.bundle)
        )
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Self.suggestedFileName(
            projectName: viewModel.projectName,
            trafficTabName: viewModel.trafficTabName,
            generatedAt: report.generatedAt
        )
        panel.title = String(localized: "Save Traffic Insights Report", bundle: RockxyLocalization.bundle)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try viewModel.markdownReport().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - TrafficInsightsHeader

/// Scope, time window, live control, and export. Its own view so the progress indicator and
/// paused timestamp can update without re-evaluating the report cards beneath it.
private struct TrafficInsightsHeader: View {
    // MARK: Internal

    let viewModel: TrafficInsightsViewModel
    let onShowTraffic: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
                titleBlock
                    .frame(minWidth: 160, alignment: .leading)
                Spacer(minLength: 12)
                controls(compact: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                controls(compact: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .rockxyFunctionalBar()
        .padding(.horizontal, toolMetrics.contentHorizontalPadding - Theme.Glass.functionalBarHorizontalInset)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Insights", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
            Text(subtitle)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
        }
    }

    private func controls(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            Button(action: onShowTraffic) {
                Label(String(localized: "Traffic", bundle: RockxyLocalization.bundle), systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
            }
            .rockxyGlassButtonStyle()
            .help(String(localized: "Return to the request list", bundle: RockxyLocalization.bundle))

            Picker(
                String(localized: "Scope", bundle: RockxyLocalization.bundle),
                selection: Binding(
                    get: { viewModel.scope },
                    set: { viewModel.scope = $0 }
                )
            ) {
                ForEach(TrafficInsightsScope.allCases, id: \.self) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(String(
                localized: "All Traffic: every request in this tab. Visible Traffic: what the current filters show.",
                bundle: RockxyLocalization.bundle
            ))

            Picker(
                String(localized: "Time Window", bundle: RockxyLocalization.bundle),
                selection: Binding(
                    get: { viewModel.timeWindow },
                    set: { viewModel.timeWindow = $0 }
                )
            ) {
                ForEach(TrafficInsightsTimeWindow.allCases, id: \.self) { window in
                    Text(window.displayName).tag(window)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help(String(localized: "Counted back from the latest request", bundle: RockxyLocalization.bundle))

            Toggle(isOn: Binding(
                get: { viewModel.isLive },
                set: { viewModel.isLive = $0 }
            )) {
                if compact {
                    Label(liveTitle, systemImage: liveSymbol)
                        .labelStyle(.iconOnly)
                } else {
                    Label(liveTitle, systemImage: liveSymbol)
                        .labelStyle(.titleAndIcon)
                }
            }
            .toggleStyle(.button)
            .help(String(localized: "Pause to freeze the numbers while reading", bundle: RockxyLocalization.bundle))

            if !viewModel.isLive {
                Button {
                    viewModel.refreshNow()
                } label: {
                    Label(
                        String(localized: "Refresh", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.clockwise"
                    )
                    .labelStyle(.iconOnly)
                }
                .rockxyGlassButtonStyle()
                .keyboardShortcut("r", modifiers: [.command])
                .help(String(localized: "Rebuild now", bundle: RockxyLocalization.bundle))
            }

            if viewModel.isComputing, viewModel.hasReport {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Updating report", bundle: RockxyLocalization.bundle))
            }

            Menu {
                Button(String(localized: "Copy Report as Markdown", bundle: RockxyLocalization.bundle), action: onCopy)
                Button(String(localized: "Save Report…", bundle: RockxyLocalization.bundle), action: onSave)
            } label: {
                Label(
                    String(localized: "Export", bundle: RockxyLocalization.bundle),
                    systemImage: "square.and.arrow.up"
                )
                .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .rockxyGlassButtonStyle()
            .fixedSize()
            .disabled(!canExport)
            .help(String(
                localized: "Markdown with hosts, paths, counts, and timings — no payloads",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private var report: TrafficInsightsReport {
        viewModel.report
    }

    private var liveTitle: String {
        viewModel.isLive
            ? String(localized: "Live", bundle: RockxyLocalization.bundle)
            : String(localized: "Paused", bundle: RockxyLocalization.bundle)
    }

    private var liveSymbol: String {
        viewModel.isLive ? "dot.radiowaves.left.and.right" : "pause.fill"
    }

    private var canExport: Bool {
        viewModel.hasReport && !report.isEmpty
    }

    private var subtitle: String {
        let totals = report.totals
        var parts = [TrafficInsightsText.inflected("^[\(totals.requestCount) request](inflect: true)")]
        if totals.span > 0 {
            parts.append(TrafficInsightsReportFormatter.formatSpan(totals.span))
        }
        if totals.totalBytes > 0 {
            parts.append(TrafficInsightsFormatting.bytes(totals.totalBytes))
        }
        if !viewModel.isLive, let refreshedAt = viewModel.lastRefreshedAt {
            parts.append(String(
                localized: "Paused \(TrafficInsightsFormatting.clockTime(refreshedAt))",
                bundle: RockxyLocalization.bundle
            ))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - TrafficInsightsSourceMonitor

/// Zero-size view whose only dependency is the coordinator source token. Batch appends and
/// filter recomputes invalidate this view alone and forward the token to the view model.
private struct TrafficInsightsSourceMonitor: View {
    let coordinator: MainContentCoordinator
    let viewModel: TrafficInsightsViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: coordinator.trafficInsightsSourceToken) { _, token in
                viewModel.sourceDidChange(token)
            }
            .accessibilityHidden(true)
    }
}
