import Foundation

enum BreakpointRuleForm {
    struct Decoded: Equatable {
        let displayPattern: String
        let matchType: RuleMatchType
        let includeSubpaths: Bool
        let httpMethod: HTTPMethodFilter
        let breakpointRequest: Bool
        let breakpointResponse: Bool
    }

    static func decode(rule: ProxyRule) -> Decoded {
        let rawPattern = rule.matchCondition.urlPattern ?? ""
        let fallback = decodeLegacyPattern(rawPattern)
        let matchType = rule.matchCondition.matchType ?? fallback.matchType
        let displayPattern = rule.matchCondition.sourceURLPattern
            ?? (matchType == .regex ? rawPattern : fallback.displayPattern)
        let includeSubpaths = matchType == .wildcard
            ? rule.matchCondition.includeSubpaths ?? fallback.includeSubpaths
            : false
        let method = HTTPMethodFilter.allCases.first {
            $0.rawValue == rule.matchCondition.method
        } ?? .any

        let phases: (request: Bool, response: Bool) = {
            guard case let .breakpoint(phase) = rule.action else {
                return (true, true)
            }
            switch phase {
            case .request:
                return (true, false)
            case .response:
                return (false, true)
            case .both:
                return (true, true)
            }
        }()

        return Decoded(
            displayPattern: displayPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            httpMethod: method,
            breakpointRequest: phases.request,
            breakpointResponse: phases.response
        )
    }

    static func makeRule(
        original: ProxyRule?,
        ruleName: String,
        rawPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool
    ) -> ProxyRule {
        let trimmedPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIncludeSubpaths = matchType == .wildcard && includeSubpaths
        let originalDecoded = original.map(decode)
        let scopeIsUnchanged = originalDecoded.map {
            $0.displayPattern == trimmedPattern
                && $0.httpMethod == httpMethod
                && $0.matchType == matchType
                && $0.includeSubpaths == normalizedIncludeSubpaths
        } ?? false

        let condition: RuleMatchCondition
        if scopeIsUnchanged, let originalCondition = original?.matchCondition {
            condition = originalCondition
        } else {
            condition = RuleMatchCondition(
                urlPattern: RulePatternBuilder.regexSource(
                    rawPattern: trimmedPattern,
                    matchType: matchType,
                    includeSubpaths: normalizedIncludeSubpaths
                ),
                sourceURLPattern: trimmedPattern,
                method: httpMethod.methodValue,
                headerName: original?.matchCondition.headerName,
                headerValue: original?.matchCondition.headerValue,
                matchType: matchType,
                includeSubpaths: matchType == .wildcard ? normalizedIncludeSubpaths : nil
            )
        }

        let trimmedName = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProxyRule(
            id: original?.id ?? UUID(),
            name: trimmedName.isEmpty ? trimmedPattern : trimmedName,
            isEnabled: original?.isEnabled ?? true,
            matchCondition: condition,
            action: .breakpoint(phase: phase(request: phaseRequest, response: phaseResponse)),
            priority: original?.priority ?? 0
        )
    }

    static func patternValidationMessage(
        rawPattern: String,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    ) -> String? {
        let trimmedPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return String(localized: "Enter a URL pattern.")
        }
        let runtimePattern = RulePatternBuilder.regexSource(
            rawPattern: trimmedPattern,
            matchType: matchType,
            includeSubpaths: matchType == .wildcard && includeSubpaths
        )
        if case let .failure(error) = RegexValidator.compile(runtimePattern) {
            return error.localizedDescription
        }
        return nil
    }

    static func phaseValidationMessage(request: Bool, response: Bool) -> String? {
        guard !request, !response else {
            return nil
        }
        return String(localized: "Select Request, Response, or both.")
    }

    private static func phase(request: Bool, response: Bool) -> BreakpointRulePhase {
        switch (request, response) {
        case (true, true):
            .both
        case (true, false):
            .request
        case (false, true):
            .response
        case (false, false):
            .both
        }
    }

    private static func decodeLegacyPattern(
        _ pattern: String
    ) -> (displayPattern: String, matchType: RuleMatchType, includeSubpaths: Bool) {
        var working = pattern
        var includeSubpaths = true

        if working.hasSuffix(".*") {
            working = String(working.dropLast(2))
        } else if working.hasSuffix("($|[?#])") {
            working = String(working.dropLast("($|[?#])".count))
            includeSubpaths = false
        }

        let wildcardStarMarker = "\u{E000}"
        let literalDotMarker = "\u{E001}"
        let wildcardAnyMarker = "\u{E002}"
        let staged = working
            .replacingOccurrences(of: ".*", with: wildcardStarMarker)
            .replacingOccurrences(of: "\\.", with: literalDotMarker)
            .replacingOccurrences(of: ".", with: wildcardAnyMarker)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\-", with: "-")
            .replacingOccurrences(of: "\\_", with: "_")

        let regexMetaScalars = CharacterSet(charactersIn: "^$|()[]{}+?\\")
        if staged.unicodeScalars.contains(where: { regexMetaScalars.contains($0) }) {
            return (pattern, .regex, true)
        }

        return (
            staged
                .replacingOccurrences(of: wildcardStarMarker, with: "*")
                .replacingOccurrences(of: literalDotMarker, with: ".")
                .replacingOccurrences(of: wildcardAnyMarker, with: "?"),
            .wildcard,
            includeSubpaths
        )
    }
}
