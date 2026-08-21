import NIOCore
import NIOEmbedded
import NIOWebSocket
@testable import Rockxy
import Testing

struct WebSocketFrameHandlerTests {
    @Test("Capture limit never interrupts the proxied WebSocket")
    func captureLimitKeepsRelayActive() throws {
        let request = TestFixtures.makeRequest(url: "wss://example.com/ws")
        let connection = WebSocketConnection(upgradeRequest: request)
        connection.stopCaptureAtLimit()
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel()
        let handler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let channel = EmbeddedChannel(handler: handler)
        try peer.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8_081)).wait()
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8_082)).wait()
        var payload = channel.allocator.buffer(capacity: 5)
        payload.writeString("hello")

        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: payload))

        let forwarded = try #require(try peer.readOutbound(as: WebSocketFrame.self))
        var forwardedPayload = forwarded.unmaskedData
        #expect(forwardedPayload.readString(length: 5) == "hello")
        #expect(channel.isActive)
        #expect(peer.isActive)
        #expect(connection.frames.isEmpty)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }
}
