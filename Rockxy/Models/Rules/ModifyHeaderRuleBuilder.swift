import Foundation

enum ModifyHeaderRuleBuilder {
    static func build(
        existingRule: ProxyRule? = nil,
        ruleName: String,
        rawPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool,
        operations: [HeaderOperation]
    ) -> ProxyRule {
        let trimmedPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = RulePatternBuilder.regexSource(
            rawPattern: trimmedPattern,
            matchType: matchType,
            includeSubpaths: matchType == .wildcard ? includeSubpaths : false
        )
        let displayName = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)

        return ProxyRule(
            id: existingRule?.id ?? UUID(),
            name: displayName.isEmpty ? trimmedPattern : displayName,
            isEnabled: existingRule?.isEnabled ?? true,
            // Persist the authored pattern and match semantics alongside the compiled
            // regex so reopening the rule restores the wildcard the user typed instead
            // of presenting the compiled expression as an editable regex.
            matchCondition: RuleMatchCondition(
                urlPattern: pattern,
                sourceURLPattern: trimmedPattern,
                method: httpMethod.methodValue,
                matchType: matchType,
                includeSubpaths: matchType == .wildcard ? includeSubpaths : false
            ),
            action: .modifyHeader(operations: operations),
            priority: existingRule?.priority ?? 0
        )
    }
}
