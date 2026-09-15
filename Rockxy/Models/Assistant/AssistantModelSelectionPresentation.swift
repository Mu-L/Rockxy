import Foundation

// MARK: - AssistantModelSelectionPresentation

/// Read-only labels for the Assistant model picker. Keeping this presentation outside
/// the dock prevents provider/runtime identity and data-destination rules from drifting
/// across compact UI call sites.
struct AssistantModelSelectionPresentation: Equatable {
    // MARK: Lifecycle

    init(
        configuration: AssistantProviderConfiguration?,
        isModelAccessEnabled: Bool,
        usesConfiguredModel: Bool
    ) {
        self.configuration = configuration
        self.isModelAccessEnabled = isModelAccessEnabled
        self.usesConfiguredModel = usesConfiguredModel
    }

    // MARK: Internal

    var isConfiguredModelAvailable: Bool {
        isModelAccessEnabled && configuration?.isComplete == true
    }

    var configuredModelLabel: String {
        guard let configuration, configuration.isComplete else {
            return String(localized: "No Configured Model", bundle: RockxyLocalization.bundle)
        }
        return String(
            localized: "Global Default · \(sourceTitle) · \(configuration.model)",
            bundle: RockxyLocalization.bundle
        )
    }

    var selectionLabel: String {
        guard usesConfiguredModel, isConfiguredModelAvailable else {
            return String(localized: "Built-in", bundle: RockxyLocalization.bundle)
        }
        guard let configuration else {
            return String(localized: "Model", bundle: RockxyLocalization.bundle)
        }
        return "\(sourceTitle) · \(configuration.model)"
    }

    var selectionSystemImage: String {
        guard usesConfiguredModel, isConfiguredModelAvailable, let configuration else {
            return "cpu"
        }
        return configuration.executionLocation.isLocal ? "desktopcomputer" : "cloud"
    }

    var destinationLabel: String? {
        guard let configuration, configuration.isComplete else {
            return nil
        }
        if configuration.executionLocation.isLocal {
            return String(
                localized: "Local · \(configuration.endpointHost)",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Remote · \(configuration.endpointHost)",
            bundle: RockxyLocalization.bundle
        )
    }

    var destinationSystemImage: String {
        configuration?.executionLocation.isLocal == true ? "lock.fill" : "arrow.up.forward.app"
    }

    // MARK: Private

    private let configuration: AssistantProviderConfiguration?
    private let isModelAccessEnabled: Bool
    private let usesConfiguredModel: Bool

    private var sourceTitle: String {
        guard let configuration else {
            return String(localized: "Model", bundle: RockxyLocalization.bundle)
        }
        if let preset = AssistantLocalRuntimePreset.matching(configuration) {
            return preset.name
        }
        if configuration.executionLocation.isLocal {
            return String(localized: "Local endpoint", bundle: RockxyLocalization.bundle)
        }
        return configuration.kind.title
    }
}
