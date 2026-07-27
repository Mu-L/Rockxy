import Foundation
@testable import Rockxy
import Testing

/// Decoder, builder, and round-trip contract for the Breakpoint rule form.
@MainActor
struct BreakpointRuleFormDecodeTests {
    @Test("Decode roundtrips a wildcard rule with subpaths back to user-friendly form")
    func decodeWildcardWithSubpaths() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Test",
            urlPattern: "*.example.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .wildcard)
        #expect(decoded.includeSubpaths == true)
        #expect(decoded.httpMethod == .post)
        #expect(decoded.breakpointRequest == true)
        #expect(decoded.breakpointResponse == true)
        #expect(decoded.displayPattern.contains("example.com"))
    }

    @Test("Decode roundtrips a wildcard rule without subpaths")
    func decodeWildcardWithoutSubpaths() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Exact",
            urlPattern: "example.com/path",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .wildcard)
        #expect(decoded.includeSubpaths == false)
    }

    @Test("Decode falls back to regex for rules that cannot be decoded as wildcard")
    func decodeRegexFallback() throws {
        let vm = BreakpointRulesViewModel()
        let rawRegex = "^https://api\\.example\\.com/v[0-9]+/users$"
        vm.addBreakpointRule(
            ruleName: "Regex Rule",
            urlPattern: rawRegex,
            httpMethod: .get,
            matchType: .regex,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .regex)
        #expect(decoded.displayPattern == rawRegex)
    }

    @Test("Decode recovers request-only phase from rule")
    func decodeRequestOnlyPhase() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "ReqOnly",
            urlPattern: "*.req.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.breakpointRequest == true)
        #expect(decoded.breakpointResponse == false)
    }

    @Test("Decode recovers response-only phase from rule")
    func decodeResponseOnlyPhase() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "ResOnly",
            urlPattern: "*.res.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.breakpointRequest == false)
        #expect(decoded.breakpointResponse == true)
    }

    @Test("Decode recovers both phases from rule")
    func decodeBothPhases() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Both",
            urlPattern: "*.both.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.breakpointRequest == true)
        #expect(decoded.breakpointResponse == true)
    }

    @Test("Decode recovers HTTP method from rule")
    func decodeHTTPMethod() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "MethodTest",
            urlPattern: "*.example.com/*",
            httpMethod: .delete,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.httpMethod == .delete)
    }

    @Test("Decode returns ANY method for rule with nil method")
    func decodeAnyMethod() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "AnyMethod",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.httpMethod == .any)
    }

    @Test("Decode preserves wildcard ? character round-trip")
    func decodeWildcardQuestionMarkRoundTrip() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Single char",
            urlPattern: "*.example.com/?page",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .wildcard)
        #expect(decoded.displayPattern == "*.example.com/?page")
    }

    @Test("Decode preserves multiple wildcard ? characters")
    func decodeMultipleQuestionMarks() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Multi",
            urlPattern: "api.?.example.com/v?/users",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .wildcard)
        #expect(decoded.displayPattern == "api.?.example.com/v?/users")
    }

    @Test("Decode preserves mixed * and ? wildcards in the same pattern")
    func decodeMixedStarAndQuestion() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Mixed",
            urlPattern: "*.api.?.example.com/?page",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .wildcard)
        #expect(decoded.displayPattern == "*.api.?.example.com/?page")
    }

    @Test("Wildcard ? is not confused with escaped literal dot")
    func decodeLiteralDotNotConfusedWithQuestionMark() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "DotOnly",
            urlPattern: "example.com/login",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let rule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: rule)

        // Literal dots must stay as `.`, not be resurrected as `?`
        #expect(decoded.displayPattern == "example.com/login")
    }

    @Test("Wildcard ? round-trip through add → edit → update preserves the rule")
    func questionMarkEditRoundTrip() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "RoundQ",
            urlPattern: "*.round.com/?page",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        let ruleID = try #require(vm.breakpointRules.first?.id)
        let originalPattern = vm.breakpointRules.first?.matchCondition.urlPattern
        let decoded = try BreakpointRuleForm.decode(rule: #require(vm.breakpointRules.first))

        // Save again with the decoded values — compiled pattern must be identical.
        vm.updateRule(
            id: ruleID,
            ruleName: "RoundQ",
            urlPattern: decoded.displayPattern,
            httpMethod: decoded.httpMethod,
            matchType: decoded.matchType,
            phaseRequest: decoded.breakpointRequest,
            phaseResponse: decoded.breakpointResponse,
            includeSubpaths: decoded.includeSubpaths
        )

        #expect(vm.breakpointRules.count == 1)
        #expect(vm.breakpointRules.first?.matchCondition.urlPattern == originalPattern)
    }

    @Test("Add-then-edit roundtrip produces equivalent rule state")
    func addThenEditRoundtrip() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Roundtrip",
            urlPattern: "*.round.com/*",
            httpMethod: .put,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        let ruleID = try #require(vm.breakpointRules.first?.id)
        let originalRule = try #require(vm.breakpointRules.first)
        let decoded = BreakpointRuleForm.decode(rule: originalRule)

        // Save again with the same decoded values — should not mutate meaningfully.
        vm.updateRule(
            id: ruleID,
            ruleName: originalRule.name,
            urlPattern: decoded.displayPattern,
            httpMethod: decoded.httpMethod,
            matchType: decoded.matchType,
            phaseRequest: decoded.breakpointRequest,
            phaseResponse: decoded.breakpointResponse,
            includeSubpaths: decoded.includeSubpaths
        )

        let updated = try #require(vm.breakpointRules.first)
        #expect(updated.id == ruleID)
        #expect(updated.matchCondition.urlPattern == originalRule.matchCondition.urlPattern)
        #expect(updated.matchCondition.method == originalRule.matchCondition.method)
        if case let .breakpoint(phase) = updated.action {
            #expect(phase == .request)
        } else {
            Issue.record("Expected breakpoint action")
        }
    }

    // MARK: - Authored wildcard metacharacters

    @Test("Authored wildcard metacharacters round-trip verbatim as the display pattern")
    func authoredWildcardMetacharactersRoundTrip() {
        let authoredPatterns = [
            "*.example.com/search+results",
            "*.example.com/path(group)",
            "*.example.com/items[0]",
        ]

        for authored in authoredPatterns {
            let rule = BreakpointRuleForm.makeRule(
                original: nil,
                ruleName: "Metachar",
                rawPattern: authored,
                httpMethod: .any,
                matchType: .wildcard,
                phaseRequest: true,
                phaseResponse: true,
                includeSubpaths: false
            )
            let decoded = BreakpointRuleForm.decode(rule: rule)

            #expect(decoded.matchType == .wildcard)
            #expect(decoded.displayPattern == authored, "Authored wildcard should survive decode verbatim")
            // Metacharacters must be escaped in the compiled runtime pattern.
            #expect(rule.matchCondition.sourceURLPattern == authored)
        }
    }

    @Test("Authored wildcard brackets compile as literals, not a regex character class")
    func authoredWildcardBracketsCompileAsLiterals() throws {
        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: "Bracket",
            rawPattern: "*.example.com/items[0]",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )

        let runtimePattern = try #require(rule.matchCondition.urlPattern)
        let regex = try NSRegularExpression(pattern: runtimePattern)

        #expect(regexMatches(regex, text: "https://api.example.com/items[0]"))
        #expect(!regexMatches(regex, text: "https://api.example.com/items0"))
    }

    // MARK: - Legacy condition preservation

    @Test("Legacy regex condition decodes to its raw pattern unchanged")
    func legacyRegexConditionDecodesUnchanged() {
        let rawRegex = #"^https://api\.example\.com/v1$"#
        let rule = ProxyRule(
            name: "Legacy Regex",
            matchCondition: RuleMatchCondition(urlPattern: rawRegex),
            action: .breakpoint(phase: .response)
        )

        let decoded = BreakpointRuleForm.decode(rule: rule)

        #expect(decoded.matchType == .regex)
        #expect(decoded.displayPattern == rawRegex)
        #expect(decoded.includeSubpaths == false)
    }

    @Test("makeRule preserves the legacy condition verbatim when scope is unchanged")
    func makeRulePreservesLegacyConditionWhenScopeUnchanged() {
        let fixedID = UUID()
        let originalCondition = RuleMatchCondition(
            urlPattern: RulePatternBuilder.regexSource(
                rawPattern: "*.example.com/api",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            sourceURLPattern: "*.example.com/api",
            method: "GET",
            headerName: "X-Env",
            headerValue: "staging",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let original = ProxyRule(
            id: fixedID,
            name: "Legacy",
            isEnabled: false,
            matchCondition: originalCondition,
            action: .breakpoint(phase: .request),
            priority: 7
        )

        let rebuilt = BreakpointRuleForm.makeRule(
            original: original,
            ruleName: "Legacy",
            rawPattern: "*.example.com/api",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )

        #expect(rebuilt.matchCondition == originalCondition)
        #expect(rebuilt.id == fixedID)
        #expect(rebuilt.isEnabled == false)
        #expect(rebuilt.priority == 7)
        #expect(rebuilt.matchCondition.headerName == "X-Env")
        #expect(rebuilt.matchCondition.headerValue == "staging")
    }

    @Test("makeRule rebuilds the condition on scope change but preserves rule metadata")
    func makeRuleRebuildsConditionOnScopeChangeKeepingMetadata() {
        let fixedID = UUID()
        let originalCondition = RuleMatchCondition(
            urlPattern: RulePatternBuilder.regexSource(
                rawPattern: "*.example.com/api",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            sourceURLPattern: "*.example.com/api",
            method: "GET",
            headerName: "X-Env",
            headerValue: "staging",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let original = ProxyRule(
            id: fixedID,
            name: "Legacy",
            isEnabled: false,
            matchCondition: originalCondition,
            action: .breakpoint(phase: .request),
            priority: 7
        )

        // Flip Include subpaths — a scope change that forces a rebuild.
        let rebuilt = BreakpointRuleForm.makeRule(
            original: original,
            ruleName: "Legacy",
            rawPattern: "*.example.com/api",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        #expect(rebuilt.matchCondition != originalCondition)
        #expect(rebuilt.matchCondition.includeSubpaths == true)
        #expect(rebuilt.matchCondition.sourceURLPattern == "*.example.com/api")
        // Rule identity and header metadata survive the rebuild.
        #expect(rebuilt.id == fixedID)
        #expect(rebuilt.isEnabled == false)
        #expect(rebuilt.priority == 7)
        #expect(rebuilt.matchCondition.headerName == "X-Env")
        #expect(rebuilt.matchCondition.headerValue == "staging")
    }

    private func regexMatches(_ regex: NSRegularExpression, text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
