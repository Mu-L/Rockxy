import SwiftUI

// MARK: - SidebarOpenHTTPSDecryptionButton

struct SidebarOpenHTTPSDecryptionButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openSSLProxyingList, object: nil)
        } label: {
            Label(
                String(localized: "Open HTTPS Decryption", bundle: RockxyLocalization.bundle),
                systemImage: "slider.horizontal.3"
            )
        }
    }
}

// MARK: - FavoriteTransactionHTTPSBehaviorMenu

/// Keeps Pinned and Saved transaction actions aligned with the request table's
/// application-versus-host HTTPS behavior choices.
struct FavoriteTransactionHTTPSBehaviorMenu: View {
    let coordinator: MainContentCoordinator
    let transaction: HTTPTransaction
    let canConfigureHost: Bool
    let hostConfigurationDisabledReason: String?

    var body: some View {
        Menu {
            if let applicationIdentity {
                Button {
                    coordinator.setSSLProxyingFromInspector(
                        for: applicationIdentity,
                        listType: .include,
                        fallbackDomain: transaction.request.host
                    )
                } label: {
                    Label(
                        String(localized: "Decrypt All HTTPS from This Application", bundle: RockxyLocalization.bundle),
                        systemImage: "lock.open"
                    )
                }
            }

            Button {
                coordinator.enableSSLProxying(for: transaction)
            } label: {
                Label(
                    String(localized: "Decrypt Only This Host", bundle: RockxyLocalization.bundle),
                    systemImage: "globe"
                )
            }
            .disabled(!hostActionState.canDecryptHost)
            .help(hostActionHelp)

            if let applicationIdentity {
                Button {
                    coordinator.setSSLProxyingFromInspector(
                        for: applicationIdentity,
                        listType: .exclude,
                        fallbackDomain: transaction.request.host
                    )
                } label: {
                    Label(
                        String(localized: "Tunnel All HTTPS from This Application", bundle: RockxyLocalization.bundle),
                        systemImage: "lock"
                    )
                }
            }

            Divider()

            SidebarOpenHTTPSDecryptionButton()
        } label: {
            Label(
                String(localized: "HTTPS Behavior", bundle: RockxyLocalization.bundle),
                systemImage: "lock.shield"
            )
        }
    }

    private var applicationIdentity: ClientApplicationIdentity? {
        transaction.clientApplicationIdentity
    }

    private var hasApplicationTunnel: Bool {
        guard let applicationIdentity else {
            return false
        }
        return SSLProxyingManager.shared.applicationExcludeRules.contains {
            $0.isEnabled && $0.applicationIdentifier == applicationIdentity.identifier
        }
    }

    private var hostActionState: FavoriteTransactionHTTPSBehaviorState {
        FavoriteTransactionHTTPSBehaviorState(
            canConfigureHost: canConfigureHost,
            hasApplicationTunnel: hasApplicationTunnel
        )
    }

    private var hostActionHelp: String {
        switch hostActionState.blocker {
        case .applicationTunnel:
            return String(
                localized: "The application Tunnel rule takes priority. Change the application behavior first.",
                bundle: RockxyLocalization.bundle
            )
        case .missingHost:
            return hostConfigurationDisabledReason ?? ""
        case nil:
            return ""
        }
    }
}
