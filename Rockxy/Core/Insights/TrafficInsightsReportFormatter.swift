import Foundation

// Renders a Traffic Insights report as shareable Markdown.

// MARK: - TrafficInsightsReportFormatter

/// Deterministic Markdown export of a report. Hosts, paths, and app names are written verbatim
/// because they are the evidence a teammate needs; bodies, headers, and cookies are never part
/// of the report, so the export contains no captured payload data.
nonisolated enum TrafficInsightsReportFormatter {
    // MARK: Internal

    struct Context: Sendable {
        var projectName: String
        var trafficTabName: String
        var generatedAt: Date
        var locale: Locale = .current
        var timeZone: TimeZone = .current
    }

    static func markdown(for report: TrafficInsightsReport, context: Context) -> String {
        var lines: [String] = []
        let totals = report.totals

        lines.append("# \(RockxyIdentity.current.displayName) Traffic Insights")
        lines.append("")
        lines.append("- Project: \(context.projectName)")
        lines.append("- Traffic Tab: \(context.trafficTabName)")
        lines.append("- Scope: \(report.scope.displayName) · \(report.timeWindow.displayName)")
        lines.append("- Generated: \(timestamp(context.generatedAt, context: context))")
        if let first = totals.firstTimestamp, let last = totals.lastTimestamp {
            lines.append(
                "- Captured: \(timestamp(first, context: context)) → \(timestamp(last, context: context))"
                    + " (\(DurationFormatter.format(seconds: totals.span)))"
            )
        }
        lines.append("")

        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|---|---|")
        lines.append("| Requests | \(formatCount(totals.requestCount)) |")
        lines.append("| In flight | \(formatCount(totals.inFlightCount)) |")
        lines.append("| Errors | \(formatCount(totals.errorCount)) (\(formatPercent(totals.errorRate))) |")
        lines.append("| Sent | \(formatBytes(totals.sentBytes)) |")
        lines.append("| Received | \(formatBytes(totals.receivedBytes)) |")
        lines.append("| Median latency | \(formatDuration(totals.medianDuration)) |")
        lines.append("| p95 latency | \(formatDuration(totals.p95Duration)) |")
        lines.append("| Hosts | \(formatCount(totals.hostCount)) |")
        lines.append("| Apps | \(formatCount(totals.appCount)) |")
        lines.append("")

        if !report.findings.isEmpty {
            lines.append("## Findings")
            lines.append("")
            for finding in report.findings {
                lines.append("- **\(severityLabel(finding.severity))** \(finding.title)")
                lines.append("  \(finding.detail)")
            }
            lines.append("")
        }

        appendShareTable(
            &lines,
            title: "Protocols",
            rows: report.protocols.map { ($0.key.displayName, $0.requestCount, $0.bytes) },
            totalRequests: totals.requestCount
        )
        appendShareTable(
            &lines,
            title: "Status",
            rows: report.statusClasses.map { ($0.key.displayName, $0.requestCount, $0.bytes) },
            totalRequests: totals.requestCount
        )
        appendShareTable(
            &lines,
            title: "Content Types",
            rows: report.contentCategories.map { ($0.key.displayName, $0.requestCount, $0.bytes) },
            totalRequests: report.contentCategories.reduce(0) { $0 + $1.requestCount }
        )
        appendShareTable(
            &lines,
            title: "Methods",
            rows: report.methods.map { ($0.key, $0.requestCount, $0.bytes) },
            totalRequests: totals.requestCount
        )

        appendRankedTable(&lines, title: "Top Apps", entries: report.topApps, totalBytes: totals.totalBytes)
        appendRankedTable(&lines, title: "Top Hosts", entries: report.topHosts, totalBytes: totals.totalBytes)

        if !report.slowestRequests.isEmpty {
            lines.append("## Slowest Requests")
            lines.append("")
            lines.append("| Duration | Status | Request |")
            lines.append("|---|---|---|")
            for entry in report.slowestRequests {
                lines.append(
                    "| \(formatDuration(entry.duration)) | \(statusLabel(entry)) | `\(entry.method) \(entry.host)\(entry.path)` |"
                )
            }
            lines.append("")
        }

        if !report.largestResponses.isEmpty {
            lines.append("## Largest Responses")
            lines.append("")
            lines.append("| Size | Status | Request |")
            lines.append("|---|---|---|")
            for entry in report.largestResponses {
                lines.append(
                    "| \(formatBytes(entry.bytes)) | \(statusLabel(entry)) | `\(entry.method) \(entry.host)\(entry.path)` |"
                )
            }
            lines.append("")
        }

        if !report.bins.isEmpty {
            lines.append("## Traffic Over Time")
            lines.append("")
            lines.append("Bin width: \(formatBinWidth(report.binWidth))")
            lines.append("")
            lines.append("| Start | Requests | Errors | Sent | Received | Median | p95 |")
            lines.append("|---|---|---|---|---|---|---|")
            for bin in report.bins {
                lines.append(
                    "| \(clockTime(bin.start, context: context)) | \(bin.requestCount) | \(bin.errorCount) "
                        + "| \(formatBytes(bin.sentBytes)) | \(formatBytes(bin.receivedBytes)) "
                        + "| \(formatDuration(bin.medianDuration)) | \(formatDuration(bin.tailDuration)) |"
                )
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }

    /// Whole-unit label for a bin width ("1 s", "5 min", "1 hr") so chart subtitles never show
    /// fractional seconds for values that are always whole.
    static func formatBinWidth(_ width: TimeInterval) -> String {
        if width >= 3_600, width.truncatingRemainder(dividingBy: 3_600) == 0 {
            return String(localized: "\(Int(width / 3_600)) hr", bundle: RockxyLocalization.bundle)
        }
        if width >= 60, width.truncatingRemainder(dividingBy: 60) == 0 {
            return String(localized: "\(Int(width / 60)) min", bundle: RockxyLocalization.bundle)
        }
        if width.rounded() == width {
            return String(localized: "\(Int(width)) s", bundle: RockxyLocalization.bundle)
        }
        return DurationFormatter.format(seconds: width)
    }

    /// Session spans read better without fractional seconds once they pass ten seconds.
    static func formatSpan(_ span: TimeInterval) -> String {
        if span >= 3_600 {
            let hours = Int(span / 3_600)
            let minutes = Int(span.truncatingRemainder(dividingBy: 3_600) / 60)
            return String(localized: "\(hours) h \(minutes) min", bundle: RockxyLocalization.bundle)
        }
        if span >= 60 {
            let minutes = Int(span / 60)
            let seconds = Int(span.truncatingRemainder(dividingBy: 60))
            return String(localized: "\(minutes) min \(seconds) s", bundle: RockxyLocalization.bundle)
        }
        if span >= 10 {
            return String(localized: "\(Int(span.rounded())) s", bundle: RockxyLocalization.bundle)
        }
        return DurationFormatter.format(seconds: span)
    }

    static func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "—"
        }
        return DurationFormatter.format(seconds: duration)
    }

    static func formatPercent(_ fraction: Double, minimumLabel: String = "<1%") -> String {
        guard fraction.isFinite, fraction > 0 else {
            return "0%"
        }
        let percent = fraction * 100
        if percent < 1 {
            return minimumLabel
        }
        if percent >= 99.5, fraction < 1 {
            return ">99%"
        }
        return "\(Int(percent.rounded()))%"
    }

    static func formatCount(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    // MARK: Private

    /// Binary units to match the rest of Rockxy, but never the spelled-out "Zero KB" form.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static func severityLabel(_ severity: TrafficInsightsFindingSeverity) -> String {
        switch severity {
        case .info: "Info"
        case .notice: "Notice"
        case .warning: "Warning"
        }
    }

    private static func statusLabel(_ entry: TrafficInsightsTransactionRef) -> String {
        if let code = entry.statusCode {
            return String(code)
        }
        return entry.statusClass.displayName
    }

    private static func appendShareTable(
        _ lines: inout [String],
        title: String,
        rows: [(String, Int, Int64)],
        totalRequests: Int
    ) {
        guard !rows.isEmpty else {
            return
        }
        lines.append("## \(title)")
        lines.append("")
        lines.append("| Name | Requests | Share | Bytes |")
        lines.append("|---|---|---|---|")
        for (name, count, bytes) in rows {
            let share = totalRequests == 0 ? 0 : Double(count) / Double(totalRequests)
            lines.append("| \(name) | \(formatCount(count)) | \(formatPercent(share)) | \(formatBytes(bytes)) |")
        }
        lines.append("")
    }

    private static func appendRankedTable(
        _ lines: inout [String],
        title: String,
        entries: [TrafficInsightsRankedEntry],
        totalBytes: Int64
    ) {
        guard !entries.isEmpty else {
            return
        }
        lines.append("## \(title)")
        lines.append("")
        lines.append("| # | Name | Requests | Errors | Median | Transferred | Share |")
        lines.append("|---|---|---|---|---|---|---|")
        for (index, entry) in entries.enumerated() {
            let share = totalBytes == 0 ? 0 : Double(entry.totalBytes) / Double(totalBytes)
            lines.append(
                "| \(index + 1) | \(entry.name) | \(formatCount(entry.requestCount)) | \(formatCount(entry.errorCount)) "
                    + "| \(formatDuration(entry.medianDuration)) | \(formatBytes(entry.totalBytes)) | \(formatPercent(share)) |"
            )
        }
        lines.append("")
    }

    private static func timestamp(_ date: Date, context: Context) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard, locale: context.locale, timeZone: context.timeZone)
        )
    }

    private static func clockTime(_ date: Date, context: Context) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .standard, locale: context.locale, timeZone: context.timeZone)
        )
    }
}
