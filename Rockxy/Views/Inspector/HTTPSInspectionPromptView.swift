import AppKit
import SwiftUI

// MARK: - HTTPSInspectionPromptView

/// Compact controls for CONNECT tunnels whose payload was not decrypted.
struct HTTPSInspectionPromptView: View {
    let prompt: HTTPSInspectionPromptModel
    let onAction: (HTTPSInspectionPromptAction) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let insight = prompt.insight {
                    connectionInsight(insight)
                }

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
    @State private var isInsightExpanded = false

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
            if let action = prompt.certificateAction {
                onAction(action)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityHint(String(localized: "Installs and trusts the Rockxy root certificate"))
    }

    private func connectionInsight(_ insight: HTTPSConnectionInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: insight.systemImage)
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
                    .foregroundStyle(
                        insight.isWarning ?
                            Color(nsColor: .systemOrange) :
                            Color(nsColor: .secondaryLabelColor)
                    )
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: metrics.controlFontSize, weight: .semibold))
                    Text(insight.summary)
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isInsightExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(isInsightExpanded ? String(localized: "Hide") : String(localized: "Details"))
                        Image(systemName: isInsightExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: metrics.metadataFontSize, weight: .medium))
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityHint(String(localized: "Shows the evidence and recommended next step"))
            }

            if isInsightExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    insightDetail(label: String(localized: "Evidence"), text: insight.evidence)
                    insightDetail(label: String(localized: "Next Step"), text: insight.nextStep)
                }
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            insight.isWarning ?
                Color(nsColor: .systemOrange).opacity(0.08) :
                Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    insight.isWarning ?
                        Color(nsColor: .systemOrange).opacity(0.25) :
                        Color.clear,
                    lineWidth: 0.5
                )
        }
    }

    private func insightDetail(label: String, text: String) -> some View {
        (Text("\(label): ").bold() + Text(text))
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Decrypt Future Connections"))
                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            VStack(spacing: 0) {
                if let hostScope = prompt.hostScope {
                    scopeActionRow(scope: hostScope)
                }

                if let appScope = prompt.appScope {
                    Divider()
                        .padding(.leading, 28)
                    scopeActionRow(scope: appScope)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            }

            Text(String(localized: "Changes apply when the app opens a new connection. This response stays encrypted."))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func scopeActionRow(scope: HTTPSInspectionScopePresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: scope.kind.systemImage)
                .font(.system(size: metrics.controlFontSize))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(scope.value)
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let statusDetail = scope.statusDetail {
                    Text(statusDetail)
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                        .help(scope.helpText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            scopeTrailingControl(scope)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func scopeTrailingControl(_ scope: HTTPSInspectionScopePresentation) -> some View {
        switch scope.control {
        case let .toggle(isOn):
            Toggle(
                scope.controlTitle ?? String(localized: "Decrypt Host"),
                isOn: Binding(
                    get: { isOn },
                    set: { _ in
                        if let action = scope.action {
                            onAction(action)
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: metrics.controlFontSize))
            .fixedSize()
            .help(scope.actionDescription)
            .accessibilityLabel(scope.controlTitle ?? String(localized: "Decrypt Host"))
            .accessibilityHint(String(localized: "The current captured response is unchanged"))

        case .button:
            if let action = scope.action, let controlTitle = scope.controlTitle {
                Button(controlTitle) {
                    onAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help(scope.actionDescription)
                .accessibilityLabel(scope.actionDescription)
                .accessibilityHint(String(localized: "The current captured response is unchanged"))
            }

        case .status:
            Label(String(localized: "Ready"), systemImage: "checkmark.circle.fill")
                .font(.system(size: metrics.metadataFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .fixedSize()
                .accessibilityLabel(scope.actionDescription)
        }
    }
}

// MARK: - HTTPSInspectionScopePresentation

struct HTTPSInspectionScopePresentation: Equatable {
    enum Control: Equatable {
        case toggle(isOn: Bool)
        case button
        case status
    }

    enum State: Equatable {
        case available
        case partial
        case ready
    }

    enum Kind: Equatable {
        case host
        case appHosts

        var title: String {
            switch self {
            case .host: String(localized: "This Host")
            case .appHosts: String(localized: "Known App Hosts")
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
    let state: State
    let statusDetail: String?
    let control: Control
    let action: HTTPSInspectionPromptAction?
    let controlTitle: String?
    let actionDescription: String

    var helpText: String {
        [value, statusDetail].compactMap { $0 }.joined(separator: ", ")
    }

    static func host(
        value: String,
        isReady: Bool,
        requiresRetry: Bool = false
    )
        -> HTTPSInspectionScopePresentation
    {
        if requiresRetry {
            return HTTPSInspectionScopePresentation(
                kind: .host,
                value: value,
                state: .partial,
                statusDetail: String(localized: "Protected tunnel active"),
                control: .button,
                action: .retryDomain(value),
                controlTitle: String(localized: "Retry"),
                actionDescription: String(localized: "Retry HTTPS decryption for \(value) on the next connection")
            )
        }

        return HTTPSInspectionScopePresentation(
            kind: .host,
            value: value,
            state: isReady ? .ready : .available,
            statusDetail: isReady ?
                String(localized: "Enabled for new connections") :
                String(localized: "Off for new connections"),
            control: .toggle(isOn: isReady),
            action: isReady ? .disableDomain(value) : .enableDomain(value),
            controlTitle: String(localized: "Decrypt Host"),
            actionDescription: isReady ?
                String(localized: "Turn off HTTPS decryption for new connections to \(value)") :
                String(localized: "Turn on HTTPS decryption for new connections to \(value)")
        )
    }

    static func appHosts(
        name: String,
        enabledHostCount: Int,
        knownHostCount: Int,
        fallbackDomain: String
    )
        -> HTTPSInspectionScopePresentation?
    {
        let total = max(knownHostCount, 1)
        guard total > 1 else {
            return nil
        }

        let enabled = min(max(enabledHostCount, 0), total)
        let state: State = if enabled == total {
            .ready
        } else if enabled > 0 {
            .partial
        } else {
            .available
        }
        let remaining = total - enabled

        return HTTPSInspectionScopePresentation(
            kind: .appHosts,
            value: name,
            state: state,
            statusDetail: state == .ready ?
                String(localized: "All \(total) known hosts enabled") :
                String(localized: "\(enabled) of \(total) known hosts enabled"),
            control: state == .ready ? .status : .button,
            action: state == .ready ? nil : .enableApp(name, fallbackDomain: fallbackDomain),
            controlTitle: state == .ready ? nil : String(localized: "Enable All"),
            actionDescription: state == .ready ?
                String(localized: "HTTPS decryption is enabled for all known hosts used by \(name)") :
                String(localized: "Enable HTTPS decryption for \(remaining) more known hosts used by \(name)")
        )
    }
}
