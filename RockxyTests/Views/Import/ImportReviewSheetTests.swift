import Foundation
@testable import Rockxy
import Testing

// MARK: - ImportReviewSheetTests

struct ImportReviewSheetTests {
    // MARK: Internal

    // MARK: File type labels

    @Test("HAR preview uses HAR labels and hides session-only metadata")
    func harPreviewUsesHARLabels() {
        let summary = ImportReviewSummary(
            preview: makePreview(fileType: .har, transactionCount: 4, logEntryCount: 0, rockxyVersion: nil),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.isRockxySession == false)
        #expect(summary.fileTypeLabel == "HAR Archive (HTTP Archive 1.2)")
        #expect(summary.title == "Import HAR Archive")
        #expect(summary.versionLabel == nil)
    }

    @Test("Rockxy session preview uses session labels and version")
    func rockxySessionPreviewUsesSessionLabels() {
        let summary = ImportReviewSummary(
            preview: makePreview(
                fileType: .rockxysession,
                transactionCount: 9,
                logEntryCount: 3,
                rockxyVersion: "1.4.2"
            ),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.isRockxySession == true)
        #expect(summary.fileTypeLabel == "Rockxy Session")
        #expect(summary.title == "Open Rockxy Session")
        #expect(summary.versionLabel == "Rockxy v1.4.2")
    }

    @Test("Blank version string is treated as absent")
    func blankVersionTreatedAsAbsent() {
        let summary = ImportReviewSummary(
            preview: makePreview(fileType: .rockxysession, transactionCount: 1, logEntryCount: 0, rockxyVersion: ""),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.versionLabel == nil)
    }

    @Test("Whitespace-only version string is treated as absent")
    func whitespaceVersionTreatedAsAbsent() {
        let summary = ImportReviewSummary(
            preview: makePreview(
                fileType: .rockxysession,
                transactionCount: 1,
                logEntryCount: 0,
                rockxyVersion: "  \n "
            ),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.versionLabel == nil)
    }

    // MARK: Singular / plural counts

    @Test("Request and log labels use singular and plural forms")
    func countLabelsUseSingularAndPlural() {
        #expect(ImportReviewCopy.requests(1) == "1 request")
        #expect(ImportReviewCopy.requests(2) == "2 requests")
        #expect(ImportReviewCopy.requests(0) == "0 requests")

        #expect(ImportReviewCopy.logEntries(1) == "1 log entry")
        #expect(ImportReviewCopy.logEntries(4) == "4 log entries")
        #expect(ImportReviewCopy.logEntries(0) == "0 log entries")
    }

    @Test("Incoming count labels reflect the preview")
    func incomingCountLabelsReflectPreview() {
        let single = ImportReviewSummary(
            preview: makePreview(fileType: .rockxysession, transactionCount: 1, logEntryCount: 1, rockxyVersion: nil),
            currentTransactionCount: 0,
            currentLogCount: 0
        )
        #expect(single.incomingRequestsLabel == "1 request")
        #expect(single.incomingLogsLabel == "1 log entry")

        let many = ImportReviewSummary(
            preview: makePreview(fileType: .rockxysession, transactionCount: 12, logEntryCount: 7, rockxyVersion: nil),
            currentTransactionCount: 0,
            currentLogCount: 0
        )
        #expect(many.incomingRequestsLabel == "12 requests")
        #expect(many.incomingLogsLabel == "7 log entries")
    }

    // MARK: Empty vs populated semantics

    @Test("Empty session is non-destructive with a neutral primary action")
    func emptySessionIsNonDestructive() {
        let summary = ImportReviewSummary(
            preview: makePreview(fileType: .har, transactionCount: 5, logEntryCount: 0, rockxyVersion: nil),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.isSessionEmpty == true)
        #expect(summary.isDestructive == false)
        #expect(summary.actionTitle == "Import")
        #expect(summary.impactSummary.localizedCaseInsensitiveContains("empty"))
        #expect(summary.impactSummary.contains("5 requests"))
        #expect(!summary.impactSummary.localizedCaseInsensitiveContains("replace"))
    }

    @Test("Empty Rockxy session uses the Open Session action and reports all incoming content")
    func emptyRockxySessionUsesOpenAction() {
        let summary = ImportReviewSummary(
            preview: makePreview(
                fileType: .rockxysession,
                transactionCount: 5,
                logEntryCount: 2,
                rockxyVersion: "2.0"
            ),
            currentTransactionCount: 0,
            currentLogCount: 0
        )

        #expect(summary.actionTitle == "Open Session")
        #expect(summary.isDestructive == false)
        #expect(summary.impactSummary.localizedCaseInsensitiveContains("current session is empty"))
        #expect(summary.impactSummary.contains("5 requests"))
        #expect(summary.impactSummary.contains("2 log entries"))
        #expect(summary.impactSummary.localizedCaseInsensitiveContains("opening"))
    }

    @Test("Populated session is destructive and truthfully labels the action")
    func populatedSessionIsDestructive() {
        let summary = ImportReviewSummary(
            preview: makePreview(fileType: .rockxysession, transactionCount: 5, logEntryCount: 2, rockxyVersion: "2.0"),
            currentTransactionCount: 42,
            currentLogCount: 8
        )

        #expect(summary.isSessionEmpty == false)
        #expect(summary.isDestructive == true)
        #expect(summary.actionTitle == "Replace Session")

        let impact = summary.impactSummary
        #expect(impact.localizedCaseInsensitiveContains("entire current session"))
        #expect(impact.contains("42 requests"))
        #expect(impact.contains("8 log entries"))
    }

    @Test("A session with only logs still counts as populated")
    func logsOnlySessionIsPopulated() {
        let summary = ImportReviewSummary(
            preview: makePreview(fileType: .har, transactionCount: 3, logEntryCount: 0, rockxyVersion: nil),
            currentTransactionCount: 0,
            currentLogCount: 1
        )

        #expect(summary.isDestructive == true)
        #expect(summary.actionTitle == "Replace Session")
        #expect(summary.impactSummary.contains("0 requests"))
        #expect(summary.impactSummary.contains("1 log entry"))
    }

    @Test("Equatable summaries compare by value")
    func summariesCompareByValue() {
        let preview = makePreview(fileType: .har, transactionCount: 2, logEntryCount: 0, rockxyVersion: nil)
        let first = ImportReviewSummary(preview: preview, currentTransactionCount: 1, currentLogCount: 0)
        let second = ImportReviewSummary(preview: preview, currentTransactionCount: 1, currentLogCount: 0)
        let different = ImportReviewSummary(preview: preview, currentTransactionCount: 0, currentLogCount: 0)

        #expect(first == second)
        #expect(first != different)
    }

    // MARK: Source contract

    @Test("Sheet keeps a native, scalable, honestly-gated import contract")
    func sheetKeepsNativeContract() throws {
        let source = try readProjectFile("Rockxy/Views/Import/ImportReviewSheet.swift")

        // Native controls, no custom plain destructive button.
        #expect(source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains(".rockxyGlassButtonStyle(prominent: true)"))
        #expect(source.contains("Button(role: .destructive)"))
        #expect(source.contains("exclamationmark.triangle.fill"))
        #expect(!source.contains(".buttonStyle(.plain)"))

        // No hard-coded RGB or Unicode warning glyph regressions.
        #expect(!source.contains("Color(red:"))
        #expect(!source.contains("\\u{26A0}"))
        #expect(!source.contains("FILE INFO"))
        #expect(!source.contains(".textCase(.uppercase)"))

        // Scales from tool-window metrics and uses the Rockxy font family.
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("footerActionWidth"))
        #expect(source.contains("toolMetrics.formControlHeight"))
        #expect(source.contains("toolMetrics.font("))

        // Escape cancels; the empty-session primary is the default action.
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains(".keyboardShortcut(.defaultAction)"))

        // The destructive Replace Session action must NOT take the default Return key.
        let destructiveRange = try #require(source.range(of: "Button(role: .destructive)"))
        let afterDestructive = source[destructiveRange.lowerBound...]
        let identifierRange = try #require(afterDestructive.range(of: #"importReview.actionButton"#))
        let destructiveBlock = afterDestructive[..<identifierRange.upperBound]
        #expect(!destructiveBlock.contains("keyboardShortcut(.defaultAction)"))

        // Stable accessibility identifiers for focused UI testing.
        for identifier in [
            "importReview.header",
            "importReview.summary.file",
            "importReview.summary.type",
            "importReview.summary.size",
            "importReview.summary.requests",
            "importReview.summary.logs",
            "importReview.impact",
            "importReview.cancelButton",
            "importReview.actionButton",
        ] {
            #expect(source.contains(identifier), "missing accessibility identifier \(identifier)")
        }
    }

    // MARK: Private

    private func makePreview(
        fileType: ImportFileType,
        transactionCount: Int,
        logEntryCount: Int,
        rockxyVersion: String?
    )
        -> ImportPreview
    {
        ImportPreview(
            fileName: "capture.\(fileType == .har ? "har" : "rockxysession")",
            fileType: fileType,
            transactionCount: transactionCount,
            logEntryCount: logEntryCount,
            fileSize: 2_048,
            captureStartDate: fileType == .rockxysession ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            captureEndDate: fileType == .rockxysession ? Date(timeIntervalSince1970: 1_700_000_600) : nil,
            rockxyVersion: rockxyVersion,
            sourceURL: URL(fileURLWithPath: "/tmp/capture")
        )
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
