import Foundation
@testable import Rockxy
import Testing

/// Tests that transaction quick-create carries captured response headers into the
/// Map Local draft, preserving repeats, with backward-compatible defaults.
@MainActor
struct MapLocalDraftHeaderTests {
    @Test("Transaction builder carries captured response headers preserving repeats and order")
    func builderCarriesResponseHeaders() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/session",
            statusCode: 200
        )
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Set-Cookie", value: "a=1"),
                HTTPHeader(name: "Set-Cookie", value: "b=2"),
                HTTPHeader(name: "X-Trace", value: "abc"),
            ],
            body: Data("{}".utf8)
        )

        let draft = MapLocalDraftBuilder.fromTransaction(transaction)

        #expect(draft.responseHeaders.map(\.name) == [
            "Content-Type", "Set-Cookie", "Set-Cookie", "X-Trace",
        ])
        #expect(draft.responseHeaders.filter { $0.name == "Set-Cookie" }.map(\.value) == ["a=1", "b=2"])
        #expect(draft.responseHeaders.first { $0.name == "X-Trace" }?.value == "abc")
    }

    @Test("Transaction builder yields empty headers when the response carries none")
    func builderEmptyWhenNoResponse() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/pending",
            statusCode: 200
        )
        transaction.response = nil

        let draft = MapLocalDraftBuilder.fromTransaction(transaction)
        #expect(draft.responseHeaders.isEmpty)
    }

    @Test("Domain builder and legacy init default to empty response headers")
    func domainAndLegacyDefaultEmpty() {
        let domainDraft = MapLocalDraftBuilder.fromDomain("cdn.example.com")
        #expect(domainDraft.responseHeaders.isEmpty)

        let legacyDraft = MapLocalDraft(
            origin: .selectedTransaction,
            suggestedName: "Legacy",
            sourceHost: "example.com"
        )
        #expect(legacyDraft.responseHeaders.isEmpty)
    }
}
