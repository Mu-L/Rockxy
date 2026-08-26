import AppKit
import SwiftUI

// Renders the protocol filter bar interface for toolbar controls and filtering.

// MARK: - ProtocolFilterBar

/// Dense, native filtering surface for narrowing traffic. An adaptive single line shows the most
/// useful `FilterPillButton`s directly — `All`, transport, the AI / Web3 / content lenses, and the
/// common status ranges — with a native `ellipsis.circle` overflow menu holding the rest, grouped
/// under Transport / Protocol / Content / Status. `ViewThatFits` picks the widest deterministic
/// tier that fits, so the row never scrolls or clips and visible pills never reorder on selection.
/// Traffic-type and status filters combine with AND across groups; selections within a group
/// combine with OR (see `MainContentCoordinator+Filtering`).
struct ProtocolFilterBar: View {
    // MARK: Internal

    @Binding var activeFilters: Set<ProtocolFilter>

    var isEmbeddedInControlShelf = false

    var body: some View {
        // Widest tier first; `ViewThatFits` keeps the first that fits. Tier 5 (`.all` + overflow +
        // icon Clear All) is the always-fitting fallback. Kept in sync with `inlinePillTiers`.
        ViewThatFits(in: .horizontal) {
            tierRow(0)
            tierRow(1)
            tierRow(2)
            tierRow(3)
            tierRow(4)
            tierRow(5)
        }
        .padding(.horizontal, Theme.Layout.contentPadding)
        .padding(.vertical, max(4, (metrics.fontSize - 10) / 3))
        .background {
            if !isEmbeddedInControlShelf {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay(alignment: .bottom) {
            if !isEmbeddedInControlShelf {
                Divider()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ToolbarCustomizationWindowReader(reference: customizationWindowReference)
                .frame(width: 0, height: 0)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var customizationWindowReference = ToolbarCustomizationWindowReference()

    private var hasActiveFilters: Bool {
        !activeFilters.isEmpty
    }

    private var anyStatusBinding: Binding<Bool> {
        Binding(
            get: { ProtocolFilterSelection.activeStatusFilters(in: activeFilters).isEmpty },
            set: { _ in activeFilters = ProtocolFilterSelection.clearingStatusFilters(in: activeFilters) }
        )
    }

    private func tierRow(_ tier: Int) -> some View {
        let visible = ProtocolFilterSelection.inlinePills(forTier: tier)
        let isNarrowest = tier == ProtocolFilterSelection.inlinePillTiers.count - 1
        return HStack(spacing: Theme.Layout.controlSpacing) {
            pillRow(visible: visible)
            overflowMenu(visiblePills: visible)
            Spacer(minLength: 0)
            if hasActiveFilters {
                clearAllButton(iconOnly: isNarrowest)
            }
        }
    }

    private func pillRow(visible: [ProtocolFilter]) -> some View {
        let typePills = visible.filter { !$0.isStatusFilter }
        let statusPills = visible.filter(\.isStatusFilter)
        return HStack(spacing: Theme.Layout.controlSpacing) {
            ForEach(typePills, id: \.self) { pill(for: $0) }
            if !statusPills.isEmpty {
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
                ForEach(statusPills, id: \.self) { pill(for: $0) }
            }
        }
    }

    private func pill(for filter: ProtocolFilter) -> some View {
        FilterPillButton(
            title: filter.displayName,
            isActive: ProtocolFilterSelection.isSelected(filter, in: activeFilters),
            action: { activeFilters = ProtocolFilterSelection.toggling(filter, in: activeFilters) }
        )
    }

    private func overflowMenu(visiblePills: [ProtocolFilter]) -> some View {
        let hasHidden = ProtocolFilterSelection.hasHiddenActiveFilter(
            activeFilters: activeFilters,
            visiblePills: visiblePills
        )
        return Menu {
            overflowSection(String(localized: "Transport"), ProtocolFilterSelection.transportFilters, visiblePills)
            overflowSection(String(localized: "Protocol"), ProtocolFilterSelection.protocolFilters, visiblePills)
            overflowSection(String(localized: "Content"), ProtocolFilterSelection.contentTypeFilters, visiblePills)
            overflowStatusSection(visiblePills)
            Divider()
            Button(String(localized: "Customize Toolbar…")) {
                NativeWorkspaceToolbar.presentCustomizationPalette(
                    preferredWindow: customizationWindowReference.window
                )
            }
        } label: {
            Image(systemName: hasHidden ? "ellipsis.circle.fill" : "ellipsis.circle")
                .font(.system(size: metrics.secondaryFontSize))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(hasHidden ? Color.accentColor : Color.secondary)
        .help(String(localized: "More filters"))
        .accessibilityLabel(String(localized: "More filters"))
        .accessibilityValue(
            hasHidden
                ? String(localized: "Hidden filters active")
                : String(localized: "No hidden filters active")
        )
    }

    @ViewBuilder
    private func overflowSection(
        _ title: String,
        _ group: [ProtocolFilter],
        _ visiblePills: [ProtocolFilter]
    )
        -> some View
    {
        let hidden = ProtocolFilterSelection.overflowFilters(in: group, visiblePills: visiblePills)
        if !hidden.isEmpty {
            Section(title) {
                ForEach(hidden, id: \.self) { filter in
                    Toggle(ProtocolFilterSelection.menuLabel(for: filter), isOn: binding(for: filter))
                }
            }
        }
    }

    @ViewBuilder
    private func overflowStatusSection(_ visiblePills: [ProtocolFilter]) -> some View {
        let hidden = ProtocolFilterSelection.overflowFilters(
            in: ProtocolFilterSelection.statusFilters,
            visiblePills: visiblePills
        )
        if !hidden.isEmpty {
            Section(String(localized: "Status")) {
                Toggle(String(localized: "Any Status"), isOn: anyStatusBinding)
                Divider()
                ForEach(hidden, id: \.self) { filter in
                    Toggle(ProtocolFilterSelection.menuLabel(for: filter), isOn: binding(for: filter))
                }
            }
        }
    }

    private func clearAllButton(iconOnly: Bool) -> some View {
        Button {
            activeFilters = ProtocolFilterSelection.clearingAllFilters(in: activeFilters)
        } label: {
            if iconOnly {
                Image(systemName: "xmark.circle")
            } else {
                Text(String(localized: "Clear All"))
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: metrics.secondaryFontSize, weight: .medium))
        .foregroundStyle(Color.accentColor)
        .help(String(localized: "Clear all traffic-type and status filters"))
        .accessibilityLabel(String(localized: "Clear all protocol filters"))
    }

    private func binding(for filter: ProtocolFilter) -> Binding<Bool> {
        Binding(
            get: { ProtocolFilterSelection.isSelected(filter, in: activeFilters) },
            set: { _ in activeFilters = ProtocolFilterSelection.toggling(filter, in: activeFilters) }
        )
    }
}

// MARK: - ToolbarCustomizationWindowReader

@MainActor
private final class ToolbarCustomizationWindowReference {
    weak var window: NSWindow?
}

private struct ToolbarCustomizationWindowReader: NSViewRepresentable {
    let reference: ToolbarCustomizationWindowReference

    func makeNSView(context: Context) -> ToolbarCustomizationWindowAnchor {
        let view = ToolbarCustomizationWindowAnchor()
        view.reference = reference
        return view
    }

    func updateNSView(_ nsView: ToolbarCustomizationWindowAnchor, context: Context) {
        nsView.reference = reference
        nsView.captureWindow()
    }
}

@MainActor
private final class ToolbarCustomizationWindowAnchor: NSView {
    weak var reference: ToolbarCustomizationWindowReference?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        captureWindow()
    }

    func captureWindow() {
        reference?.window = window
    }
}
