import SwiftUI

// Renders the filter pill button interface for toolbar controls and filtering.

// MARK: - FilterPillButton

/// Compact toggle-style pill button used in the protocol filter bar. Renders with themed
/// active/inactive colors from `Theme.FilterPill`.
struct FilterPillButton: View {
    // MARK: Internal

    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            pillLabel
        }
        .buttonStyle(.borderless)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var pillLabel: some View {
        Text(title)
            .font(.system(size: metrics.secondaryFontSize, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Theme.FilterPill.activeForeground : Theme.FilterPill.inactiveForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, max(3, (metrics.fontSize - 10) / 3))
            .rockxyChipStyle(isActive: isActive)
    }
}
