import SwiftUI

// Renders the active filter summary bar interface for toolbar controls and filtering.

// MARK: - ActiveFilterSummaryBar

/// Compact horizontal bar displaying removable chips for each active filter dimension.
/// Only visible when at least one filter is active, providing at-a-glance filter state
/// and one-tap clearing of individual or all filters.
struct ActiveFilterSummaryBar: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    var isEmbeddedInControlShelf = false

    var body: some View {
        if hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let signal = coordinator.activeWorkspace.activeTrafficSignal {
                        FilterChip(label: String(localized: "Signal: \(signal.title)")) {
                            coordinator.toggleTrafficSignal(signal)
                        }
                    }

                    if let focusSet = coordinator.activeWorkspace.activeFocusSet {
                        FilterChip(label: String(localized: "Focus: \(focusSet.displayName)")) {
                            coordinator.applyFocusSet(nil)
                        }
                    }

                    if !coordinator.activeWorkspace.mutedTrafficSources.isEmpty {
                        FilterChip(
                            label: String(
                                localized: "\(coordinator.activeWorkspace.mutedTrafficSources.count) muted sources"
                            ),
                            onRemove: coordinator.unmuteAllTrafficSources
                        )
                    }

                    if let domain = coordinator.filterCriteria.sidebarDomain {
                        let pathPrefix = coordinator.filterCriteria.sidebarPathPrefix ?? ""
                        FilterChip(
                            label: String(localized: "Domain: \(domain)\(pathPrefix)"),
                            onRemove: {
                                coordinator.filterCriteria.sidebarDomain = nil
                                coordinator.filterCriteria.sidebarPathPrefix = nil
                                coordinator.sidebarSelection = nil
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if let app = coordinator.filterCriteria.sidebarApp {
                        FilterChip(
                            label: String(localized: "App: \(app)"),
                            onRemove: {
                                coordinator.filterCriteria.sidebarApp = nil
                                coordinator.sidebarSelection = nil
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if coordinator.filterCriteria.sidebarScope == .saved {
                        FilterChip(label: String(localized: "Saved")) {
                            coordinator.filterCriteria.sidebarScope = .allTraffic
                            coordinator.filterCriteria.exactTransactionID = nil
                            coordinator.sidebarSelection = nil
                            coordinator.recomputeFilteredTransactions()
                        }
                    }

                    if coordinator.filterCriteria.sidebarScope == .pinned {
                        FilterChip(label: String(localized: "Pinned")) {
                            coordinator.filterCriteria.sidebarScope = .allTraffic
                            coordinator.filterCriteria.exactTransactionID = nil
                            coordinator.sidebarSelection = nil
                            coordinator.recomputeFilteredTransactions()
                        }
                    }

                    if coordinator.filterCriteria.sidebarScope == .notes {
                        FilterChip(label: String(localized: "Notes")) {
                            coordinator.filterCriteria.sidebarScope = .allTraffic
                            coordinator.filterCriteria.exactTransactionID = nil
                            coordinator.sidebarSelection = nil
                            coordinator.recomputeFilteredTransactions()
                        }
                    }

                    Button(String(localized: "Clear All")) {
                        coordinator.clearAllWorkspaceFilters()
                    }
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: metrics.filterBarHeight)
            .background {
                if !isEmbeddedInControlShelf {
                    Color(nsColor: .controlBackgroundColor).opacity(0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if !isEmbeddedInControlShelf {
                    Divider()
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var hasActiveFilters: Bool {
        coordinator.activeWorkspace.activeTrafficSignal != nil
            || coordinator.activeWorkspace.activeFocusSet != nil
            || !coordinator.activeWorkspace.mutedTrafficSources.isEmpty
            || coordinator.filterCriteria.sidebarDomain != nil
            || coordinator.filterCriteria.sidebarPathPrefix != nil
            || coordinator.filterCriteria.sidebarApp != nil
            || coordinator.filterCriteria.sidebarScope == .saved
            || coordinator.filterCriteria.sidebarScope == .pinned
            || coordinator.filterCriteria.sidebarScope == .notes
    }
}

// MARK: - FilterChip

/// Removable pill displaying a single active filter with an X button.
private struct FilterChip: View {
    // MARK: Internal

    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: metrics.badgeFontSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .rockxyChipStyle(isActive: true)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}
