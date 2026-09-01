import Darwin
import Foundation

// MARK: - SSLHostPatternValidation

/// Validation shared by HTTPS decryption rules and TLS passthrough exceptions.
///
/// The runtime matcher accepts `*`, a leading `*.` suffix pattern, or an exact
/// host string. This validator keeps the editor from persisting values that can
/// never be presented as a bare CONNECT/SNI host, such as URLs and host:port
/// pairs, while retaining exact IPv4 and IPv6 support.
enum SSLHostPatternValidation {
    // MARK: Internal

    static func message(for rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        guard HostPatternMatcher.isValid(pattern: value) else {
            return String(
                localized: "Host patterns must be 255 characters or fewer and contain no spaces.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard !value.contains("://"),
              !value.contains("/"),
              !value.contains("?"),
              !value.contains("#"),
              !value.contains("@"),
              !value.contains(",") else
        {
            return String(
                localized: "Enter only a host pattern, without a scheme, path, query, or user information.",
                bundle: RockxyLocalization.bundle
            )
        }
        if value == "*" {
            return nil
        }
        if value.hasPrefix("*.") {
            let suffix = String(value.dropFirst(2))
            guard !suffix.isEmpty, !suffix.contains("*"), isValidHostname(suffix) else {
                return String(
                    localized: "Enter a complete wildcard host such as *.example.com.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return nil
        }
        guard !value.contains("*") else {
            return String(localized: "Use * alone, or *.domain.com for subdomains.", bundle: RockxyLocalization.bundle)
        }
        if value.contains(":") {
            return isValidIPv6(value)
                ? nil
                : String(
                    localized: "Ports are not supported. Enter a bare host or a valid unbracketed IPv6 address.",
                    bundle: RockxyLocalization.bundle
                )
        }
        guard isValidIPv4(value) || isValidHostname(value) else {
            return String(
                localized: "Enter a valid hostname, IPv4 address, or IPv6 address.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }

    // MARK: Private

    private static func isValidHostname(_ value: String) -> Bool {
        guard value.utf8.count <= 253, !value.hasPrefix(".") else {
            return false
        }
        let hostname = value.hasSuffix(".") ? String(value.dropLast()) : value
        guard !hostname.isEmpty else {
            return false
        }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty
                && label.utf8.count <= 63
                && label.first != "-"
                && label.last != "-"
                && label.allSatisfy { character in
                    character.isASCII
                        && (character.isLetter || character.isNumber || character == "-" || character == "_")
                }
        }
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isValidIPv6(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }
}

// MARK: - SSLProxyingListViewModel

/// View model for the HTTPS Decryption management window.
///
/// Presents host and application rules in one unified list. Each rule carries an
/// explicit behavior derived from its `listType`: `.include` rules mean "Decrypt
/// HTTPS", `.exclude` rules mean "Tunnel Without Decryption". The underlying
/// `SSLProxyingManager` semantics, persistence, and import/export formats are
/// unchanged — this type only owns UI selection, search, and CRUD delegation.
@MainActor @Observable
final class SSLProxyingListViewModel {
    @MainActor enum Row: Identifiable, Equatable {
        case host(SSLProxyingRule)
        case application(ApplicationSSLProxyingRule)

        var id: UUID {
            switch self {
            case let .host(rule): rule.id
            case let .application(rule): rule.id
            }
        }

        var target: String {
            switch self {
            case let .host(rule): rule.domain
            case let .application(rule): rule.displayName
            }
        }

        var targetDetail: String? {
            switch self {
            case .host: nil
            case let .application(rule): rule.bundleIdentifier ?? rule.applicationIdentifier
            }
        }

        var scopeLabel: String {
            switch self {
            case .host: String(localized: "Host", bundle: RockxyLocalization.bundle)
            case .application: String(localized: "Application", bundle: RockxyLocalization.bundle)
            }
        }

        var isEnabled: Bool {
            switch self {
            case let .host(rule): rule.isEnabled
            case let .application(rule): rule.isEnabled
            }
        }

        var listType: SSLProxyingListType {
            switch self {
            case let .host(rule): rule.listType
            case let .application(rule): rule.listType
            }
        }
    }

    // MARK: Lifecycle

    init() {
        manager = .shared
    }

    init(manager: SSLProxyingManager) {
        self.manager = manager
    }

    // MARK: Internal

    let manager: SSLProxyingManager

    var selectedRuleID: UUID?
    var searchText = ""
    var showAddDomainSheet = false
    var showAddAppSheet = false
    var showAddObservedHostsSheet = false
    var showBypassSheet = false
    var editingRule: SSLProxyingRule?
    var editingApplicationRule: ApplicationSSLProxyingRule?

    var isSSLProxyingEnabled: Bool {
        manager.isEnabled
    }

    /// Every rule, optionally narrowed by the always-visible search field.
    var filteredRules: [SSLProxyingRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return manager.rules
        }
        return manager.rules.filter { rule in
            rule.domain.localizedCaseInsensitiveContains(query)
                || Self.behaviorLabel(for: rule.listType).localizedCaseInsensitiveContains(query)
        }
    }

    var filteredRows: [Row] {
        let rows = manager.applicationRules.map(Row.application) + manager.rules.map(Row.host)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { row in
            row.target.localizedCaseInsensitiveContains(query)
                || row.targetDetail?.localizedCaseInsensitiveContains(query) == true
                || row.scopeLabel.localizedCaseInsensitiveContains(query)
                || Self.behaviorLabel(for: row.listType).localizedCaseInsensitiveContains(query)
        }
    }

    var ruleCount: Int {
        manager.rules.count + manager.applicationRules.count
    }

    /// Count of rules that decrypt HTTPS (`.include`).
    var decryptCount: Int {
        manager.rules.count { $0.listType == .include }
            + manager.applicationRules.count { $0.listType == .include }
    }

    /// Count of rules that tunnel without decrypting (`.exclude`).
    var tunnelCount: Int {
        manager.rules.count { $0.listType == .exclude }
            + manager.applicationRules.count { $0.listType == .exclude }
    }

    var enabledDecryptCount: Int {
        manager.rules.count { $0.isEnabled && $0.listType == .include }
            + manager.applicationRules.count { $0.isEnabled && $0.listType == .include }
    }

    var enabledTunnelCount: Int {
        manager.rules.count { $0.isEnabled && $0.listType == .exclude }
            + manager.applicationRules.count { $0.isEnabled && $0.listType == .exclude }
    }

    /// Enable/Disable label for the current selection.
    var enableDisableLabel: String {
        guard let id = selectedRuleID else {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return toggleLabel(for: id)
    }

    /// Reader-facing behavior label for a rule's list type.
    static func behaviorLabel(for listType: SSLProxyingListType) -> String {
        switch listType {
        case .include:
            String(localized: "Decrypt HTTPS", bundle: RockxyLocalization.bundle)
        case .exclude:
            String(localized: "Tunnel Without Decryption", bundle: RockxyLocalization.bundle)
        }
    }

    /// Row-specific enable/disable label.
    func toggleLabel(for id: UUID) -> String {
        guard let row = row(withID: id) else {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return row.isEnabled
            ? String(localized: "Disable Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
    }

    func setEnabled(_ enabled: Bool) {
        manager.setEnabled(enabled)
    }

    // MARK: - CRUD

    @discardableResult
    func addRule(domain: String, listType: SSLProxyingListType) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              SSLHostPatternValidation.message(for: trimmed) == nil,
              !ruleExists(domain: trimmed, listType: listType) else
        {
            return false
        }
        let rule = SSLProxyingRule(domain: trimmed, listType: listType)
        selectedRuleID = rule.id
        manager.addRule(rule)
        return true
    }

    /// Batch add: trims each value, skips empties, and skips duplicates of the same
    /// domain + behavior (case-insensitively) whether they already exist or repeat
    /// within the batch. Cross-behavior duplicates are allowed on purpose because a
    /// tunnel rule intentionally overrides a decrypt rule for the same host.
    func addRules(_ domains: [String], listType: SSLProxyingListType) {
        var seen = Set(
            manager.rules
                .filter { $0.listType == listType }
                .map { $0.domain.lowercased() }
        )
        var newRules: [SSLProxyingRule] = []
        for domain in domains {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, SSLHostPatternValidation.message(for: trimmed) == nil else {
                continue
            }
            guard seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            newRules.append(SSLProxyingRule(domain: trimmed, listType: listType))
        }
        guard !newRules.isEmpty else {
            return
        }
        selectedRuleID = newRules.last?.id
        manager.addRules(newRules)
    }

    @discardableResult
    func addApplicationRule(identity: ClientApplicationIdentity, listType: SSLProxyingListType) -> Bool {
        guard !applicationRuleExists(identifier: identity.identifier, listType: listType) else {
            return false
        }
        let rule = ApplicationSSLProxyingRule(identity: identity, listType: listType)
        manager.addApplicationRule(rule)
        clearObservedAutoPassthrough(for: identity, listType: listType)
        selectedRuleID = rule.id
        return true
    }

    @discardableResult
    func updateApplicationRule(
        id: UUID,
        identity: ClientApplicationIdentity,
        listType: SSLProxyingListType
    ) -> Bool {
        guard !applicationRuleExists(identifier: identity.identifier, listType: listType, excluding: id),
              var rule = manager.applicationRules.first(where: { $0.id == id }) else
        {
            return false
        }
        rule.applicationIdentifier = identity.identifier
        rule.displayName = identity.displayName
        rule.bundleIdentifier = identity.bundleIdentifier
        rule.listType = listType
        manager.updateApplicationRule(rule)
        clearObservedAutoPassthrough(for: identity, listType: listType)
        selectedRuleID = id
        return true
    }

    /// Edits an existing rule's host pattern and/or behavior while preserving its
    /// UUID and enabled state.
    @discardableResult
    func updateRule(id: UUID, domain: String, listType: SSLProxyingListType) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              SSLHostPatternValidation.message(for: trimmed) == nil,
              !ruleExists(domain: trimmed, listType: listType, excluding: id) else
        {
            return false
        }
        guard var rule = manager.rules.first(where: { $0.id == id }) else {
            return false
        }
        rule.domain = trimmed
        rule.listType = listType
        manager.updateRule(rule)
        selectedRuleID = rule.id
        return true
    }

    /// Removes the selected rule and falls back to the adjacent visible rule.
    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        let visible = filteredRows
        let removedIndex = visible.firstIndex { $0.id == id }
        removeRuleFromManager(id: id)

        let remaining = filteredRows
        if let removedIndex, !remaining.isEmpty {
            selectedRuleID = remaining[min(removedIndex, remaining.count - 1)].id
        } else {
            selectedRuleID = nil
        }
    }

    func removeRule(id: UUID) {
        removeRuleFromManager(id: id)
        if selectedRuleID == id {
            selectedRuleID = nil
        }
    }

    func selectRule(id: UUID) {
        selectedRuleID = id
    }

    func toggleRule(id: UUID) {
        if manager.rules.contains(where: { $0.id == id }) {
            manager.toggleRule(id: id)
        } else {
            manager.toggleApplicationRule(id: id)
        }
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        if manager.rules.contains(where: { $0.id == id }) {
            manager.setRuleEnabled(id: id, enabled: enabled)
        } else {
            manager.setApplicationRuleEnabled(id: id, enabled: enabled)
        }
    }

    func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        if !filteredRows.contains(where: { $0.id == id }) {
            selectedRuleID = nil
        }
    }

    func presentEditor(for id: UUID) {
        if let rule = manager.rules.first(where: { $0.id == id }) {
            editingRule = rule
            showAddDomainSheet = true
        } else if let rule = manager.applicationRules.first(where: { $0.id == id }) {
            editingApplicationRule = rule
            showAddAppSheet = true
        }
    }

    func presentEditorForSelection() {
        guard let id = selectedRuleID else {
            return
        }
        presentEditor(for: id)
    }

    // MARK: Private

    private func ruleExists(
        domain: String,
        listType: SSLProxyingListType,
        excluding excludedID: UUID? = nil
    )
        -> Bool
    {
        manager.rules.contains {
            $0.id != excludedID
                && $0.listType == listType
                && $0.domain.caseInsensitiveCompare(domain) == .orderedSame
        }
    }

    private func applicationRuleExists(
        identifier: String,
        listType: SSLProxyingListType,
        excluding excludedID: UUID? = nil
    ) -> Bool {
        manager.applicationRules.contains {
            $0.id != excludedID
                && $0.listType == listType
                && $0.applicationIdentifier == identifier
        }
    }

    private func row(withID id: UUID) -> Row? {
        if let rule = manager.rules.first(where: { $0.id == id }) {
            return .host(rule)
        }
        return manager.applicationRules.first(where: { $0.id == id }).map(Row.application)
    }

    private func removeRuleFromManager(id: UUID) {
        if manager.rules.contains(where: { $0.id == id }) {
            manager.removeRule(id: id)
        } else {
            manager.removeApplicationRule(id: id)
        }
    }

    private func clearObservedAutoPassthrough(
        for identity: ClientApplicationIdentity,
        listType: SSLProxyingListType
    ) {
        guard listType == .include else {
            return
        }
        let hosts = TrafficDomainSnapshot.shared.appEntries
            .filter { $0.identity?.identifier == identity.identifier }
            .flatMap(\.domains)
        for host in Set(hosts) {
            manager.retryInterception(for: host)
        }
    }
}
