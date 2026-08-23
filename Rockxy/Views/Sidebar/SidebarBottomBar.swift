import AppKit
import SwiftUI

// Bottom toolbar for the sidebar, providing a native filter field and an add-favorite button.
// Mirrors Xcode's navigator control bar: the add action stands apart from the expanding search field.

// MARK: - SidebarBottomBar

struct SidebarBottomBar: View {
    // MARK: Internal

    @Binding var filterText: String
    @Binding var isAddFavoritePresented: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isAddFavoritePresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: metrics.sidebarIconFontSize))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Add favorite app or domain"))
            .help(String(localized: "Add favorite app or domain"))

            NativeSidebarSearchField(
                text: $filterText,
                fontSize: metrics.sidebarNavigationFontSize
            )
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - NativeSidebarSearchField

private struct NativeSidebarSearchField: NSViewRepresentable {
    // MARK: Internal

    @Binding var text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = String(localized: "Filter")
        searchField.toolTip = String(localized: "Filter sidebar items")
        searchField.controlSize = .regular
        searchField.focusRingType = .exterior
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = context.coordinator
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.setAccessibilityLabel(String(localized: "Filter sidebar"))
        configure(searchField)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        configure(searchField)
    }

    // MARK: Private

    private func configure(_ searchField: NSSearchField) {
        searchField.font = .systemFont(ofSize: fontSize)
        guard let searchCell = searchField.cell as? NSSearchFieldCell else { return }
        searchCell.searchButtonCell?.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease.circle",
            accessibilityDescription: String(localized: "Filter")
        )
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }
    }
}
