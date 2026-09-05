import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - BreakpointHarnessError

enum BreakpointHarnessError: Error, CustomStringConvertible {
    case noNetwork(URL, underlying: Error)
    case timeout(String)
    case socket(String)

    // MARK: Internal

    var description: String {
        switch self {
        case let .noNetwork(url, underlying):
            "No network response from \(url.absoluteString): \(underlying.localizedDescription)"
        case let .timeout(message):
            message
        case let .socket(message):
            message
        }
    }
}

// MARK: - BreakpointTestHarness

actor BreakpointTestHarness {
    // MARK: Lifecycle

    init(
        manager: BreakpointManager,
        ruleEngine: RuleEngine
    ) {
        self.manager = manager
        self.ruleEngine = ruleEngine
    }

    // MARK: Internal

    let manager: BreakpointManager
    let ruleEngine: RuleEngine

    static func start() async throws -> BreakpointTestHarness {
        let manager = await MainActor.run { BreakpointManager() }
        let engine = RuleEngine()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: engine)
        _ = try await harness.startProxy()
        return harness
    }

    static func dataWithRetry(
        from url: URL,
        session: URLSession = .shared
    )
        async throws -> (Data, URLResponse)
    {
        try await dataWithRetry(
            from: url,
            request: { requestURL in
                try await session.data(from: requestURL)
            }
        )
    }

    static func dataWithRetry(
        from url: URL,
        request: @escaping @Sendable (URL) async throws -> (Data, URLResponse)
    )
        async throws -> (Data, URLResponse)
    {
        do {
            return try await request(url)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCannotFindHost
               || (error as NSError).code == NSURLErrorDNSLookupFailed
            {
                try await Task.sleep(nanoseconds: 300_000_000)
                return try await request(url)
            }
            throw BreakpointHarnessError.noNetwork(url, underlying: error)
        }
    }

    func startProxy() async throws -> Int {
        if let proxyPort {
            return proxyPort
        }
        let port = try Self.findFreePort()
        let manager = manager
        let sink = captureSink
        let server = ProxyServer(
            configuration: ProxyConfiguration(port: port, listenAddress: "127.0.0.1", listenIPv6: false),
            ruleEngine: ruleEngine,
            onTransactionComplete: { transaction in
                Task { await sink.append(transaction) }
            },
            onBreakpointHit: { data in
                await manager.enqueueAndWait(data)
            }
        )
        try await server.start()
        proxyServer = server
        proxyPort = port
        return port
    }

    func stop() async {
        await stopProxyOnly()
        await MainActor.run {
            manager.resolveAll(decision: .cancel)
        }
    }

    func stopProxyOnly() async {
        await proxyServer?.stop()
        proxyServer = nil
        proxyPort = nil
    }

    func client() async throws -> URLSession {
        let port = try await startProxy()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": port,
        ]
        return URLSession(configuration: configuration)
    }

    func addRule(_ rule: ProxyRule) async {
        await ruleEngine.addRule(rule)
    }

    func clearRules() async {
        await ruleEngine.replaceAll([])
    }

    func setGlobalEnable(_ enabled: Bool) async {
        await ruleEngine.setBreakpointToolEnabled(enabled)
    }

    func awaitNextPause(timeout seconds: TimeInterval = 5) async throws -> PausedBreakpointItem {
        // A pause stays queued until this harness resolves it. Observe that durable state,
        // not a notification registered after checking it: that check/subscribe gap loses
        // a pause that arrives between the two and falsely times out on a populated queue.
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let item = await MainActor.run(body: { manager.pausedItems.first }) {
                return item
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw BreakpointHarnessError.timeout("Timed out waiting \(seconds)s for the next breakpoint pause.")
    }

    func editDraft(
        _ itemID: UUID,
        mutate: @MainActor @escaping (inout BreakpointRequestData) -> Void
    )
        async
    {
        await MainActor.run {
            manager.updateDraft(id: itemID, mutate)
        }
    }

    func resolve(_ itemID: UUID, decision: BreakpointDecision) async {
        await MainActor.run {
            manager.resolve(id: itemID, decision: decision)
        }
    }

    @MainActor
    func addTemplate(_ template: BreakpointTemplate, to store: BreakpointTemplateStore) {
        let created = store.addTemplate(kind: template.kind)
        store.updateTemplate(id: created.id, name: template.name, rawMessage: template.rawMessage)
    }

    @MainActor
    func clearTemplates(_ store: BreakpointTemplateStore) {
        for template in store.templates {
            store.deleteTemplate(id: template.id)
        }
    }

    func lastCapturedRow() async -> HTTPTransaction? {
        await captureSink.last()
    }

    func capturedRows() async -> [HTTPTransaction] {
        await captureSink.all()
    }

    // MARK: Private

    private let captureSink = CaptureSink()
    private var proxyServer: ProxyServer?
    private var proxyPort: Int?

    private static func findFreePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BreakpointHarnessError.socket("Unable to create socket.")
        }
        defer { close(fd) }

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
            throw BreakpointHarnessError.socket("Unable to bind test socket.")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw BreakpointHarnessError.socket("Unable to inspect test socket port.")
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - BreakpointRawHTTPClient

/// A minimal explicit-proxy client for lifecycle tests. Closing its descriptor sends a
/// real downstream disconnect to the proxy, unlike URLSession cancellation which may
/// retain a pooled connection after the request task has been cancelled.
final class BreakpointRawHTTPClient: @unchecked Sendable {
    // MARK: Lifecycle

    deinit {
        close()
    }

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    // MARK: Internal

    static func connect(proxyPort: Int, requestURL: URL) throws -> BreakpointRawHTTPClient {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BreakpointHarnessError.socket("Unable to create raw breakpoint client socket.")
        }

        var noSignal: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(proxyPort).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            Darwin.close(descriptor)
            throw BreakpointHarnessError.socket("Unable to connect raw breakpoint client to the proxy.")
        }

        let client = BreakpointRawHTTPClient(descriptor: descriptor)
        try client.sendRequest(to: requestURL)
        return client
    }

    func close() {
        lock.lock()
        let descriptor = self.descriptor
        self.descriptor = -1
        lock.unlock()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var descriptor: Int32

    private func sendRequest(to url: URL) throws {
        guard let host = url.host else {
            throw BreakpointHarnessError.socket("Raw breakpoint client received a URL without a host.")
        }
        let authority = url.port.map { "\(host):\($0)" } ?? host
        let request = "GET \(url.absoluteString) HTTP/1.1\r\nHost: \(authority)\r\nConnection: close\r\n\r\n"
        let bytes = Array(request.utf8)

        let sentAll = bytes.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else {
                return false
            }
            var sentCount = 0
            while sentCount < rawBuffer.count {
                let result = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sentCount),
                    rawBuffer.count - sentCount,
                    0
                )
                guard result > 0 else {
                    return false
                }
                sentCount += result
            }
            return true
        }
        guard sentAll else {
            close()
            throw BreakpointHarnessError.socket("Unable to send the raw breakpoint client request.")
        }
    }
}

// MARK: - BreakpointLocalHTTPServer

actor BreakpointLocalHTTPServer {
    // MARK: Internal

    static func start() async throws -> BreakpointLocalHTTPServer {
        let server = BreakpointLocalHTTPServer()
        try await server.start()
        return server
    }

    func url(_ path: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        guard let url = components.url else {
            preconditionFailure("Breakpoint local test server produced an invalid URL.")
        }
        return url
    }

    func matchingRule(_ path: String) -> String {
        "\(host):\(port)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func stop() async {
        let channel = serverChannel
        serverChannel = nil
        if let channel {
            try? await channel.close().get()
        }
        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        eventLoopGroup = nil
        port = 0
    }

    // MARK: Private

    private let host = "127.0.0.1"
    private var port = 0
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(.backlog, value: 16)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(BreakpointLocalHTTPHandler())
                    }
                }
                .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: host, port: 0)
                .get()

            guard let boundPort = channel.localAddress?.port else {
                try await channel.close().get()
                throw BreakpointHarnessError.socket("Unable to inspect local test server port.")
            }
            serverChannel = channel
            port = boundPort
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw error
        }
    }
}

// MARK: - BreakpointLocalHTTPHandler

private final class BreakpointLocalHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            requestHead = head
        case .body:
            break
        case .end:
            respond(context: context)
            requestHead = nil
        }
    }

    // MARK: Private

    private var requestHead: HTTPRequestHead?

    private func respond(context: ChannelHandlerContext) {
        let head = requestHead
        let path = URLComponents(string: head?.uri ?? "/")?.path ?? "/"
        let response = response(for: path, requestHeaders: head?.headers ?? HTTPHeaders())
        var headers = response.headers
        headers.add(name: "Content-Length", value: "\(response.body.readableBytes)")
        headers.add(name: "Connection", value: "close")

        let responseHead = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(response.body))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func response(for path: String, requestHeaders: HTTPHeaders) -> (
        status: HTTPResponseStatus,
        headers: HTTPHeaders,
        body: ByteBuffer
    ) {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        var headers = HTTPHeaders()

        switch path {
        case "/headers":
            headers.add(name: "Content-Type", value: "application/json")
            let echoedHeaders = Dictionary(
                requestHeaders.map { ($0.name, $0.value) },
                uniquingKeysWith: { _, latest in latest }
            )
            let payload = (try? JSONSerialization.data(withJSONObject: ["headers": echoedHeaders])) ?? Data("{}".utf8)
            buffer.writeBytes(payload)
            return (.ok, headers, buffer)
        case "/status/401":
            headers.add(name: "Content-Type", value: "text/plain")
            buffer.writeString("unauthorized")
            return (.unauthorized, headers, buffer)
        case "/delay/1",
             "/get":
            headers.add(name: "Content-Type", value: "application/json")
            buffer.writeString(#"{"ok":true}"#)
            return (.ok, headers, buffer)
        default:
            headers.add(name: "Content-Type", value: "text/plain")
            buffer.writeString("not found")
            return (.notFound, headers, buffer)
        }
    }
}

// MARK: - CaptureSink

private actor CaptureSink {
    // MARK: Internal

    func append(_ transaction: HTTPTransaction) {
        transactions.append(transaction)
    }

    func last() -> HTTPTransaction? {
        transactions.last
    }

    func all() -> [HTTPTransaction] {
        transactions
    }

    // MARK: Private

    private var transactions: [HTTPTransaction] = []
}

extension ProxyRule {
    static func breakpointTest(
        name: String = "Breakpoint Test Rule",
        matchingRule: String,
        method: HTTPMethodFilter = .any,
        matchType: RuleMatchType = .wildcard,
        phases: BreakpointRulePhase = .both,
        includeSubpaths: Bool = false,
        isEnabled: Bool = true
    )
        -> ProxyRule
    {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(
                urlPattern: RulePatternBuilder.regexSource(
                    rawPattern: matchingRule,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths
                ),
                method: method.methodValue
            ),
            action: .breakpoint(phase: phases)
        )
    }
}

extension BreakpointRequestData {
    static func test(
        method: String = "GET",
        url: String = "https://httpbin.org/get",
        headers: [EditableHeader] = [],
        body: String = "",
        statusCode: Int = 200,
        phase: BreakpointPhase = .request
    )
        -> BreakpointRequestData
    {
        BreakpointRequestData(
            method: method,
            url: url,
            headers: headers,
            body: body,
            statusCode: statusCode,
            phase: phase
        )
    }
}

// MARK: - BreakpointRuleStateBackup

struct BreakpointRuleStateBackup {
    let diskData: Data?
    let engineRules: [ProxyRule]
    let breakpointToolEnabled: Bool?
}

// MARK: - BreakpointRuleTestIsolation

enum BreakpointRuleTestIsolation {
    // MARK: Internal

    static func withSharedRuleState(_ body: () async throws -> Void) async rethrows {
        await RuleTestLock.shared.acquire()
        let backup = await backup()
        do {
            try await body()
            await restore(backup)
            await RuleTestLock.shared.release()
        } catch {
            await restore(backup)
            await RuleTestLock.shared.release()
            throw error
        }
    }

    // MARK: Private

    private static let breakpointToolEnabledKey = "breakpointToolEnabled"

    private static let rulesPath = RockxyIdentity.current.appSupportPath(TestIdentity.rulesPathComponent)

    private static func backup() async -> BreakpointRuleStateBackup {
        await BreakpointRuleStateBackup(
            diskData: try? Data(contentsOf: rulesPath),
            engineRules: RuleEngine.shared.allRules,
            breakpointToolEnabled: UserDefaults.standard.object(forKey: breakpointToolEnabledKey) as? Bool
        )
    }

    private static func restore(_ backup: BreakpointRuleStateBackup) async {
        if let diskData = backup.diskData {
            try? FileManager.default.createDirectory(
                at: rulesPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? diskData.write(to: rulesPath)
        } else {
            try? FileManager.default.removeItem(at: rulesPath)
        }
        if let breakpointToolEnabled = backup.breakpointToolEnabled {
            UserDefaults.standard.set(breakpointToolEnabled, forKey: breakpointToolEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: breakpointToolEnabledKey)
        }
        await RuleEngine.shared.replaceAll(backup.engineRules)
        await RuleEngine.shared.setBreakpointToolEnabled(backup.breakpointToolEnabled ?? true)
    }
}
