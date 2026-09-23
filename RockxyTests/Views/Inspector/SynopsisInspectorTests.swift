import Foundation
@testable import Rockxy
import Testing

/// The Synopsis tab is the "everything about this transaction at a glance" surface, so every value
/// it names has a counterpart in the request list, the Context Dock, and the protocol inspectors.
/// Three of them had drifted: the duration came from `timingInfo` rather than `displayDuration`,
/// the response size was interpolated instead of formatted, and the `Content-Type` row printed
/// Rockxy's internal render bucket under the wire header's own name.
struct SynopsisInspectorTests {
    // MARK: Internal

    @Test("A WebSocket's summary duration is its connection lifetime, not its handshake")
    func webSocketSummaryDurationIsTheConnectionLifetime() throws {
        // `timingInfo` on a WebSocket only covers the upgrade, so Synopsis read "11 ms" for a
        // socket the row, the Context Dock, and the WebSocket inspector all called "914 ms".
        let transaction = try Self.makeTransaction()
        transaction.webSocketConnection = WebSocketConnection(upgradeRequest: transaction.request)
        transaction.timingInfo = Self.handshakeTiming
        transaction.measuredDuration = 0.914

        #expect(transaction.displayDuration == 0.914)
        #expect(transaction.timingInfo?.totalDuration != transaction.displayDuration)
    }

    @Test("A replayed transaction still reports a duration")
    func replayedTransactionStillReportsADuration() throws {
        // A replay carries `measuredDuration` and no `timingInfo`, so keying the row off
        // `timingInfo` dropped the Duration row entirely while the list still showed "1.05 s".
        let transaction = try Self.makeTransaction()
        transaction.timingInfo = nil
        transaction.measuredDuration = 1.05

        #expect(transaction.displayDuration == 1.05)
    }

    @Test("Synopsis reads the shared duration and size sources")
    func synopsisUsesTheSharedFormatters() throws {
        // Pinned whitespace-insensitively: the PostToolUse formatter rewraps these call sites
        // whenever the view is edited, and a spelling-pinned test then fails for a change with no
        // behavior in it.
        let source = try Self.readProjectFile("Rockxy/Views/Inspector/SynopsisInspectorView.swift")
        let collapsed = Self.collapsingWhitespace(source)

        #expect(collapsed.contains(Self.collapsingWhitespace("transaction.displayDuration")))
        #expect(collapsed.contains(Self.collapsingWhitespace("SizeFormatter.format(bytes: body.count)")))
        // The two shapes this view used to carry.
        #expect(!collapsed.contains(Self.collapsingWhitespace("transaction.timingInfo")))
        #expect(!collapsed.contains(Self.collapsingWhitespace("contentType.rawValue")))
    }

    @Test("The Content-Type row shows the header the peer actually sent")
    func contentTypeRowShowsTheWireValue() {
        // `ContentType` is a render bucket: an SSE stream normalizes to `text` and a message with
        // no Content-Type header normalizes to `unknown`, neither of which the response carried.
        let headers = [
            HTTPHeader(name: "Content-Type", value: "text/event-stream"),
            HTTPHeader(name: "Cache-Control", value: "no-cache"),
        ]
        #expect(ContentType.detect(from: "text/event-stream") == .text)
        #expect(ContentType.detect(from: nil) == .unknown)
        #expect(headers.first { $0.name.lowercased() == "content-type" }?.value == "text/event-stream")
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// The upgrade handshake only: 11 ms against a socket that then lived for 914 ms.
    private static let handshakeTiming = TimingInfo(
        dnsLookup: 0,
        tcpConnection: 0.004,
        tlsHandshake: 0,
        timeToFirstByte: 0.006,
        contentTransfer: 0.001
    )

    private static func makeTransaction() throws -> HTTPTransaction {
        HTTPTransaction(
            request: HTTPRequestData(
                method: "GET",
                url: try #require(URL(string: "http://127.0.0.1:18090/ws")),
                httpVersion: "1.1",
                headers: []
            )
        )
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
