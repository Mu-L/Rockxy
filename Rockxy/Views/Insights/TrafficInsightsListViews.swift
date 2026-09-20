import AppKit
import SwiftUI

// Renders the breakdown, ranked, outlier, and findings lists for the Traffic Insights report.

// MARK: - TrafficInsightsBreakdownList

/// Compact proportional bars for one categorical breakdown (outcome, content, or method). Rows
/// with a matching request-list filter toggle it; the checkmark mirrors the pill bar.
struct TrafficInsightsBreakdownList<Key: Hashable & Sendable>: View {
    let shares: [TrafficInsightsShare<Key>]
    let total: Int
    let name: (Key) -> String
    let color: (Key) -> Color
    var note: (Key) -> String? = { _ in nil }
    var help: (Key) -> String? = { _ in nil }
    var drillDown: (Key) -> TrafficInsightsDrillDown? = { _ in nil }
    var isActive: (TrafficInsightsDrillDown) -> Bool = { _ in false }
    var onToggle: (TrafficInsightsDrillDown) -> Void = { _ in }
    var emptyMessage: String

    var body: some View {
        if shares.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares) { share in
                    let target = drillDown(share.key)
                    TrafficInsightsShareRow(
                        color: color(share.key),
                        name: name(share.key),
                        primaryValue: TrafficInsightsFormatting.count(share.requestCount),
                        secondaryValue: TrafficInsightsFormatting.percent(
                            TrafficInsightsFormatting.share(share.requestCount, of: total)
                        ),
                        fraction: TrafficInsightsFormatting.share(share.requestCount, of: total),
                        note: note(share.key),
                        isActive: target.map(isActive) ?? false,
                        action: target.map { target in { onToggle(target) } }
                    )
                    .help(tooltip(for: share))
                }
            }
        }
    }

    private func tooltip(for share: TrafficInsightsShare<Key>) -> String {
        var lines = [name(share.key)]
        lines.append(TrafficInsightsText.inflected("^[\(share.requestCount) request](inflect: true)"))
        lines.append(TrafficInsightsFormatting.bytes(share.bytes))
        if let detail = help(share.key), !detail.isEmpty {
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - TrafficInsightsRankedKind

enum TrafficInsightsRankedKind {
    case apps
    case hosts
}

// MARK: - TrafficInsightsRankedList

/// Top-N list with rank, icon, name, transferred bytes, share, and a proportional bar. Every row
/// is a real button that focuses the main workspace, with a context menu for secondary actions.
struct TrafficInsightsRankedList: View {
    // MARK: Internal

    let kind: TrafficInsightsRankedKind
    let entries: [TrafficInsightsRankedEntry]
    let totalBytes: Int64
    let emptyMessage: String
    let onFocus: (TrafficInsightsRankedEntry) -> Void

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(index: index, entry: entry)
                    if index < entries.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var hoveredID: String?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var focusTitle: String {
        switch kind {
        case .apps: String(localized: "Focus App in Traffic", bundle: RockxyLocalization.bundle)
        case .hosts: String(localized: "Focus Host in Traffic", bundle: RockxyLocalization.bundle)
        }
    }

    private var focusHelp: String {
        switch kind {
        case .apps:
            String(localized: "Click to show only this app's requests", bundle: RockxyLocalization.bundle)
        case .hosts:
            String(localized: "Click to show only this host's requests", bundle: RockxyLocalization.bundle)
        }
    }

    private func row(index: Int, entry: TrafficInsightsRankedEntry) -> some View {
        let share = TrafficInsightsFormatting.share(entry.totalBytes, of: totalBytes)
        let leader = entries.first?.totalBytes ?? 0
        let barFraction = TrafficInsightsFormatting.share(entry.totalBytes, of: leader)
        return Button {
            onFocus(entry)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(String(index + 1))
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
                    .accessibilityHidden(true)
                icon(for: entry)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.name)
                            .font(toolMetrics.secondaryFont(weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(detailLabel(for: entry))
                            .font(toolMetrics.metadataFont())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(TrafficInsightsFormatting.bytes(entry.totalBytes))
                            .font(toolMetrics.secondaryFont(weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .frame(minWidth: 64, alignment: .trailing)
                        Text(TrafficInsightsFormatting.percent(share))
                            .font(toolMetrics.metadataFont(weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    TrafficInsightsProportionBar(fraction: barFraction, color: .accentColor)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hoveredID == entry.id ? 0.05 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredID = isHovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
        .help(tooltip(for: entry))
        .accessibilityLabel(accessibilityLabel(index: index, entry: entry, share: share))
        .accessibilityHint(focusHelp)
        .contextMenu {
            Button(focusTitle) {
                onFocus(entry)
            }
            Button(String(localized: "Copy Name", bundle: RockxyLocalization.bundle)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.name, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func icon(for entry: TrafficInsightsRankedEntry) -> some View {
        switch kind {
        case .apps:
            TrafficInsightsAppIcon(appName: entry.name)
        case .hosts:
            TrafficInsightsHostIcon(host: entry.name)
        }
    }

    private func tooltip(for entry: TrafficInsightsRankedEntry) -> String {
        var lines: [String] = [entry.name]
        lines.append(TrafficInsightsText.inflected(
            "^[\(entry.requestCount) request](inflect: true) · ^[\(entry.errorCount) error](inflect: true)"
        ))
        lines.append(String(
            localized: "↓ \(TrafficInsightsFormatting.bytes(entry.receivedBytes))  ↑ \(TrafficInsightsFormatting.bytes(entry.sentBytes))",
            bundle: RockxyLocalization.bundle
        ))
        if let median = entry.medianDuration {
            lines.append(String(
                localized: "Median \(DurationFormatter.format(seconds: median))",
                bundle: RockxyLocalization.bundle
            ))
        }
        lines.append(focusHelp)
        return lines.joined(separator: "\n")
    }

    private func detailLabel(for entry: TrafficInsightsRankedEntry) -> String {
        var parts: [String] = []
        parts.append(
            String(localized: "\(entry.requestCount) req", bundle: RockxyLocalization.bundle)
        )
        if entry.errorCount > 0 {
            parts.append(
                String(localized: "\(entry.errorCount) err", bundle: RockxyLocalization.bundle)
            )
        }
        if let median = entry.medianDuration {
            parts.append(DurationFormatter.format(seconds: median))
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(index: Int, entry: TrafficInsightsRankedEntry, share: Double) -> String {
        TrafficInsightsText
            .inflected(
                "Rank \(index + 1), \(entry.name), \(TrafficInsightsFormatting.bytes(entry.totalBytes)), \(TrafficInsightsFormatting.percent(share)) of traffic, ^[\(entry.requestCount) request](inflect: true), ^[\(entry.errorCount) error](inflect: true)"
            )
    }
}

// MARK: - TrafficInsightsOutlierKind

enum TrafficInsightsOutlierKind {
    case slowest
    case largest
}

// MARK: - TrafficInsightsOutlierList

/// Slowest requests or largest responses. Rows reveal the transaction in the main window.
struct TrafficInsightsOutlierList: View {
    // MARK: Internal

    let kind: TrafficInsightsOutlierKind
    let entries: [TrafficInsightsTransactionRef]
    let emptyMessage: String
    let onReveal: (TrafficInsightsTransactionRef) -> Void

    var body: some View {
        if entries.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                    if index < entries.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var hoveredID: UUID?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var revealHelp: String {
        String(localized: "Click to select this request", bundle: RockxyLocalization.bundle)
    }

    private func row(_ entry: TrafficInsightsTransactionRef) -> some View {
        Button {
            onReveal(entry)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(metricLabel(for: entry))
                    .font(toolMetrics.secondaryFont(weight: .semibold, monospaced: true))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 72, alignment: .trailing)
                statusBadge(for: entry)
                    .frame(width: 44, alignment: .leading)
                StatusBadge(method: entry.method)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.host)
                        .font(toolMetrics.secondaryFont(weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.path)
                        .font(toolMetrics.metadataFont(monospaced: true))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let app = entry.clientApp, !app.isEmpty {
                    Text(app)
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hoveredID == entry.id ? 0.05 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredID = isHovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
        .help("\(entry.method) \(entry.url)\n\(revealHelp)")
        .accessibilityLabel(accessibilityLabel(for: entry))
        .accessibilityHint(revealHelp)
        .contextMenu {
            Button(String(localized: "Reveal in Traffic", bundle: RockxyLocalization.bundle)) {
                onReveal(entry)
            }
            Button(String(localized: "Copy URL", bundle: RockxyLocalization.bundle)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for entry: TrafficInsightsTransactionRef) -> some View {
        if let code = entry.statusCode {
            StatusCodeBadge(statusCode: code)
        } else {
            Text(entry.statusClass.displayName)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func metricLabel(for entry: TrafficInsightsTransactionRef) -> String {
        switch kind {
        case .slowest: TrafficInsightsFormatting.duration(entry.duration)
        case .largest: TrafficInsightsFormatting.bytes(entry.bytes)
        }
    }

    private func accessibilityLabel(for entry: TrafficInsightsTransactionRef) -> String {
        let status = entry.statusCode.map(String.init) ?? entry.statusClass.displayName
        return "\(metricLabel(for: entry)), \(status), \(entry.method) \(entry.url)"
    }
}

// MARK: - TrafficInsightsFindingsList

/// Deterministic observations with a single handoff action each. The list never mutates traffic
/// or rules; every action only focuses or reveals requests in the main window.
struct TrafficInsightsFindingsList: View {
    // MARK: Internal

    let findings: [TrafficInsightsFinding]
    let onHandoff: (TrafficInsightsFinding) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleFindings.enumerated()), id: \.element.id) { index, finding in
                row(finding)
                if index < visibleFindings.count - 1 {
                    Divider().opacity(0.5)
                }
            }
            if findings.count > Self.collapsedLimit {
                Divider().opacity(0.5)
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(
                        isExpanded
                            ? String(localized: "Show Fewer", bundle: RockxyLocalization.bundle)
                            : String(
                                localized: "Show All \(findings.count) Findings",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                    .font(toolMetrics.secondaryFont(weight: .medium))
                }
                .buttonStyle(.link)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Private

    private static let collapsedLimit = 5

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var isExpanded = false

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var visibleFindings: [TrafficInsightsFinding] {
        isExpanded ? findings : Array(findings.prefix(Self.collapsedLimit))
    }

    private func row(_ finding: TrafficInsightsFinding) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol(for: finding.severity))
                .font(.system(size: toolMetrics.bodyFontSize, weight: .semibold))
                .foregroundStyle(color(for: finding.severity))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(finding.title)
                .font(toolMetrics.secondaryFont(weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            if let title = actionTitle(for: finding) {
                Button(title) {
                    onHandoff(finding)
                }
                .rockxyGlassButtonStyle()
                .controlSize(.small)
                .help(actionHelp(for: finding))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .help(finding.detail)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(severityLabel(for: finding.severity)): \(finding.title). \(finding.detail)")
    }

    private func symbol(for severity: TrafficInsightsFindingSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .notice: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(for severity: TrafficInsightsFindingSeverity) -> Color {
        switch severity {
        case .info: Theme.Insights.findingInfo
        case .notice: Theme.Insights.findingNotice
        case .warning: Theme.Insights.findingWarning
        }
    }

    private func severityLabel(for severity: TrafficInsightsFindingSeverity) -> String {
        switch severity {
        case .info: String(localized: "Info", bundle: RockxyLocalization.bundle)
        case .notice: String(localized: "Notice", bundle: RockxyLocalization.bundle)
        case .warning: String(localized: "Warning", bundle: RockxyLocalization.bundle)
        }
    }

    private func actionTitle(for finding: TrafficInsightsFinding) -> String? {
        switch finding.handoff {
        case .focusHost: String(localized: "Focus Host", bundle: RockxyLocalization.bundle)
        case .focusApp: String(localized: "Focus App", bundle: RockxyLocalization.bundle)
        case let .revealTransactions(ids):
            TrafficInsightsText.inflected("Select ^[\(ids.count) Request](inflect: true)")
        case .openHTTPSDecryption: String(localized: "HTTPS Decryption…", bundle: RockxyLocalization.bundle)
        case .none: nil
        }
    }

    private func actionHelp(for finding: TrafficInsightsFinding) -> String {
        switch finding.handoff {
        case .focusHost,
             .focusApp:
            String(localized: "Show only this source in the request list", bundle: RockxyLocalization.bundle)
        case .revealTransactions:
            String(localized: "Select these requests in the request list", bundle: RockxyLocalization.bundle)
        case .openHTTPSDecryption:
            String(localized: "Open HTTPS Decryption to add these hosts", bundle: RockxyLocalization.bundle)
        case .none:
            ""
        }
    }
}
