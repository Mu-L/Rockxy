import Foundation

/// Pure, view-free selection and presentation logic for the adaptive protocol filter bar.
///
/// The bar shows a single line of `FilterPillButton`s plus an `ellipsis.circle` overflow menu.
/// This type partitions the `ProtocolFilter` cases into stable, ordered groups (Transport /
/// Protocol / Content / Status), decides which pills appear inline at each adaptive width tier,
/// and derives the complementary overflow-menu contents. All matching semantics (OR within a
/// group, AND across groups) live in `MainContentCoordinator+Filtering`; this type only decides
/// what is shown and how a toggle mutates the active set. `.all` is a presentation-only sentinel —
/// it is never stored as an active filter.
enum ProtocolFilterSelection {
    /// Transport section of the overflow menu, in stable display order.
    static let transportFilters: [ProtocolFilter] = [.all, .http, .https, .websocket]

    /// Smart / protocol section of the overflow menu, in stable display order.
    static let protocolFilters: [ProtocolFilter] = [.ai, .aiSession, .web3RPC, .rpcError, .graphql, .grpc]

    /// Content section of the overflow menu, in stable display order.
    static let contentTypeFilters: [ProtocolFilter] = [
        .json, .xml, .js, .css, .document, .media, .form, .font, .other,
    ]

    /// Status section of the overflow menu, in ascending range order.
    static let statusFilters: [ProtocolFilter] = [.status1xx, .status2xx, .status3xx, .status4xx, .status5xx]

    /// Stable pill sets shown at each adaptive width tier, widest first. Practical tiers keep both
    /// traffic-type and status filters visible so the bar continues to advertise both capabilities
    /// as it contracts. The last (`.all` only) is the safe fallback. Selection never changes these
    /// arrays, so pills do not reorder when toggled. Keep the tier count in sync with
    /// `ProtocolFilterBar`'s explicit `ViewThatFits` candidates.
    static let inlinePillTiers: [[ProtocolFilter]] = [
        [
            .all,
            .http,
            .https,
            .websocket,
            .ai,
            .aiSession,
            .web3RPC,
            .json,
            .graphql,
            .status2xx,
            .status4xx,
            .status5xx
        ],
        [.all, .http, .https, .websocket, .ai, .json, .status2xx, .status4xx, .status5xx],
        [.all, .https, .websocket, .ai, .json, .status2xx, .status4xx],
        [.all, .https, .ai, .status2xx, .status4xx],
        [.all, .https, .status2xx, .status4xx],
        [.all],
    ]

    /// Active, user-selectable traffic-type filters (excludes `.all` and status filters),
    /// returned in `ProtocolFilter.allCases` order.
    static func activeTypeFilters(in filters: Set<ProtocolFilter>) -> [ProtocolFilter] {
        ProtocolFilter.allCases.filter { $0 != .all && !$0.isStatusFilter && filters.contains($0) }
    }

    /// Active status filters, returned in `ProtocolFilter.allCases` order.
    static func activeStatusFilters(in filters: Set<ProtocolFilter>) -> [ProtocolFilter] {
        ProtocolFilter.allCases.filter { $0.isStatusFilter && filters.contains($0) }
    }

    /// Inline pills shown at the given adaptive tier (0 = widest).
    static func inlinePills(forTier tier: Int) -> [ProtocolFilter] {
        let clamped = min(max(tier, 0), inlinePillTiers.count - 1)
        return inlinePillTiers[clamped]
    }

    /// Members of `section` that are hidden at the current tier and therefore belong in the
    /// overflow menu, in the section's stable order. `.all` is never an overflow toggle — it is a
    /// pill at every tier.
    static func overflowFilters(in section: [ProtocolFilter], visiblePills: [ProtocolFilter]) -> [ProtocolFilter] {
        let visible = Set(visiblePills)
        return section.filter { $0 != .all && !visible.contains($0) }
    }

    /// Whether any active filter is hidden at the current tier, so the overflow icon should signal
    /// it. `.all` is never stored, so it never counts as a hidden active filter.
    static func hasHiddenActiveFilter(
        activeFilters: Set<ProtocolFilter>,
        visiblePills: [ProtocolFilter]
    )
        -> Bool
    {
        let visible = Set(visiblePills)
        return activeFilters.contains { !visible.contains($0) }
    }

    /// Whether the given filter reads as selected. `.all` is selected exactly when no traffic-type
    /// filter is active.
    static func isSelected(_ filter: ProtocolFilter, in filters: Set<ProtocolFilter>) -> Bool {
        if filter == .all {
            return activeTypeFilters(in: filters).isEmpty
        }
        return filters.contains(filter)
    }

    /// The set produced by toggling `filter`. Selecting `.all` clears traffic-type filters while
    /// preserving status filters; every other toggle flips membership. `.all` is never stored.
    static func toggling(_ filter: ProtocolFilter, in filters: Set<ProtocolFilter>) -> Set<ProtocolFilter> {
        if filter == .all {
            return clearingTypeFilters(in: filters)
        }
        var next = filters
        if next.contains(filter) {
            next.remove(filter)
        } else {
            next.insert(filter)
            next.remove(.all)
        }
        return next
    }

    /// "All Traffic" action — removes traffic-type filters, preserves status filters.
    static func clearingTypeFilters(in filters: Set<ProtocolFilter>) -> Set<ProtocolFilter> {
        Set(filters.filter(\.isStatusFilter))
    }

    /// "Any Status" action — removes status filters, preserves traffic-type filters.
    static func clearingStatusFilters(in filters: Set<ProtocolFilter>) -> Set<ProtocolFilter> {
        Set(filters.filter { !$0.isStatusFilter && $0 != .all })
    }

    /// "Clear All" action — removes both traffic-type and status filters.
    static func clearingAllFilters(in _: Set<ProtocolFilter>) -> Set<ProtocolFilter> {
        []
    }

    /// Removable summary chips for the active filter bar, in `ProtocolFilter.allCases` order.
    /// Excludes the `.all` sentinel.
    static func summaryFilters(in filters: Set<ProtocolFilter>) -> [ProtocolFilter] {
        ProtocolFilter.allCases.filter { $0 != .all && filters.contains($0) }
    }

    /// Menu row label. `.all` renders as "All Traffic"; everything else uses its display name.
    static func menuLabel(for filter: ProtocolFilter) -> String {
        filter == .all ? String(localized: "All Traffic", bundle: RockxyLocalization.bundle) : filter.displayName
    }
}
