import Charts
import SwiftUI

// Renders the protocol share donut and its legend for the Traffic Insights report.

// MARK: - TrafficInsightsProtocolChart

/// Donut of protocol families with a legend that doubles as the accessible, text-first
/// representation of the same numbers. Hovering a sector or a legend row highlights both.
struct TrafficInsightsProtocolChart: View {
    // MARK: Internal

    let shares: [TrafficInsightsShare<TrafficInsightsProtocol>]
    let basis: TrafficInsightsShareBasis
    var isActive: (TrafficInsightsDrillDown) -> Bool = { _ in false }
    var onToggle: (TrafficInsightsDrillDown) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            donut
                .frame(width: 150, height: 150)
            legend
        }
        .onChange(of: selectedAngle) { _, angle in
            hoveredProtocol = angle.flatMap(protocolKind(atAngle:))
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var selectedAngle: Double?
    @State private var hoveredProtocol: TrafficInsightsProtocol?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var total: Double {
        shares.reduce(0) { $0 + value(of: $1) }
    }

    private var hoveredShare: TrafficInsightsShare<TrafficInsightsProtocol>? {
        shares.first { $0.key == hoveredProtocol }
    }

    private var accessibilitySummary: String {
        let parts = shares.map { share in
            "\(share.key.displayName) \(TrafficInsightsFormatting.percent(fraction(of: share)))"
        }
        return String(
            localized: "Protocol share by \(basis.displayName): \(parts.joined(separator: ", "))",
            bundle: RockxyLocalization.bundle
        )
    }

    private var donut: some View {
        Chart(shares) { share in
            SectorMark(
                angle: .value("Share", value(of: share)),
                innerRadius: .ratio(Theme.Insights.donutInnerRadiusRatio),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(Theme.Insights.protocolColor(share.key))
            .opacity(hoveredProtocol == nil || hoveredProtocol == share.key ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { _ in
            VStack(spacing: 1) {
                Text(hoveredShare.map { TrafficInsightsFormatting.percent(fraction(of: $0)) }
                     ?? TrafficInsightsFormatting.count(shares.count))
                    .font(.system(size: toolMetrics.bodyFontSize + 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(hoveredShare?.key.displayName ?? (shares.count == 1
                    ? String(localized: "protocol", bundle: RockxyLocalization.bundle)
                    : String(localized: "protocols", bundle: RockxyLocalization.bundle)))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                if let hoveredShare {
                    Text("\(TrafficInsightsFormatting.count(hoveredShare.requestCount)) · \(TrafficInsightsFormatting.bytes(hoveredShare.bytes))")
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: 90)
        }
        .help(hoveredShare.map { legendHelp(for: $0) } ?? accessibilitySummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(shares) { share in
                let target = share.key.drillDown
                TrafficInsightsShareRow(
                    color: Theme.Insights.protocolColor(share.key),
                    name: share.key.displayName,
                    primaryValue: TrafficInsightsFormatting.percent(fraction(of: share)),
                    secondaryValue: secondaryLabel(for: share),
                    fraction: fraction(of: share),
                    isHighlighted: hoveredProtocol == share.key,
                    isDimmed: hoveredProtocol != nil && hoveredProtocol != share.key,
                    isActive: target.map(isActive) ?? false,
                    action: target.map { target in { onToggle(target) } }
                )
                .onHover { isHovering in
                    hoveredProtocol = isHovering ? share.key : nil
                }
                .help(legendHelp(for: share))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legendHelp(for share: TrafficInsightsShare<TrafficInsightsProtocol>) -> String {
        let counts = "\(TrafficInsightsFormatting.count(share.requestCount)) · \(TrafficInsightsFormatting.bytes(share.bytes))"
        let action = share.key.drillDown == nil
            ? String(localized: "Visible only as CONNECT rows", bundle: RockxyLocalization.bundle)
            : String(localized: "Click to filter the request list", bundle: RockxyLocalization.bundle)
        return "\(share.key.detailDescription)\n\(counts)\n\(action)"
    }

    private func value(of share: TrafficInsightsShare<TrafficInsightsProtocol>) -> Double {
        switch basis {
        case .requests: Double(share.requestCount)
        case .bytes: Double(share.bytes)
        }
    }

    private func fraction(of share: TrafficInsightsShare<TrafficInsightsProtocol>) -> Double {
        total <= 0 ? 0 : value(of: share) / total
    }

    private func secondaryLabel(for share: TrafficInsightsShare<TrafficInsightsProtocol>) -> String {
        switch basis {
        case .requests: TrafficInsightsFormatting.count(share.requestCount)
        case .bytes: TrafficInsightsFormatting.bytes(share.bytes)
        }
    }

    private func protocolKind(atAngle angle: Double) -> TrafficInsightsProtocol? {
        var cumulative = 0.0
        for share in shares {
            cumulative += value(of: share)
            if angle <= cumulative {
                return share.key
            }
        }
        return shares.last?.key
    }
}
