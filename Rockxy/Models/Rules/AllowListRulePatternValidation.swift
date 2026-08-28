import Foundation

enum AllowListRulePatternValidation {
    static let maxRegexLength = 2_048

    static func isValid(
        rawPattern: String,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    )
        -> Bool
    {
        if matchType == .regex, rawPattern.count > maxRegexLength {
            return false
        }
        let source = RulePatternBuilder.regexSource(
            rawPattern: rawPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
        return (try? NSRegularExpression(pattern: source)) != nil
    }

    static func editorMessage(
        rawPattern: String,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    )
        -> String?
    {
        guard matchType == .regex, !rawPattern.isEmpty else {
            return nil
        }
        guard rawPattern.count <= maxRegexLength else {
            return String(
                localized: "Regular expressions are limited to 2,048 characters.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard isValid(
            rawPattern: rawPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        ) else {
            return String(localized: "Enter a valid regular expression.", bundle: RockxyLocalization.bundle)
        }
        return nil
    }
}
