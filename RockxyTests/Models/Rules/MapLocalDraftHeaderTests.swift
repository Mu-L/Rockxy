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

    @Test("Transaction builder decodes a compressed body and drops the compressed-representation headers")
    func builderDecodesCompressedBody() throws {
        let plain = Data(#"{"users":[{"id":1,"name":"Ada"}],"page":1}"#.utf8)
        let compressed = try (plain as NSData).compressed(using: .zlib) as Data
        #expect(compressed != plain)

        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/users",
            statusCode: 200
        )
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "deflate"),
                HTTPHeader(name: "Content-Length", value: "\(compressed.count)"),
                HTTPHeader(name: "Vary", value: "Accept-Encoding"),
                HTTPHeader(name: "Set-Cookie", value: "a=1"),
            ],
            body: compressed
        )

        let draft = MapLocalDraftBuilder.fromTransaction(transaction)

        // The editor must receive the readable body, never the compressed bytes.
        #expect(draft.responseBody == plain)
        // Headers that only described the compressed representation are gone; the rest keep order.
        #expect(draft.responseHeaders.map(\.name) == ["Content-Type", "Vary", "Set-Cookie"])
        #expect(draft.responseContentType == "application/json")
    }

    @Test("Transaction builder keeps raw bytes and headers when the body cannot be decoded")
    func builderKeepsRawBodyWhenDecodingFails() {
        let notGzip = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/blob",
            statusCode: 200
        )
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/octet-stream"),
                HTTPHeader(name: "Content-Encoding", value: "gzip"),
            ],
            body: notGzip
        )

        let draft = MapLocalDraftBuilder.fromTransaction(transaction)

        // Undecodable payload: body and its Content-Encoding stay consistent with each other.
        #expect(draft.responseBody == notGzip)
        #expect(draft.responseHeaders.map(\.name) == ["Content-Type", "Content-Encoding"])
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
