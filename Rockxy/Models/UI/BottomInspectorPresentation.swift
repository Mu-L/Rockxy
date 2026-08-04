import Foundation

// MARK: - BottomInspectorContent

/// What the bottom payload inspector can present for the current selection.
///
/// Mirrors `InspectorPanelView`: multi-selection shows a selection summary, a single
/// selection shows raw request/response payload, and an empty selection has nothing
/// to inspect.
enum BottomInspectorContent: Equatable {
    /// No transaction selected — nothing to inspect.
    case none
    /// Exactly one transaction selected — raw request/response payload.
    case single
    /// Two or more transactions selected — selection summary.
    case summary
}

// MARK: - BottomInspectorPresentation

/// Pure resolver that separates the user's persisted bottom-inspector *preference*
/// (`InspectorLayout` + automatic reveal) from the *effective* presentation shown for
/// the current selection.
///
/// The bottom inspector is temporarily collapsed whenever there is nothing to inspect,
/// so the request table reclaims the space. Collapsing here never mutates the persisted
/// layout preference or the automatic-reveal flag — it is derived state only.
enum BottomInspectorPresentation {
    /// Resolves the content state from the current selection counts.
    static func content(selectedCount: Int, hasSingleSelection: Bool) -> BottomInspectorContent {
        if selectedCount > 1 {
            return .summary
        }
        return hasSingleSelection ? .single : .none
    }

    /// Whether the native bottom split item should be expanded.
    ///
    /// Returns `false` for an empty selection regardless of the stored layout so the
    /// table gets the space; otherwise honors the persisted `InspectorLayout` preference.
    static func isPresented(layout: InspectorLayout, content: BottomInspectorContent) -> Bool {
        guard content != .none else {
            return false
        }
        return layout == .bottom
    }

    /// Whether a bottom-inspector show/hide control should be enabled.
    ///
    /// Toggling with nothing to inspect would only flip a hidden preference with no
    /// visible result, so controls are disabled (and the toggle is a no-op) in that case.
    static func allowsToggle(content: BottomInspectorContent) -> Bool {
        content != .none
    }
}
