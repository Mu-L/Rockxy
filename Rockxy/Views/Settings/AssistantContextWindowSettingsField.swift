import SwiftUI

/// Model-aware context control kept separate from the provider form's general connection fields.
struct AssistantContextWindowSettingsField: View {
    // MARK: Internal

    @Binding var configuration: AssistantProviderConfiguration

    var body: some View {
        SettingsFieldRow(String(localized: "Context Window", bundle: RockxyLocalization.bundle)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField(
                        String(localized: "Context window tokens", bundle: RockxyLocalization.bundle),
                        value: contextWindow,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: settingsMetrics.fieldWidth(120))
                    Text(String(localized: "tokens", bundle: RockxyLocalization.bundle))
                        .foregroundStyle(.secondary)
                }
                Text(
                    String(
                        localized: "Rockxy uses 8,192 tokens by default and limits local inference to 32,768 tokens to avoid excessive memory pressure.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(settingsMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var contextWindow: Binding<Int> {
        Binding(
            get: {
                configuration.effectiveContextWindowTokens
                    ?? AssistantProviderConfiguration.defaultLocalContextWindowTokens
            },
            set: {
                let valid = AssistantProviderConfiguration.validContextWindowTokens($0)
                    ?? AssistantProviderConfiguration.defaultLocalContextWindowTokens
                configuration.contextWindowTokens = configuration.kind == .ollama
                    ? min(valid, AssistantProviderConfiguration.maxLocalContextWindowTokens)
                    : valid
            }
        )
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
