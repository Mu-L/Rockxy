import AppKit
import SwiftUI

// MARK: - MacCertificateSetupGuideView

struct MacCertificateSetupGuideView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()

            switch selectedTab {
            case .automatic:
                ScrollView {
                    automaticContent
                        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                        .padding(.top, toolMetrics.headerTopPadding + 10)
                        .padding(.bottom, toolMetrics.headerTopPadding)
                }
            case .manual:
                ScrollView {
                    manualContent
                        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                        .padding(.top, toolMetrics.headerTopPadding + 10)
                        .padding(.bottom, toolMetrics.headerTopPadding)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .font(toolMetrics.font())
        .task { await refreshStatus(validate: true) }
        .onChange(of: selectedTab) { _, _ in manualTrustCopyMessage = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard activeOperation == nil else {
                return
            }
            Task { await refreshStatus(validate: true) }
        }
        .alert(String(localized: "Certificate Setup Failed", bundle: RockxyLocalization.bundle), isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum Tab: CaseIterable, Identifiable {
        case automatic
        case manual

        // MARK: Internal

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .automatic:
                String(localized: "Automatic", bundle: RockxyLocalization.bundle)
            case .manual:
                String(localized: "Manual", bundle: RockxyLocalization.bundle)
            }
        }
    }

    private enum Operation {
        case generating
        case installing
        case checking

        // MARK: Internal

        var statusMessage: String {
            switch self {
            case .generating:
                String(localized: "Generating the Rockxy certificate…", bundle: RockxyLocalization.bundle)
            case .installing:
                String(localized: "Installing and trusting the certificate…", bundle: RockxyLocalization.bundle)
            case .checking:
                String(localized: "Checking certificate trust…", bundle: RockxyLocalization.bundle)
            }
        }
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var selectedTab = Tab.automatic
    @State private var snapshot: RootCAStatusSnapshot?
    @State private var hasLoadedSnapshot = false
    @State private var activeOperation: Operation?
    @State private var errorMessage: String?
    @State private var manualTrustCopyMessage: String?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var currentState: CertificateSetupState {
        CertificateSetupState(snapshot: snapshot ?? .empty)
    }

    private var primaryActionTitle: String {
        switch currentState {
        case .missing:
            String(localized: "Generate, Install & Trust", bundle: RockxyLocalization.bundle)
        case .generatedOnly:
            String(localized: "Install & Trust", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "Repair Trust", bundle: RockxyLocalization.bundle)
        case .installedAndTrusted:
            String(localized: "Installed & Trusted", bundle: RockxyLocalization.bundle)
        case .statusUnavailable:
            String(localized: "Recheck Status", bundle: RockxyLocalization.bundle)
        }
    }

    private var primaryActionIcon: String {
        switch currentState {
        case .statusUnavailable:
            "arrow.clockwise"
        case .installedAndTrusted:
            "checkmark.shield.fill"
        case .generatedOnly,
             .installedNotTrusted,
             .missing:
            "checkmark.shield"
        }
    }

    /// True when the state is unknown rather than known-bad. The primary action becomes a read,
    /// and no field claims the certificate is missing, untrusted, or rejected.
    private var isStatusUnavailable: Bool {
        snapshot?.isStatusUnavailable == true
    }

    private var unavailableValueText: String {
        String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
    }

    private var systemValidationText: String {
        guard let snapshot else {
            return String(localized: "Not Checked", bundle: RockxyLocalization.bundle)
        }
        if snapshot.isStatusUnavailable {
            return unavailableValueText
        }
        guard snapshot.hasTrustSettings else {
            return String(localized: "Not Checked", bundle: RockxyLocalization.bundle)
        }
        return snapshot.isSystemTrustValidated
            ? String(localized: "Passed", bundle: RockxyLocalization.bundle)
            : String(localized: "Failed", bundle: RockxyLocalization.bundle)
    }

    private var systemValidationColor: Color {
        guard let snapshot else {
            return .secondary
        }
        if snapshot.isStatusUnavailable {
            return .orange
        }
        guard snapshot.hasTrustSettings else {
            return .secondary
        }
        return snapshot.isSystemTrustValidated ? .green : .red
    }

    /// The reason to show for an unreadable status, shown regardless of `hasTrustSettings` —
    /// that flag is a fail-closed default here, not evidence about the certificate.
    private var statusUnavailableMessage: String? {
        guard let snapshot, snapshot.isStatusUnavailable else {
            return nil
        }
        return snapshot.statusReadErrorMessage ?? String(
            localized: "Rockxy could not read the certificate status, so nothing was changed. Recheck the status once your keychain is available.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var expiryColor: Color {
        guard let expiryDate = snapshot?.notValidAfter else {
            return .primary
        }
        if expiryDate < Date() {
            return .red
        }
        return expiryDate.timeIntervalSinceNow < 30 * 24 * 3_600 ? .orange : .primary
    }

    private var expiryWarningMessage: String? {
        guard let expiryDate = snapshot?.notValidAfter else {
            return nil
        }
        if expiryDate < Date() {
            return String(
                localized: "This certificate has expired. Generate and trust a new certificate to restore HTTPS interception.",
                bundle: RockxyLocalization.bundle
            )
        }
        let daysRemaining = Int(expiryDate.timeIntervalSinceNow / (24 * 3_600))
        guard daysRemaining < 30 else {
            return nil
        }
        return String(
            localized: "This certificate expires in \(daysRemaining) days. Replace it soon to avoid interrupting HTTPS interception.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var truncatedFingerprint: String {
        guard let fingerprint = snapshot?.fingerprintSHA256 else {
            return "—"
        }
        guard fingerprint.count > 28 else {
            return fingerprint
        }
        return String(fingerprint.prefix(28)) + "…"
    }

    private var statusIconSize: CGFloat {
        max(26, toolMetrics.bodyFontSize + 14)
    }

    private var stepIconSize: CGFloat {
        max(18, toolMetrics.bodyFontSize + 5)
    }

    private var commandBoxHeight: CGFloat {
        max(56, toolMetrics.bodyFontSize + 40)
    }

    // MARK: Behavior

    private var manualTrustCommand: String {
        [
            "sudo security add-trusted-cert",
            "-d",
            "-r trustRoot",
            "-k /Library/Keychains/System.keychain",
            shellQuoted(CertificateStore.rootCACertificateURL.path)
        ].joined(separator: " ")
    }

    private var stepContentInset: CGFloat {
        stepIconSize + toolMetrics.controlSpacing + 2
    }

    // MARK: Mode

    private var modeBar: some View {
        ZStack {
            modePicker

            HStack {
                Spacer()
                if let helpURL = URL(string: "https://github.com/RockxyApp/Rockxy/wiki") {
                    HelpLink(destination: helpURL)
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerTopPadding)
        .rockxyFunctionalBar()
    }

    private var modePicker: some View {
        ViewThatFits(in: .horizontal) {
            modePickerBase
                .pickerStyle(.segmented)
                .frame(width: 320)
            modePickerBase
                .pickerStyle(.menu)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(String(localized: "Setup Mode", bundle: RockxyLocalization.bundle))
    }

    private var modePickerBase: some View {
        Picker(String(localized: "Setup Mode", bundle: RockxyLocalization.bundle), selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .labelsHidden()
    }

    // MARK: Readiness

    @ViewBuilder private var readinessSection: some View {
        if hasLoadedSnapshot {
            let state = currentState
            HStack(alignment: .top, spacing: toolMetrics.controlSpacing + 4) {
                Image(systemName: state.systemImageName)
                    .font(.system(size: statusIconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.isReady ? Color.green : Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(toolMetrics.font(weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.message)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: toolMetrics.controlSpacing + 4) {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: statusIconSize, height: statusIconSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Checking Certificate", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .semibold))
                    Text(String(
                        localized: "Reading the certificate, Keychain, and macOS trust state.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Automatic

    private var automaticContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            readinessSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                            diagnosticsGrid
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            readinessSection
                            diagnosticsGrid
                        }
                    }

                    validationCallout

                    if let activeOperation {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(activeOperation.statusMessage)
                                .font(toolMetrics.secondaryFont())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Divider()
                    automaticActionRow
                }
                .padding(6)
            } label: {
                Label(
                    String(localized: "Certificate Readiness", bundle: RockxyLocalization.bundle),
                    systemImage: "checkmark.shield"
                )
                .font(toolMetrics.font(weight: .semibold))
            }

            if snapshot?.hasGeneratedCertificate == true {
                GroupBox {
                    certificateDetails
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(
                        String(localized: "Certificate Details", bundle: RockxyLocalization.bundle),
                        systemImage: "info.circle"
                    )
                    .font(toolMetrics.font(weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var automaticActionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: toolMetrics.controlSpacing) {
                automaticPrimaryActions
                Spacer(minLength: toolMetrics.controlSpacing)
                certificateUtilityActions
            }

            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    automaticPrimaryActions
                }
                HStack(spacing: toolMetrics.controlSpacing) {
                    certificateUtilityActions
                }
            }
        }
    }

    @ViewBuilder private var automaticPrimaryActions: some View {
        Button {
            // An unreadable status is answered by reading it again. Installing and trusting here
            // would request administrator approval for material this window cannot describe.
            Task {
                if isStatusUnavailable {
                    await recheckStatus()
                } else {
                    await installAndTrust()
                }
            }
        } label: {
            Label(primaryActionTitle, systemImage: primaryActionIcon)
        }
        .keyboardShortcut(.defaultAction)
        .rockxyGlassButtonStyle(prominent: true)
        .disabled(activeOperation != nil || currentState.isReady || !hasLoadedSnapshot)

        if !isStatusUnavailable {
            Button {
                Task { await recheckStatus() }
            } label: {
                Label(String(localized: "Recheck", bundle: RockxyLocalization.bundle), systemImage: "arrow.clockwise")
            }
            .disabled(activeOperation != nil)
        }
    }

    @ViewBuilder private var certificateUtilityActions: some View {
        if snapshot?.hasGeneratedCertificate == true {
            exportPEMButton
            manageCertificatesButton
        }
    }

    private var diagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            diagnosticRow(
                label: String(localized: "Certificate", bundle: RockxyLocalization.bundle),
                value: snapshot?.isGeneratedStateKnown == false
                    ? unavailableValueText
                    : (
                        snapshot?.hasGeneratedCertificate == true
                            ? String(localized: "Generated", bundle: RockxyLocalization.bundle)
                            : String(localized: "Not Generated", bundle: RockxyLocalization.bundle)
                    ),
                isComplete: snapshot?.hasGeneratedCertificate == true,
                color: snapshot?.isGeneratedStateKnown == false ? .orange : nil
            )
            diagnosticRow(
                label: String(localized: "Keychain", bundle: RockxyLocalization.bundle),
                value: isStatusUnavailable
                    ? unavailableValueText
                    : (
                        snapshot?.isInstalledInKeychain == true
                            ? String(localized: "Installed", bundle: RockxyLocalization.bundle)
                            : String(localized: "Not Installed", bundle: RockxyLocalization.bundle)
                    ),
                isComplete: snapshot?.isInstalledInKeychain == true,
                color: isStatusUnavailable ? .orange : nil
            )
            diagnosticRow(
                label: String(localized: "Trust Settings", bundle: RockxyLocalization.bundle),
                value: isStatusUnavailable
                    ? unavailableValueText
                    : (
                        snapshot?.hasTrustSettings == true
                            ? String(localized: "Present", bundle: RockxyLocalization.bundle)
                            : String(localized: "Missing", bundle: RockxyLocalization.bundle)
                    ),
                isComplete: snapshot?.hasTrustSettings == true,
                color: isStatusUnavailable ? .orange : nil
            )
            diagnosticRow(
                label: String(localized: "TLS Validation", bundle: RockxyLocalization.bundle),
                value: systemValidationText,
                isComplete: snapshot?.isSystemTrustValidated == true,
                color: systemValidationColor
            )
        }
        .opacity(hasLoadedSnapshot ? 1 : 0.45)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var validationCallout: some View {
        if let statusUnavailableMessage {
            callout(
                message: statusUnavailableMessage,
                systemImage: "questionmark.circle.fill",
                color: .orange
            )
        } else if let snapshot,
                  snapshot.hasTrustSettings,
                  !snapshot.isSystemTrustValidated
        {
            let message = snapshot.lastValidationErrorMessage
                ?? String(
                    localized: "Trust settings exist, but macOS TLS validation still fails. Repair trust, then recheck the certificate.",
                    bundle: RockxyLocalization.bundle
                )
            callout(
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    private var certificateDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                detailRow(
                    label: String(localized: "Common Name", bundle: RockxyLocalization.bundle),
                    value: snapshot?.commonName ?? "—"
                )
                detailRow(
                    label: String(localized: "Valid From", bundle: RockxyLocalization.bundle),
                    value: snapshot?.notValidBefore?.formatted(date: .abbreviated, time: .omitted) ?? "—"
                )
                detailRow(
                    label: String(localized: "Valid Until", bundle: RockxyLocalization.bundle),
                    value: snapshot?.notValidAfter?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                    color: expiryColor
                )
                detailRow(
                    label: String(localized: "SHA-256", bundle: RockxyLocalization.bundle),
                    value: truncatedFingerprint,
                    monospaced: true,
                    accessibilityValue: snapshot?.fingerprintSHA256
                )
            }

            if let expiryWarningMessage {
                callout(
                    message: expiryWarningMessage,
                    systemImage: "clock.badge.exclamationmark",
                    color: expiryColor
                )
            }
        }
    }

    // MARK: Manual

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    readinessSection

                    if let activeOperation {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(activeOperation.statusMessage)
                                .font(toolMetrics.secondaryFont())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: toolMetrics.controlSpacing) {
                            recheckButton
                            if snapshot?.hasGeneratedCertificate == true {
                                manageCertificatesButton
                            }
                        }
                        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                            recheckButton
                            if snapshot?.hasGeneratedCertificate == true {
                                manageCertificatesButton
                            }
                        }
                    }
                }
                .padding(6)
            } label: {
                Label(
                    String(localized: "Current Status", bundle: RockxyLocalization.bundle),
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                .font(toolMetrics.font(weight: .semibold))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    manualStep(
                        number: 1,
                        isComplete: snapshot?.isInstalledInKeychain == true,
                        title: String(
                            localized: "Add the Rockxy CA to the System keychain",
                            bundle: RockxyLocalization.bundle
                        ),
                        lines: [
                            String(
                                localized: "Generate the certificate if needed, then export it as a PEM file.",
                                bundle: RockxyLocalization.bundle
                            ),
                            String(
                                localized: "Open Keychain Access, choose System under System Keychains, and drag the PEM into the certificate list.",
                                bundle: RockxyLocalization.bundle
                            )
                        ]
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: toolMetrics.controlSpacing) {
                            manualCertificateActions
                        }
                        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                            manualCertificateActions
                        }
                    }
                    .padding(.leading, stepContentInset)

                    Divider()

                    manualStep(
                        number: 2,
                        isComplete: snapshot?.isSystemTrustValidated == true,
                        title: String(localized: "Trust the certificate", bundle: RockxyLocalization.bundle),
                        lines: [
                            String(
                                localized: "Search for Rockxy CA, open the certificate, and expand Trust.",
                                bundle: RockxyLocalization.bundle
                            ),
                            String(
                                localized: "Set When using this certificate to Always Trust, then close the window and approve the change.",
                                bundle: RockxyLocalization.bundle
                            )
                        ]
                    )

                    openKeychainButton
                        .padding(.leading, stepContentInset)

                    if let statusUnavailableMessage {
                        // Not "macOS rejects it": nothing was read, so the manual re-trust steps
                        // are not the fix and are not offered as one.
                        callout(
                            message: statusUnavailableMessage,
                            systemImage: "questionmark.circle.fill",
                            color: .orange
                        )
                        .padding(.leading, stepContentInset)
                    } else if let snapshot,
                              snapshot.hasTrustSettings,
                              !snapshot.isSystemTrustValidated
                    {
                        callout(
                            message: snapshot.lastValidationErrorMessage
                                ?? String(
                                    localized: "macOS still rejects the certificate. Confirm the trust setting, then recheck.",
                                    bundle: RockxyLocalization.bundle
                                ),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .red
                        )
                        .padding(.leading, stepContentInset)
                    }
                }
                .padding(6)
            } label: {
                Label(String(localized: "Keychain Access", bundle: RockxyLocalization.bundle), systemImage: "key")
                    .font(toolMetrics.font(weight: .semibold))
            }

            GroupBox {
                terminalAlternative
                    .padding(6)
            } label: {
                Label(String(localized: "Terminal", bundle: RockxyLocalization.bundle), systemImage: "terminal")
                    .font(toolMetrics.font(weight: .semibold))
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var manualCertificateActions: some View {
        // Generation is offered only when the absence of a certificate is a real finding. Under
        // an unreadable status it would be a guess about material that may already exist.
        if snapshot?.hasGeneratedCertificate != true, !isStatusUnavailable {
            Button {
                Task { await generateCertificate() }
            } label: {
                Label(
                    String(localized: "Generate Certificate", bundle: RockxyLocalization.bundle),
                    systemImage: "plus.circle"
                )
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(activeOperation != nil || !hasLoadedSnapshot)
        }

        exportPEMButton
    }

    private var recheckButton: some View {
        Button {
            Task { await recheckStatus() }
        } label: {
            Label(String(localized: "Recheck", bundle: RockxyLocalization.bundle), systemImage: "arrow.clockwise")
        }
        .disabled(activeOperation != nil || !hasLoadedSnapshot)
    }

    private var openKeychainButton: some View {
        Button {
            openKeychainAccess()
        } label: {
            Label(
                String(localized: "Open Keychain Access", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.up.forward.app"
            )
        }
    }

    private var terminalAlternative: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Trust with Terminal", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
            Text(
                String(
                    localized: "Use this command if you prefer Terminal or Keychain Access cannot complete the trust change.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            commandBox(manualTrustCommand)

            Text(
                String(
                    localized: "Automatically trusts the Rockxy CA in your System keychain. Administrator approval is required.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.metadataFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: toolMetrics.controlSpacing) {
                Button(String(localized: "Copy", bundle: RockxyLocalization.bundle)) {
                    copyManualTrustCommand()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(snapshot?.hasGeneratedCertificate != true)

                if let manualTrustCopyMessage {
                    Text(manualTrustCopyMessage)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared actions

    private var exportPEMButton: some View {
        Button {
            CertificateExportPanelPresenter().export(format: .rootCertificatePEM)
        } label: {
            Label(
                String(localized: "Export PEM", bundle: RockxyLocalization.bundle),
                systemImage: "square.and.arrow.up"
            )
        }
        .disabled(activeOperation != nil || snapshot?.hasGeneratedCertificate != true)
        .help(String(localized: "Save the public Rockxy root CA as a PEM file", bundle: RockxyLocalization.bundle))
    }

    private var manageCertificatesButton: some View {
        Button(String(localized: "Manage Certificates", bundle: RockxyLocalization.bundle)) {
            openGeneralSettings()
        }
        .help(String(localized: "Open certificate management in General settings", bundle: RockxyLocalization.bundle))
    }

    private func diagnosticRow(
        label: String,
        value: String,
        isComplete: Bool,
        color: Color? = nil
    )
        -> some View
    {
        GridRow {
            Text(label)
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)

            HStack(spacing: 5) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
                Text(value)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(color ?? (isComplete ? Color.primary : Color.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detailRow(
        label: String,
        value: String,
        monospaced: Bool = false,
        color: Color = .primary,
        accessibilityValue: String? = nil
    )
        -> some View
    {
        GridRow {
            Text(label)
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(toolMetrics.secondaryFont(monospaced: monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(accessibilityValue ?? value)
        }
    }

    private func callout(message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(toolMetrics.metadataFont())
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func manualStep(number: Int, isComplete: Bool, title: String, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing + 2) {
            stepBadge(number, isComplete: isComplete)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(toolMetrics.font(weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepBadge(_ number: Int, isComplete: Bool) -> some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle.fill")
            .font(.system(size: stepIconSize))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isComplete ? Color.green : Color.secondary)
            .accessibilityHidden(true)
    }

    private func commandBox(_ command: String) -> some View {
        ScrollView(.horizontal) {
            Text(command)
                .font(toolMetrics.font(monospaced: true))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: commandBoxHeight)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityLabel(String(localized: "Manual trust command", bundle: RockxyLocalization.bundle))
        .accessibilityValue(command)
    }

    private func shellQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func copyManualTrustCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(manualTrustCommand, forType: .string)
        manualTrustCopyMessage = String(localized: "Copied.", bundle: RockxyLocalization.bundle)
    }

    private func openGeneralSettings() {
        RockxySettingsTab.select(.general)
        openWindow(id: "settings")
    }

    private func openKeychainAccess() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.keychainaccess"
        ),
            NSWorkspace.shared.open(url) else
        {
            errorMessage = String(localized: "Keychain Access is unavailable.", bundle: RockxyLocalization.bundle)
            return
        }
    }

    private func generateCertificate() async {
        activeOperation = .generating
        defer { activeOperation = nil }
        do {
            try await CertificateManager.shared.ensureRootCA()
            await refreshStatus(validate: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installAndTrust() async {
        activeOperation = .installing
        defer { activeOperation = nil }
        do {
            try await CertificateManager.shared.installAndTrust()
            await refreshStatus(validate: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recheckStatus() async {
        activeOperation = .checking
        defer { activeOperation = nil }
        await refreshStatus(validate: true)
    }

    private func refreshStatus(validate: Bool) async {
        snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: validate)
        hasLoadedSnapshot = true
    }
}

private extension RootCAStatusSnapshot {
    static let empty = RootCAStatusSnapshot(
        hasGeneratedCertificate: false,
        isInstalledInKeychain: false,
        hasTrustSettings: false,
        isSystemTrustValidated: false,
        notValidBefore: nil,
        notValidAfter: nil,
        fingerprintSHA256: nil,
        commonName: nil,
        lastValidationErrorMessage: nil
    )
}
