import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RequestReplay` in the core traffic capture layer.

struct RequestReplayTests {
    @Test("proxyBypassSession disables HTTP proxy")
    func httpProxyDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        let dict = config.connectionProxyDictionary ?? [:]
        if let httpEnable = dict[kCFNetworkProxiesHTTPEnable as String] as? Bool {
            #expect(httpEnable == false)
        } else if let httpEnable = dict[kCFNetworkProxiesHTTPEnable as String] as? Int {
            #expect(httpEnable == 0)
        }
    }

    @Test("proxyBypassSession disables HTTPS proxy")
    func httpsProxyDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        let dict = config.connectionProxyDictionary ?? [:]
        if let httpsEnable = dict[kCFNetworkProxiesHTTPSEnable as String] as? Bool {
            #expect(httpsEnable == false)
        } else if let httpsEnable = dict[kCFNetworkProxiesHTTPSEnable as String] as? Int {
            #expect(httpsEnable == 0)
        }
    }

    @Test("proxyBypassSession is not URLSession.shared")
    func notSharedSession() {
        #expect(RequestReplay.proxyBypassSession !== URLSession.shared)
    }

    @Test("replays do not persist or synthesize cookies across sends")
    func cookiesDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        #expect(config.httpShouldSetCookies == false)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.httpCookieStorage == nil)
    }

    @Test("request builder retains repeated captured header values")
    func repeatedHeadersRetained() throws {
        let request = HTTPRequestData(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com/items")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "X-Trace", value: "one"),
                HTTPHeader(name: "X-Trace", value: "two"),
            ]
        )

        let built = RequestReplay.makeURLRequest(from: request)
        let value = try #require(built.value(forHTTPHeaderField: "X-Trace"))
        #expect(value.contains("one"))
        #expect(value.contains("two"))
    }

    @Test("fast replay rejects CONNECT tunnels and WebSocket sessions")
    func unsupportedTransportsRejected() {
        let http = TestFixtures.makeTransaction(method: "GET")
        let connect = TestFixtures.makeTransaction(method: "CONNECT")
        let webSocket = TestFixtures.makeWebSocketTransaction()

        #expect(MainContentCoordinator.canReplay(http))
        #expect(!MainContentCoordinator.canReplay(connect))
        #expect(!MainContentCoordinator.canReplay(webSocket))
    }

    @Test("fast replay results become their own session row attributed to Rockxy")
    func replayResultBecomesSessionRow() throws {
        let original = TestFixtures.makeTransaction(method: "POST", url: "http://staging.example.com/api/login")
        original.clientApp = "curl"
        original.request = HTTPRequestData(
            method: "POST",
            url: try #require(URL(string: "http://staging.example.com/api/login")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "X-Trace", value: "t1")],
            body: Data("{\"user\":\"stephen\"}".utf8),
            contentType: .json,
            captureContext: TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 7)
        )
        let response = HTTPResponseData(
            statusCode: 201,
            statusMessage: "Created",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data("{}".utf8),
            contentType: .json
        )
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let replay = MainContentCoordinator.makeReplayTransaction(
            from: original,
            response: response,
            startedAt: startedAt,
            state: .completed,
            now: startedAt.addingTimeInterval(0.25)
        )

        #expect(replay.id != original.id)
        #expect(replay.timestamp == startedAt)
        #expect(replay.state == .completed)
        #expect(replay.response?.statusCode == 201)
        #expect(replay.request.method == "POST")
        #expect(replay.request.url == original.request.url)
        #expect(replay.request.headers.map(\.value) == ["t1"])
        #expect(replay.request.body == original.request.body)
        // The stale Project context must not travel with the copy or the row is dropped.
        #expect(replay.captureContext == nil)
        #expect(replay.clientApp == RockxyIdentity.current.displayName)
        #expect(replay.timingInfo?.totalDuration == 0.25)

        let failed = MainContentCoordinator.makeReplayTransaction(
            from: original,
            response: nil,
            startedAt: startedAt,
            state: .failed
        )
        #expect(failed.state == .failed)
        #expect(failed.response == nil)
    }

    @Test("plain http replays are not blocked by App Transport Security")
    func plainHTTPAllowedByATS() throws {
        let plist = try #require(Bundle.main.infoDictionary)
        let ats = try #require(plist["NSAppTransportSecurity"] as? [String: Any])
        #expect(ats["NSAllowsArbitraryLoads"] as? Bool == true)
    }
}
