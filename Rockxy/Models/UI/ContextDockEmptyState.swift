import Foundation

// MARK: - ContextDockEmptyState

/// The reason the Context Dock has nothing to show for the current selection.
///
/// Kept as a pure decision so the empty-state copy stays honest about capture and
/// filter state without embedding string comparisons in the view.
enum ContextDockEmptyState: Equatable {
    /// No traffic captured yet and capture is running — requests will arrive.
    case waitingForTraffic
    /// No traffic captured and capture is stopped — the user must start capture.
    case captureStopped
    /// Traffic has been captured, but the active filters hide every request.
    case filteredNoResults
    /// Visible traffic exists but nothing is selected — the user should pick a request.
    case selectRequest

    // MARK: Internal

    /// Resolves the empty-state reason from coordinator data.
    ///
    /// - Parameters:
    ///   - hasCapturedTraffic: any traffic captured in the current session.
    ///   - hasVisibleResults: at least one request survives the active workspace scope/filters.
    ///   - isCapturing: the proxy is currently running.
    static func resolve(
        hasCapturedTraffic: Bool,
        hasVisibleResults: Bool,
        isCapturing: Bool
    )
        -> ContextDockEmptyState
    {
        if hasVisibleResults {
            return .selectRequest
        }
        guard hasCapturedTraffic else {
            return isCapturing ? .waitingForTraffic : .captureStopped
        }
        return .filteredNoResults
    }
}

// MARK: - ContextDockEmptyStateCopy

/// User-facing copy for a `ContextDockEmptyState`, rendered through the shared
/// `InspectorEmptyStateView` so every empty state keeps the same visual language.
struct ContextDockEmptyStateCopy: Equatable {
    // MARK: Lifecycle

    init(_ state: ContextDockEmptyState) {
        switch state {
        case .waitingForTraffic:
            title = String(localized: "Waiting for Traffic", bundle: RockxyLocalization.bundle)
            systemImage = "dot.radiowaves.left.and.right"
            description = String(
                localized: "Captured requests will appear here. Select one to inspect its context.",
                bundle: RockxyLocalization.bundle
            )
        case .captureStopped:
            title = String(localized: "Capture Stopped", bundle: RockxyLocalization.bundle)
            systemImage = "stop.circle"
            description = String(
                localized: "Start capture to record requests, then select one to inspect its context.",
                bundle: RockxyLocalization.bundle
            )
        case .filteredNoResults:
            title = String(localized: "No Matching Requests", bundle: RockxyLocalization.bundle)
            systemImage = "line.3.horizontal.decrease.circle"
            description = String(
                localized: "No captured requests match the current view. Adjust or clear its filters to see traffic here.",
                bundle: RockxyLocalization.bundle
            )
        case .selectRequest:
            title = String(localized: "No Selection", bundle: RockxyLocalization.bundle)
            systemImage = "doc.text.magnifyingglass"
            description = String(
                localized: "Select a request to see diagnostics and related traffic.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    // MARK: Internal

    let title: String
    let systemImage: String
    let description: String
}
