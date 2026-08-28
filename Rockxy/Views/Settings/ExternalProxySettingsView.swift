import SwiftUI

// MARK: - ExternalProxySettingsView

struct ExternalProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            behaviorNotice
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
                    protocolSection
                    endpointSection
                    bypassSection
                }
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            if viewModel.status != nil || viewModel.hasExternalConflict {
                Divider()
                statusSection
            }

            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(900), height: 680)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .upstreamProxyConfigurationDidChange,
                object: UpstreamProxyStore.shared
            )
        ) { _ in
            viewModel.handleExternalConfigurationChange()
        }
    }

    // MARK: Private

    private enum FocusField: Hashable {
        case pacURL
        case host
        case port
        case username
        case password
        case bypass
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var viewModel = UpstreamProxySettingsViewModel()
    @FocusState private var focusedField: FocusField?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var endpointSectionTitle: String {
        switch viewModel.draft.selectedProtocol {
        case .automatic:
            String(localized: "Automatic Configuration", bundle: RockxyLocalization.bundle)
        case .http:
            String(localized: "HTTP Proxy", bundle: RockxyLocalization.bundle)
        case .https:
            String(localized: "HTTPS Proxy", bundle: RockxyLocalization.bundle)
        case .socks5:
            String(localized: "SOCKS5 Proxy", bundle: RockxyLocalization.bundle)
        }
    }

    private var protocolBinding: Binding<ExternalProxyProtocolSelection> {
        Binding(
            get: { viewModel.draft.selectedProtocol },
            set: { selection in
                guard selection != .socks5 || viewModel.canSelectSOCKS5 else {
                    return
                }
                viewModel.draft.selectedProtocol = selection
            }
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "External Proxy", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))

                Text(String(
                    localized: "Route eligible captured traffic through an upstream proxy.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                String(localized: "Enable External Proxy", bundle: RockxyLocalization.bundle),
                isOn: draftBinding(\.isEnabled)
            )
            .toggleStyle(.switch)
            .accessibilityHint(
                String(
                    localized: "Changes take effect only after you apply these settings.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var behaviorNotice: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)

            Text(
                String(
                    localized:
                    """
                    Applied settings affect new eligible captured connections. Upstream bypass entries are still \
                    captured by Rockxy; Rockxy connects to those destinations directly instead of using the upstream \
                    proxy.
                    """, bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Protocol", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            if toolMetrics.bodyFontSize >= 20 {
                Picker(
                    String(localized: "Upstream proxy protocol", bundle: RockxyLocalization.bundle),
                    selection: protocolBinding
                ) {
                    protocolOptions
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: toolMetrics.menuWidth(360))
                .accessibilityHint(fieldAccessibilityHint(
                    for: .protocolSelection,
                    fallback: String(
                        localized: "Select the upstream proxy protocol.",
                        bundle: RockxyLocalization.bundle
                    )
                ))
            } else {
                Picker(
                    String(localized: "Upstream proxy protocol", bundle: RockxyLocalization.bundle),
                    selection: protocolBinding
                ) {
                    protocolOptions
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityHint(fieldAccessibilityHint(
                    for: .protocolSelection,
                    fallback: String(
                        localized: "Select the upstream proxy protocol.",
                        bundle: RockxyLocalization.bundle
                    )
                ))
            }

            if !viewModel.canSelectSOCKS5 {
                PolicyLockNotice(
                    title: String(localized: "SOCKS5 unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "This build keeps SOCKS5 visible for configuration compatibility, but it cannot be selected or applied.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }

            fieldError(.protocolSelection)
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    private var protocolOptions: some View {
        ForEach(ExternalProxyProtocolSelection.allCases) { protocolSelection in
            Text(protocolOptionName(protocolSelection))
                .tag(protocolSelection)
                .disabled(protocolSelection == .socks5 && !viewModel.canSelectSOCKS5)
        }
    }

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            Text(endpointSectionTitle)
                .font(toolMetrics.tableHeaderFont())

            switch viewModel.draft.selectedProtocol {
            case .automatic:
                pacConfiguration
            case .http,
                 .https,
                 .socks5:
                serverConfiguration
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    private var pacConfiguration: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "PAC URL", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font())
            TextField(
                String(localized: "https://proxy.example.com/proxy.pac", bundle: RockxyLocalization.bundle),
                text: draftBinding(\.pacURL)
            )
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font())
            .frame(height: toolMetrics.formControlHeight)
            .focused($focusedField, equals: .pacURL)
            .accessibilityLabel(String(
                localized: "Proxy automatic configuration URL",
                bundle: RockxyLocalization.bundle
            ))
            .accessibilityHint(fieldAccessibilityHint(
                for: .pacURL,
                fallback: String(localized: "Enter an HTTP or HTTPS PAC file URL.", bundle: RockxyLocalization.bundle)
            ))

            if let message = viewModel.validationMessage(for: .pacURL) {
                validationText(message)
            } else {
                Text(String(
                    localized: "Rockxy downloads this PAC file when resolving a new route.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var serverConfiguration: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Host", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font())
                    TextField(
                        String(localized: "proxy.example.com", bundle: RockxyLocalization.bundle),
                        text: draftBinding(\.host)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(height: toolMetrics.formControlHeight)
                    .focused($focusedField, equals: .host)
                    .accessibilityLabel(String(localized: "Upstream proxy host", bundle: RockxyLocalization.bundle))
                    .accessibilityHint(fieldAccessibilityHint(
                        for: .host,
                        fallback: String(
                            localized: "Enter a hostname or IP address without a URL scheme.",
                            bundle: RockxyLocalization.bundle
                        )
                    ))
                    fieldError(.host)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Port", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font())
                    TextField(
                        String(localized: "8080", bundle: RockxyLocalization.bundle),
                        text: draftBinding(\.portText)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(width: toolMetrics.fieldWidth(110), height: toolMetrics.formControlHeight)
                    .focused($focusedField, equals: .port)
                    .accessibilityLabel(String(localized: "Upstream proxy port", bundle: RockxyLocalization.bundle))
                    .accessibilityHint(fieldAccessibilityHint(
                        for: .port,
                        fallback: String(
                            localized: "Enter a port between 1 and 65535.",
                            bundle: RockxyLocalization.bundle
                        )
                    ))
                    fieldError(.port)
                }
            }

            Divider()

            authenticationSection
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            Toggle(
                String(localized: "Proxy requires authentication", bundle: RockxyLocalization.bundle),
                isOn: draftBinding(\.usesAuthentication)
            )
            .toggleStyle(.checkbox)
            .disabled(viewModel.isAuthenticationToggleDisabled)
            .accessibilityHint(fieldAccessibilityHint(
                for: .authentication,
                fallback: String(
                    localized: "Use saved credentials for the upstream proxy.",
                    bundle: RockxyLocalization.bundle
                )
            ))

            if !viewModel.canEnableAuthentication {
                PolicyLockNotice(
                    title: String(localized: "Authentication unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized:
                        """
                        This build does not allow upstream proxy credentials. Existing saved credentials remain in \
                        secure storage until authentication is removed and applied.
                        """, bundle: RockxyLocalization.bundle
                    )
                )
            } else if viewModel.draft.usesAuthentication {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Username", bundle: RockxyLocalization.bundle))
                            .font(toolMetrics.font())
                        TextField(
                            String(localized: "Username", bundle: RockxyLocalization.bundle),
                            text: draftBinding(\.username)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(height: toolMetrics.formControlHeight)
                        .focused($focusedField, equals: .username)
                        .accessibilityHint(fieldAccessibilityHint(
                            for: .username,
                            fallback: String(
                                localized: "Enter the upstream proxy username.",
                                bundle: RockxyLocalization.bundle
                            )
                        ))
                        fieldError(.username)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Password", bundle: RockxyLocalization.bundle))
                            .font(toolMetrics.font())
                        SecureField(
                            viewModel.draft.hasStoredCredentials
                                ? String(
                                    localized: "Leave blank to keep saved password",
                                    bundle: RockxyLocalization.bundle
                                )
                                : String(localized: "Password", bundle: RockxyLocalization.bundle),
                            text: draftBinding(\.password)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(height: toolMetrics.formControlHeight)
                        .focused($focusedField, equals: .password)
                        .accessibilityHint(fieldAccessibilityHint(
                            for: .password,
                            fallback: viewModel.draft.hasStoredCredentials
                                ? String(
                                    localized: "Leave blank to keep the saved password.",
                                    bundle: RockxyLocalization.bundle
                                )
                                : String(
                                    localized: "Enter the upstream proxy password.",
                                    bundle: RockxyLocalization.bundle
                                )
                        ))
                        fieldError(.password)
                    }
                }
            }

            fieldError(.authentication)
        }
    }

    private var bypassSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            HStack {
                Text(String(localized: "Upstream Bypass", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())

                Spacer()

                Text(
                    String(
                        localized: "\(viewModel.bypassEntriesUsed) of \(viewModel.bypassEntriesLimit) entries",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.metadataFont(weight: .medium))
                .foregroundStyle(
                    viewModel.bypassEntriesUsed > viewModel.bypassEntriesLimit
                        ? Color.red
                        : Color.secondary
                )
            }

            TextEditor(text: draftBinding(\.bypassText))
                .font(toolMetrics.font(monospaced: true))
                .frame(height: 88)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .focused($focusedField, equals: .bypass)
                .accessibilityLabel(String(
                    localized: "Upstream proxy bypass host patterns",
                    bundle: RockxyLocalization.bundle
                ))
                .accessibilityHint(fieldAccessibilityHint(
                    for: .bypass,
                    fallback: String(
                        localized: "Separate host patterns with commas or new lines.",
                        bundle: RockxyLocalization.bundle
                    )
                ))

            fieldError(.bypass)

            Text(
                String(
                    localized: "Separate host patterns with commas or new lines. Wildcards * and ? are supported; duplicates are removed when applied.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)

            Toggle(
                String(localized: "Always bypass the upstream proxy for localhost", bundle: RockxyLocalization.bundle),
                isOn: draftBinding(\.bypassLocalhost)
            )
            .toggleStyle(.checkbox)
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    @ViewBuilder private var statusSection: some View {
        if viewModel.hasExternalConflict {
            HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)

                Text(
                    String(
                        localized: "The saved Upstream Proxy configuration changed while you were editing.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())

                Spacer()

                Button(String(localized: "Keep Editing", bundle: RockxyLocalization.bundle)) {
                    viewModel.keepEditingAfterExternalChange()
                }

                Button(String(localized: "Reload", bundle: RockxyLocalization.bundle)) {
                    viewModel.reloadExternalConfiguration()
                }
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        } else if let status = viewModel.status {
            StatusDisclosure(status: status)
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.controlSpacing)
        }
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(
                viewModel.isDirty
                    ? String(localized: "Unsaved changes", bundle: RockxyLocalization.bundle)
                    : String(localized: "Saved configuration", bundle: RockxyLocalization.bundle)
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)

            Spacer()

            footerActions
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var footerActions: some View {
        HStack(spacing: Theme.Layout.controlSpacing) {
            Button(
                viewModel.isTesting
                    ? String(localized: "Testing…", bundle: RockxyLocalization.bundle)
                    : String(localized: "Test Connection", bundle: RockxyLocalization.bundle)
            ) {
                Task {
                    await viewModel.testConnection()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!viewModel.canTest)

            Button {
                dismiss()
            } label: {
                footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
            }
            .keyboardShortcut(.cancelAction)

            Button {
                applyAndDismiss()
            } label: {
                footerButtonLabel(String(localized: "Apply", bundle: RockxyLocalization.bundle))
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(!viewModel.canApply)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: toolMetrics.footerButtonWidth - (toolMetrics.controlSpacing * 3)
            )
    }

    @ViewBuilder
    private func fieldError(_ field: UpstreamProxySettingsField) -> some View {
        if let message = viewModel.validationMessage(for: field) {
            validationText(message)
        }
    }

    private func validationText(_ message: String) -> some View {
        Text(message)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func protocolOptionName(
        _ selection: ExternalProxyProtocolSelection
    )
        -> String
    {
        guard selection == .socks5, !viewModel.canSelectSOCKS5 else {
            return selection.displayName
        }
        return String(localized: "\(selection.displayName) — Unavailable", bundle: RockxyLocalization.bundle)
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<ExternalProxySettingsDraft, Value>
    )
        -> Binding<Value>
    {
        Binding(
            get: { viewModel.draft[keyPath: keyPath] },
            set: { viewModel.draft[keyPath: keyPath] = $0 }
        )
    }

    private func fieldAccessibilityHint(
        for field: UpstreamProxySettingsField,
        fallback: String
    )
        -> String
    {
        viewModel.validationMessage(for: field) ?? fallback
    }

    private func applyAndDismiss() {
        do {
            try viewModel.apply()
            dismiss()
        } catch {
            // The view model keeps field-level errors visible. Unexpected store
            // failures are surfaced through the same status region.
        }
    }
}

// MARK: - StatusDisclosure

private struct StatusDisclosure: View {
    // MARK: Internal

    let status: UpstreamProxySettingsStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(isError ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var isError: Bool {
        if case .failure = status {
            return true
        }
        return false
    }

    private var message: String {
        switch status {
        case let .success(message),
             let .failure(message):
            message
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
