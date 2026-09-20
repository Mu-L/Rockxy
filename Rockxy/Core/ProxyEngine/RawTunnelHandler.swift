import NIOCore
import os

private let rawTunnelLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "TLSInterceptHandler"
)

// MARK: - RawTunnelHandler

/// Bidirectional byte-level relay between two channels. Used as a fallback when TLS
/// interception cannot be performed (cert generation failure, SSL pinning). Each side
/// of the tunnel gets its own RawTunnelHandler pointing at the peer channel.
final class RawTunnelHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(peerChannel: Channel) {
        self.peerChannel = peerChannel
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    nonisolated func handlerAdded(context: ChannelHandlerContext) {
        resetIdleTimeout(context: context)
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = nil
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        resetIdleTimeout(context: context)
        let buffer = unwrapInboundIn(data)
        peerChannel.writeAndFlush(NIOAny(buffer), promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
        context.close(promise: nil)
    }

    // MARK: Private

    private static let idleTimeoutDuration: TimeAmount = .seconds(60)

    private let peerChannel: Channel
    private var idleTimeout: Scheduled<Void>?

    nonisolated private func resetIdleTimeout(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = context.eventLoop.scheduleTask(in: Self.idleTimeoutDuration) {
            rawTunnelLogger.debug("Raw tunnel idle timeout, closing")
            context.close(promise: nil)
        }
    }
}
