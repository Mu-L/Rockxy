import AppKit
import SwiftUI

// Shared building blocks for the Traffic Insights report: cards, stat tiles, share rows.

// MARK: - TrafficInsightsFormatting

/// View-side formatting shared by every insights card so numbers read the same everywhere.
enum TrafficInsightsFormatting {
    static func bytes(_ value: Int64) -> String {
        TrafficInsightsReportFormatter.formatBytes(value)
    }

    static func duration(_ value: TimeInterval?) -> String {
        TrafficInsightsReportFormatter.formatDuration(value)
    }

    static func percent(_ fraction: Double) -> String {
        TrafficInsightsReportFormatter.formatPercent(fraction)
    }

    static func count(_ value: Int) -> String {
        TrafficInsightsReportFormatter.formatCount(value)
    }

    static func share(_ part: Int64, of total: Int64) -> Double {
        total <= 0 ? 0 : min(1, Double(part) / Double(total))
    }

    static func share(_ part: Int, of total: Int) -> Double {
        total <= 0 ? 0 : min(1, Double(part) / Double(total))
    }

    static func clockTime(_ date: Date) -> String {
        TimestampFormatter.string(date, date: .omitted, time: .standard)
    }

    static func isIPAddressLike(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else {
            return false
        }
        return parts.allSatisfy { Int($0) != nil }
    }
}

// MARK: - TrafficInsightsCard

/// A titled report section. Cards are the only container in the report so spacing, corner
/// radius, and header hierarchy stay identical across every chart and list.
struct TrafficInsightsCard<Content: View, Accessory: View>: View {
    // MARK: Lifecycle

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    // MARK: Internal

    let title: String
    let subtitle: String?
    let accessory: Accessory
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(toolMetrics.font(weight: .semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(toolMetrics.metadataFont())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                accessory
                    .layoutPriority(1)
            }
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Insights.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Theme.Insights.cardCornerRadius, style: .continuous)
                .fill(Theme.Insights.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Insights.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Insights.cardStroke.opacity(0.6), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

extension TrafficInsightsCard where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - TrafficInsightsStatTile

/// One headline number. The value is the only large type in the report; everything else stays
/// at body size so the tiles read as a summary row rather than a marketing banner.
struct TrafficInsightsStatTile: View {
    // MARK: Internal

    let title: String
    let value: String
    var detail: String?
    var systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: toolMetrics.bodyFontSize + 1, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .center)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: toolMetrics.bodyFontSize + 7, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Insights.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Insights.cardCornerRadius, style: .continuous)
                .fill(Theme.Insights.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Insights.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Insights.cardStroke.opacity(0.6), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \(value), \($0)" } ?? "\(title), \(value)")
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - TrafficInsightsShareRow

/// One labelled proportional bar. Used by the outcome, content, method, and protocol legends.
/// When `action` is set the row is a real button that applies the matching request-list filter;
/// `isActive` mirrors that filter so the row reads like the pill it toggles.
struct TrafficInsightsShareRow: View {
    // MARK: Internal

    let color: Color
    let name: String
    let primaryValue: String
    let secondaryValue: String?
    let fraction: Double
    var note: String?
    var isHighlighted = false
    var isDimmed = false
    var isActive = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                isHovered = isHovering
            }
            .accessibilityAddTraits(isActive ? .isSelected : [])
        } else {
            content
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var isHovered = false

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(name)
                    .font(toolMetrics.secondaryFont(weight: isHighlighted || isActive ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(2)
                if let note {
                    // The code note is supporting detail: show it whole or not at all rather
                    // than as a truncated fragment next to the label.
                    ViewThatFits(in: .horizontal) {
                        Text(note)
                            .font(toolMetrics.metadataFont())
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                Spacer(minLength: 8)
                Text(primaryValue)
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let secondaryValue {
                    Text(secondaryValue)
                        .font(toolMetrics.metadataFont())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            TrafficInsightsProportionBar(fraction: fraction, color: color)
        }
        .padding(.horizontal, action == nil ? 0 : 6)
        .padding(.vertical, action == nil ? 0 : 4)
        .background {
            if action != nil {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive
                        ? Color.accentColor.opacity(0.10)
                        : Color.primary.opacity(isHovered ? 0.05 : 0))
            }
        }
        .opacity(isDimmed ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [name, primaryValue, secondaryValue, note].compactMap { $0 }.joined(separator: ", ")
        )
    }
}

// MARK: - TrafficInsightsProportionBar

/// A thin horizontal bar whose fill width is the fraction of the row's total. Drawn with a
/// capsule on a quaternary track so it stays legible in Light, Dark, and Increase Contrast.
struct TrafficInsightsProportionBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Insights.neutralBar.opacity(0.5))
                Capsule()
                    .fill(color)
                    .frame(width: max(fraction > 0 ? 3 : 0, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: Theme.Insights.rankBarHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - TrafficInsightsHostIcon

/// Globe for named hosts, network glyph for raw IP addresses, so the two remain distinguishable
/// even when the name column is truncated.
struct TrafficInsightsHostIcon: View {
    let host: String

    var body: some View {
        Image(systemName: TrafficInsightsFormatting.isIPAddressLike(host) ? "network" : "globe")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

// MARK: - TrafficInsightsAppIcon

/// Resolves the application icon when the app is installed or running, otherwise a neutral glyph.
struct TrafficInsightsAppIcon: View {
    let appName: String

    var body: some View {
        if let icon = AppIconProvider.applicationIcon(named: appName, size: 20) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - TrafficInsightsTimingBar

/// Average time per request split into connection phases. One stacked bar answers "where does
/// the time go" faster than five numbers; the legend still carries the exact averages.
struct TrafficInsightsTimingBar: View {
    // MARK: Internal

    let timing: TrafficInsightsTimingBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(phases, id: \.title) { phase in
                        if phase.value > 0 {
                            Rectangle()
                                .fill(phase.color)
                                .frame(width: max(2, proxy.size.width * CGFloat(phase.value / total)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(phases, id: \.title) { phase in
                    HStack(spacing: 8) {
                        Circle().fill(phase.color).frame(width: 8, height: 8)
                        Text(phase.title)
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(DurationFormatter.format(seconds: phase.value))
                            .font(toolMetrics.secondaryFont(weight: .semibold))
                            .monospacedDigit()
                        Text(TrafficInsightsFormatting.percent(total > 0 ? phase.value / total : 0))
                            .font(toolMetrics.metadataFont())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(phase.title), \(DurationFormatter.format(seconds: phase.value))")
                }
            }
        }
        .help(TrafficInsightsText.inflected(
            "Average per request across ^[\(timing.sampleCount) timed request](inflect: true). Tunnels and WebSockets are excluded."
        ))
    }

    // MARK: Private

    private struct Phase {
        let title: String
        let value: TimeInterval
        let color: Color
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var total: TimeInterval {
        max(timing.total, 0.000001)
    }

    private var phases: [Phase] {
        [
            Phase(title: "DNS", value: timing.dnsLookup, color: Theme.Timing.dns),
            Phase(title: "TCP", value: timing.tcpConnection, color: Theme.Timing.tcp),
            Phase(title: "TLS", value: timing.tlsHandshake, color: Theme.Timing.tls),
            Phase(
                title: String(localized: "Waiting", bundle: RockxyLocalization.bundle),
                value: timing.timeToFirstByte,
                color: Theme.Timing.ttfb
            ),
            Phase(
                title: String(localized: "Transfer", bundle: RockxyLocalization.bundle),
                value: timing.contentTransfer,
                color: Theme.Timing.transfer
            ),
        ]
    }
}
