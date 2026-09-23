import Foundation
@testable import Rockxy
import Testing

struct StatusBarRequestSummaryTests {
    @Test("Unfiltered summaries preserve the compact existing copy")
    func unfilteredSummary() {
        #expect(StatusBarRequestSummary.text(
            visibleCount: 238,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 0
        ) == "238 requests")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 0,
            availableCount: 0,
            selectedCount: 0,
            activeFilterCount: 0
        ) == "No requests")
    }

    @Test("Active filters distinguish visible and available request counts")
    func filteredSummary() {
        #expect(StatusBarRequestSummary.text(
            visibleCount: 5,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "5 of 238 requests")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 5,
            availableCount: 238,
            selectedCount: 2,
            activeFilterCount: 1
        ) == "2 selected, 5 of 238 shown")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 238,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "238 requests")
    }

    @Test("A single request reads in the singular instead of \"1 requests\"")
    func singularSummary() {
        #expect(StatusBarRequestSummary.text(
            visibleCount: 1,
            availableCount: 1,
            selectedCount: 0,
            activeFilterCount: 0
        ) == "1 request")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 0,
            availableCount: 1,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "0 of 1 request")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 1,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "1 of 238 requests")
    }

    @Test("Imported session provenance agrees with its request count")
    func provenanceSummary() {
        let one = SessionProvenance(
            fileName: "capture.har",
            transactionCount: 1,
            logEntryCount: 0,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let many = SessionProvenance(
            fileName: "capture.har",
            transactionCount: 4,
            logEntryCount: 0,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(one.displayText == "Imported from capture.har (1 request)")
        #expect(many.displayText == "Imported from capture.har (4 requests)")
    }
}
