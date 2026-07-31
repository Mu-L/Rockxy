import Foundation
@testable import Rockxy
import Testing

/// Unified-search coverage for the Breakpoint Rules window.
@MainActor
struct BreakpointSearchDimensionTests {
    // MARK: Internal

    @Test("Each searchable dimension independently surfaces exactly its rule")
    func eachDimensionIsIndependentlyReachable() {
        let vm = makeViewModel()
        // Found only by name.
        vm.addBreakpointRule(
            ruleName: "FindByName",
            urlPattern: "https://n.host/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        // Found only by display pattern.
        vm.addBreakpointRule(
            ruleName: "Zeta",
            urlPattern: "https://payments.uniquepattern.io/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        // Found only by method.
        vm.addBreakpointRule(
            ruleName: "Zeta2",
            urlPattern: "https://m.host/*",
            httpMethod: .delete,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        // Found only by pause phase.
        vm.addBreakpointRule(
            ruleName: "Zeta3",
            urlPattern: "https://h.host/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.searchText = "findbyname"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["FindByName"])

        vm.searchText = "uniquepattern"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Zeta"])

        vm.searchText = "delete"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Zeta2"])

        vm.searchText = "response"
        #expect(vm.filteredBreakpointRules.map(\.name) == ["Zeta3"])
    }

    @Test("Label helpers emit the exact tokens the unified search relies on")
    func labelHelpersEmitSearchableTokens() throws {
        let vm = makeViewModel()
        vm.addBreakpointRule(
            ruleName: "Labelled",
            urlPattern: "https://api.example.com/orders",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )
        let rule = try #require(vm.breakpointRules.first)

        #expect(vm.methodLabel(for: rule) == "POST")
        #expect(vm.matchTypeLabel(for: rule) == "Wildcard")
        #expect(vm.matchingRuleLabel(for: rule) == "https://api.example.com/orders")
        #expect(vm.phaseLabel(for: rule) == "Request")
    }

    // MARK: Private

    private func makeViewModel() -> BreakpointRulesViewModel {
        BreakpointRulesViewModel(syncsChanges: false)
    }
}
