import Foundation

// Explicit, bounded conversion between a live ``WorkspaceState`` traffic tab and
// its durable ``ProjectTabSnapshot``. Kept separate from the DTO so the snapshot
// value type stays free of `@MainActor` UI dependencies, and separate from
// ``WorkspaceState`` so that type never gains `Codable`/persistence coupling.

@MainActor
extension ProjectTabSnapshot {
    /// Captures the durable configuration of a single live traffic tab.
    init(capturing workspace: WorkspaceState) {
        self.init(
            id: workspace.id,
            title: workspace.title.boundedToGraphemes(ProjectStructuralLimits.nameGraphemeRange.upperBound),
            isClosable: workspace.isClosable,
            filter: FilterCriteriaSnapshot(workspace.filterCriteria),
            advancedFilterRows: workspace.filterRules
                .prefix(ProjectStructuralLimits.maxAdvancedFilterRows)
                .map { FilterRuleSnapshot($0) },
            isFilterBarVisible: workspace.isFilterBarVisible,
            mainTabRawValue: workspace.activeMainTab.rawValue,
            inspectorLayoutRawValue: InspectorLayoutCoding.rawValue(for: workspace.inspectorLayout),
            isContextDockVisible: workspace.isContextDockVisible,
            contextDockTabRawValue: ContextDockTabCoding.rawValue(for: workspace.contextDockTab),
            focusNavigatorModeRawValue: workspace.focusNavigatorMode.rawValue,
            activeTrafficSignalRawValue: workspace.activeTrafficSignal?.rawValue,
            activeFocusSetID: workspace.activeFocusSetID,
            mutedTrafficSources: workspace.mutedTrafficSources
                .map { MutedTrafficSourceSnapshot($0) }
                .sorted { $0.value < $1.value }
                .boundedCount(ProjectStructuralLimits.maxMutedTrafficSources)
        )
    }

    /// Rebuilds a live traffic tab from this snapshot. Only durable view intent is
    /// restored; captured traffic and derived indexes are recomputed elsewhere and
    /// app-global focus-set definitions are loaded by ``WorkspaceState`` itself.
    func hydrateWorkspaceState() -> WorkspaceState {
        let resolvedFilter = filter.resolved
        let state = WorkspaceState(
            id: id,
            title: title,
            isClosable: isClosable,
            initialFilter: resolvedFilter,
            inspectorLayout: InspectorLayoutCoding.layout(for: inspectorLayoutRawValue),
            isContextDockVisible: isContextDockVisible,
            allowsAutomaticInspectorReveal: true
        )
        state.activeMainTab = MainTab(rawValue: mainTabRawValue) ?? .traffic
        state.contextDockTab = ContextDockTabCoding.tab(for: contextDockTabRawValue)
        state.focusNavigatorMode = FocusNavigatorMode(rawValue: focusNavigatorModeRawValue) ?? .browse
        state.activeTrafficSignal = activeTrafficSignalRawValue.flatMap { TrafficSignal(rawValue: $0) }
        state.activeFocusSetID = activeFocusSetID
        state.mutedTrafficSources = Set(mutedTrafficSources.compactMap(\.resolved))
        state.filterRules = advancedFilterRows.isEmpty
            ? [FilterRule()]
            : advancedFilterRows.map(\.resolved)
        state.isFilterBarVisible = isFilterBarVisible
        return state
    }
}
