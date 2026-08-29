import SwiftUI

// Renders the search filter bar interface for toolbar controls and filtering.

// MARK: - SearchFilterBar

/// Single-field search bar with a field selector (URL, host, path, method) and enable/disable toggle.
struct SearchFilterBar: View {
    // MARK: Internal

    @Binding var searchText: String
    @Binding var filterField: FilterField
    @Binding var isEnabled: Bool

    let isAdvancedFilterVisible: Bool
    let advancedFilterCount: Int
    let onAddFilter: () -> Void
    let onToggleAdvancedFilters: () -> Void
    var isEmbeddedInControlShelf = false

    var body: some View {
        // Widest tier first; `ViewThatFits` keeps the first that fits. The search field carries a
        // useful minimum width so it stays the flexible dominant area and never collapses; when the
        // wide row no longer fits, the compact fallback narrows the picker and drops the visible
        // `Add Filter` title while keeping every control and its order intact.
        ViewThatFits(in: .horizontal) {
            filterRow(pickerWidth: 130, showsAddFilterTitle: true)
            filterRow(pickerWidth: 100, showsAddFilterTitle: false)
        }
        .padding(.horizontal, 8)
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
        .onReceive(NotificationCenter.default.publisher(for: .focusMainSearchField)) { _ in
            isEnabled = true
            isSearchFocused = true
        }
    }

    // MARK: Private

    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var metrics

    private func filterRow(pickerWidth: CGFloat, showsAddFilterTitle: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .tint(.green)

            Picker("", selection: $filterField) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: pickerWidth)

            TextField(String(localized: "Search...", bundle: RockxyLocalization.bundle), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(metrics.swiftUIFont())
                .focused($isSearchFocused)
                .frame(minWidth: 220, maxWidth: .infinity)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Clear search", bundle: RockxyLocalization.bundle))
            }

            Divider()
                .frame(height: 18)

            Button(action: onAddFilter) {
                if showsAddFilterTitle {
                    Label(String(localized: "Add Filter", bundle: RockxyLocalization.bundle), systemImage: "plus")
                } else {
                    Image(systemName: "plus")
                }
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .help(String(localized: "Add a compound filter rule", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Filter", bundle: RockxyLocalization.bundle))

            Button(action: onToggleAdvancedFilters) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    if advancedFilterCount > 0 {
                        Text("\(advancedFilterCount)")
                            .monospacedDigit()
                    }
                    Image(systemName: isAdvancedFilterVisible ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .help(isAdvancedFilterVisible
                ? String(localized: "Hide compound filters", bundle: RockxyLocalization.bundle)
                : String(localized: "Show compound filters", bundle: RockxyLocalization.bundle))
        }
    }
}
