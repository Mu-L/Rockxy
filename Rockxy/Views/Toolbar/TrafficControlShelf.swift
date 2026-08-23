import SwiftUI

// MARK: - TrafficControlShelf

/// The top-level functional layer for traffic commands and filtering.
///
/// Liquid Glass belongs to this shared navigation/control surface, while the request table below
/// remains an opaque, high-density content layer. Child controls deliberately avoid their own
/// glass backgrounds so the shelf never becomes glass-on-glass.
struct TrafficControlShelf: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let advancedRuleCount: Int
    let onOpenToolWindow: (String) -> Void

    var body: some View {
        RockxyGlassEffectGroup(spacing: Theme.Glass.shelfSectionSpacing) {
            VStack(spacing: Theme.Glass.shelfSectionSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Layout.controlSpacing) {
                        trafficCommandBar

                        Divider()
                            .frame(height: 22)

                        searchFilterBar
                            .layoutPriority(1)
                    }

                    VStack(spacing: Theme.Glass.shelfSectionSpacing) {
                        trafficCommandBar
                        shelfSeparator
                        searchFilterBar
                    }
                }

                shelfSeparator

                ProtocolFilterBar(
                    activeFilters: Binding(
                        get: { coordinator.filterCriteria.activeProtocolFilters },
                        set: {
                            coordinator.filterCriteria.activeProtocolFilters = $0
                            coordinator.recomputeFilteredTransactions()
                        }
                    ),
                    isEmbeddedInControlShelf: true
                )

                if coordinator.isFilterBarVisible {
                    shelfSeparator

                    AdvancedFilterBar(
                        rules: Binding(
                            get: { coordinator.filterRules },
                            set: {
                                coordinator.filterRules = $0
                                coordinator.recomputeFilteredTransactions()
                            }
                        ),
                        presetStore: coordinator.filterPresetStore,
                        isEmbeddedInControlShelf: true
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ActiveFilterSummaryBar(
                    coordinator: coordinator,
                    isEmbeddedInControlShelf: true
                )
            }
            .padding(Theme.Glass.shelfInset)
            .rockxyGlassEffect(
                in: RoundedRectangle(
                    cornerRadius: Theme.Glass.shelfCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Theme.Glass.shelfCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.primary.opacity(Theme.Glass.shelfStrokeOpacity),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(Theme.Glass.shelfShadowOpacity),
                radius: Theme.Glass.shelfShadowRadius,
                x: 0,
                y: Theme.Glass.shelfShadowY
            )
        }
        .padding(.horizontal, Theme.Glass.shelfOuterPadding)
        .padding(.top, Theme.Glass.shelfOuterPadding)
        .padding(.bottom, Theme.Glass.shelfOuterPadding - 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private var shelfSeparator: some View {
        Divider()
            .opacity(Theme.Glass.separatorOpacity)
            .padding(.horizontal, Theme.Layout.contentPadding)
    }

    private var trafficCommandBar: some View {
        TrafficCommandBar(
            coordinator: coordinator,
            onOpenToolWindow: onOpenToolWindow,
            isEmbeddedInControlShelf: true,
            showsQuickTools: false
        )
    }

    private var searchFilterBar: some View {
        SearchFilterBar(
            searchText: Binding(
                get: { coordinator.filterCriteria.searchText },
                set: {
                    coordinator.filterCriteria.searchText = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            filterField: Binding(
                get: { coordinator.filterCriteria.searchField },
                set: {
                    coordinator.filterCriteria.searchField = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            isEnabled: Binding(
                get: { coordinator.filterCriteria.isSearchEnabled },
                set: {
                    coordinator.filterCriteria.isSearchEnabled = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            isAdvancedFilterVisible: coordinator.isFilterBarVisible,
            advancedFilterCount: advancedRuleCount,
            onAddFilter: coordinator.addAdvancedFilterRule,
            onToggleAdvancedFilters: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    coordinator.isFilterBarVisible.toggle()
                }
                coordinator.recomputeFilteredTransactions()
            },
            isEmbeddedInControlShelf: true
        )
    }
}
