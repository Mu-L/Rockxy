import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import os

// Defines `WebSocketFrameHandler`, which handles web socket frame flow in the proxy
// engine.

nonisolated(unsafe) private let wsLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "WebSocketFrameHandler"
)

// MARK: - WebSocketDetector

/// Detects WebSocket upgrade requests by inspecting HTTP headers per RFC 6455.
nonisolated enum WebSocketDetector {
    nonisolated static func isWebSocketUpgrade(headers: HTTPHeaders) -> Bool {
        let hasUpgrade = headers.contains(name: "Upgrade") &&
            headers["Upgrade"].contains(where: { $0.lowercased() == "websocket" })
        let hasConnection = headers.contains(name: "Connection") &&
            headers["Connection"].contains(where: { $0.lowercased().contains("upgrade") })
        return hasUpgrade && hasConnection
    }
}

// MARK: - WebSocketLifecycle

/// Delivers the terminal transaction and upstream-channel release exactly once even though
/// either half of a proxied WebSocket may observe channel inactivity first.
final class WebSocketLifecycle: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onChannelClosed: @escaping @Sendable () -> Void = {}
    ) {
        self.onTransactionComplete = onTransactionComplete
        self.onChannelClosed = onChannelClosed
    }

    // MARK: Internal

    func complete(_ transaction: HTTPTransaction) {
        guard claimTerminalState() else {
            return
        }
        // The session was delivered as `.active` when the upgrade completed and has been
        // observed by the UI since, so its terminal state is written on the main actor
        // before the closing delivery updates the existing row.
        Task { @MainActor in
            transaction.state = .completed
            transaction.webSocketFrameVersion += 1
        }
        onTransactionComplete(transaction)
        onChannelClosed()
    }

    func failSetup() {
        guard claimTerminalState() else {
            return
        }
        onChannelClosed()
    }

    // MARK: Private

    private let lock = NSLock()
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onChannelClosed: @Sendable () -> Void
    private var isComplete = false

    private func claimTerminalState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else {
            return false
        }
        isComplete = true
        return true
    }
}

// MARK: - WebSocketFrameHandler

/// Captures and relays WebSocket frames in one direction (client->server or server->client).
/// Each upgraded WebSocket connection uses two instances — one per direction — sharing
/// the same `WebSocketConnection` model to collect all frames for inspection.
final class WebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        direction: FrameDirection,
        peerChannel: Channel?,
        webSocketConnection: WebSocketConnection,
        parentTransaction: HTTPTransaction,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        lifecycle: WebSocketLifecycle? = nil
    ) {
        self.direction = direction
        self.peerChannel = peerChannel
        self.webSocketConnection = webSocketConnection
        self.parentTransaction = parentTransaction
        self.lifecycle = lifecycle ?? WebSocketLifecycle(onTransactionComplete: onTransactionComplete)
    }

    // MARK: Internal

    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        captureFrame(frame)
        forwardFrame(frame, context: context)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        wsLogger.error("WebSocket error (\(self.direction.rawValue)): \(error.localizedDescription)")
        peerChannel?.close(promise: nil)
        context.close(promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        peerChannel?.close(promise: nil)
        lifecycle.complete(parentTransaction)
    }

    // MARK: Private

    private let direction: FrameDirection
    private let peerChannel: Channel?
    private let webSocketConnection: WebSocketConnection
    private let lifecycle: WebSocketLifecycle
    private let parentTransaction: HTTPTransaction

    /// Unmasks the frame payload (WebSocket client frames are always masked per RFC 6455)
    /// and records it in the shared connection model before forwarding.
    nonisolated private func captureFrame(_ frame: WebSocketFrame) {
        guard !webSocketConnection.isCaptureLimitReached else {
            return
        }
        let opcode = mapOpcode(frame.opcode)
        var dataBuffer = frame.unmaskedData
        let payloadBytes = dataBuffer.readBytes(length: dataBuffer.readableBytes) ?? []
        let payload = Data(payloadBytes)

        guard payload.count <= ProxyLimits.maxWebSocketFrameSize else {
            webSocketConnection.stopCaptureAtLimit()
            notifyTransactionUpdate()
            wsLogger.warning(
                "WebSocket frame exceeds capture limit; capture stopped while relay remains active"
            )
            return
        }
        let frameData = WebSocketFrameData(
            direction: direction,
            opcode: opcode,
            payload: payload,
            isFinal: frame.fin
        )

        guard webSocketConnection.addFrame(
            frameData,
            maximumTotalPayloadSize: ProxyLimits.maxWebSocketConnectionSize,
            maximumFrameCount: ProxyLimits.maxWebSocketFrameCount
        ) else {
            notifyTransactionUpdate()
            wsLogger.warning(
                "WebSocket connection exceeds capture limits; capture stopped while relay remains active"
            )
            return
        }

        notifyTransactionUpdate()
    }

    nonisolated private func notifyTransactionUpdate() {
        let transaction = parentTransaction
        Task { @MainActor in
            transaction.webSocketFrameVersion += 1
        }
    }

    nonisolated private func forwardFrame(
        _ frame: WebSocketFrame,
        context: ChannelHandlerContext
    ) {
        guard let peer = peerChannel else {
            return
        }
        // NIO's decoder intentionally preserves the masked bytes and mask key. Its encoder,
        // however, expects unmasked application data and applies the key while writing. Passing
        // a decoded client frame through unchanged therefore masks the payload a second time and
        // puts plaintext on the wire. Normalize the payload before the peer encoder sees it,
        // while preserving the client's key in the client-to-server direction and never sending
        // a masked frame to a client.
        let forwardedFrame = WebSocketFrame(
            fin: frame.fin,
            rsv1: frame.rsv1,
            rsv2: frame.rsv2,
            rsv3: frame.rsv3,
            opcode: frame.opcode,
            maskKey: direction == .sent ? frame.maskKey : nil,
            data: frame.unmaskedData,
            extensionData: frame.unmaskedExtensionData
        )
        peer.writeAndFlush(NIOAny(forwardedFrame), promise: nil)
    }

    nonisolated private func mapOpcode(_ opcode: WebSocketOpcode) -> FrameOpcode {
        switch opcode {
        case .continuation: .continuation
        case .text: .text
        case .binary: .binary
        case .connectionClose: .connectionClose
        case .ping: .ping
        case .pong: .pong
        default: .binary
        }
    }
}

// MARK: - WebSocketPipelineConfigurator

/// Reconfigures both client and server channel pipelines for WebSocket frame-level
/// proxying after an HTTP upgrade handshake completes.
nonisolated enum WebSocketPipelineConfigurator {
    nonisolated static func upgradeToWebSocket(
        clientChannel: Channel,
        serverChannel: Channel,
        requestData: HTTPRequestData,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        lifecycle: WebSocketLifecycle? = nil
    )
        -> EventLoopFuture<Void>
    {
        let wsConnection = WebSocketConnection(upgradeRequest: requestData)
        let transaction = HTTPTransaction(
            request: requestData,
            state: .active,
            webSocketConnection: wsConnection
        )
        let lifecycle = lifecycle ?? WebSocketLifecycle(onTransactionComplete: onTransactionComplete)

        let clientHandler = WebSocketFrameHandler(
            direction: .sent,
            peerChannel: serverChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete,
            lifecycle: lifecycle
        )
        let serverHandler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: clientChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete,
            lifecycle: lifecycle
        )

        let clientFuture = ProxyPipeline.configureClientWebSocketPipeline(
            channel: clientChannel,
            handler: clientHandler
        )
        let serverFuture = ProxyPipeline.configureUpstreamWebSocketPipeline(
            channel: serverChannel,
            handler: serverHandler
        )

        // The accepted and upstream channels may live on different event loops.
        // Complete the combined transition on the client loop so callers can safely
        // chain this future from the flushed 101 response promise.
        return clientFuture.and(serverFuture.hop(to: clientChannel.eventLoop)).map { _ in
            // Deliver the open session now so the row appears while it is live and frames
            // render as they arrive; the closing delivery later updates the same row.
            onTransactionComplete(transaction)
        }
    }
}
