import Foundation
@testable import Rockxy
import Testing

// Regression tests for `MapLocalResponseBuilder` — Map Local response header construction
// and sanitization shared by the plain-HTTP and intercepted-HTTPS handlers.

struct MapLocalResponseBuilderTests {
    @Test("Content-Length is always recomputed from the served bytes")
    func recomputesContentLength() {
        // A persisted (and wrong) Content-Length must never be trusted.
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [HTTPHeader(name: "Content-Length", value: "999999")],
            bodyByteCount: 42,
            inferredContentType: "application/json"
        )
        let lengths = headers.filter { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
        #expect(lengths.count == 1)
        #expect(lengths[0].value == "42")
    }

    @Test("Configured Content-Type wins over MIME inference")
    func configuredContentTypeWins() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [HTTPHeader(name: "Content-Type", value: "text/custom")],
            bodyByteCount: 10,
            inferredContentType: "application/json"
        )
        let types = headers.filter { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        #expect(types.count == 1)
        #expect(types[0].value == "text/custom")
    }

    @Test("Missing Content-Type falls back to MIME inference")
    func inferredContentTypeUsed() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [HTTPHeader(name: "X-Custom", value: "1")],
            bodyByteCount: 10,
            inferredContentType: "image/png"
        )
        let types = headers.filter { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        #expect(types.first?.value == "image/png")
    }

    @Test("Custom end-to-end header and recomputed length coexist")
    func customHeaderPreserved() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "X-Custom", value: "abc"),
            ],
            bodyByteCount: 7,
            inferredContentType: "text/plain"
        )
        #expect(headers.contains { $0.name == "X-Custom" && $0.value == "abc" })
        #expect(headers.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        #expect(headers.contains { $0.name == "Content-Length" && $0.value == "7" })
    }

    @Test("Repeated Set-Cookie headers are preserved")
    func repeatedSetCookiePreserved() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [
                HTTPHeader(name: "Set-Cookie", value: "a=1"),
                HTTPHeader(name: "Set-Cookie", value: "b=2"),
            ],
            bodyByteCount: 1,
            inferredContentType: "text/plain"
        )
        let cookies = headers.filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
        #expect(cookies.count == 2)
    }

    @Test("Configured headers keep their authored order")
    func configuredHeaderOrderPreserved() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [
                HTTPHeader(name: "X-First", value: "1"),
                HTTPHeader(name: "X-Second", value: "2"),
                HTTPHeader(name: "X-Third", value: "3"),
            ],
            bodyByteCount: 4,
            inferredContentType: "text/plain"
        )
        let custom = headers
            .map(\.name)
            .filter { $0.hasPrefix("X-") }
        #expect(custom == ["X-First", "X-Second", "X-Third"])
    }

    @Test("Hop-by-hop and framing headers are stripped")
    func framingHeadersStripped() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [
                HTTPHeader(name: "Transfer-Encoding", value: "chunked"),
                HTTPHeader(name: "Connection", value: "keep-alive"),
                HTTPHeader(name: "Keep-Alive", value: "timeout=5"),
            ],
            bodyByteCount: 3,
            inferredContentType: "text/plain"
        )
        #expect(!headers.contains { $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame })
        #expect(!headers.contains { $0.name.caseInsensitiveCompare("Connection") == .orderedSame })
        #expect(!headers.contains { $0.name.caseInsensitiveCompare("Keep-Alive") == .orderedSame })
    }

    @Test("CRLF header injection is rejected")
    func crlfInjectionRejected() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [
                HTTPHeader(name: "X-Evil", value: "value\r\nSet-Cookie: pwned=1"),
                HTTPHeader(name: "X-Bad\r\nName", value: "1"),
                HTTPHeader(name: "Valid", value: "ok"),
            ],
            bodyByteCount: 3,
            inferredContentType: "text/plain"
        )
        #expect(!headers.contains { $0.name == "X-Evil" })
        #expect(!headers.contains { $0.name.contains("X-Bad") })
        #expect(headers.contains { $0.name == "Valid" && $0.value == "ok" })
    }

    @Test("C0 control characters (other than tab), DEL, CR, LF, and NUL are rejected in values")
    func controlCharactersRejectedInValues() {
        // Every C0 control except horizontal tab (0x09) must be rejected, plus DEL (0x7F).
        let rejectedCodes = Array(0x00 ... 0x1F).filter { $0 != 0x09 } + [0x7F]
        for code in rejectedCodes {
            guard let scalar = Unicode.Scalar(code) else {
                continue
            }
            let headers = MapLocalResponseBuilder.responseHeaders(
                configured: [HTTPHeader(name: "X-Ctl", value: "a\(Character(scalar))b")],
                bodyByteCount: 1,
                inferredContentType: "text/plain"
            )
            #expect(!headers.contains { $0.name == "X-Ctl" }, "control byte 0x\(String(code, radix: 16)) not rejected")
        }
    }

    @Test("Horizontal tab is allowed in header values")
    func horizontalTabAllowedInValues() {
        let headers = MapLocalResponseBuilder.responseHeaders(
            configured: [HTTPHeader(name: "X-Tabbed", value: "a\tb")],
            bodyByteCount: 1,
            inferredContentType: "text/plain"
        )
        #expect(headers.contains { $0.name == "X-Tabbed" && $0.value == "a\tb" })
    }
}
