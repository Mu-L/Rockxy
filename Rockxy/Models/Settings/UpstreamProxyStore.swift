import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Observation
import os

// MARK: - UpstreamProxyCredentialStorage

protocol UpstreamProxyCredentialStorage: Sendable {
    func save(_ credentials: UpstreamProxyCredentials) throws
    func load() throws -> UpstreamProxyCredentials?
    func delete() throws
}

// MARK: - KeychainUpstreamProxyCredentialStorage

struct KeychainUpstreamProxyCredentialStorage: UpstreamProxyCredentialStorage {
    // MARK: Internal

    func save(_ credentials: UpstreamProxyCredentials) throws {
        let payload = CredentialPayload(username: credentials.username, password: credentials.password)
        let data = try JSONEncoder().encode(payload)
        try KeychainHelper.saveSecureData(data, service: Self.service, account: Self.account)
    }

    func load() throws -> UpstreamProxyCredentials? {
        guard let data = try KeychainHelper.loadSecureData(service: Self.service, account: Self.account) else {
            return nil
        }
        let payload = try JSONDecoder().decode(CredentialPayload.self, from: data)
        return UpstreamProxyCredentials(username: payload.username, password: payload.password)
    }

    func delete() throws {
        try KeychainHelper.deleteSecureData(service: Self.service, account: Self.account)
    }

    // MARK: Private

    private struct CredentialPayload: Codable {
        let username: String
        let password: String
    }

    private static let service = "\(RockxyIdentity.current.defaultsPrefix).upstreamProxy"
    private static let account = "default"
}

// MARK: - UpstreamProxyStore

@MainActor @Observable
final class UpstreamProxyStore {
    // MARK: Lifecycle

    init(
        policy: any AppPolicy = DefaultAppPolicy(),
        userDefaults: UserDefaults = .standard,
        credentialStorage: any UpstreamProxyCredentialStorage = KeychainUpstreamProxyCredentialStorage(),
        testTarget: UpstreamProxyTestTarget = .default
    ) {
        self.policy = policy
        self.userDefaults = userDefaults
        self.credentialStorage = credentialStorage
        self.testTarget = testTarget
        self.configuration = Self.loadConfiguration(from: userDefaults)
        rebuildCache()
    }

    // MARK: Internal

    struct UpstreamProxyTestTarget: Equatable {
        static let `default` = UpstreamProxyTestTarget(host: "example.com", port: 80)

        let host: String
        let port: Int
    }

    static let shared = UpstreamProxyStore()

    private(set) var configuration: UpstreamProxyConfiguration

    var canSelectSOCKS5: Bool {
        policy.upstreamProxyAllowsSOCKS5
    }

    var canEnableAuthentication: Bool {
        policy.upstreamProxyAllowsAuthentication
    }

    var canAddBypassEntry: Bool {
        bypassEntriesUsed < bypassEntriesLimit
    }

    var bypassEntriesUsed: Int {
        configuration.bypassHostPatterns.count
    }

    var bypassEntriesLimit: Int {
        policy.maxUpstreamProxyBypassEntries
    }

    func storedCredentialUsername() -> String? {
        do {
            return try credentialStorage.load()?.username
        } catch {
            return nil
        }
    }

    func saveConfiguration(
        _ newConfiguration: UpstreamProxyConfiguration,
        credentials suppliedCredentials: UpstreamProxyCredentials? = nil
    )
        throws
    {
        let resolvedCredentials = try suppliedCredentials ??
            (newConfiguration.hasCredentials ? credentialStorage.load() : nil)
        if newConfiguration.hasCredentials, resolvedCredentials == nil {
            throw UpstreamProxyStoreError.credentialsUnavailable
        }
        try enforcePolicy(for: newConfiguration, credentials: resolvedCredentials)
        try newConfiguration.validate(
            credentials: resolvedCredentials,
            bypassEntryLimit: policy.maxUpstreamProxyBypassEntries
        )

        var persisted = normalized(newConfiguration, credentials: resolvedCredentials)
        if let suppliedCredentials {
            try credentialStorage.save(suppliedCredentials)
            persisted.hasCredentials = true
            persisted.username = suppliedCredentials.username
        } else if !persisted.hasCredentials {
            try credentialStorage.delete()
            persisted.username = nil
        }

        try persist(persisted)
        Self.logger.info("Upstream Proxy configuration updated")
    }

    func disable() throws {
        try setEnabled(false)
    }

    func setEnabled(_ isEnabled: Bool) throws {
        var updated = configuration
        updated.isEnabled = isEnabled
        if isEnabled {
            try saveConfiguration(updated)
        } else {
            try persist(updated)
            Self.logger.info("Upstream Proxy disabled")
        }
    }

    nonisolated func resolvedSnapshot() -> UpstreamProxyResolvedConfiguration? {
        lock.lock()
        let snapshot = cachedResolvedConfiguration
        lock.unlock()
        return snapshot
    }

    func testConnection() async -> Result<UpstreamProxyTestResult, UpstreamProxyError> {
        guard configuration.isEnabled else {
            return .failure(.invalidConfiguration(String(
                localized: "Upstream Proxy is disabled.",
                bundle: RockxyLocalization.bundle
            )))
        }
        return await testConnection(configuration: configuration)
    }

    func testConnection(
        configuration draftConfiguration: UpstreamProxyConfiguration,
        credentials suppliedCredentials: UpstreamProxyCredentials? = nil
    )
        async -> Result<UpstreamProxyTestResult, UpstreamProxyError>
    {
        do {
            var testConfiguration = draftConfiguration
            testConfiguration.isEnabled = true
            let resolvedCredentials = try suppliedCredentials ??
                (testConfiguration.hasCredentials ? credentialStorage.load() : nil)
            if testConfiguration.hasCredentials, resolvedCredentials == nil {
                throw UpstreamProxyStoreError.credentialsUnavailable
            }
            try enforcePolicy(for: testConfiguration, credentials: resolvedCredentials)
            try testConfiguration.validate(
                credentials: resolvedCredentials,
                bypassEntryLimit: policy.maxUpstreamProxyBypassEntries
            )
            let normalizedConfiguration = normalized(
                testConfiguration,
                credentials: resolvedCredentials
            )
            let snapshot = reachabilitySnapshot(from: UpstreamProxyResolvedConfiguration(
                configuration: normalizedConfiguration,
                credentials: normalizedConfiguration.hasCredentials ? resolvedCredentials : nil,
                allowsSOCKS5: policy.upstreamProxyAllowsSOCKS5
            ))
            return await testConnection(using: snapshot)
        } catch {
            return .failure(.invalidConfiguration(error.localizedDescription))
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "UpstreamProxy")
    private static let userDefaultsKey = "upstreamProxy.config.v1"

    private let policy: any AppPolicy
    private let userDefaults: UserDefaults
    private let credentialStorage: any UpstreamProxyCredentialStorage
    private let testTarget: UpstreamProxyTestTarget
    private let lock = NSLock()
    nonisolated(unsafe) private var cachedResolvedConfiguration: UpstreamProxyResolvedConfiguration?

    private static func loadConfiguration(from userDefaults: UserDefaults) -> UpstreamProxyConfiguration {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let configuration = try? JSONDecoder().decode(UpstreamProxyConfiguration.self, from: data) else
        {
            return .disabled
        }
        return configuration
    }

    private func testConnection(
        using snapshot: UpstreamProxyResolvedConfiguration?
    )
        async -> Result<UpstreamProxyTestResult, UpstreamProxyError>
    {
        let start = ContinuousClock.now
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            Task {
                try? await group.shutdownGracefully()
            }
        }

        do {
            let routeCapture = PACRouteCapture()
            // A 443 target exercises the CONNECT handshake; any other port is a plain-HTTP
            // target that HTTP proxies serve in absolute form, so the probe sends a real GET
            // and waits for the proxy's reply instead of trusting a bare TCP connect.
            let targetScheme = testTarget.port == 443 ? "https" : "http"
            let probe = UpstreamProxyProbeResponseHandler()
            let channel = try await UpstreamProxyConnector.connect(
                eventLoop: group.next(),
                targetScheme: targetScheme,
                targetHost: testTarget.host,
                targetPort: testTarget.port,
                configuration: snapshot,
                timeout: ProxyTimeouts.upstreamConnect,
                pacResolver: { eventLoop, pacURL, targetScheme, targetHost, targetPort in
                    UpstreamPACResolver.resolve(
                        eventLoop: eventLoop,
                        pacURL: pacURL,
                        targetScheme: targetScheme,
                        targetHost: targetHost,
                        targetPort: targetPort
                    ).map { route in
                        routeCapture.store(route)
                        return route
                    }
                }
            ) { channel in
                guard targetScheme == "http" else {
                    return channel.eventLoop.makeSucceededVoidFuture()
                }
                return channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(probe)
                }
            }.get()
            if targetScheme == "http" {
                try await Self.sendProbeRequest(
                    on: channel,
                    host: testTarget.host,
                    port: testTarget.port,
                    probe: probe
                )
            }
            try? await channel.close().get()
            let duration = start.duration(to: ContinuousClock.now)
            return .success(UpstreamProxyTestResult(
                targetHost: testTarget.host,
                targetPort: testTarget.port,
                negotiatedType: snapshot?.configuration.type,
                duration: duration,
                resolvedPACRoute: routeCapture.route()
            ))
        } catch let error as UpstreamProxyError {
            return .failure(error)
        } catch {
            return .failure(.invalidConfiguration(error.localizedDescription))
        }
    }

    /// Sends `GET /` to the test target through the freshly connected channel and waits for a
    /// response head. Any status counts: the point is that the route (direct or via the proxy)
    /// speaks HTTP back, which a plain TCP connect to the proxy cannot show.
    private static func sendProbeRequest(
        on channel: Channel,
        host: String,
        port: Int,
        probe: UpstreamProxyProbeResponseHandler
    ) async throws {
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: port == 80 ? host : "\(host):\(port)")
        headers.add(name: "Connection", value: "close")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/", headers: headers)
        channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        try await channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil))).get()

        let timeout = channel.eventLoop.scheduleTask(in: ProxyTimeouts.upstreamHandshake) {
            probe.fail(UpstreamProxyError.timeout)
        }
        defer { timeout.cancel() }
        _ = try await probe.responseStatus(on: channel.eventLoop).get()
    }

    private func enforcePolicy(
        for configuration: UpstreamProxyConfiguration,
        credentials: UpstreamProxyCredentials?
    )
        throws
    {
        if configuration.type == .socks5, !policy.upstreamProxyAllowsSOCKS5 {
            throw AppPolicyViolation.upstreamProxySOCKS5Unavailable
        }
        if configuration.hasCredentials || credentials != nil, !policy.upstreamProxyAllowsAuthentication {
            throw AppPolicyViolation.upstreamProxyAuthenticationUnavailable
        }
        if configuration.bypassHostPatterns.count > policy.maxUpstreamProxyBypassEntries {
            throw AppPolicyViolation.upstreamProxyBypassEntryLimitReached(
                limit: policy.maxUpstreamProxyBypassEntries
            )
        }
    }

    private func normalized(
        _ configuration: UpstreamProxyConfiguration,
        credentials: UpstreamProxyCredentials?
    )
        -> UpstreamProxyConfiguration
    {
        var result = configuration
        result.host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
        result.pacURL = configuration.pacURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = credentials?.username ?? configuration.username
        result.hasCredentials = credentials != nil || configuration.hasCredentials
        result.bypassHostPatterns = configuration.bypassHostPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return result
    }

    private func reachabilitySnapshot(
        from snapshot: UpstreamProxyResolvedConfiguration
    )
        -> UpstreamProxyResolvedConfiguration
    {
        var configuration = snapshot.configuration
        configuration.bypassHostPatterns = []
        configuration.bypassLocalhost = false
        return UpstreamProxyResolvedConfiguration(
            configuration: configuration,
            credentials: snapshot.credentials,
            allowsSOCKS5: snapshot.allowsSOCKS5
        )
    }

    private func persist(_ persisted: UpstreamProxyConfiguration) throws {
        let data = try JSONEncoder().encode(persisted)
        userDefaults.set(data, forKey: Self.userDefaultsKey)
        configuration = persisted
        rebuildCache()
        NotificationCenter.default.post(name: .upstreamProxyConfigurationDidChange, object: self)
    }

    private func rebuildCache() {
        let credentials = try? credentialStorage.load()
        let resolved = UpstreamProxyResolvedConfiguration(
            configuration: configuration,
            credentials: configuration.hasCredentials ? credentials : nil,
            allowsSOCKS5: policy.upstreamProxyAllowsSOCKS5
        )
        lock.lock()
        cachedResolvedConfiguration = resolved
        lock.unlock()
    }
}

// MARK: - UpstreamProxyStoreError

enum UpstreamProxyStoreError: LocalizedError {
    case credentialsUnavailable

    // MARK: Internal

    var errorDescription: String? {
        String(
            localized:
            "Saved upstream proxy credentials are unavailable. Enter the username and password again.",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - PACRouteCapture

private final class PACRouteCapture: @unchecked Sendable {
    // MARK: Internal

    func store(_ route: UpstreamPACRoute) {
        lock.lock()
        capturedRoute = route
        lock.unlock()
    }

    func route() -> UpstreamPACRoute? {
        lock.lock()
        let snapshot = capturedRoute
        lock.unlock()
        return snapshot
    }

    // MARK: Private

    private let lock = NSLock()
    private var capturedRoute: UpstreamPACRoute?
}

// MARK: - UpstreamProxyProbeResponseHandler

/// Completes once the first response head arrives on the probe channel.
final class UpstreamProxyProbeResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    func responseStatus(on eventLoop: EventLoop) -> EventLoopFuture<Int> {
        lock.lock()
        defer { lock.unlock() }
        if let promise {
            return promise.futureResult
        }
        let created = eventLoop.makePromise(of: Int.self)
        promise = created
        if let outcome {
            switch outcome {
            case let .success(status): created.succeed(status)
            case let .failure(error): created.fail(error)
            }
        }
        return created.futureResult
    }

    func fail(_ error: Error) {
        settle(.failure(error))
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case let .head(head) = unwrapInboundIn(data) {
            settle(.success(Int(head.status.code)))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        settle(.failure(error))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        settle(.failure(UpstreamProxyError.malformedResponse))
    }

    private let lock = NSLock()
    private var promise: EventLoopPromise<Int>?
    private var outcome: Result<Int, Error>?

    private func settle(_ result: Result<Int, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == nil else {
            return
        }
        outcome = result
        guard let promise else {
            return
        }
        switch result {
        case let .success(status): promise.succeed(status)
        case let .failure(error): promise.fail(error)
        }
    }
}
