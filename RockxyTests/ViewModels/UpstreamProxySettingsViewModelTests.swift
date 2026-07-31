import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - UpstreamProxySettingsViewModelTests

@MainActor
@Suite("UpstreamProxySettingsViewModel")
struct UpstreamProxySettingsViewModelTests {
    @Test("Draft changes track dirty state and live bypass validation")
    func dirtyStateAndBypassValidation() {
        let viewModel = UpstreamProxySettingsViewModel(store: makeStore())

        #expect(!viewModel.isDirty)
        viewModel.draft.host = "proxy.example.com"
        viewModel.draft.isEnabled = true
        viewModel.draft.bypassText = "a.example, b.example\nc.example, d.example"

        #expect(viewModel.isDirty)
        #expect(viewModel.bypassEntriesUsed == 4)
        #expect(viewModel.validationMessage(for: .bypass) != nil)
        #expect(!viewModel.canApply)
    }

    @Test("Default policy keeps SOCKS5 and authentication locked")
    func policyLocks() {
        let viewModel = UpstreamProxySettingsViewModel(store: makeStore())

        viewModel.draft.selectedProtocol = .socks5
        #expect(!viewModel.canSelectSOCKS5)
        #expect(viewModel.validationMessage(for: .protocolSelection) != nil)

        viewModel.draft.selectedProtocol = .http
        viewModel.draft.usesAuthentication = true
        #expect(!viewModel.canEnableAuthentication)
        #expect(viewModel.validationMessage(for: .authentication) != nil)
    }

    @Test("Clean external changes reload while dirty changes require a decision")
    func externalChangeConflict() throws {
        let store = makeStore()
        let cleanViewModel = UpstreamProxySettingsViewModel(store: store)
        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: false,
            type: .https,
            host: "external.example.com",
            port: 8_443
        ))

        cleanViewModel.handleExternalConfigurationChange()
        #expect(cleanViewModel.draft.selectedProtocol == .https)
        #expect(cleanViewModel.draft.host == "external.example.com")
        #expect(!cleanViewModel.hasExternalConflict)

        cleanViewModel.draft.host = "local-edit.example.com"
        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: false,
            type: .http,
            host: "second-external.example.com",
            port: 8_080
        ))
        cleanViewModel.handleExternalConfigurationChange()

        #expect(cleanViewModel.hasExternalConflict)
        #expect(cleanViewModel.draft.host == "local-edit.example.com")

        cleanViewModel.reloadExternalConfiguration()
        #expect(cleanViewModel.draft.host == "second-external.example.com")
        #expect(!cleanViewModel.hasExternalConflict)
        #expect(!cleanViewModel.isDirty)
    }

    @Test("An unresolved external change blocks Apply until the user chooses a resolution")
    func unresolvedConflictBlocksApply() throws {
        let store = makeStore()
        let viewModel = UpstreamProxySettingsViewModel(store: store)
        viewModel.draft.host = "local-edit.example.com"

        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: false,
            type: .https,
            host: "external.example.com",
            port: 8_443
        ))
        viewModel.handleExternalConfigurationChange()

        #expect(viewModel.hasExternalConflict)
        #expect(!viewModel.canApply)
        #expect(throws: UpstreamProxySettingsViewModelError.unresolvedConflict) {
            try viewModel.apply()
        }
        #expect(store.configuration.host == "external.example.com")

        viewModel.keepEditingAfterExternalChange()
        #expect(!viewModel.hasExternalConflict)
        #expect(viewModel.canApply)
    }

    @Test("Apply preserves an unchanged password and removes it when authentication is disabled")
    func credentialApply() throws {
        let credentials = ViewModelCredentials()
        let store = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: credentials
        )
        try store.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                type: .http,
                host: "proxy.example.com",
                port: 8_080,
                hasCredentials: true,
                username: "saved-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "saved-user",
                password: "saved-secret"
            )
        )

        let viewModel = UpstreamProxySettingsViewModel(store: store)
        viewModel.draft.bypassText = "*.internal"
        try viewModel.apply()
        #expect(try credentials.load()?.password == "saved-secret")
        #expect(store.configuration.bypassHostPatterns == ["*.internal"])

        viewModel.draft.usesAuthentication = false
        try viewModel.apply()
        #expect(try credentials.load() == nil)
        #expect(!store.configuration.hasCredentials)
    }

    @Test("Changing a stored username requires a replacement password")
    func usernameReplacementValidation() throws {
        let credentials = ViewModelCredentials()
        let store = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: credentials
        )
        try store.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: true,
                host: "proxy.example.com",
                hasCredentials: true,
                username: "old-user"
            ),
            credentials: UpstreamProxyCredentials(username: "old-user", password: "secret")
        )
        let viewModel = UpstreamProxySettingsViewModel(store: store)

        viewModel.draft.username = "new-user"
        #expect(viewModel.validationMessage(for: .password) != nil)
        #expect(!viewModel.canApply)

        viewModel.draft.password = "replacement"
        #expect(viewModel.validationMessage(for: .password) == nil)
        #expect(viewModel.canApply)
    }

    @Test("Restricted policy can remove legacy credentials but cannot add them")
    func restrictedPolicyCanRemoveLegacyCredentials() throws {
        let defaults = makeDefaults()
        let credentials = ViewModelCredentials()
        let permissiveStore = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: defaults,
            credentialStorage: credentials
        )
        try permissiveStore.saveConfiguration(
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

        let restrictedStore = UpstreamProxyStore(
            userDefaults: defaults,
            credentialStorage: credentials
        )
        let viewModel = UpstreamProxySettingsViewModel(store: restrictedStore)
        #expect(!viewModel.canEnableAuthentication)
        #expect(viewModel.draft.usesAuthentication)
        #expect(!viewModel.isAuthenticationToggleDisabled)

        viewModel.draft.usesAuthentication = false
        #expect(viewModel.isAuthenticationToggleDisabled)
        #expect(viewModel.canApply)
        try viewModel.apply()

        #expect(!restrictedStore.configuration.hasCredentials)
        #expect(try credentials.load() == nil)
    }

    @Test("Keep Editing reconciles credentials removed by an external save")
    func keepEditingReconcilesRemovedCredentials() throws {
        let credentials = ViewModelCredentials()
        let store = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
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

        let viewModel = UpstreamProxySettingsViewModel(store: store)
        viewModel.draft.bypassText = "*.internal"
        try store.saveConfiguration(UpstreamProxyConfiguration(
            isEnabled: true,
            host: "external.example.com"
        ))
        viewModel.handleExternalConfigurationChange()
        viewModel.keepEditingAfterExternalChange()

        #expect(!viewModel.draft.hasStoredCredentials)
        #expect(viewModel.validationMessage(for: .password) != nil)
        #expect(!viewModel.canApply)
    }

    @Test("Apply exposes secure-storage failures in the status region")
    func applyFailureStatus() {
        let store = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: makeDefaults(),
            credentialStorage: FailingViewModelCredentials()
        )
        let viewModel = UpstreamProxySettingsViewModel(store: store)
        viewModel.draft.isEnabled = true
        viewModel.draft.host = "proxy.example.com"
        viewModel.draft.usesAuthentication = true
        viewModel.draft.username = "user"
        viewModel.draft.password = "secret"

        #expect(throws: FailingViewModelCredentials.StorageError.self) {
            try viewModel.apply()
        }
        guard case let .failure(message) = viewModel.status else {
            Issue.record("Expected an Apply failure status")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("Connection testing stays inside the draft boundary")
    func connectionTestDoesNotPersistDraft() async throws {
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
        let credentials = ViewModelCredentials()
        let store = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: defaults,
            credentialStorage: credentials,
            testTarget: .init(host: "api.example.com", port: 443)
        )
        try store.saveConfiguration(
            UpstreamProxyConfiguration(
                isEnabled: false,
                host: "saved.example.com",
                hasCredentials: true,
                username: "saved-user"
            ),
            credentials: UpstreamProxyCredentials(
                username: "saved-user",
                password: "saved-secret"
            )
        )
        let savedConfiguration = store.configuration
        let savedSnapshot = store.resolvedSnapshot()
        let viewModel = UpstreamProxySettingsViewModel(store: store)
        viewModel.draft.isEnabled = true
        viewModel.draft.host = "127.0.0.1"
        viewModel.draft.portText = "\(proxy.localAddress?.port ?? 0)"
        viewModel.draft.bypassText = "api.example.com"

        let notificationCounter = ViewModelNotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await viewModel.testConnection()

        #expect(capture.wait()?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(viewModel.isDirty)
        #expect(notificationCounter.value == 0)
        #expect(store.configuration == savedConfiguration)
        #expect(store.resolvedSnapshot() == savedSnapshot)
        #expect(try credentials.load()?.password == "saved-secret")

        let reloaded = UpstreamProxyStore(
            policy: ViewModelPermissivePolicy(),
            userDefaults: defaults,
            credentialStorage: credentials
        )
        #expect(reloaded.configuration == savedConfiguration)
        guard case .success? = viewModel.status else {
            Issue.record("Expected a successful draft-only connection status")
            return
        }
    }

    private func makeStore() -> UpstreamProxyStore {
        UpstreamProxyStore(
            userDefaults: Self.makeDefaults(),
            credentialStorage: ViewModelCredentials()
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "Rockxy.UpstreamProxySettingsViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated Upstream Proxy settings defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDefaults() -> UserDefaults {
        Self.makeDefaults()
    }
}

// MARK: - ViewModelCredentials

private final class ViewModelCredentials: UpstreamProxyCredentialStorage, @unchecked Sendable {
    func save(_ credentials: UpstreamProxyCredentials) throws {
        lock.lock()
        value = credentials
        lock.unlock()
    }

    func load() throws -> UpstreamProxyCredentials? {
        lock.lock()
        let snapshot = value
        lock.unlock()
        return snapshot
    }

    func delete() throws {
        lock.lock()
        value = nil
        lock.unlock()
    }

    private let lock = NSLock()
    private var value: UpstreamProxyCredentials?
}

// MARK: - FailingViewModelCredentials

private struct FailingViewModelCredentials: UpstreamProxyCredentialStorage {
    enum StorageError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Secure storage is unavailable."
        }
    }

    func save(_ credentials: UpstreamProxyCredentials) throws {
        throw StorageError.unavailable
    }

    func load() throws -> UpstreamProxyCredentials? {
        nil
    }

    func delete() throws {}
}

// MARK: - ViewModelNotificationCounter

private final class ViewModelNotificationCounter: @unchecked Sendable {
    var value: Int {
        lock.lock()
        let snapshot = count
        lock.unlock()
        return snapshot
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    private let lock = NSLock()
    private var count = 0
}

// MARK: - ViewModelPermissivePolicy

private struct ViewModelPermissivePolicy: AppPolicy {
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
