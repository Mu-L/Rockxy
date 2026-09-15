import Foundation
import NIOCore
@testable import Rockxy
import Testing

// MARK: - ProtocolDetectorHandlerTests

struct ProtocolDetectorHandlerTests {
    @Test("An HTTP/1.x request line inside a CONNECT tunnel is recognised as plain HTTP")
    func recognisesRequestLines() {
        for line in [
            "GET /socket?room=live HTTP/1.1\r\nHost: api.example.com\r\nUpgrade: websocket\r\n\r\n",
            "POST /api/login HTTP/1.0\r\nContent-Length: 2\r\n\r\n{}",
            "OPTIONS /preflight HTTP/1.1\r\n\r\n",
        ] {
            #expect(ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer(line)), Comment(rawValue: line))
        }
    }

    @Test("TLS records, short prefaces, and other protocols stay raw tunnels")
    func rejectsNonHTTPPrefaces() {
        let clientHello = ByteBuffer(bytes: [0x16, 0x03, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0xFC, 0x03, 0x03] + [UInt8](repeating: 0, count: 32))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(clientHello))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer("GET /")))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer("SSH-2.0-OpenSSH_9.0\r\nmore-bytes-here")))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer("get /lower HTTP/1.1\r\n\r\n")))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer("GET http://x/ HTTP/1.1\r\n\r\n")))
        #expect(!ProtocolDetectorHandler.looksLikePlainHTTPRequest(Self.buffer("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")))
    }

    private static func buffer(_ text: String) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        return buffer
    }
}
