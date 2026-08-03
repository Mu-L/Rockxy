import Foundation

// MARK: - MatchedRuleNavigationTarget

/// Pure mapping from a matched rule's `RuleAction` to the existing tool window that edits that
/// rule category. This is deliberately a bounded routing table — it opens the correct existing
/// rules window rather than inventing a cross-window rule-selection framework. Categories that
/// have no dedicated tool window resolve to `.unavailable`, so the Context dock can stay honest
/// and hide "Open Rule" instead of routing to a wrong or non-existent surface.
enum MatchedRuleNavigationTarget: Equatable {
    case toolWindow(id: String, windowTitle: String)
    case unavailable

    // MARK: Lifecycle

    init(action: RuleAction) {
        switch action {
        case .breakpoint:
            self = .toolWindow(id: "breakpointRules", windowTitle: String(localized: "Breakpoint Rules"))
        case .mapLocal:
            self = .toolWindow(id: "mapLocal", windowTitle: String(localized: "Map Local"))
        case .mapRemote:
            self = .toolWindow(id: "mapRemote", windowTitle: String(localized: "Map Remote"))
        case .block:
            self = .toolWindow(id: "blockList", windowTitle: String(localized: "Block List"))
        case .modifyHeader:
            self = .toolWindow(id: "modifyHeaders", windowTitle: String(localized: "Modify Headers"))
        case .networkCondition:
            self = .toolWindow(id: "networkConditions", windowTitle: String(localized: "Network Conditions"))
        case .throttle:
            // Throttle rules have no standalone tool window; they live in the generic rule list.
            self = .unavailable
        }
    }

    // MARK: Internal

    var windowID: String? {
        switch self {
        case let .toolWindow(id, _): id
        case .unavailable: nil
        }
    }

    /// Truthful help text: this opens the rule's editor window, it does not reveal the exact rule.
    var openHelp: String? {
        switch self {
        case let .toolWindow(_, windowTitle):
            String(localized: "Open the \(windowTitle) window")
        case .unavailable:
            nil
        }
    }
}
