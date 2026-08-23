import SwiftUI

/// Reusable tab button for the inspector tab bars. Renders as a plain text button
/// with bold/regular weight to indicate active state, styled via `Theme.Inspector`.
struct InspectorTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: metrics.controlFontSize, weight: isActive ? .bold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .frame(minHeight: max(18, metrics.inspectorTabHeight - 4))
                .rockxyChipStyle(isActive: isActive, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .frame(minHeight: metrics.inspectorTabHeight)
        .onHover { isHovered = $0 }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var isHovered = false
}
