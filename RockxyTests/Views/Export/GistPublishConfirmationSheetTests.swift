import Foundation
@testable import Rockxy
import Testing

// MARK: - GistPublishConfirmationSheetTests

struct GistPublishConfirmationSheetTests {
    // MARK: Internal

    // MARK: Review summary

    @Test("Summary reports exact request count, unique hosts, and mirrored file count")
    func summaryReportsCountsAndFileCount() {
        let transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/one"),
            TestFixtures.makeTransaction(url: "https://api.example.com/two"),
            TestFixtures.makeTransaction(url: "https://cdn.example.com/asset"),
        ]

        let summary = GistPublishReviewSummary(transactions: transactions)

        #expect(summary.requestCount == 3)
        #expect(summary.uniqueHostCount == 2)
        #expect(summary.hasWebSocketFrames == false)
        // README + HAR + one transaction file per request, no WebSocket file.
        #expect(summary.fileCount == 5)
        #expect(summary.fileCountLabel == "5 files")
        #expect(summary.requestSummary == "3 requests selected")
        #expect(summary.hostCountLabel == "2 hosts")
        #expect(summary.fileSummary.contains("3 transaction files"))
        #expect(!summary.fileSummary.contains("WebSocket frames"))
    }

    @Test("Single request uses singular copy")
    func singleRequestUsesSingularCopy() {
        let summary = GistPublishReviewSummary(
            transactions: [TestFixtures.makeTransaction(url: "https://api.example.com/one")]
        )

        #expect(summary.requestSummary == "1 request selected")
        #expect(summary.hostCountLabel == "1 host")
        #expect(summary.fileCount == 3)
        #expect(summary.fileCountLabel == "3 files")
        #expect(summary.fileSummary.contains("1 transaction file"))
    }

    @Test("Host summary compacts long host lists with a +N more overflow")
    func hostSummaryCompactsLongLists() {
        let one = GistPublishReviewSummary(
            transactions: [TestFixtures.makeTransaction(url: "https://api.example.com/x")]
        )
        #expect(one.hostSummary == "api.example.com")

        let two = GistPublishReviewSummary(transactions: [
            TestFixtures.makeTransaction(url: "https://api.example.com/x"),
            TestFixtures.makeTransaction(url: "https://cdn.example.com/y"),
        ])
        #expect(two.hostSummary == "api.example.com, cdn.example.com")

        let many = GistPublishReviewSummary(transactions: [
            TestFixtures.makeTransaction(url: "https://a.example.com/1"),
            TestFixtures.makeTransaction(url: "https://b.example.com/2"),
            TestFixtures.makeTransaction(url: "https://c.example.com/3"),
            TestFixtures.makeTransaction(url: "https://d.example.com/4"),
        ])
        #expect(many.uniqueHostCount == 4)
        #expect(many.hostSummary == "a.example.com, b.example.com +2 more")
    }

    @Test("WebSocket frames add a file and surface in the file summary")
    func webSocketFramesSurfaceInSummary() {
        let summary = GistPublishReviewSummary(transactions: [
            TestFixtures.makeTransaction(url: "https://api.example.com/x"),
            TestFixtures.makeWebSocketTransaction(),
        ])

        #expect(summary.hasWebSocketFrames == true)
        // README + HAR + 2 transaction files + websocket-frames.json.
        #expect(summary.fileCount == 5)
        #expect(summary.fileSummary.contains("WebSocket frames"))
    }

    // MARK: Truthful visibility copy

    @Test("Secret and Public visibility copy is truthful, not private")
    func visibilityCopyIsTruthful() {
        #expect(GistPublishCopy.visibilityTitle(.secret) == "Secret Gist")
        #expect(GistPublishCopy.visibilityTitle(.public) == "Public Gist")

        let secret = GistPublishCopy.visibilityDescription(.secret)
        #expect(secret.contains("anyone with the link"))
        #expect(secret.contains("not searchable"))
        #expect(!secret.localizedCaseInsensitiveContains("private"))

        let publicCopy = GistPublishCopy.visibilityDescription(.public)
        #expect(publicCopy.localizedCaseInsensitiveContains("searchable"))
        #expect(GitHubGistVisibility.secret.sharingDescription == secret)
    }

    // MARK: Redaction and warning copy

    @Test("Redaction copy is best-effort and warnings are explicit")
    func redactionCopyIsBestEffort() {
        #expect(GistPublishCopy.redactionDescription.contains("Best-effort"))
        #expect(GistPublishCopy.redactionDescription.contains("not a guarantee"))
        #expect(GistPublishCopy.redactionOffWarning.localizedCaseInsensitiveContains("redaction is off"))
        #expect(GistPublishCopy.publicWarning.localizedCaseInsensitiveContains("searchable"))
    }

    @Test("Unredacted publishing always requires review")
    func unredactedPublishingRequiresReview() {
        #expect(GistPublishConfirmationPolicy.requiresReview(
            askBeforePublishing: false,
            redactsSensitiveData: false
        ))
        #expect(GistPublishConfirmationPolicy.requiresReview(
            askBeforePublishing: true,
            redactsSensitiveData: true
        ))
        #expect(!GistPublishConfirmationPolicy.requiresReview(
            askBeforePublishing: false,
            redactsSensitiveData: true
        ))
    }

    // MARK: Source contract

    @Test("Sheet keeps a native, scalable, progress-aware publish contract")
    func sheetKeepsNativeProgressContract() throws {
        let source = try readProjectFile("Rockxy/Views/Export/GistPublishConfirmationSheet.swift")

        // Progress + duplicate-submit + disabled-during-publish contract.
        #expect(source.contains("ProgressView()"))
        #expect(source.contains("Publishing"))
        #expect(source.contains("guard !isPublishing else {"))
        #expect(source.contains(".disabled(isPublishing)"))
        #expect(source.contains(".rockxyGlassButtonStyle(prominent: true)"))

        // Failure re-enables controls and shows an inline error.
        #expect(source.contains("errorMessage = error.localizedDescription"))
        #expect(source.contains("gistPublish.error"))

        // Scales from tool-window metrics and honors the Rockxy font family.
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("footerActionWidth"))
        #expect(source.contains("toolMetrics.formControlHeight"))
        #expect(source.contains("toolMetrics.font("))

        // Stable accessibility identifiers for focused UI testing.
        for identifier in [
            "gistPublish.sheet",
            "gistPublish.summary.requests",
            "gistPublish.summary.hosts",
            "gistPublish.summary.files",
            "gistPublish.visibility",
            "gistPublish.redactToggle",
            "gistPublish.publishButton",
            "gistPublish.cancelButton",
        ] {
            #expect(source.contains(identifier), "missing accessibility identifier \(identifier)")
        }

        // No dashboard-style or compact-fixed regressions.
        #expect(!source.contains(".font(.caption"))
        #expect(!source.contains(".font(.system(.body"))
        #expect(!source.contains("Private Gist"))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
