import Foundation

/// Top-level navigation tabs in the main window toolbar.
/// Each tab corresponds to a core debugging pillar: network traffic,
/// application logs, and request timeline.
enum MainTab: String, CaseIterable {
    case traffic
    case logs
    case timeline

    // MARK: Internal

    var displayName: String {
        switch self {
        case .traffic: String(localized: "Traffic", bundle: RockxyLocalization.bundle)
        case .logs: String(localized: "Logs", bundle: RockxyLocalization.bundle)
        case .timeline: String(localized: "Timeline", bundle: RockxyLocalization.bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .traffic: "network"
        case .logs: "doc.text"
        case .timeline: "chart.bar.xaxis"
        }
    }
}
