import Foundation
@testable import Rockxy
import Testing

/// The assistant dock's scope labels are whole catalog sentences resolved through
/// `AttributedString`, so a count of one must read in the singular and the inflection
/// markup must never survive into the rendered string.
struct AssistantScopeSummaryTests {
    @Test("Selected-scope menu title agrees with its count")
    func selectedScopeTitleAgreesWithCount() {
        #expect(AssistantScopeSummary.selectedScopeTitle(attached: 1, selected: 1)
            == "Selected Traffic Only (1 request)")
        #expect(AssistantScopeSummary.selectedScopeTitle(attached: 4, selected: 4)
            == "Selected Traffic Only (4 requests)")
    }

    @Test("A capped selection shows the attached share of the whole selection")
    func selectedScopeTitleShowsCappedShare() {
        #expect(AssistantScopeSummary.selectedScopeTitle(attached: 1, selected: 12)
            == "Selected Traffic Only (1 of 12 requests)")
        #expect(AssistantScopeSummary.selectedScopeTitle(attached: 0, selected: 1)
            == "Selected Traffic Only (0 of 1 request)")
    }

    @Test("Scope accessibility labels agree with their counts")
    func accessibilityLabelsAgreeWithCount() {
        #expect(AssistantScopeSummary.scopeAccessibilityLabel(attached: 1)
            == "Read-only traffic scope, 1 request")
        #expect(AssistantScopeSummary.scopeAccessibilityLabel(attached: 3)
            == "Read-only traffic scope, 3 requests")
        #expect(AssistantScopeSummary.attachedTrafficAccessibilityLabel(summary: "GET 200  api.test/v1", attached: 1)
            == "Attached traffic: GET 200  api.test/v1, 1 request")
        #expect(AssistantScopeSummary.attachedTrafficAccessibilityLabel(summary: "GET 200  api.test/v1", attached: 2)
            == "Attached traffic: GET 200  api.test/v1, 2 requests")
    }

    @Test("No label leaks raw inflection markup")
    func labelsNeverRenderInflectionMarkup() {
        let rendered = [
            AssistantScopeSummary.selectedScopeTitle(attached: 1, selected: 1),
            AssistantScopeSummary.selectedScopeTitle(attached: 1, selected: 9),
            AssistantScopeSummary.scopeAccessibilityLabel(attached: 1),
            AssistantScopeSummary.attachedTrafficAccessibilityLabel(summary: "GET 200  api.test", attached: 1),
        ]
        for label in rendered {
            #expect(!label.contains("inflect: true"), "Raw inflection markup rendered: \(label)")
            #expect(!label.contains("^["), "Raw inflection markup rendered: \(label)")
        }
    }
}
