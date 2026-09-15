import SwiftUI

/// Debugging tools settings.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | noCaching              | WIRED  | NoCacheHeaderMutator               |
/// | acceptUntrustedUpstreamCertificates | WIRED | UpstreamTrustPolicy       |
struct ToolsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "Request Behavior", bundle: RockxyLocalization.bundle)) {
                SettingsIndentedContent {
                    Toggle(
                        String(localized: "Disable caching (No-Cache headers)", bundle: RockxyLocalization.bundle),
                        isOn: $noCaching
                    )
                    .toggleStyle(.checkbox)
                }
            }

            SettingsSection(String(localized: "Upstream Servers", bundle: RockxyLocalization.bundle)) {
                SettingsIndentedContent {
                    Toggle(
                        String(localized: "Accept untrusted upstream certificates", bundle: RockxyLocalization.bundle),
                        isOn: $acceptUntrustedUpstreamCertificates
                    )
                    .toggleStyle(.checkbox)
                    Text(
                        String(
                            localized: """
                            Decrypt HTTPS to staging or internal servers whose certificate is self-signed or \
                            issued by a private CA. Rockxy stops verifying the server it connects to, so only \
                            enable this on networks you control.
                            """,
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("noCaching")) private var noCaching =
        false // WIRED: NoCacheHeaderMutator
    @AppStorage(UpstreamTrustPolicy.userDefaultsKey) private var acceptUntrustedUpstreamCertificates =
        false // WIRED: UpstreamTrustPolicy
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
