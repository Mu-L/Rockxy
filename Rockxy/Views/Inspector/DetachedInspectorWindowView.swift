import SwiftUI

// Standalone Inspector window that mirrors the main horizontal request/response
// inspector for one pinned transaction.

// MARK: - DetachedInspectorWindowView

/// Detached Inspector window. Adopts the latest requested selection on appear and
/// whenever the handoff store re-targets it, then renders the URL bar plus the same
/// side-by-side request/response inspector as the main window. The selection is held
/// as a strong `@State` reference so main-window selection changes or live-buffer
/// eviction never blank this window; it keeps live-updating its pinned transaction.
struct DetachedInspectorWindowView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let selection {
                InspectorURLBar(
                    transaction: selection.transaction,
                    highlightContext: selection.highlightContext
                )
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: selection.transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: selection.highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    ResponseInspectorView(
                        transaction: selection.transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: selection.highlightContext,
                        onOpenToolWindow: { id in openWindow(id: id) }
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                InspectorEmptyStateView(
                    requestSelectionDescription: String(localized: "Select a request to inspect")
                )
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onAppear {
            adoptLatestSelection()
        }
        .onChange(of: DetachedInspectorStore.shared.version) {
            adoptLatestSelection()
        }
        .onDisappear {
            guard let selection else {
                return
            }
            DetachedInspectorStore.shared.dismiss(selectionID: selection.id)
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    @State private var selection: DetachedInspectorSelection?

    private func adoptLatestSelection() {
        guard let requested = DetachedInspectorStore.shared.requestedSelection else {
            return
        }
        selection = requested
    }
}
