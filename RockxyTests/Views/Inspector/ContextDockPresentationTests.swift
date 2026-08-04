import Foundation
@testable import Rockxy
import Testing

// MARK: - MatchedRuleNavigationTargetTests

struct MatchedRuleNavigationTargetTests {
    @Test("Each windowed rule category routes to its existing tool window")
    func windowedCategoriesRouteToToolWindows() {
        let cases: [(RuleAction, String)] = [
            (.breakpoint(), "breakpointRules"),
            (.mapLocal(filePath: "/tmp/mock.json"), "mapLocal"),
            (.mapRemote(configuration: MapRemoteConfiguration()), "mapRemote"),
            (.block(statusCode: 403), "blockList"),
            (.modifyHeader(operations: []), "modifyHeaders"),
            (.networkCondition(preset: .wifi, delayMs: 0), "networkConditions"),
        ]

        for (action, expectedID) in cases {
            let target = MatchedRuleNavigationTarget(action: action)
            #expect(target.windowID == expectedID, "\(action.toolCategory) should open \(expectedID)")
            #expect(target.openHelp != nil)
        }
    }

    @Test("Throttle has no dedicated window and stays honestly unavailable")
    func throttleIsUnavailable() {
        let target = MatchedRuleNavigationTarget(action: .throttle(delayMs: 1_000))
        #expect(target == .unavailable)
        #expect(target.windowID == nil)
        #expect(target.openHelp == nil)
    }
}

// MARK: - InvestigationResultPresentationTests

struct InvestigationResultPresentationTests {
    // MARK: Internal

    @Test("Evidence groups keep observed → derived → inferred → unknown order and drop empties")
    func evidenceGroupsAreOrderedAndCompact() {
        let evidence = [
            makeEvidence(id: "a", kind: .inferred),
            makeEvidence(id: "b", kind: .observed),
            makeEvidence(id: "c", kind: .unknown),
            makeEvidence(id: "d", kind: .observed),
        ]

        let groups = InvestigationResultPresentation.evidenceGroups(for: evidence)
        #expect(groups.map(\.kind) == [.observed, .inferred, .unknown])
        #expect(groups.first?.evidence.map(\.id) == ["b", "d"])
    }

    @Test("Findings exclude unknowns and the unknowns section captures open questions")
    func findingsAndUnknownsSplitByKind() {
        let evidence = [
            makeEvidence(id: "obs", kind: .observed),
            makeEvidence(id: "der", kind: .derived),
            makeEvidence(id: "unk1", kind: .unknown),
            makeEvidence(id: "unk2", kind: .unknown),
        ]

        let findingGroups = InvestigationResultPresentation.findingGroups(for: evidence)
        #expect(findingGroups.allSatisfy { !$0.isUnknown })
        #expect(findingGroups.map(\.kind) == [.observed, .derived])
        #expect(InvestigationResultPresentation.findingCount(for: evidence) == 2)

        let unknowns = InvestigationResultPresentation.unknowns(for: evidence)
        #expect(unknowns.map(\.id) == ["unk1", "unk2"])
    }

    @Test("Empty evidence yields no groups, findings, or unknowns")
    func emptyEvidenceIsEmpty() {
        #expect(InvestigationResultPresentation.evidenceGroups(for: []).isEmpty)
        #expect(InvestigationResultPresentation.findingGroups(for: []).isEmpty)
        #expect(InvestigationResultPresentation.unknowns(for: []).isEmpty)
        #expect(InvestigationResultPresentation.findingCount(for: []) == 0)
    }

    // MARK: Private

    private func makeEvidence(id: String, kind: InvestigationEvidenceKind) -> InvestigationEvidence {
        InvestigationEvidence(
            id: id,
            kind: kind,
            title: "Finding \(id)",
            detail: "Detail \(id)",
            sourceTransactionID: nil
        )
    }
}

// MARK: - ContextDockInvestigationReportTests

/// Source contract for the recipe-first, evidence-grounded Investigate surface (GitHub #214/#217):
/// completed turns render as a labelled full-width investigation report, user prompts are compact
/// query rows, and the deprecated trailing chat bubble is gone.
struct ContextDockInvestigationReportTests {
    // MARK: Internal

    @Test("Investigate renders a native investigation report, not a chat transcript bubble")
    func investigateRendersLabeledReport() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")

        // User prompts are compact full-width query rows; the trailing chat bubble is removed.
        #expect(!dock.contains("AssistantUserMessageBubble"))
        #expect(dock.contains("AssistantQueryRow(text: message.text)"))

        // Completed investigation turns route through the full-width report surface.
        #expect(dock.contains("InvestigationReportView("))

        // Every contracted section is visibly labelled; Summary uses InvestigationResult.summary.
        #expect(report.contains("String(localized: \"Scope\")"))
        #expect(report.contains("String(localized: \"Summary\")"))
        #expect(report.contains("reportBody(result.summary)"))
        #expect(report.contains("String(localized: \"Findings\")"))
        #expect(report.contains("String(localized: \"Unknowns\")"))
        #expect(report.contains("String(localized: \"Next Step\")"))
        #expect(report.contains("String(localized: \"Proposed Actions\")"))

        // Findings stay grouped (observed/derived/inferred) behind a native disclosure.
        #expect(report.contains("DisclosureGroup"))
        #expect(report.contains("InvestigationFindingsDisclosure"))

        // Review Data / Continue With Model and the existing handoffs remain wired.
        #expect(report.contains("Continue With Model"))
        #expect(report.contains("onHandoff"))
        #expect(report.contains("onPrepareReplay"))
    }

    @Test("Unknowns section is always present with a truthful empty state")
    func unknownsHasTruthfulEmptyState() throws {
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")
        #expect(report.contains("struct InvestigationUnknownsView"))
        #expect(report.contains("if unknowns.isEmpty"))
        #expect(report.contains("No open questions"))
    }

    @Test("Evidence without a source request cannot pretend to navigate")
    func evidenceWithoutSourceIsNotRevealable() throws {
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")
        #expect(report.contains(".disabled(evidence.sourceTransactionID == nil)"))
    }

    @Test("Empty-state entry point uses compact horizontal suggestion cards in a two-column grid")
    func emptyStateUsesSuggestionGrid() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")
        // Suggestions are a compact two-column grid of bordered cards, not a single-column list.
        #expect(dock.contains("suggestionGrid"))
        #expect(dock.contains("LazyVGrid"))
        #expect(!dock.contains("recipeList"))
        // Exactly two flexible columns.
        #expect(dock.components(separatedBy: "GridItem(.flexible()").count - 1 == 2)
        // Compact bordered cards, small control size.
        #expect(dock.contains(".buttonStyle(.bordered)"))
        #expect(dock.contains(".controlSize(.small)"))
        // Titles stay recipe-driven, the full detail stays in help, and titles may wrap to 2 lines.
        #expect(dock.contains("DebugAssistantRecipe.allCases"))
        #expect(dock.contains(".help(recipe.detail)"))
        #expect(dock.contains(".lineLimit(2)"))
        #expect(dock.contains("Investigate captured traffic"))
        #expect(dock.contains("Start an investigation"))
        #expect(!dock.contains("What should I check?"))
        #expect(!dock.contains("Ask about captured traffic"))
    }

    @Test("Mode switcher shows Details / AI Assistant, not Context / Investigate")
    func modeSwitcherUsesRestoredLabels() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")
        #expect(dock.contains("Text(String(localized: \"Details\")).tag(ContextDockTab.details)"))
        #expect(dock.contains("Text(String(localized: \"AI Assistant\")).tag(ContextDockTab.aiAssistant)"))
        #expect(!dock.contains("Text(String(localized: \"Context\")).tag"))
        #expect(!dock.contains("Text(String(localized: \"Investigate\")).tag"))
        #expect(dock.contains("Picker(String(localized: \"Inspector\")"))
        #expect(dock.contains(".accessibilityLabel(String(localized: \"Inspector\"))"))
        // Stable internal enum cases are unchanged.
        #expect(dock.contains("ContextDockTab.details"))
        #expect(dock.contains("ContextDockTab.aiAssistant"))
    }

    @Test("Context Details renders every group as a native inspector table matching the horizontal inspector")
    func contextDetailsUsesInspectorTables() throws {
        let details = try readProjectFile("Rockxy/Views/Inspector/ContextDetailsView.swift")
        let table = try readProjectFile("Rockxy/Views/Inspector/ContextInspectorTable.swift")

        // Explicit Appearance-derived typography — no semantic font styles.
        #expect(details.contains("@Environment(\\.appUIDisplayMetrics)"))
        #expect(details.contains(".system(size: metrics."))
        #expect(!details.contains(".font(.headline"))
        #expect(!details.contains(".font(.subheadline"))
        #expect(!details.contains(".font(.caption"))
        #expect(!details.contains(".font(.callout"))

        // The reusable shell mirrors HeaderKeyValueTable's visual language.
        #expect(table.contains("struct ContextInspectorTable"))
        #expect(table.contains("VStack(spacing: 0)"))
        #expect(table.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(table.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(table.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(table.contains("lineWidth: 0.5"))
        #expect(table.contains(".clipShape(RoundedRectangle(cornerRadius: 6))"))
        // A vertical divider splits the field column from the value column.
        #expect(table.contains("struct ContextInspectorFieldRow"))
        #expect(table.contains("struct ContextInspectorInsightRow"))
        #expect(table.contains("struct ContextInspectorFullRow"))
        #expect(table.contains("struct ContextInspectorDisclosureTable"))

        // Flat ScrollView of stacked tables replaces List/Section, tinted rows, and loose dividers.
        #expect(details.contains("ScrollView {"))
        #expect(!details.contains("List {"))
        #expect(!details.contains("Section(String(localized:"))
        #expect(!details.contains(".listStyle"))
        #expect(!details.contains(".listRowBackground"))
        #expect(!details.contains("private func sectionHeader("))
        #expect(!details.contains("private func detailRow("))

        // Every named diagnostics group maps to a table.
        #expect(details.contains(#"ContextInspectorFieldTable("#))
        #expect(details.contains(#"title: String(localized: "Selection")"#))
        #expect(details.contains(#"title: String(localized: "Details")"#))
        #expect(details.contains(#"ContextInspectorTable(title: String(localized: "Rule Impact"))"#))
        #expect(details.contains(#"ContextInspectorTable(title: String(localized: "Payload"))"#))
        #expect(details.contains(#"ContextInspectorTable(title: String(localized: "Insights"))"#))
        #expect(details.contains(#"ContextInspectorTable(title: String(localized: "Notes"))"#))
        #expect(details.contains(#"title: String(localized: "Timing")"#))
        #expect(details.contains(#"title: String(localized: "Related Requests")"#))

        // Rule Impact keeps truthful rows plus an in-table Open Rule action row.
        #expect(details.contains(#"label: String(localized: "Rule")"#))
        #expect(details.contains(#"label: String(localized: "Action")"#))
        #expect(details.contains(#"label: String(localized: "Pattern")"#))
        #expect(details.contains("openRuleActionRow(windowID:"))

        // Timing and Related keep progressive disclosure via the table disclosure shell.
        #expect(details.contains("ContextInspectorDisclosureTable("))
        #expect(details.contains("isExpanded: $isTimingExpanded"))
        #expect(details.contains("isExpanded: $isRelatedExpanded"))

        // Technical data stays monospaced.
        #expect(details.contains("design: .monospaced"))

        // Behavior preserved: honest Open Rule routing, native Compare handoff, Notes identity.
        #expect(details.contains("matchedRuleNavigationTarget(transaction)"))
        #expect(details.contains("coordinator.compareTransactions(transactions[0], transactions[1])"))
        #expect(details.contains("ContextNotesEditor(coordinator: coordinator, transaction: transaction)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}
