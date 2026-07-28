import Foundation
import Observation

// MARK: - UpstreamProxySettingsField

enum UpstreamProxySettingsField: Hashable {
    case protocolSelection
    case pacURL
    case host
    case port
    case authentication
    case username
    case password
    case bypass
}

// MARK: - UpstreamProxySettingsValidationIssue

struct UpstreamProxySettingsValidationIssue: Equatable {
    let field: UpstreamProxySettingsField
    let message: String
}

// MARK: - UpstreamProxySettingsStatus

enum UpstreamProxySettingsStatus: Equatable {
    case success(String)
    case failure(String)
}

// MARK: - UpstreamProxySettingsViewModel

@MainActor @Observable
final class UpstreamProxySettingsViewModel {
    // MARK: Lifecycle

    convenience init() {
        self.init(store: .shared)
    }

    init(store: UpstreamProxyStore) {
        self.store = store
        let initialDraft = ExternalProxySettingsDraft(
            configuration: store.configuration,
            storedCredentialUsername: store.storedCredentialUsername()
        )
        draft = initialDraft
        baselineDraft = initialDraft
        baselineConfiguration = store.configuration
        refreshValidation()
    }

    // MARK: Internal

    var draft: ExternalProxySettingsDraft {
        didSet {
            guard !isLoadingDraft else {
                return
            }
            editGeneration &+= 1
            status = nil
            refreshValidation()
        }
    }

    private(set) var validationIssues: [UpstreamProxySettingsValidationIssue] = []
    private(set) var status: UpstreamProxySettingsStatus?
    private(set) var isTesting = false
    private(set) var hasExternalConflict = false

    var isDirty: Bool {
        draft != baselineDraft
    }

    var canSelectSOCKS5: Bool {
        store.canSelectSOCKS5
    }

    var canEnableAuthentication: Bool {
        store.canEnableAuthentication
    }

    var isAuthenticationToggleDisabled: Bool {
        !canEnableAuthentication && !draft.usesAuthentication
    }

    var bypassEntriesLimit: Int {
        store.bypassEntriesLimit
    }

    var bypassEntriesUsed: Int {
        draft.bypassEntriesUsed
    }

    var canApply: Bool {
        !hasExternalConflict
            && validationIssuesForCurrentDraft(testing: false).isEmpty
            && !isTesting
    }

    var canTest: Bool {
        validationIssuesForCurrentDraft(testing: true).isEmpty && !isTesting
    }

    func validationMessage(for field: UpstreamProxySettingsField) -> String? {
        validationIssues.first(where: { $0.field == field })?.message
    }

    func apply() throws {
        guard !hasExternalConflict else {
            status = .failure(UpstreamProxySettingsViewModelError.unresolvedConflict.localizedDescription)
            throw UpstreamProxySettingsViewModelError.unresolvedConflict
        }
        let issues = validationIssuesForCurrentDraft(testing: false)
        validationIssues = issues
        guard issues.isEmpty else {
            throw UpstreamProxySettingsViewModelError.validationFailed
        }

        do {
            let configuration = try draft.configuration()
            try store.saveConfiguration(configuration, credentials: draft.credentials())
            loadFromStore()
            status = .success(String(localized: "Upstream Proxy settings saved."))
        } catch {
            status = .failure(error.localizedDescription)
            throw error
        }
    }

    func testConnection() async {
        let issues = validationIssuesForCurrentDraft(testing: true)
        validationIssues = issues
        guard issues.isEmpty, !isTesting else {
            return
        }

        let generation = editGeneration
        let configuration: UpstreamProxyConfiguration
        do {
            configuration = try draft.configuration()
        } catch {
            status = .failure(error.localizedDescription)
            return
        }

        isTesting = true
        status = nil
        let result = await store.testConnection(
            configuration: configuration,
            credentials: draft.credentials()
        )
        guard generation == editGeneration else {
            isTesting = false
            return
        }

        isTesting = false
        switch result {
        case let .success(testResult):
            status = .success(testResult.displayMessage)
        case let .failure(error):
            status = .failure(error.localizedDescription)
        }
    }

    func handleExternalConfigurationChange() {
        guard store.configuration != baselineConfiguration else {
            return
        }
        editGeneration &+= 1
        status = nil
        if isDirty {
            hasExternalConflict = true
        } else {
            loadFromStore()
        }
    }

    func reloadExternalConfiguration() {
        loadFromStore()
    }

    func keepEditingAfterExternalChange() {
        baselineConfiguration = store.configuration
        let storedUsername = store.storedCredentialUsername()
        draft.hasStoredCredentials = storedUsername != nil
        draft.storedUsername = storedUsername ?? ""
        hasExternalConflict = false
        refreshValidation()
    }

    func clearStatus() {
        status = nil
    }

    // MARK: Private

    private let store: UpstreamProxyStore
    private var baselineDraft: ExternalProxySettingsDraft
    private var baselineConfiguration: UpstreamProxyConfiguration
    private var editGeneration: UInt = 0
    private var isLoadingDraft = false

    private func loadFromStore() {
        isLoadingDraft = true
        editGeneration &+= 1
        status = nil
        let nextDraft = ExternalProxySettingsDraft(
            configuration: store.configuration,
            storedCredentialUsername: store.storedCredentialUsername()
        )
        draft = nextDraft
        baselineDraft = nextDraft
        baselineConfiguration = store.configuration
        hasExternalConflict = false
        validationIssues = validationIssuesForCurrentDraft(testing: false)
        isLoadingDraft = false
    }

    private func refreshValidation() {
        validationIssues = validationIssuesForCurrentDraft(testing: false)
    }

    private func validationIssuesForCurrentDraft(
        testing: Bool
    ) -> [UpstreamProxySettingsValidationIssue] {
        var issues: [UpstreamProxySettingsValidationIssue] = []

        if draft.selectedProtocol == .socks5, !canSelectSOCKS5 {
            issues.append(.init(
                field: .protocolSelection,
                message: String(localized: "SOCKS5 upstream proxy is unavailable in this build.")
            ))
        }
        if draft.usesAuthentication, !canEnableAuthentication {
            issues.append(.init(
                field: .authentication,
                message: String(localized: "Upstream proxy authentication is unavailable in this build.")
            ))
        } else if draft.needsReplacementPassword {
            issues.append(.init(
                field: .password,
                message: draft.hasStoredCredentials
                    ? String(localized: "Enter the password again when changing the saved username.")
                    : String(localized: "Enter the upstream proxy password.")
            ))
        }

        do {
            var configuration = try draft.configuration()
            if testing {
                configuration.isEnabled = true
            }
            try configuration.validate(
                credentials: draft.credentials(),
                bypassEntryLimit: bypassEntriesLimit
            )
        } catch let error as UpstreamProxyConfigurationError {
            issues.append(.init(field: field(for: error), message: error.localizedDescription))
        } catch {
            issues.append(.init(field: .host, message: error.localizedDescription))
        }
        return issues
    }

    private func field(
        for error: UpstreamProxyConfigurationError
    ) -> UpstreamProxySettingsField {
        switch error {
        case .hostInvalid:
            .host
        case .portOutOfRange:
            .port
        case .usernameTooLong:
            .username
        case .passwordTooLong:
            .password
        case .bypassPatternInvalid,
             .tooManyBypassEntries:
            .bypass
        case .pacURLRequired,
             .pacURLInvalid,
             .pacURLUnsupportedScheme:
            .pacURL
        }
    }
}

// MARK: - UpstreamProxySettingsViewModelError

enum UpstreamProxySettingsViewModelError: LocalizedError {
    case validationFailed
    case unresolvedConflict

    var errorDescription: String? {
        switch self {
        case .validationFailed:
            String(localized: "Review the highlighted Upstream Proxy settings.")
        case .unresolvedConflict:
            String(localized: "Resolve the externally changed Upstream Proxy settings before applying.")
        }
    }
}

private extension UpstreamProxyTestResult {
    var displayMessage: String {
        let milliseconds = duration.components.seconds * 1_000
            + duration.components.attoseconds / 1_000_000_000_000_000
        let typeName = resolvedPACRoute?.displayName
            ?? negotiatedType?.displayName
            ?? String(localized: "Direct")
        return String(
            localized: "Connected to \(targetHost):\(targetPort) through \(typeName) in \(milliseconds) ms."
        )
    }
}
