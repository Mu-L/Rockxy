import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - ProxyLoopGuardTests

/// A request aimed at Rockxy's own listener must be refused at the first hop. Before the
/// guard, one such request bounced through the proxy until the per-destination connection
/// cap tripped, leaving dozens of 503 rows behind a single client call.
struct ProxyLoopGuardTests {
    @Test("Own listener is recognised by loopback names, the accepting address, and LAN addresses")
    func detectsOwnListener() {
        let guardPort = 9_090
        for host in ["localhost", "127.0.0.1", "127.1.2.3", "::1", "[::1]", "api.localhost", "0.0.0.0"] {
            #expect(ProxyLoopGuard.targetsOwnListener(
                host: host, port: guardPort, proxyPort: guardPort, proxyHost: nil, localAddresses: []
            ), "\(host) should be treated as the proxy itself")
        }
        #expect(ProxyLoopGuard.targetsOwnListener(
            host: "192.168.1.20", port: guardPort, proxyPort: guardPort, proxyHost: "192.168.1.20", localAddresses: []
        ))
        #expect(ProxyLoopGuard.targetsOwnListener(
            host: "10.0.0.7", port: guardPort, proxyPort: guardPort, proxyHost: nil, localAddresses: ["10.0.0.7"]
        ))
    }

    @Test("Other ports and other hosts are never treated as a loop")
    func ignoresOtherDestinations() {
        #expect(!ProxyLoopGuard.targetsOwnListener(
            host: "127.0.0.1", port: 18_080, proxyPort: 9_090, proxyHost: "127.0.0.1", localAddresses: []
        ))
        #expect(!ProxyLoopGuard.targetsOwnListener(
            host: "api.example.com", port: 9_090, proxyPort: 9_090, proxyHost: "127.0.0.1", localAddresses: ["10.0.0.7"]
        ))
        #expect(!ProxyLoopGuard.targetsOwnListener(
            host: "", port: 9_090, proxyPort: 9_090, proxyHost: nil, localAddresses: []
        ))
    }

    @Test("A live proxy answers a self-targeted request with 508 and records exactly one row")
    func liveProxyRefusesSelfRequest() async throws {
        let engine = RuleEngine()
        let port = try Self.reserveLoopbackPort()
        let recorder = TransactionRecorder()
        let proxy = ProxyServer(
            configuration: ProxyConfiguration(port: port, listenAddress: "127.0.0.1", listenIPv6: false),
            ruleEngine: engine,
            onTransactionComplete: { recorder.record($0) }
        )
        try await proxy.start()
        defer { Task { await proxy.stop() } }

        let status = try await Self.sendAbsoluteForm(
            "http://127.0.0.1:\(port)/loop",
            hostHeader: "127.0.0.1:\(port)",
            proxyPort: port
        )

        #expect(status == 508)
        try await Task.sleep(for: .milliseconds(300))
        let recorded = recorder.snapshot()
        #expect(recorded.count == 1)
        #expect(recorded.first?.response?.statusCode == 508)
        #expect(recorded.first?.state == .failed)
    }

    // MARK: Private

    private final class TransactionRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var transactions: [HTTPTransaction] = []

        func record(_ transaction: HTTPTransaction) {
            lock.lock()
            transactions.append(transaction)
            lock.unlock()
        }

        func snapshot() -> [HTTPTransaction] {
            lock.lock()
            defer { lock.unlock() }
            return transactions
        }
    }

    private static func sendAbsoluteForm(_ absoluteURL: String, hostHeader: String, proxyPort: Int) async throws -> Int {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { Task { try? await group.shutdownGracefully() } }
        let promise = group.next().makePromise(of: Int.self)
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: hostHeader)
        headers.add(name: "Connection", value: "close")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: absoluteURL, headers: headers)

        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(StatusOnlyHandler(requestHead: head, promise: promise))
                }
            }
            .connect(host: "127.0.0.1", port: proxyPort)
            .get()
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(12)) {
            promise.fail(LoopTestError.timeout)
        }
        defer {
            timeout.cancel()
            channel.close(promise: nil)
        }
        return try await promise.futureResult.get()
    }

    private static func reserveLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LoopTestError.socket
        }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw LoopTestError.socket
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw LoopTestError.socket
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    private enum LoopTestError: Error {
        case socket
        case timeout
    }
}

// MARK: - StatusOnlyHandler

private final class StatusOnlyHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    init(requestHead: HTTPRequestHead, promise: EventLoopPromise<Int>) {
        self.requestHead = requestHead
        self.promise = promise
    }

    func channelActive(context: ChannelHandlerContext) {
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case let .head(head) = unwrapInboundIn(data) {
            promise.succeed(Int(head.status.code))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    private let requestHead: HTTPRequestHead
    private let promise: EventLoopPromise<Int>
}
