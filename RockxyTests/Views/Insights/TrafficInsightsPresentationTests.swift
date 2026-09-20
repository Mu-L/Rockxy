import Foundation
@testable import Rockxy
import Testing

// Source-contract tests for the Traffic Insights presentation: Liquid Glass roles, opaque
// content surfaces, and the drill-down wiring that keeps the report tied to the request list.

// MARK: - TrafficInsightsPresentationTests

struct TrafficInsightsPresentationTests {
    // MARK: Internal

    @Test("The report header is the only custom glass layer; cards stay opaque content")
    func headerIsFunctionalGlassAndCardsStayOpaque() throws {
        let report = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsReportView.swift")
        let components = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsComponents.swift")

        #expect(report.contains(".rockxyFunctionalBar()"))
        #expect(report.contains(".safeAreaBar(edge: .top, spacing: 0)"))
        #expect(report.contains(".scrollEdgeEffectStyle(.soft, for: .vertical)"))
        #expect(report.contains("private var legacyReportLayout: some View"))
        #expect(report.components(separatedBy: ".rockxyFunctionalBar()").count == 2)
        #expect(!report.contains("GroupBox"))

        // Cards are reading surfaces: opaque system color, never a glass or material background.
        #expect(components.contains(".fill(Theme.Insights.cardBackground)"))
        #expect(!components.contains("rockxyGlassEffect("))
        #expect(!components.contains(".regularMaterial"))
    }

    @Test("Floating controls use the shared glass button policy and the callout is a glass surface")
    func floatingControlsUseSharedGlassPolicy() throws {
        let report = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsReportView.swift")
        let lists = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsListViews.swift")
        let chart = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsTimelineChart.swift")

        #expect(report.components(separatedBy: ".rockxyGlassButtonStyle()").count >= 3)
        #expect(lists.contains(".rockxyGlassButtonStyle()"))
        #expect(chart.contains(".rockxyGlassEffect(in: RoundedRectangle(cornerRadius: 8, style: .continuous))"))
        #expect(!chart.contains(".fill(.regularMaterial)"))
    }

    @Test("Every breakdown row routes through the shared drill-down and the timeline reveals bins")
    func drillDownsAreWired() throws {
        let report = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsReportView.swift")
        let chart = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsTimelineChart.swift")
        let donut = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsProtocolChart.swift")

        #expect(report.components(separatedBy: "onToggle: { viewModel.toggleDrillDown($0) }").count == 5)
        #expect(report.contains("onSelectBin: { viewModel.reveal($0) }"))
        #expect(report.contains("note: { statusCodeNote(for: $0) }"))
        #expect(chart.contains(".chartXSelection(value: $selectedDate)"))
        #expect(chart.contains("onSelectBin?(selectedBin)"))
        #expect(donut.contains("let target = share.key.drillDown"))
        #expect(donut.contains(".chartAngleSelection(value: $selectedAngle)"))
    }

    @Test("Copy stays terse: no explanatory subtitles under cards and findings are single lines")
    func copyStaysTerse() throws {
        let report = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsReportView.swift")
        let lists = try readProjectFile("Rockxy/Views/Insights/TrafficInsightsListViews.swift")

        #expect(!report.contains("nothing leaves this Mac"))
        #expect(!report.contains("Deterministic observations"))
        #expect(!report.contains("Updated \\("))
        #expect(lists.contains(".help(finding.detail)"))
        #expect(lists.contains("Text(finding.title)"))
        #expect(!lists.contains("Text(finding.detail)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
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
