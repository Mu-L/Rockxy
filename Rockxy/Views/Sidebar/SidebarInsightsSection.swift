import SwiftUI

// Renders the Insights destination at the top of the Browse navigator.

// MARK: - SidebarInsightsSection

/// Report destination for the active Traffic Tab. It sits above the source tree because it
/// summarizes everything below it, and it is a real list selection so keyboard navigation,
/// persistence, and the View menu all agree on which center content is showing.
struct SidebarInsightsSection: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        Section {
            Label {
                Text(String(localized: "Insights", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.sidebarNavigationFontSize))
            } icon: {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: metrics.sidebarIconFontSize))
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: metrics.sidebarNavigationFontSize))
            .badge(coordinator.transactions.count)
            .tag(SidebarItem.insights)
            .frame(minHeight: metrics.sidebarRowHeight)
            .accessibilityIdentifier("sidebar.insights")
            .help(String(
                localized: "Report on this Traffic Tab: findings, traffic over time, protocols, top apps and hosts.",
                bundle: RockxyLocalization.bundle
            ))
        } header: {
            Text(String(localized: "Overview", bundle: RockxyLocalization.bundle))
                .foregroundStyle(Theme.Sidebar.sectionHeader)
                .font(.system(size: metrics.sidebarSectionHeaderFontSize, weight: .semibold))
        }
        .headerProminence(.increased)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}
