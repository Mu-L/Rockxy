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
    static func message(for rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        guard HostPatternMatcher.isValid(pattern: value) else {
            return String(localized: "Host patterns must be 255 characters or fewer and contain no spaces.")
        }
        guard !value.contains("://"),
              !value.contains("/"),
              !value.contains("?"),
              !value.contains("#"),
              !value.contains("@"),
              !value.contains(",")
        else {
            return String(localized: "Enter only a host pattern, without a scheme, path, query, or user information.")
        }
        if value == "*" {
            return nil
        }
        if value.hasPrefix("*.") {
            let suffix = String(value.dropFirst(2))
            guard !suffix.isEmpty, !suffix.contains("*"), isValidHostname(suffix) else {
                return String(localized: "Enter a complete wildcard host such as *.example.com.")
            }
            return nil
        }
        guard !value.contains("*") else {
            return String(localized: "Use * alone, or *.domain.com for subdomains.")
        }
        if value.contains(":") {
            return isValidIPv6(value)
                ? nil
                : String(localized: "Ports are not supported. Enter a bare host or a valid unbracketed IPv6 address.")
        }
        guard isValidIPv4(value) || isValidHostname(value) else {
            return String(localized: "Enter a valid hostname, IPv4 address, or IPv6 address.")
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
/// Presents every `SSLProxyingRule` in one unified list. Each rule carries an
/// explicit behavior derived from its `listType`: `.include` rules mean "Decrypt
/// HTTPS", `.exclude` rules mean "Tunnel Without Decryption". The underlying
/// `SSLProxyingManager` semantics, persistence, and import/export formats are
/// unchanged — this type only owns UI selection, search, and CRUD delegation.
@MainActor @Observable
final class SSLProxyingListViewModel {
    // MARK: Lifecycle

    init(manager: SSLProxyingManager = .shared) {
        self.manager = manager
    }

    // MARK: Internal

    let manager: SSLProxyingManager

    var selectedRuleID: UUID?
    var searchText = ""
    var showAddDomainSheet = false
    var showAddAppSheet = false
    var showBypassSheet = false
    var editingRule: SSLProxyingRule?

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

    var ruleCount: Int {
        manager.rules.count
    }

    /// Count of rules that decrypt HTTPS (`.include`).
    var decryptCount: Int {
        manager.rules.count { $0.listType == .include }
    }

    /// Count of rules that tunnel without decrypting (`.exclude`).
    var tunnelCount: Int {
        manager.rules.count { $0.listType == .exclude }
    }

    var enabledDecryptCount: Int {
        manager.rules.count { $0.isEnabled && $0.listType == .include }
    }

    var enabledTunnelCount: Int {
        manager.rules.count { $0.isEnabled && $0.listType == .exclude }
    }

    /// Enable/Disable label for the current selection.
    var enableDisableLabel: String {
        guard let id = selectedRuleID else {
            return String(localized: "Enable Rule")
        }
        return toggleLabel(for: id)
    }

    /// Reader-facing behavior label for a rule's list type.
    static func behaviorLabel(for listType: SSLProxyingListType) -> String {
        switch listType {
        case .include:
            String(localized: "Decrypt HTTPS")
        case .exclude:
            String(localized: "Tunnel Without Decryption")
        }
    }

    /// Row-specific enable/disable label.
    func toggleLabel(for id: UUID) -> String {
        guard let rule = manager.rules.first(where: { $0.id == id }) else {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
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
              !ruleExists(domain: trimmed, listType: listType)
        else {
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

    /// Edits an existing rule's host pattern and/or behavior while preserving its
    /// UUID and enabled state.
    @discardableResult
    func updateRule(id: UUID, domain: String, listType: SSLProxyingListType) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              SSLHostPatternValidation.message(for: trimmed) == nil,
              !ruleExists(domain: trimmed, listType: listType, excluding: id)
        else {
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
        let visible = filteredRules
        let removedIndex = visible.firstIndex { $0.id == id }
        manager.removeRule(id: id)

        let remaining = filteredRules
        if let removedIndex, !remaining.isEmpty {
            selectedRuleID = remaining[min(removedIndex, remaining.count - 1)].id
        } else {
            selectedRuleID = nil
        }
    }

    func removeRule(id: UUID) {
        manager.removeRule(id: id)
        if selectedRuleID == id {
            selectedRuleID = nil
        }
    }

    func selectRule(id: UUID) {
        selectedRuleID = id
    }

    func toggleRule(id: UUID) {
        manager.toggleRule(id: id)
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        manager.setRuleEnabled(id: id, enabled: enabled)
    }

    func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        if !filteredRules.contains(where: { $0.id == id }) {
            selectedRuleID = nil
        }
    }

    func presentEditor(for id: UUID) {
        guard let rule = manager.rules.first(where: { $0.id == id }) else {
            return
        }
        editingRule = rule
        showAddDomainSheet = true
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
    ) -> Bool {
        manager.rules.contains {
            $0.id != excludedID
                && $0.listType == listType
                && $0.domain.caseInsensitiveCompare(domain) == .orderedSame
        }
    }
}
