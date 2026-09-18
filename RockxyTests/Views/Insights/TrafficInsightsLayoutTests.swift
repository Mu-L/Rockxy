import Foundation
@testable import Rockxy
import Testing

// Column math for the Traffic Insights report rows: every row fills the workspace width and
// cards wrap into balanced rows instead of leaving a trailing gap.

// MARK: - TrafficInsightsLayoutTests

struct TrafficInsightsLayoutTests {
    // MARK: Internal

    @Test("Breakdown cards take four columns whenever four fit, at any wider width")
    func breakdownCardsFillWideRows() {
        for width in stride(from: 900.0, through: 2_600.0, by: 100.0) {
            #expect(columns(items: 4, width: width, minimum: 210) == 4, "width \(width)")
        }
    }

    @Test("Four cards in a three-column space wrap 2 + 2, not 3 + 1")
    func fourCardsAvoidOrphanRow() {
        // 3 × 210 + 2 × 12 = 654 fits three columns; four need 876.
        #expect(columns(items: 4, width: 700, minimum: 210) == 2)
        #expect(columns(items: 4, width: 875, minimum: 210) == 2)
        #expect(columns(items: 4, width: 876, minimum: 210) == 4)
    }

    @Test("Narrow rows fall back to one or two columns and never below one")
    func narrowRows() {
        #expect(columns(items: 4, width: 431, minimum: 210) == 1)
        #expect(columns(items: 4, width: 432, minimum: 210) == 2)
        #expect(columns(items: 4, width: 0, minimum: 210) == 1)
        #expect(columns(items: 1, width: 5_000, minimum: 210) == 1)
    }

    @Test("Five headline tiles prefer 3 + 2 over 4 + 1 and 5 across when they fit")
    func headlineTilesBalance() {
        // Four fit: 4 × 168 + 3 × 12 = 708; five need 888.
        #expect(columns(items: 5, width: 800, minimum: 168) == 3)
        #expect(columns(items: 5, width: 887, minimum: 168) == 3)
        #expect(columns(items: 5, width: 888, minimum: 168) == 5)
        // Three fit but a 3 + 2 split keeps two rows, so three columns stay.
        #expect(columns(items: 5, width: 600, minimum: 168) == 3)
        // Two fit: reducing to one column would add rows, so two columns stay.
        #expect(columns(items: 5, width: 400, minimum: 168) == 2)
    }

    @Test("The four list cards sit side by side only when a full row of four fits")
    func listCardsUseFourOrTwoColumns() {
        // 4 × 400 + 3 × 12 = 1_636.
        #expect(columns(items: 4, width: 1_635, minimum: 400) == 2)
        #expect(columns(items: 4, width: 1_636, minimum: 400) == 4)
        #expect(columns(items: 4, width: 1_290, minimum: 400) == 2)
        #expect(columns(items: 4, width: 811, minimum: 400) == 1)
    }

    @Test("Timeline and protocols share a row only when the timeline keeps its minimum width")
    func splitRowThreshold() {
        let threshold = Theme.Insights.timelineMinimumWidth + Theme.Insights.protocolsCardWidth
            + Theme.Insights.cardSpacing
        #expect(fitsSideBySide(width: threshold))
        #expect(!fitsSideBySide(width: threshold - 1))
        #expect(fitsSideBySide(width: 1_290))
        #expect(!fitsSideBySide(width: 800))
    }

    @Test("Report rows are built from the width-filling layouts, not a lazy grid")
    func reportUsesFillingLayouts() throws {
        let report = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsReportView.swift")

        #expect(!report.contains("LazyVGrid"))
        #expect(!report.contains("GridItem(.adaptive"))
        #expect(report.components(separatedBy: "TrafficInsightsCardGrid(").count == 4)
        #expect(report.contains("TrafficInsightsSplitRow("))
        #expect(report.contains("fillsLastRow: true"))
        #expect(report.contains("TrafficInsightsSourceMonitor(coordinator: coordinator, viewModel: viewModel)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    private func columns(items: Int, width: Double, minimum: Double) -> Int {
        TrafficInsightsCardGrid.columnCount(
            itemCount: items,
            availableWidth: width,
            minimumColumnWidth: minimum,
            spacing: Theme.Insights.cardSpacing
        )
    }

    private func fitsSideBySide(width: Double) -> Bool {
        TrafficInsightsSplitRow.fitsSideBySide(
            availableWidth: width,
            secondaryWidth: Theme.Insights.protocolsCardWidth,
            minimumPrimaryWidth: Theme.Insights.timelineMinimumWidth,
            spacing: Theme.Insights.cardSpacing
        )
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
