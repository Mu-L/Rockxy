import AppKit
import SwiftUI

// MARK: - InspectorTabDescriptor

/// A single tab presented by `InspectorTabStrip`. Value-typed so the strip can measure and
/// distribute tabs deterministically; the `action` closure carries the exact selection-state
/// mutation the owning inspector wants to perform when the tab is chosen (directly or from the
/// overflow menu).
struct InspectorTabDescriptor: Identifiable {
    // MARK: Lifecycle

    init(
        id: String,
        title: String,
        isActive: Bool,
        startsNewGroup: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.isActive = isActive
        self.startsNewGroup = startsNewGroup
        self.action = action
    }

    // MARK: Internal

    let id: String
    let title: String
    let isActive: Bool
    /// When `true`, a group separator is drawn before this tab in the direct strip and its
    /// reserved width includes that separator during layout planning.
    let startsNewGroup: Bool
    let action: () -> Void
}

// MARK: - InspectorTabStripLayout

/// Layout constants shared by `InspectorTabStrip`. Kept at file scope because a generic type
/// cannot declare static stored properties.
private enum InspectorTabStripLayout {
    /// Combined leading + trailing padding used by `InspectorTabButton` (6 pt each side).
    static let horizontalTabPadding: CGFloat = 12
    /// Reserved width for a group separator (8 pt horizontal padding + ~1 pt divider).
    static let groupSeparatorWidth: CGFloat = 9
    static let leadingStripPadding: CGFloat = 4
}

// MARK: - InspectorTabStrip

/// Single-line inspector tab strip that keeps every tab reachable in narrow split panes.
/// Tabs that fit are rendered directly; the remainder collapse into a native overflow menu that
/// still lists every tab (with a checkmark on the active one). Trailing controls are laid out
/// first, so the strip plans overflow against the width that is actually left for tabs.
struct InspectorTabStrip<TrailingContent: View>: View {
    // MARK: Internal

    let tabs: [InspectorTabDescriptor]
    @ViewBuilder let trailingContent: TrailingContent

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                tabRow(availableWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: metrics.inspectorTabHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            trailingContent
                .layoutPriority(1)
                .padding(.leading, 4)
                .padding(.trailing, 4)
        }
        .frame(minHeight: metrics.inspectorTabHeight)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var overflowButtonWidth: CGFloat {
        metrics.inspectorTabHeight + 8
    }

    private var groupSeparator: some View {
        Divider()
            .frame(height: max(14, metrics.controlFontSize + 2))
            .padding(.horizontal, 4)
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(tabs) { descriptor in
                Button(action: descriptor.action) {
                    overflowMenuLabel(descriptor)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: metrics.inspectorTabHeight, height: metrics.inspectorTabHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "More inspector tabs", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(localized: "More inspector tabs", bundle: RockxyLocalization.bundle))
    }

    @ViewBuilder
    private func tabRow(availableWidth: CGFloat) -> some View {
        let plan = InspectorTabOverflowPlanner.plan(
            items: layoutItems(),
            activeID: tabs.first(where: \.isActive)?.id,
            availableWidth: max(0, availableWidth - InspectorTabStripLayout.leadingStripPadding),
            overflowAffordanceWidth: overflowButtonWidth
        )
        let visibleIDs = Set(plan.visibleIDs)
        let visibleTabs = tabs.filter { visibleIDs.contains($0.id) }

        HStack(spacing: 0) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { index, descriptor in
                if descriptor.startsNewGroup, index > 0 {
                    groupSeparator
                }
                InspectorTabButton(
                    title: descriptor.title,
                    isActive: descriptor.isActive,
                    action: descriptor.action
                )
            }

            if plan.hasOverflow {
                overflowMenu
            }
        }
        .padding(.leading, InspectorTabStripLayout.leadingStripPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overflowMenuLabel(_ descriptor: InspectorTabDescriptor) -> some View {
        HStack {
            if descriptor.isActive {
                Image(systemName: "checkmark")
            }
            Text(descriptor.title)
        }
    }

    private static func measuredWidth(
        title: String,
        fontSize: CGFloat,
        startsNewGroup: Bool
    )
        -> CGFloat
    {
        // Measure at bold weight (the active-tab weight) so a tab never overflows after selection.
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth)
            + InspectorTabStripLayout.horizontalTabPadding
            + (startsNewGroup ? InspectorTabStripLayout.groupSeparatorWidth : 0)
    }

    private func layoutItems() -> [InspectorTabLayoutItem] {
        tabs.map { descriptor in
            InspectorTabLayoutItem(
                id: descriptor.id,
                width: Self.measuredWidth(
                    title: descriptor.title,
                    fontSize: metrics.controlFontSize,
                    startsNewGroup: descriptor.startsNewGroup
                )
            )
        }
    }
}
