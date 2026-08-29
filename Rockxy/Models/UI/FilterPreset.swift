import Foundation

// MARK: - FilterPreset

struct FilterPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var rules: [FilterRule]
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: - FilterPresetStore

@MainActor @Observable
final class FilterPresetStore {
    // MARK: Lifecycle

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = RockxyIdentity.current.defaultsKey("advancedFilterPresets")
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        presets = Self.loadPresets(from: userDefaults, key: storageKey)
    }

    // MARK: Internal

    var presets: [FilterPreset] = []

    @discardableResult
    func savePreset(name: String, rules: [FilterRule]) -> FilterPreset? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabledRules = FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true)
        guard !trimmedName.isEmpty, !enabledRules.isEmpty else {
            return nil
        }

        var preset = FilterPreset(name: trimmedName, rules: enabledRules)
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            preset.id = presets[index].id
            preset.createdAt = presets[index].createdAt
            preset.updatedAt = Date()
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist()
        return preset
    }

    @discardableResult
    func saveGeneratedPreset(rules: [FilterRule]) -> FilterPreset? {
        savePreset(name: generatedPresetName(for: rules), rules: rules)
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    // MARK: Private

    private let userDefaults: UserDefaults
    private let storageKey: String

    private static func loadPresets(from userDefaults: UserDefaults, key: String) -> [FilterPreset] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FilterPreset].self, from: data) else
        {
            return []
        }
        return decoded
    }

    private func generatedPresetName(for rules: [FilterRule]) -> String {
        let activeRules = FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true)
        guard let first = activeRules.first else {
            return String(localized: "Advanced Filter", bundle: RockxyLocalization.bundle)
        }
        let base = "\(first.field.displayName): \(first.value)"
        if activeRules.count == 1 {
            return base
        }
        return "\(base) + \(activeRules.count - 1)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
