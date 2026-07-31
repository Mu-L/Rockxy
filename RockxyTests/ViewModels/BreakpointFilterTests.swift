import Foundation
@testable import Rockxy
import Testing

/// Unified always-visible search over `BreakpointRulesViewModel.searchText`.
/// The redesigned window replaced the per-column filter bar with a single query
/// that matches name, method, display pattern, and pause phase.
@MainActor
struct BreakpointFilterTests {
    // MARK: Internal

    // MARK: - Cross-field matching

    @Test("Search matches the rule name case-insensitively")
    func searchMatchesNameCaseInsensitively() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Alpha Checkout",
            urlPattern: "https://payments.stripe.test/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.searchText = "alpha"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Alpha Checkout"])
    }

    @Test("Search matches the display pattern even when the name does not")
    func searchMatchesDisplayPattern() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Alpha",
            urlPattern: "https://payments.stripe.test/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Beta",
            urlPattern: "https://cdn.other.test/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.searchText = "stripe"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Alpha"])
    }

    @Test("Search matches the method label case-insensitively")
    func searchMatchesMethodLabel() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Submit",
            urlPattern: "https://api.test/submit",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )
        vm.addBreakpointRule(
            ruleName: "Fetch",
            urlPattern: "https://api.test/fetch",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )

        vm.searchText = "post"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Submit"])
    }

    @Test("Search matches ANY for rules with no specific method")
    func searchMatchesAnyMethod() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Wildcard method",
            urlPattern: "https://api.test/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.searchText = "any"
        #expect(vm.filteredBreakpointRules.count == 1)
    }

    @Test("Search matches the pause-phase label")
    func searchMatchesPhaseLabel() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Only on the way out",
            urlPattern: "https://api.test/req",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Only on the way back",
            urlPattern: "https://api.test/res",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.searchText = "response"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Only on the way back"])
    }

    // MARK: - Whitespace, empties, no-results

    @Test("Search trims surrounding whitespace before matching")
    func searchTrimsWhitespace() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "api.example.com",
            urlPattern: "https://api.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.searchText = "   api   "
        #expect(vm.filteredBreakpointRules.count == 1)
    }

    @Test("Whitespace-only search returns all rules")
    func whitespaceOnlySearchReturnsAll() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Rule A",
            urlPattern: "https://a.com/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule B",
            urlPattern: "https://b.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.searchText = "   \n  "
        #expect(vm.filteredBreakpointRules.count == 2)
    }

    @Test("Empty search returns all rules")
    func emptySearchReturnsAll() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Rule A",
            urlPattern: "https://a.com/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule B",
            urlPattern: "https://b.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.searchText = ""
        #expect(vm.filteredBreakpointRules.count == 2)
    }

    @Test("Search with no match returns empty")
    func searchWithNoMatchReturnsEmpty() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Real Rule",
            urlPattern: "https://real.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.searchText = "nonexistent-zzz"
        #expect(vm.filteredBreakpointRules.isEmpty)
    }

    // MARK: - Ordering & reactivity

    @Test("Filtered results preserve insertion (runtime) order")
    func filteredResultsPreserveRuntimeOrder() {
        let vm = makeViewModel()
        let names = ["svc one", "svc two", "svc three", "svc four"]
        for name in names {
            vm.addBreakpointRule(
                ruleName: name,
                urlPattern: "https://svc.test/\(name)",
                httpMethod: .any,
                matchType: .wildcard,
                phaseRequest: true,
                phaseResponse: true,
                includeSubpaths: true
            )
        }

        vm.searchText = "svc"
        #expect(vm.filteredBreakpointRules.map(\.name) == names)
        #expect(vm.filteredBreakpointRules.map(\.id) == vm.breakpointRules.map(\.id))
    }

    @Test("Filter updates reactively as searchText changes")
    func filterUpdatesReactively() {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "alpha.example.com",
            urlPattern: "https://alpha.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "beta.other.com",
            urlPattern: "https://beta.other.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.searchText = "alpha"
        #expect(vm.filteredBreakpointRules.count == 1)

        vm.searchText = ""
        #expect(vm.filteredBreakpointRules.count == 2)
    }

    // MARK: - Selection reconciliation

    @Test("Selection is cleared when the selected rule is filtered out of view")
    func hiddenSelectionIsCleared() throws {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Keepme",
            urlPattern: "https://keep.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Dropme",
            urlPattern: "https://drop.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let dropID = try #require(vm.breakpointRules.first { $0.name == "Dropme" }?.id)
        vm.selectedRuleID = dropID

        vm.searchText = "keep"
        #expect(vm.selectedRuleID == nil)
    }

    @Test("Selection is preserved when the selected rule stays visible")
    func visibleSelectionIsPreserved() throws {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Keepme",
            urlPattern: "https://keep.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Dropme",
            urlPattern: "https://drop.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let keepID = try #require(vm.breakpointRules.first { $0.name == "Keepme" }?.id)
        vm.selectedRuleID = keepID

        vm.searchText = "keep"
        #expect(vm.selectedRuleID == keepID)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeViewModel() -> BreakpointRulesViewModel {
        BreakpointRulesViewModel(syncsChanges: false)
    }
}
