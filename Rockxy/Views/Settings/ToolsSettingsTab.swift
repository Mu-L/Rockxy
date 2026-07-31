import SwiftUI

/// Debugging tools settings.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | noCaching              | WIRED  | NoCacheHeaderMutator               |
struct ToolsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSectionCard(String(localized: "Request Behavior")) {
                SettingsIndentedContent {
                    Toggle(
                        String(localized: "Disable caching (No-Cache headers)"),
                        isOn: $noCaching
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("noCaching")) private var noCaching =
        false // WIRED: NoCacheHeaderMutator
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
