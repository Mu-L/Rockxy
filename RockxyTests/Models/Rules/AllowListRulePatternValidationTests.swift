@testable import Rockxy
import Testing

struct AllowListRulePatternValidationTests {
    @Test
    func wildcardPatternsUseRuntimeCompatibleValidation() {
        #expect(
            AllowListRulePatternValidation.isValid(
                rawPattern: "https://*.example.com/api/?",
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
    }

    @Test
    func malformedRegexProducesEditorMessage() {
        #expect(
            AllowListRulePatternValidation.editorMessage(
                rawPattern: "(",
                matchType: .regex,
                includeSubpaths: false
            ) == "Enter a valid regular expression."
        )
    }

    @Test
    func oversizedRegexUsesSharedRuntimeLimit() {
        let oversized = String(
            repeating: "a",
            count: AllowListRulePatternValidation.maxRegexLength + 1
        )

        #expect(
            !AllowListRulePatternValidation.isValid(
                rawPattern: oversized,
                matchType: .regex,
                includeSubpaths: false
            )
        )
        #expect(
            AllowListRulePatternValidation.editorMessage(
                rawPattern: oversized,
                matchType: .regex,
                includeSubpaths: false
            ) == "Regular expressions are limited to 2,048 characters."
        )
    }

    @Test
    func emptyPatternDefersToRequiredFieldValidation() {
        #expect(
            AllowListRulePatternValidation.editorMessage(
                rawPattern: "",
                matchType: .regex,
                includeSubpaths: false
            ) == nil
        )
    }
}
