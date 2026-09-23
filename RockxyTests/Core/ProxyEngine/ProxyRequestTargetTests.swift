import Foundation
@testable import Rockxy
import Testing

/// How the plain-HTTP proxy listener turns a request target into the URL it forwards and records.
struct ProxyRequestTargetTests {
    @Test("Origin-form targets are resolved against the Host header")
    func originFormUsesHost() {
        #expect(HTTPProxyHandler.requestURLString(uri: "/api/users?page=2", host: "127.0.0.1:18090")
            == "http://127.0.0.1:18090/api/users?page=2")
    }

    @Test("HTTP absolute-form targets are kept as sent")
    func httpAbsoluteFormIsKept() {
        #expect(HTTPProxyHandler.requestURLString(uri: "http://api.example.com:8080/v1", host: "ignored")
            == "http://api.example.com:8080/v1")
        #expect(HTTPProxyHandler.requestURLString(uri: "HTTPS://api.example.com/v1", host: "ignored")
            == "HTTPS://api.example.com/v1")
    }

    @Test("A WebSocket absolute-form target keeps its host, port, and path")
    func webSocketAbsoluteFormKeepsItsPath() throws {
        // `GET ws://host:port/socket` used to be glued onto the Host into an unparseable URL, which
        // fell back to `http://host/`: the upgrade went to "/" on port 80 and the origin said 404.
        let plain = HTTPProxyHandler.requestURLString(uri: "ws://127.0.0.1:18090/ws?room=1", host: "127.0.0.1:18090")
        let url = try #require(URL(string: plain))
        #expect(url.scheme == "http")
        #expect(url.port == 18090)
        #expect(url.path == "/ws")
        #expect(url.query == "room=1")

        #expect(HTTPProxyHandler.requestURLString(uri: "wss://chat.example.com/socket", host: "chat.example.com")
            == "https://chat.example.com/socket")
    }
}
