import SwiftUI

// MARK: - MapLocalRuleTesterSection

struct MapLocalRuleTesterSection: View {
    @Bindable var viewModel: MapLocalEditorViewModel

    let toolMetrics: ToolWindowDisplayMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Test this rule"))
                .font(toolMetrics.secondaryFont(weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: toolMetrics.controlSpacing) {
                Picker(String(localized: "Test method"), selection: $viewModel.testMethod) {
                    ForEach(MapLocalHTTPMethod.allCases.filter { $0 != .any }) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(94))

                TextField("https://example.com/api/users", text: $viewModel.testURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "Test request URL"))

                Button(String(localized: "Test")) { viewModel.testRule() }
                    .disabled(viewModel.testURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(String(localized: "Test Map Local rule"))
            }

            if let result = viewModel.visibleTestResult {
                resultLabel(result)
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func resultLabel(_ result: MapLocalRuleTestResult) -> some View {
        switch result {
        case .matched:
            Label(
                String(localized: "Matched — this request will use the local response."),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .notMatched:
            Label(
                String(localized: "Not matched — this request will continue to the origin."),
                systemImage: "xmark.circle.fill"
            )
            .foregroundStyle(.secondary)
        case .invalidURL:
            Label(
                String(localized: "Enter a complete HTTP or HTTPS URL."),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
        case let .invalidPattern(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - MapLocalHTTPSPrerequisiteNotice

/// Keeps HTTPS interception prerequisites visible at the point where a Map Local URL is authored.
/// Enabling interception remains an explicit user action and never removes Exclude/Bypass policy.
struct MapLocalHTTPSPrerequisiteNotice: View {
    // MARK: Internal

    let isHTTPSPattern: Bool
    let targetHost: String?
    let toolMetrics: ToolWindowDisplayMetrics

    var body: some View {
        if isHTTPSPattern {
            if let targetHost {
                hostNotice(targetHost)
            } else {
                manualConfigurationNotice
            }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @State private var sslProxyingManager = SSLProxyingManager.shared

    private var manualConfigurationNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
            Text(
                String(
                    localized:
                    "HTTPS regex or wildcard-host rules require a matching host in HTTPS Decryption. Rockxy cannot safely infer one from this pattern."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Open HTTPS Decryption")) {
                openWindow(id: "sslProxyingList")
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func hostNotice(_ host: String) -> some View {
        let ready = sslProxyingManager.shouldIntercept(host)
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(ready ? Color.green : Color.orange)
            Text(
                ready
                    ? String(localized: "HTTPS interception is ready for \(host).")
                    :
                    String(
                        localized: "HTTPS Map Local needs SSL Proxying for \(host) before this rule can see the request."
                    )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
            if !ready {
                Button(String(localized: "Enable for Host")) {
                    enableSSLProxying(for: host)
                }
            }
            Button(String(localized: "Open HTTPS Decryption")) {
                openWindow(id: "sslProxyingList")
            }
        }
        .padding(9)
        .background((ready ? Color.green : Color.orange).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func enableSSLProxying(for host: String) {
        if !sslProxyingManager.isEnabled {
            sslProxyingManager.setEnabled(true)
        }
        if let rule = sslProxyingManager.includeRules.first(where: { $0.matches(host) }) {
            sslProxyingManager.setRuleEnabled(id: rule.id, enabled: true)
        } else {
            sslProxyingManager.addRule(SSLProxyingRule(domain: host, listType: .include))
        }
        _ = sslProxyingManager.retryInterception(for: host)
    }
}

// MARK: - MapLocalHTTPResponseSection

/// Full HTTP response message editor shared by file and directory Map Local sources.
struct MapLocalHTTPResponseSection: View {
    @Binding var text: String

    let bodyIsEditable: Bool
    let bodyDescription: String
    let toolMetrics: ToolWindowDisplayMetrics
    var messageIsEditable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bodyIsEditable ? String(localized: "HTTP response") : String(localized: "Response status and headers"))
                .foregroundStyle(.secondary)
            MapLocalHTTPMessageEditor(
                text: $text,
                editorSettings: toolMetrics.codeEditorSettings,
                isEditable: messageIsEditable
            )
            .frame(minHeight: bodyIsEditable ? 230 : 150)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            Text(bodyDescription)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }
}
