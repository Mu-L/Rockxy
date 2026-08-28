import Foundation
import Observation
import os

// MARK: - ProtobufMappingRuleStore

@MainActor @Observable
final class ProtobufMappingRuleStore {
    // MARK: Lifecycle

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.rules = Self.loadRules(from: userDefaults)
    }

    // MARK: Internal

    static let shared = ProtobufMappingRuleStore()

    private(set) var rules: [ProtobufMappingRule]

    var selectedRuleID: UUID?

    var selectedRule: ProtobufMappingRule? {
        guard let selectedRuleID else {
            return nil
        }
        return rules.first { $0.id == selectedRuleID }
    }

    static func validate(_ rule: ProtobufMappingRule) throws {
        guard !rule.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProtobufMappingRuleValidationError.emptyPattern
        }
        try validateMessageType(rule.messageType)
        try validateMessageType(rule.requestMessageType ?? "")
        try validateMessageType(rule.responseMessageType ?? "")
    }

    static func isMessageTypeValid(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return true
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.$"))
        return !value.unicodeScalars.contains(where: { !allowed.contains($0) })
    }

    func addRule(_ rule: ProtobufMappingRule) throws {
        try Self.validate(rule)
        rules.append(rule)
        selectedRuleID = rule.id
        persist()
    }

    func updateRule(_ rule: ProtobufMappingRule) throws {
        try Self.validate(rule)
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            throw ProtobufMappingRuleStoreError.ruleNoLongerExists
        }
        rules[index] = rule
        selectedRuleID = rule.id
        persist()
    }

    func removeSelectedRule() {
        guard let selectedRuleID else {
            return
        }
        removeRule(id: selectedRuleID)
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        persist()
    }

    func duplicateSelectedRule() {
        guard let selectedRule else {
            return
        }
        duplicateRule(id: selectedRule.id)
    }

    func duplicateRule(id: UUID) {
        guard let selectedRule = rules.first(where: { $0.id == id }) else {
            return
        }
        var copy = selectedRule
        copy = ProtobufMappingRule(
            isEnabled: selectedRule.isEnabled,
            urlPattern: selectedRule.urlPattern,
            method: selectedRule.method,
            matchType: selectedRule.matchType,
            includeSubpaths: selectedRule.includeSubpaths,
            schemaID: selectedRule.schemaID,
            messageType: selectedRule.messageType,
            requestMessageType: selectedRule.requestMessageType,
            responseMessageType: selectedRule.responseMessageType,
            payloadEncoding: selectedRule.payloadEncoding
        )
        rules.append(copy)
        selectedRuleID = copy.id
        persist()
    }

    func toggleRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled.toggle()
        persist()
    }

    /// Resolves how a definition's stored schema id maps onto the local schema list,
    /// distinguishing "no schema chosen" from "chosen schema no longer exists".
    func schemaReference(for id: UUID?, schemas: [ProtobufSchemaDescriptor]) -> ProtobufSchemaReference {
        guard let id else {
            return .notSelected
        }
        guard let schema = schemas.first(where: { $0.id == id }) else {
            return .missing
        }
        return .selected(schema.fileName)
    }

    func schemaLabel(for id: UUID?, schemas: [ProtobufSchemaDescriptor]) -> String {
        schemaReference(for: id, schemas: schemas).displayLabel
    }

    func referenceCount(forSchema id: UUID) -> Int {
        rules.filter { $0.schemaID == id }.count
    }

    /// Clears the stored schema id on every definition that referenced `id`, persisting the result.
    /// Returns the number of definitions detached.
    @discardableResult
    func detachSchema(id: UUID) throws -> Int {
        let original = rules
        var detached = 0
        for index in rules.indices where rules[index].schemaID == id {
            rules[index].schemaID = nil
            detached += 1
        }
        if detached > 0 {
            do {
                try persistThrowing()
            } catch {
                rules = original
                throw error
            }
        }
        return detached
    }

    /// Restores a previously captured rule snapshot after a coordinated operation fails.
    func restoreRules(_ snapshot: [ProtobufMappingRule]) throws {
        let original = rules
        rules = snapshot
        do {
            try persistThrowing()
        } catch {
            rules = original
            throw error
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProtobufDecoder")
    private static let userDefaultsKey = "protobuf.mappingRules.v1"

    private let userDefaults: UserDefaults

    private static func loadRules(from userDefaults: UserDefaults) -> [ProtobufMappingRule] {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let rules = try? JSONDecoder().decode([ProtobufMappingRule].self, from: data) else
        {
            return []
        }
        return rules
    }

    private static func validateMessageType(_ value: String) throws {
        if !isMessageTypeValid(value) {
            throw ProtobufMappingRuleValidationError.invalidMessageType
        }
    }

    private func persist() {
        do {
            try persistThrowing()
        } catch {
            Self.logger.error("Failed to persist Protobuf mapping rules: \(error.localizedDescription)")
        }
    }

    private func persistThrowing() throws {
        let data = try JSONEncoder().encode(rules)
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }
}

// MARK: - ProtobufMappingRuleStoreError

enum ProtobufMappingRuleStoreError: LocalizedError, Equatable {
    case ruleNoLongerExists

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .ruleNoLongerExists:
            String(
                localized: "This mapping definition was deleted in another window.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
