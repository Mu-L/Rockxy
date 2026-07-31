import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - UpstreamProxyStoreTests

@MainActor
@Suite("UpstreamProxyStore")
struct UpstreamProxyStoreTests {
    // MARK: Internal

    @Test("DefaultAppPolicy predicates expose Community caps")
    func defaultPredicates() {
        let store = makeStore()
        #expect(!store.canSelectSOCKS5)
        #expect(!store.canEnableAuthentication)
        #expect(store.bypassEntriesLimit == 3)
        #expect(store.canAddBypassEntry)
    }

    @Test("rejects SOCKS5 and auth under DefaultAppPolicy")
    func policyRefusals() throws {
        let store = makeStore()
        let socks = UpstreamProxyConfiguration(isEnabled: true, type: .socks5, host: "proxy.example.com")
        #expect(throws: AppPolicyViolation.upstreamProxySOCKS5Unavailable) {
            try store.saveConfiguration(socks)
        }

        let auth = UpstreamProxyConfiguration(isEnabled: true, host: "proxy.example.com", hasCredentials: true)
        #expect(throws: AppPolicyViolation.upstreamProxyAuthenticationUnavailable) {
            try store.saveConfiguration(auth, credentials: UpstreamProxyCredentials(username: "u", password: "p"))
        }
    }

    @Test("rejects bypass entries above policy cap")
    func bypassCap() {
        let store = makeStore()
        let config = UpstreamProxyConfiguration(
            isEnabled: true,
            host: "proxy.example.com",
            bypassHostPatterns: ["a.com", "b.com", "c.com", "d.com"]
        )
        #expect(throws: AppPolicyViolation.upstreamProxyBypassEntryLimitReached(limit: 3)) {
            try store.saveConfiguration(config)
        }
    }

    @Test("setEnabled persists toggle state and posts notification")
    func setEnabledPersistsToggleState() throws {
        let defaults = makeDefaults()
        let store = UpstreamProxyStore(userDefaults: defaults, credentialStorage: InMemoryCredentials())
        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: false,
            type: .http,
            host: "proxy.example.com"
        ))

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try store.setEnabled(true)
        #expect(store.configuration.isEnabled)

        try store.setEnabled(false)
        #expect(!store.configuration.isEnabled)
        #expect(notificationCount == 2)
    }

    @Test("setEnabled validates configuration before turning on")
    func setEnabledValidatesBeforeTurningOn() {
        let store = makeStore()

        #expect(throws: UpstreamProxyConfigurationError.hostInvalid) {
            try store.setEnabled(true)
        }
        #expect(!store.configuration.isEnabled)
    }

    @Test("round-trips persistence and posts notification")
    func persistenceAndNotification() throws {
        let defaults = makeDefaults()
        let credentials = InMemoryCredentials()
        let store = UpstreamProxyStore(userDefaults: defaults, credentialStorage: credentials)
        var didNotify = false
        let observer = NotificationCenter.default.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: store,
            queue: nil
        ) { _ in
            didNotify = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let config = UpstreamProxyConfiguration(
            isEnabled: true,
            type: .http,
            host: "proxy.example.com",
            port: 8_080,
            bypassHostPatterns: ["*.internal"]
        )
        try store.saveConfiguration(config)

        let reloaded = UpstreamProxyStore(userDefaults: defaults, credentialStorage: credentials)
        #expect(reloaded.configuration.host == "proxy.example.com")
        #expect(reloaded.configuration.bypassHostPatterns == ["*.internal"])
        #expect(didNotify)
    }

    @Test("persists automatic PAC configuration under DefaultAppPolicy")
    func automaticPACPersistence() throws {
        let defaults = makeDefaults()
        let store = UpstreamProxyStore(userDefaults: defaults, credentialStorage: InMemoryCredentials())

        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: true,
            type: .automatic,
            host: "",
            port: 0,
            pacURL: " https://proxy.example.com/proxy.pac "
        ))

        let reloaded = UpstreamProxyStore(userDefaults: defaults, credentialStorage: InMemoryCredentials())
        #expect(reloaded.configuration.type == .automatic)
        #expect(reloaded.configuration.pacURL == "https://proxy.example.com/proxy.pac")
        #expect(reloaded.resolvedSnapshot()?.allowsSOCKS5 == false)
    }

    @Test("stores credentials outside UserDefaults when policy allows auth")
    func credentialStorage() throws {
        let credentials = InMemoryCredentials()
        let store = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: credentials
        )
        let config = UpstreamProxyConfiguration(
            isEnabled: true,
            host: "proxy.example.com",
            hasCredentials: true,
            username: "user"
        )
        try store.saveConfiguration(config, credentials: UpstreamProxyCredentials(username: "user", password: "secret"))

        #expect(try credentials.load()?.password == "secret")
        let persisted = store.configuration
        #expect(persisted.hasCredentials)
        #expect(persisted.username == "user")
    }

    @Test("saving unchanged authentication preserves credentials and disabling removes them")
    func credentialIntent() throws {
        let credentials = InMemoryCredentials()
        let store = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: credentials
        )
        try store.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                host: "proxy.example.com",
                hasCredentials: true,
                username: "saved-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "saved-user",
                password: "saved-secret"
            )
        )

        var unchanged = store.configuration
        unchanged.bypassHostPatterns = ["*.internal"]
        try store.saveConfiguration(unchanged)
        #expect(try credentials.load()?.password == "saved-secret")

        unchanged.hasCredentials = false
        unchanged.username = nil
        try store.saveConfiguration(unchanged)
        #expect(try credentials.load() == nil)
        #expect(!store.configuration.hasCredentials)
    }

    @Test("test connection reports success through a stub HTTP proxy")
    func connectionSuccess() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            Task {
                try? await group.shutdownGracefully()
            }
        }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { proxy.close(promise: nil) }

        let store = UpstreamProxyStore(
            userDefaults: makeDefaults(),
            credentialStorage: InMemoryCredentials(),
            testTarget: .init(host: "api.example.com", port: 443)
        )
        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: true,
            type: .http,
            host: "127.0.0.1",
            port: proxy.localAddress?.port ?? 0
        ))

        let result = await store.testConnection()
        guard case let .success(success) = result else {
            Issue.record("Expected successful Upstream Proxy test connection")
            return
        }
        #expect(success.targetHost == "api.example.com")
        #expect(success.targetPort == 443)
        #expect(success.negotiatedType == .http)
        #expect(capture.wait()?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
    }

    @Test("draft connection test does not mutate persisted or live configuration")
    func draftConnectionTestIsNonPersisting() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            Task {
                try? await group.shutdownGracefully()
            }
        }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { proxy.close(promise: nil) }

        let defaults = makeDefaults()
        let credentials = InMemoryCredentials()
        let store = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: defaults,
            credentialStorage: credentials,
            testTarget: .init(host: "api.example.com", port: 443)
        )
        let savedConfiguration = UpstreamProxyConfiguration(
            isEnabled: false,
            type: .http,
            host: "saved-proxy.example.com",
            port: 8_080,
            hasCredentials: true,
            username: "saved-user"
        )
        try store.saveConfiguration(
            savedConfiguration,
            credentials: UpstreamProxyCredentials(
                username: "saved-user",
                password: "saved-secret"
            )
        )
        let savedSnapshot = store.resolvedSnapshot()

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let draft = UpstreamProxyConfiguration(
            isEnabled: false,
            type: .http,
            host: "127.0.0.1",
            port: proxy.localAddress?.port ?? 0,
            bypassHostPatterns: ["api.example.com"]
        )
        let result = await store.testConnection(configuration: draft)

        guard case .success = result else {
            Issue.record("Expected successful non-persisting draft test")
            return
        }
        #expect(capture.wait()?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(notificationCount == 0)
        #expect(store.configuration == savedConfiguration)
        #expect(store.resolvedSnapshot() == savedSnapshot)
        #expect(try credentials.load()?.password == "saved-secret")

        let reloaded = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: defaults,
            credentialStorage: credentials
        )
        #expect(reloaded.configuration == savedConfiguration)
    }

    @Test("configuration metadata cannot preserve credentials that are missing from secure storage")
    func missingCredentialsAreRejected() async throws {
        let credentials = InMemoryCredentials()
        let store = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: credentials
        )
        try store.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                host: "proxy.example.com",
                hasCredentials: true,
                username: "saved-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "saved-user",
                password: "saved-secret"
            )
        )
        try credentials.delete()

        #expect(store.storedCredentialUsername() == nil)
        #expect(throws: UpstreamProxyStoreError.credentialsUnavailable) {
            try store.saveConfiguration(store.configuration)
        }
        let result = await store.testConnection()
        guard case let .failure(error) = result else {
            Issue.record("Expected connection testing to reject missing secure credentials")
            return
        }
        #expect(error.localizedDescription.contains("credentials are unavailable"))
    }

    @Test("disabling always succeeds for legacy configurations that current policy cannot enable")
    func safeDisableLegacyConfigurations() throws {
        let authDefaults = makeDefaults()
        let authCredentials = InMemoryCredentials()
        let permissiveAuthStore = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: authDefaults,
            credentialStorage: authCredentials
        )
        try permissiveAuthStore.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                host: "proxy.example.com",
                hasCredentials: true,
                username: "legacy-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "legacy-user",
                password: "legacy-secret"
            )
        )

        let restrictedAuthStore = UpstreamProxyStore(
            userDefaults: authDefaults,
            credentialStorage: authCredentials
        )
        try restrictedAuthStore.setEnabled(false)
        #expect(!restrictedAuthStore.configuration.isEnabled)
        #expect(restrictedAuthStore.configuration.hasCredentials)
        #expect(try authCredentials.load()?.password == "legacy-secret")

        let socksDefaults = makeDefaults()
        let permissiveSOCKSStore = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: socksDefaults,
            credentialStorage: InMemoryCredentials()
        )
        try permissiveSOCKSStore.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: true,
            type: .socks5,
            host: "proxy.example.com",
            port: 1_080
        ))

        let restrictedSOCKSStore = UpstreamProxyStore(
            userDefaults: socksDefaults,
            credentialStorage: InMemoryCredentials()
        )
        try restrictedSOCKSStore.setEnabled(false)
        #expect(!restrictedSOCKSStore.configuration.isEnabled)
        #expect(restrictedSOCKSStore.configuration.type == .socks5)

        let missingCredentialsDefaults = makeDefaults()
        let missingCredentials = InMemoryCredentials()
        let missingCredentialsStore = UpstreamProxyStore(
            policy: PermissivePolicy(),
            userDefaults: missingCredentialsDefaults,
            credentialStorage: missingCredentials
        )
        try missingCredentialsStore.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                host: "proxy.example.com",
                hasCredentials: true,
                username: "missing-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "missing-user",
                password: "missing-secret"
            )
        )
        try missingCredentials.delete()

        try missingCredentialsStore.setEnabled(false)
        #expect(!missingCredentialsStore.configuration.isEnabled)
        #expect(missingCredentialsStore.configuration.hasCredentials)
    }

    // MARK: Private

    private func makeStore() -> UpstreamProxyStore {
        UpstreamProxyStore(userDefaults: makeDefaults(), credentialStorage: InMemoryCredentials())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Rockxy.UpstreamProxyStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated Upstream Proxy defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

// MARK: - InMemoryCredentials

private final class InMemoryCredentials: UpstreamProxyCredentialStorage, @unchecked Sendable {
    // MARK: Internal

    func save(_ credentials: UpstreamProxyCredentials) throws {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func load() throws -> UpstreamProxyCredentials? {
        lock.lock()
        let snapshot = credentials
        lock.unlock()
        return snapshot
    }

    func delete() throws {
        lock.lock()
        credentials = nil
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var credentials: UpstreamProxyCredentials?
}

// MARK: - PermissivePolicy

private struct PermissivePolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = true
    let maxUpstreamProxyBypassEntries = 100
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = 100
}
