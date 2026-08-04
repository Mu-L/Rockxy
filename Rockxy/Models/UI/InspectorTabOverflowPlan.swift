import CoreGraphics

// MARK: - InspectorTabLayoutItem

/// A single tab competing for horizontal space in an inspector tab strip.
///
/// Pure and value-typed so the overflow distribution can be verified without a live
/// window. `width` is the measured/estimated intrinsic width the tab needs when rendered
/// directly in the strip (including any leading group separator it reserves).
struct InspectorTabLayoutItem: Equatable {
    let id: String
    let width: CGFloat
}

// MARK: - InspectorTabOverflowPlan

/// Result of distributing tabs between the directly-visible strip and the overflow menu.
struct InspectorTabOverflowPlan: Equatable {
    let visibleIDs: [String]
    let overflowIDs: [String]

    var hasOverflow: Bool {
        !overflowIDs.isEmpty
    }
}

// MARK: - InspectorTabOverflowPlanner

/// Distributes inspector tabs between the visible strip and a native overflow menu.
///
/// Guarantees, for a given (`items`, `activeID`, `availableWidth`) triple:
/// - visible tabs fit within `availableWidth` (minus the overflow affordance when overflow occurs),
/// - the `activeID` tab is always visible, even at extremely narrow widths,
/// - source order is preserved in both the visible strip and the overflow menu.
///
/// The function is pure: the same inputs always produce the same plan, so resize and font-size
/// changes recompute deterministically without oscillation or selection changes.
enum InspectorTabOverflowPlanner {
    static func plan(
        items: [InspectorTabLayoutItem],
        activeID: String?,
        availableWidth: CGFloat,
        overflowAffordanceWidth: CGFloat
    )
        -> InspectorTabOverflowPlan
    {
        guard !items.isEmpty else {
            return InspectorTabOverflowPlan(visibleIDs: [], overflowIDs: [])
        }

        let totalWidth = items.reduce(0) { $0 + $1.width }
        if totalWidth <= availableWidth {
            return InspectorTabOverflowPlan(visibleIDs: items.map(\.id), overflowIDs: [])
        }

        var remaining = max(0, availableWidth - overflowAffordanceWidth)
        var visible = Set<String>()

        // Reserve the active tab first so it is always directly reachable. In an extremely narrow
        // strip this can drive `remaining` negative, which simply forces every other tab to overflow.
        if let activeID, let active = items.first(where: { $0.id == activeID }) {
            visible.insert(active.id)
            remaining -= active.width
        }

        for item in items where !visible.contains(item.id) {
            if item.width <= remaining {
                visible.insert(item.id)
                remaining -= item.width
            }
        }

        let visibleIDs = items.filter { visible.contains($0.id) }.map(\.id)
        let overflowIDs = items.filter { !visible.contains($0.id) }.map(\.id)
        return InspectorTabOverflowPlan(visibleIDs: visibleIDs, overflowIDs: overflowIDs)
    }
}
