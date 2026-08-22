import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct TrafficBoundaryNavigationTests {
    // MARK: Internal

    @Test("Boundary shortcuts belong only to the focused request table")
    func boundaryShortcutsRequireCommandArrowWithoutCompetingModifiers() {
        #expect(RequestTableBoundaryNavigation.resolve(
            keyCode: 126,
            modifierFlags: [.command, .numericPad]
        ) == .first)
        #expect(RequestTableBoundaryNavigation.resolve(
            keyCode: 125,
            modifierFlags: [.command, .function]
        ) == .last)
        #expect(RequestTableBoundaryNavigation.resolve(
            keyCode: 126,
            modifierFlags: [.command, .option]
        ) == nil)
        #expect(RequestTableBoundaryNavigation.resolve(
            keyCode: 125,
            modifierFlags: []
        ) == nil)
    }

    @Test("Jump reveal is one-shot and a new generation can reveal the same endpoint again")
    func jumpRevealUsesWorkspaceGeneration() {
        let workspaceID = UUID()
        let transactions = TestFixtures.makeBulkTransactions(count: 100)
        let rows = transactions.map { RequestListRow(from: $0, sslState: .insecure) }
        let selectionIndex = Dictionary(
            uniqueKeysWithValues: transactions.enumerated().map { index, transaction in
                (
                    transaction.id,
                    TrafficSelectionIndexEntry(transaction: transaction, rowIndex: index)
                )
            }
        )
        var selectedIDs: Set<UUID> = [transactions[99].id]
        let parent = RequestTableView(
            workspaceID: workspaceID,
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            selectionIndex: selectionIndex,
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator)
        let scrollView = makeScrollView(documentView: tableView)
        let firstRequest = TrafficRevealRequest(transactionID: transactions[99].id, generation: 1)

        coordinator.syncRevealRequest(firstRequest, workspaceID: workspaceID, in: tableView)
        #expect(scrollView.contentView.bounds.origin.y > 0)

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        coordinator.syncRevealRequest(firstRequest, workspaceID: workspaceID, in: tableView)
        #expect(scrollView.contentView.bounds.origin.y == 0)

        coordinator.syncRevealRequest(
            TrafficRevealRequest(transactionID: transactions[99].id, generation: 2),
            workspaceID: workspaceID,
            in: tableView
        )
        #expect(scrollView.contentView.bounds.origin.y > 0)
    }

    @Test("Jump reveal remains consumed after switching away from and back to a workspace")
    func jumpRevealConsumptionPersistsAcrossWorkspaceSwitches() {
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()
        let transactions = TestFixtures.makeBulkTransactions(count: 100)
        let rows = transactions.map { RequestListRow(from: $0, sslState: .insecure) }
        let target = transactions[99]
        let selectionIndex = [
            target.id: TrafficSelectionIndexEntry(transaction: target, rowIndex: 99)
        ]
        var selectedIDs: Set<UUID> = [target.id]
        let parent = RequestTableView(
            workspaceID: firstWorkspaceID,
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            selectionIndex: selectionIndex,
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator)
        let scrollView = makeScrollView(documentView: tableView)
        let request = TrafficRevealRequest(transactionID: target.id, generation: 1)

        coordinator.syncRevealRequest(request, workspaceID: firstWorkspaceID, in: tableView)
        #expect(scrollView.contentView.bounds.origin.y > 0)

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        coordinator.syncRevealRequest(request, workspaceID: secondWorkspaceID, in: tableView)
        #expect(scrollView.contentView.bounds.origin.y > 0)

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        coordinator.syncRevealRequest(request, workspaceID: firstWorkspaceID, in: tableView)
        #expect(scrollView.contentView.bounds.origin.y == 0)
    }

    // MARK: Private

    private func makeScrollView(documentView: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        return scrollView
    }

    private func makeTableView(
        rowCount: Int,
        coordinator: RequestTableView.Coordinator
    )
        -> NSTableView
    {
        let tableView = NSTableView(
            frame: NSRect(x: 0, y: 0, width: 480, height: CGFloat(rowCount) * 28)
        )
        tableView.rowHeight = 28
        tableView.intercellSpacing = .zero
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        coordinator.tableView = tableView
        tableView.reloadData()
        return tableView
    }
}
