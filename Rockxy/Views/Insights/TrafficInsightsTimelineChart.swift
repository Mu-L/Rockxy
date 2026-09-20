import Charts
import SwiftUI

// Renders the traffic-over-time chart for the Traffic Insights report.

// MARK: - TrafficInsightsTimelineChart

/// Bytes, requests, or latency per time bin. One y-axis only: the metric switch replaces the
/// series family instead of stacking unrelated scales on one plot.
struct TrafficInsightsTimelineChart: View {
    // MARK: Internal

    let bins: [TrafficInsightsTimelineBin]
    let binWidth: TimeInterval
    let metric: TrafficInsightsTimelineMetric
    /// Invoked with the hovered bin when the user clicks the plot; the report selects its rows.
    var onSelectBin: ((TrafficInsightsTimelineBin) -> Void)?

    var body: some View {
        chart
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(gridColor)
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(axisLabelColor)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(gridColor)
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(axisLabel(for: doubleValue))
                                .font(toolMetrics.metadataFont())
                                .foregroundStyle(axisLabelColor)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... yDomainMaximum)
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedDate)
            // The overlay must stay non-interactive: a hit-testable overlay steals the pointer
            // tracking that drives `chartXSelection`, so hover would never light the crosshair.
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    calloutOverlay(proxy: proxy, geometry: geometry)
                }
                .allowsHitTesting(false)
            }
            .simultaneousGesture(TapGesture().onEnded {
                if let selectedBin, selectedBin.requestCount > 0 {
                    onSelectBin?(selectedBin)
                }
            })
            .frame(height: Theme.Insights.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate: Date?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var gridColor: Color {
        Color(nsColor: .separatorColor).opacity(0.5)
    }

    private var axisLabelColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    private var selectedBin: TrafficInsightsTimelineBin? {
        guard let selectedDate, let first = bins.first else {
            return nil
        }
        let offset = selectedDate.timeIntervalSince(first.start)
        let index = Int((offset / binWidth).rounded(.down))
        guard bins.indices.contains(index) else {
            return nil
        }
        return bins[index]
    }

    private var yDomainMaximum: Double {
        let maximum: Double = switch metric {
        case .bytes:
            Double(bins.map { max($0.sentBytes, $0.receivedBytes) }.max() ?? 0)
        case .requests:
            Double(bins.map(\.requestCount).max() ?? 0)
        case .latency:
            bins.compactMap { $0.tailDuration ?? $0.medianDuration }.max() ?? 0
        }
        return maximum > 0 ? maximum * 1.12 : 1
    }

    private var statusClassesInUse: [TrafficInsightsStatusClass] {
        let present = Set(bins.flatMap(\.countsByStatusClass.keys))
        return TrafficInsightsStatusClass.allCases.filter { present.contains($0) }
    }

    private var accessibilitySummary: String {
        let span = bins.count
        switch metric {
        case .bytes:
            let sent = bins.reduce(Int64(0)) { $0 + $1.sentBytes }
            let received = bins.reduce(Int64(0)) { $0 + $1.receivedBytes }
            return String(
                localized: "Bytes over time across \(span) intervals. Sent \(TrafficInsightsFormatting.bytes(sent)), received \(TrafficInsightsFormatting.bytes(received)).",
                bundle: RockxyLocalization.bundle
            )
        case .requests:
            let total = bins.reduce(0) { $0 + $1.requestCount }
            return String(
                localized: "Requests over time across \(span) intervals, \(total) requests in total.",
                bundle: RockxyLocalization.bundle
            )
        case .latency:
            let tail = bins.compactMap(\.tailDuration).max()
            return String(
                localized: "Latency over time across \(span) intervals. Highest p95 \(TrafficInsightsFormatting.duration(tail)).",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    /// Crosshair only. The callout is drawn in `chartOverlay` so hovering never changes the
    /// chart's layout size — an annotation that overflows the plot re-measures the chart and
    /// makes the surrounding scroll view jump under the pointer.
    @ChartContentBuilder private var selectionMarks: some ChartContent {
        if let selectedBin {
            RuleMark(x: .value("Selected", selectedBin.start.addingTimeInterval(binWidth / 2)))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// Manually stacked bar segments so each bin can span its real width on a date axis.
    private var stackedSegments: [StackedSegment] {
        var segments: [StackedSegment] = []
        let classes = statusClassesInUse
        for bin in bins {
            var cumulative = 0
            for statusClass in classes {
                guard let count = bin.countsByStatusClass[statusClass], count > 0 else {
                    continue
                }
                segments.append(StackedSegment(
                    id: "\(bin.start.timeIntervalSinceReferenceDate)-\(statusClass.rawValue)",
                    start: bin.start,
                    end: bin.start.addingTimeInterval(binWidth * 0.88),
                    statusClass: statusClass,
                    yStart: cumulative,
                    yEnd: cumulative + count
                ))
                cumulative += count
            }
        }
        return segments
    }

    /// Latency samples grouped into contiguous runs so the line breaks across empty bins instead
    /// of interpolating a value where nothing was measured.
    private var latencyPoints: [LatencyPoint] {
        var points: [LatencyPoint] = []
        var run = 0
        var previousHadValue = false
        for bin in bins {
            guard let median = bin.medianDuration else {
                previousHadValue = false
                continue
            }
            if !previousHadValue {
                run += 1
            }
            previousHadValue = true
            points.append(LatencyPoint(start: bin.start, median: median, tail: bin.tailDuration, run: run))
        }
        return points
    }

    @ViewBuilder private var chart: some View {
        switch metric {
        case .bytes:
            bytesChart
        case .requests:
            requestsChart
        case .latency:
            latencyChart
        }
    }

    private var bytesChart: some View {
        Chart {
            ForEach(bins) { bin in
                AreaMark(
                    x: .value("Time", bin.start),
                    y: .value("Received", bin.receivedBytes),
                    series: .value("Direction", "received"),
                    stacking: .unstacked
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.Insights.received.opacity(0.16))
                LineMark(
                    x: .value("Time", bin.start),
                    y: .value("Received", bin.receivedBytes),
                    series: .value("Direction", "received")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Theme.Insights.received)

                AreaMark(
                    x: .value("Time", bin.start),
                    y: .value("Sent", bin.sentBytes),
                    series: .value("Direction", "sent"),
                    stacking: .unstacked
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.Insights.sent.opacity(0.14))
                LineMark(
                    x: .value("Time", bin.start),
                    y: .value("Sent", bin.sentBytes),
                    series: .value("Direction", "sent")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Theme.Insights.sent)
            }
            selectionMarks
        }
    }

    private var requestsChart: some View {
        Chart {
            ForEach(stackedSegments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.start),
                    xEnd: .value("End", segment.end),
                    yStart: .value("From", segment.yStart),
                    yEnd: .value("To", segment.yEnd)
                )
                .foregroundStyle(Theme.Insights.statusClassColor(segment.statusClass))
                .cornerRadius(2)
            }
            selectionMarks
        }
    }

    private var latencyChart: some View {
        Chart {
            ForEach(latencyPoints) { point in
                if let tail = point.tail {
                    LineMark(
                        x: .value("Time", point.start),
                        y: .value("p95", tail),
                        series: .value("Series", "p95-\(point.run)")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .foregroundStyle(Theme.Insights.latencyTail)
                }
                LineMark(
                    x: .value("Time", point.start),
                    y: .value("Median", point.median),
                    series: .value("Series", "p50-\(point.run)")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Theme.Insights.latencyMedian)
                PointMark(
                    x: .value("Time", point.start),
                    y: .value("Median", point.median)
                )
                .symbolSize(18)
                .foregroundStyle(Theme.Insights.latencyMedian)
            }
            selectionMarks
        }
    }

    /// Positions the hover callout inside the plot, flipping to the left of the crosshair near
    /// the trailing edge so it never extends past the chart frame.
    @ViewBuilder
    private func calloutOverlay(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let selectedBin,
           let plotFrame = proxy.plotFrame,
           let xPosition = proxy.position(forX: selectedBin.start.addingTimeInterval(binWidth / 2))
        {
            let plot = geometry[plotFrame]
            let calloutWidth: CGFloat = 200
            let anchorX = plot.minX + xPosition
            let placeLeft = anchorX + 8 + calloutWidth > plot.maxX
            TrafficInsightsBinCallout(bin: selectedBin, binWidth: binWidth, metric: metric)
                .frame(width: calloutWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: placeLeft ? anchorX - 8 - calloutWidth : anchorX + 8, y: plot.minY + 4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func axisLabel(for value: Double) -> String {
        switch metric {
        case .bytes:
            value == 0 ? "0" : TrafficInsightsFormatting.bytes(Int64(value))
        case .requests:
            TrafficInsightsFormatting.count(Int(value))
        case .latency:
            value == 0 ? "0" : DurationFormatter.format(seconds: value)
        }
    }
}

// MARK: - LatencyPoint

private struct LatencyPoint: Identifiable {
    let start: Date
    let median: TimeInterval
    let tail: TimeInterval?
    let run: Int

    var id: Date {
        start
    }
}

// MARK: - StackedSegment

private struct StackedSegment: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let statusClass: TrafficInsightsStatusClass
    let yStart: Int
    let yEnd: Int
}

// MARK: - TrafficInsightsBinCallout

/// Hover detail for one bin. Shows every series of the active metric so a reader never has to
/// guess which line the pointer is closest to.
private struct TrafficInsightsBinCallout: View {
    // MARK: Internal

    let bin: TrafficInsightsTimelineBin
    let binWidth: TimeInterval
    let metric: TrafficInsightsTimelineMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rangeLabel)
                .font(toolMetrics.metadataFont(weight: .semibold))
                .foregroundStyle(.primary)
            switch metric {
            case .bytes:
                calloutRow(
                    color: Theme.Insights.received,
                    label: String(localized: "Received", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.bytes(bin.receivedBytes)
                )
                calloutRow(
                    color: Theme.Insights.sent,
                    label: String(localized: "Sent", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.bytes(bin.sentBytes)
                )
            case .requests:
                ForEach(TrafficInsightsStatusClass.allCases, id: \.self) { statusClass in
                    if let count = bin.countsByStatusClass[statusClass], count > 0 {
                        calloutRow(
                            color: Theme.Insights.statusClassColor(statusClass),
                            label: statusClass.displayName,
                            value: TrafficInsightsFormatting.count(count)
                        )
                    }
                }
            case .latency:
                calloutRow(
                    color: Theme.Insights.latencyMedian,
                    label: String(localized: "Median", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.duration(bin.medianDuration)
                )
                calloutRow(
                    color: Theme.Insights.latencyTail,
                    label: "p95",
                    value: TrafficInsightsFormatting.duration(bin.tailDuration)
                )
            }
            if metric != .bytes {
                calloutRow(
                    color: Theme.Insights.received,
                    label: String(localized: "Received", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.bytes(bin.receivedBytes)
                )
                calloutRow(
                    color: Theme.Insights.sent,
                    label: String(localized: "Sent", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.bytes(bin.sentBytes)
                )
            }
            if metric != .latency {
                calloutRow(
                    color: Theme.Insights.latencyMedian,
                    label: String(localized: "Median", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.duration(bin.medianDuration)
                )
                calloutRow(
                    color: Theme.Insights.latencyTail,
                    label: "p95",
                    value: TrafficInsightsFormatting.duration(bin.tailDuration)
                )
            }
            if metric != .requests, bin.errorCount > 0 {
                calloutRow(
                    color: Theme.Insights.statusClassColor(.serverError),
                    label: String(localized: "Errors", bundle: RockxyLocalization.bundle),
                    value: TrafficInsightsFormatting.count(bin.errorCount)
                )
            }
            if bin.requestCount > 0 {
                Text(String(localized: "Click to select", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rockxyGlassEffect(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var rangeLabel: String {
        let start = TrafficInsightsFormatting.clockTime(bin.start)
        let requests = TrafficInsightsText.inflected("^[\(bin.requestCount) request](inflect: true)")
        if binWidth >= 2 {
            let end = TrafficInsightsFormatting.clockTime(bin.start.addingTimeInterval(binWidth))
            return "\(start) – \(end) · \(requests)"
        }
        return "\(start) · \(requests)"
    }

    private func calloutRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(toolMetrics.metadataFont(weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}
