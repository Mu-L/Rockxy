import Foundation
@testable import Rockxy
import Testing

// MARK: - MapLocalResponseResolverTests

// Regression tests for `MapLocalResponseResolver`, the shared bounded parser/resolver that turns
// Map Local file bytes into a response payload (or an origin fallback signal).

struct MapLocalResponseResolverTests {
    // MARK: Internal

    // MARK: - Raw files use the rule's status + configured headers

    @Test("Raw JSON file serves the rule status and configured headers with a recomputed length")
    func rawFileUsesActionMetadata() {
        let body = Data(#"{"source":"local"}"#.utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: body,
            actionStatusCode: 201,
            configuredHeaders: [HTTPHeader(name: "X-Custom", value: "abc")],
            inferredContentType: "application/json"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.statusCode == 201)
        #expect(payload.statusMessage == nil)
        #expect(payload.body == body)
        #expect(payload.headers.contains(HTTPHeader(name: "X-Custom", value: "abc")))
        #expect(headerValue(payload.headers, "Content-Length") == "\(body.count)")
        #expect(headerValue(payload.headers, "Content-Type") == "application/json")
    }

    @Test("Binary file that does not start with an HTTP signature is served byte-for-byte as raw")
    func binaryFileIsRaw() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x10])
        let outcome = MapLocalResponseResolver.resolve(
            fileData: bytes,
            actionStatusCode: 200,
            configuredHeaders: [],
            inferredContentType: "image/png"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.body == bytes)
        #expect(payload.statusCode == 200)
        #expect(headerValue(payload.headers, "Content-Length") == "7")
    }

    @Test("Empty file serves the rule status with a zero-length body")
    func emptyFileServed() {
        let outcome = MapLocalResponseResolver.resolve(
            fileData: Data(),
            actionStatusCode: 204,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.statusCode == 204)
        #expect(payload.body.isEmpty)
        #expect(headerValue(payload.headers, "Content-Length") == "0")
    }

    // MARK: - Full HTTP message files are authoritative

    @Test("Full HTTP message file drives the status, ordered/repeated headers, and body")
    func fullMessageFileIsAuthoritative() {
        let file = Data("""
        HTTP/1.1 203 Non-Authoritative Information\r
        Content-Type: application/problem+json\r
        Set-Cookie: one=1\r
        Set-Cookie: two=2\r
        X-Map-Local: Rockxy\r
        \r
        {"source":"file"}
        """.utf8)

        // The rule metadata (status 500, its own headers) must be ignored — the file wins.
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 500,
            configuredHeaders: [HTTPHeader(name: "X-Should-Not-Appear", value: "1")],
            inferredContentType: "application/octet-stream"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.statusCode == 203)
        #expect(payload.statusMessage == "Non-Authoritative Information")
        #expect(payload.body == Data(#"{"source":"file"}"#.utf8))
        #expect(headerValue(payload.headers, "Content-Type") == "application/problem+json")
        #expect(payload.headers.filter { $0.name == "Set-Cookie" }.map(\.value) == ["one=1", "two=2"])
        #expect(payload.headers.contains(HTTPHeader(name: "X-Map-Local", value: "Rockxy")))
        #expect(!payload.headers.contains { $0.name == "X-Should-Not-Appear" })
        // Content-Length is recomputed from the body, never trusted from the file.
        #expect(headerValue(payload.headers, "Content-Length") == "\(Data(#"{"source":"file"}"#.utf8).count)")
    }

    @Test("Full message with LF-only line endings still parses")
    func fullMessageLFOnly() {
        let file = Data("HTTP/1.1 200 OK\nContent-Type: text/plain\n\nhello".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 500,
            configuredHeaders: [],
            inferredContentType: "application/octet-stream"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.statusCode == 200)
        #expect(payload.body == Data("hello".utf8))
        #expect(headerValue(payload.headers, "Content-Type") == "text/plain")
    }

    @Test("Full message with a persisted Content-Length header recomputes from the body")
    func fullMessageRecomputesContentLength() {
        let file = Data("HTTP/1.1 200 OK\r\nContent-Length: 9999\r\n\r\nBODY".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 200,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(headerValue(payload.headers, "Content-Length") == "4")
    }

    @Test("Status-only full message with no headers serves an empty body")
    func fullMessageStatusOnly() {
        let file = Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 500,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        guard case let .serve(payload) = outcome else {
            Issue.record("Expected serve, got \(outcome)")
            return
        }
        #expect(payload.statusCode == 204)
        #expect(payload.statusMessage == "No Content")
        #expect(payload.body.isEmpty)
    }

    // MARK: - Malformed message-looking files fall back to the origin

    @Test("Message-looking file with an out-of-range status falls back to the origin")
    func fullMessageInvalidStatusFallsBack() {
        let file = Data("HTTP/1.1 999 Nonsense\r\nContent-Type: text/plain\r\n\r\nbody".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 200,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        #expect(outcome == .fallbackToOrigin)
    }

    @Test("Message-looking file with an invalid HTTP version falls back to the origin")
    func fullMessageInvalidVersionFallsBack() {
        for statusLine in ["HTTP/foo 200 OK", "HTTP/1 200 OK", "HTTP/1.x 200 OK"] {
            let file = Data("\(statusLine)\r\nContent-Type: text/plain\r\n\r\nbody".utf8)
            let outcome = MapLocalResponseResolver.resolve(
                fileData: file,
                actionStatusCode: 200,
                configuredHeaders: [],
                inferredContentType: "text/plain"
            )
            #expect(outcome == .fallbackToOrigin)
        }
    }

    @Test("Message-looking file with no terminating blank line falls back to the origin")
    func fullMessageNoBlankLineFallsBack() {
        let file = Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 200,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        #expect(outcome == .fallbackToOrigin)
    }

    @Test("Message-looking file with a header line missing its colon falls back to the origin")
    func fullMessageBadHeaderFallsBack() {
        let file = Data("HTTP/1.1 200 OK\r\nThisIsNotAHeader\r\n\r\nbody".utf8)
        let outcome = MapLocalResponseResolver.resolve(
            fileData: file,
            actionStatusCode: 200,
            configuredHeaders: [],
            inferredContentType: "text/plain"
        )
        #expect(outcome == .fallbackToOrigin)
    }

    // MARK: - Runtime status validation for raw files (imported / programmatic rules)

    @Test("Raw file with an out-of-range rule status falls back to the origin")
    func rawFileInvalidStatusFallsBack() {
        for invalid in [0, 99, 600, 700, -1] {
            let outcome = MapLocalResponseResolver.resolve(
                fileData: Data("body".utf8),
                actionStatusCode: invalid,
                configuredHeaders: [],
                inferredContentType: "text/plain"
            )
            #expect(outcome == .fallbackToOrigin, "status \(invalid) must fall back")
        }
    }

    @Test("Status-code validation accepts the full 100...599 range and rejects outside it")
    func statusCodeValidationRange() {
        #expect(MapLocalResponseResolver.isValidStatusCode(100))
        #expect(MapLocalResponseResolver.isValidStatusCode(599))
        #expect(MapLocalResponseResolver.isValidStatusCode(203))
        #expect(!MapLocalResponseResolver.isValidStatusCode(99))
        #expect(!MapLocalResponseResolver.isValidStatusCode(600))
        #expect(!MapLocalResponseResolver.isValidStatusCode(0))
    }

    // MARK: - Concurrency (no serialization / hang)

    @Test("Concurrent resolves of mixed payloads all complete with correct results")
    func concurrentResolvesDoNotSerializeOrHang() {
        let iterations = 240
        let results = UnsafeConcurrentResults(count: iterations)

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let kind = index % 3
            switch kind {
            case 0:
                let outcome = MapLocalResponseResolver.resolve(
                    fileData: Data("HTTP/1.1 202 Accepted\r\nX-N: \(index)\r\n\r\nbody\(index)".utf8),
                    actionStatusCode: 200,
                    configuredHeaders: [],
                    inferredContentType: "text/plain"
                )
                if case let .serve(payload) = outcome, payload.statusCode == 202 {
                    results.record(index, true)
                } else {
                    results.record(index, false)
                }
            case 1:
                let outcome = MapLocalResponseResolver.resolve(
                    fileData: Data("raw-\(index)".utf8),
                    actionStatusCode: 200,
                    configuredHeaders: [],
                    inferredContentType: "text/plain"
                )
                if case let .serve(payload) = outcome, payload.body == Data("raw-\(index)".utf8) {
                    results.record(index, true)
                } else {
                    results.record(index, false)
                }
            default:
                let outcome = MapLocalResponseResolver.resolve(
                    fileData: Data("HTTP/1.1 999 Bad\r\n\r\nx".utf8),
                    actionStatusCode: 700,
                    configuredHeaders: [],
                    inferredContentType: "text/plain"
                )
                results.record(index, outcome == .fallbackToOrigin)
            }
        }

        #expect(results.allTrue())
    }

    // MARK: Private

    private func headerValue(_ headers: [HTTPHeader], _ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// MARK: - UnsafeConcurrentResults

/// A fixed-size boolean result sink written from `DispatchQueue.concurrentPerform` at unique
/// indices (no two workers share an index), then read once after the barrier completes. Backed by
/// a stably-allocated buffer so concurrent writes to distinct indices never touch shared Array
/// bookkeeping.
private final class UnsafeConcurrentResults: @unchecked Sendable {
    // MARK: Lifecycle

    init(count: Int) {
        self.count = count
        storage = UnsafeMutablePointer<Bool>.allocate(capacity: count)
        storage.initialize(repeating: false, count: count)
    }

    deinit {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    // MARK: Internal

    func record(_ index: Int, _ value: Bool) {
        (storage + index).pointee = value
    }

    func allTrue() -> Bool {
        UnsafeBufferPointer(start: storage, count: count).allSatisfy { $0 }
    }

    // MARK: Private

    private let count: Int
    private let storage: UnsafeMutablePointer<Bool>
}
