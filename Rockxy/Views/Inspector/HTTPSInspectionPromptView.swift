import AppKit
import SwiftUI

// MARK: - HTTPSInspectionPromptView

/// Compact controls for CONNECT tunnels whose payload was not decrypted.
struct HTTPSInspectionPromptView: View {
    let prompt: HTTPSInspectionPromptModel
    let onAction: (HTTPSInspectionPromptAction) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if prompt.requiresCertificateSetup {
                    certificateAction
                } else {
                    scopeControls
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: prompt.requiresCertificateSetup ? "exclamationmark.lock.fill" : "lock.fill")
                .font(.system(size: metrics.primaryFontSize, weight: .medium))
                .foregroundStyle(
                    prompt.requiresCertificateSetup
                        ? Color(nsColor: .systemOrange)
                        : Color(nsColor: .secondaryLabelColor)
                )
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(
                prompt.requiresCertificateSetup
                    ? String(localized: "Certificate Required")
                    : String(localized: "Encrypted HTTPS")
            )
            .font(.system(size: metrics.controlFontSize, weight: .semibold))

            Spacer(minLength: 8)

            Button {
                onAction(.openSSLProxyingList)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "Manage HTTPS Decryption"))
            .accessibilityLabel(String(localized: "Manage HTTPS Decryption"))
        }
    }

    private var certificateAction: some View {
        Button(String(localized: "Install & Trust…")) {
            onAction(prompt.primaryAction)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityHint(String(localized: "Installs and trusts the Rockxy root certificate"))
    }

    private var scopeControls: some View {
        VStack(spacing: 0) {
            Divider()
            scopeActionRow(action: prompt.primaryAction)

            if let secondaryAction = prompt.secondaryAction {
                Divider()
                    .padding(.leading, 24)
                scopeActionRow(action: secondaryAction)
            }
        }
    }

    @ViewBuilder
    private func scopeActionRow(action: HTTPSInspectionPromptAction) -> some View {
        if let scope = HTTPSInspectionScopePresentation(action: action) {
            HStack(spacing: 8) {
                Image(systemName: scope.kind.systemImage)
                    .font(.system(size: metrics.controlFontSize))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(scope.kind.title)
                        .font(.system(size: metrics.controlFontSize, weight: .medium))

                    Text(scope.value)
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(scope.value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(scope.actionTitle) {
                    onAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help(scope.actionDescription)
                .accessibilityLabel(scope.actionDescription)
                .accessibilityHint(String(localized: "The current captured response is unchanged"))
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 40)
        }
    }
}

// MARK: - HTTPSInspectionScopePresentation

struct HTTPSInspectionScopePresentation: Equatable {
    enum Kind: Equatable {
        case host
        case appHosts

        var title: String {
            switch self {
            case .host: String(localized: "Host")
            case .appHosts: String(localized: "App Hosts")
            }
        }

        var systemImage: String {
            switch self {
            case .host: "network"
            case .appHosts: "macwindow"
            }
        }
    }

    let kind: Kind
    let value: String
    let isEnabled: Bool

    var actionTitle: String {
        isEnabled ? String(localized: "Disable") : String(localized: "Decrypt")
    }

    var actionDescription: String {
        switch (kind, isEnabled) {
        case (.host, false):
            String(localized: "Decrypt new HTTPS connections to \(value)")
        case (.host, true):
            String(localized: "Stop decrypting new HTTPS connections to \(value)")
        case (.appHosts, false):
            String(localized: "Decrypt new HTTPS connections to known hosts used by \(value)")
        case (.appHosts, true):
            String(localized: "Stop decrypting new HTTPS connections to known hosts used by \(value)")
        }
    }

    init(kind: Kind, value: String, isEnabled: Bool) {
        self.kind = kind
        self.value = value
        self.isEnabled = isEnabled
    }

    init?(action: HTTPSInspectionPromptAction) {
        switch action {
        case let .enableDomain(host):
            self.init(kind: .host, value: host, isEnabled: false)
        case let .disableDomain(host):
            self.init(kind: .host, value: host, isEnabled: true)
        case let .enableApp(appName, _):
            self.init(kind: .appHosts, value: appName, isEnabled: false)
        case let .disableApp(appName, _):
            self.init(kind: .appHosts, value: appName, isEnabled: true)
        case .installCertificate,
             .openSSLProxyingList:
            return nil
        }
    }
}
