import SwiftUI

// MARK: - InspectorPanelView

/// Top-level payload inspector that hosts the URL bar and side-by-side request/response panes.
/// Shown below the request list when a transaction is selected.
struct InspectorPanelView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    var onOpenToolWindow: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.selectedTransactionIDs.count > 1 {
                InspectorSelectionSummaryView(coordinator: coordinator)
            } else if let transaction = coordinator.selectedTransaction {
                let highlightContext = coordinator.activeInspectorHighlightContext()
                InspectorURLBar(
                    transaction: transaction,
                    highlightContext: highlightContext,
                    onOpenDetachedInspector: {
                        DetachedInspectorStore.shared.present(
                            transaction: transaction,
                            highlightContext: highlightContext
                        )
                        openWindow(id: "detachedInspector")
                    }
                )
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    ResponseInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext,
                        onOpenToolWindow: onOpenToolWindow
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                InspectorEmptyStateView(
                    requestSelectionDescription: String(localized: "Select a request to inspect")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}

// MARK: - InspectorSelectionSummaryView

private struct InspectorSelectionSummaryView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Selection Summary"), systemImage: "square.stack.3d.up")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                summaryRow(String(localized: "Selected"), "\(transactions.count)")
                summaryRow(String(localized: "Hosts"), "\(Set(transactions.map { $0.request.host }).count)")
                summaryRow(String(localized: "Errors"), "\(transactions.count { ($0.response?.statusCode ?? 0) >= 400 })")
                summaryRow(
                    String(localized: "Transferred"),
                    ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
                )
            }
            Text(String(localized: "Select one request to inspect raw payload, or exactly two requests to compare."))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private

    private var transactions: [HTTPTransaction] {
        coordinator.selectedTransactionIDs.compactMap(coordinator.transaction(for:))
    }

    private var transferredBytes: Int64 {
        transactions.reduce(0) { total, transaction in
            total + Int64(transaction.request.body?.count ?? 0) + Int64(transaction.response?.body?.count ?? 0)
        }
    }

    @ViewBuilder
    private func summaryRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
