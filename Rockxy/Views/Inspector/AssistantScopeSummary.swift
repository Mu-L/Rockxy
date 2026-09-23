import Foundation

// MARK: - AssistantScopeSummary

/// Counted labels for the assistant dock's read-only traffic scope.
///
/// Each label is one whole sentence in the catalog so translators control the word order around
/// both counts, and every count resolves through `AttributedString` so grammar agreement applies
/// ("1 request" rather than "1 requests").
enum AssistantScopeSummary {
    /// Menu title for the selected-traffic scope. Shows the capped share when the selection is
    /// larger than the assistant's context limit.
    static func selectedScopeTitle(attached: Int, selected: Int) -> String {
        guard attached < selected else {
            return String(AttributedString(
                localized: "Selected Traffic Only (^[\(attached) request](inflect: true))",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        }
        return String(AttributedString(
            localized: "Selected Traffic Only (\(attached) of ^[\(selected) request](inflect: true))",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    /// VoiceOver label for the scope menu itself.
    static func scopeAccessibilityLabel(attached: Int) -> String {
        String(AttributedString(
            localized: "Read-only traffic scope, ^[\(attached) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    /// VoiceOver label for the attached-context header row.
    static func attachedTrafficAccessibilityLabel(summary: String, attached: Int) -> String {
        String(AttributedString(
            localized: "Attached traffic: \(summary), ^[\(attached) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }
}
