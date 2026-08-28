import AppKit
import SwiftUI

// MARK: - GitHubSettingsTab

struct GitHubSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "Account", bundle: RockxyLocalization.bundle)) {
                permissionSection
            }

            SettingsSection(String(localized: "Publishing Defaults", bundle: RockxyLocalization.bundle)) {
                defaultsSection
            }

            SettingsSection(String(localized: "Access & Help", bundle: RockxyLocalization.bundle)) {
                advancedSection
            }
        }
        .sheet(isPresented: $showPersonalAccessTokenSheet) {
            PersonalAccessTokenFallbackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showDeviceCodeSheet) {
            GitHubDeviceCodeAuthorizationSheet(viewModel: viewModel)
        }
    }

    // MARK: Private

    @State private var viewModel = GitHubSettingsViewModel()
    @State private var showPersonalAccessTokenSheet = false
    @State private var showDeviceCodeSheet = false

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.visibility"))
    private var gistVisibility = GitHubGistVisibility.secret.rawValue

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.redactSensitiveData"))
    private var redactSensitiveData = true

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.openInBrowser")) private var openInBrowser = true

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.copyURLToClipboard"))
    private var copyURLToClipboard = false

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var selectedGistVisibility: GitHubGistVisibility {
        GitHubGistVisibility(rawValue: gistVisibility) ?? .secret
    }

    private var gistVisibilityBinding: Binding<GitHubGistVisibility> {
        Binding(
            get: { selectedGistVisibility },
            set: { visibility in
                gistVisibility = visibility.rawValue
                AppSettingsManager.shared.updateGitHubGistVisibility(visibility)
            }
        )
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            alignedRow(label: String(localized: "Gist Permission:", bundle: RockxyLocalization.bundle)) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.isConnected ? .green : .orange)
                    Text(viewModel.connectionTitle)
                        .font(settingsMetrics.font())
                }
            }

            alignedRow(label: "") {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            accountActions
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            accountActions
                        }
                    }

                    Text(
                        String(
                            localized: """
                            To read or write Gists on a user's behalf, Rockxy requires Gist Permission from your \
                            GitHub account. After the authorization, your GitHub Access Token will securely store \
                            in System Keychain.
                            """, bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: settingsMetrics.fieldWidth(640), alignment: .leading)

                    if !viewModel.canUseOAuth {
                        Text(
                            String(
                                localized: "OAuth is not configured for this build. Personal access token fallback is available.",
                                bundle: RockxyLocalization.bundle
                            )
                        )
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            alignedRow(label: String(localized: "Publish as:", bundle: RockxyLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(
                        String(localized: "Publish as", bundle: RockxyLocalization.bundle),
                        selection: gistVisibilityBinding
                    ) {
                        ForEach(GitHubGistVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text(selectedGistVisibility.sharingDescription)
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if GitHubGistVisibility(rawValue: gistVisibility) == .public {
                        Text(
                            String(
                                localized: "Public Gists are discoverable. Review captured traffic before publishing.",
                                bundle: RockxyLocalization.bundle
                            )
                        )
                        .font(settingsMetrics.secondaryFont(weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    checkboxWithHelp(
                        title: String(
                            localized: "Automatic redact sensitive headers",
                            bundle: RockxyLocalization.bundle
                        ),
                        subtitle: String(
                            localized: "Authorization, Cookies, Set-Cookies, ... are censored before publishing to Gist.",
                            bundle: RockxyLocalization.bundle
                        ),
                        isOn: $redactSensitiveData,
                        onChange: AppSettingsManager.shared.updateGitHubGistRedactSensitiveData
                    )
                }
            }

            alignedRow(label: String(localized: "After Publish:", bundle: RockxyLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 12) {
                    checkboxWithHelp(
                        title: String(
                            localized: "Open Gist with default Web Browser",
                            bundle: RockxyLocalization.bundle
                        ),
                        subtitle: nil,
                        isOn: $openInBrowser,
                        onChange: AppSettingsManager.shared.updateGitHubGistOpenInBrowser
                    )
                    checkboxWithHelp(
                        title: String(localized: "Copy Gist URL to clipboard", bundle: RockxyLocalization.bundle),
                        subtitle: nil,
                        isOn: $copyURLToClipboard,
                        onChange: AppSettingsManager.shared.updateGitHubGistCopyURLToClipboard
                    )
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            alignedRow(label: String(localized: "Advanced:", bundle: RockxyLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 12) {
                    Button(String(localized: "Manage Access", bundle: RockxyLocalization.bundle)) {
                        viewModel.openManageAccess()
                    }
                    .controlSize(.large)

                    Text(String(
                        localized: "Review or Revoke Application Authorization.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        viewModel.openHelp()
                    } label: {
                        Image(systemName: "questionmark")
                            .font(settingsMetrics.font(weight: .semibold))
                    }
                    .rockxyGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help(String(localized: "Open Publish to Gist documentation", bundle: RockxyLocalization.bundle))
                }
            }
        }
    }

    @ViewBuilder private var accountActions: some View {
        Button(
            viewModel.isConnected
                ? String(localized: "Reconnect...", bundle: RockxyLocalization.bundle)
                : String(localized: "Authorize...", bundle: RockxyLocalization.bundle)
        ) {
            if viewModel.canUseOAuth {
                showDeviceCodeSheet = true
            } else {
                showPersonalAccessTokenSheet = true
            }
        }
        .rockxyGlassButtonStyle(prominent: true)
        .controlSize(.regular)

        Button(String(localized: "Use Token...", bundle: RockxyLocalization.bundle)) {
            showPersonalAccessTokenSheet = true
        }
        .controlSize(.regular)

        if viewModel.isConnected {
            Button(String(localized: "Disconnect", bundle: RockxyLocalization.bundle)) {
                viewModel.disconnect()
            }
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private func alignedRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        if label.isEmpty {
            SettingsIndentedContent {
                content()
            }
        } else {
            SettingsFieldRow(label) {
                content()
            }
        }
    }

    private func checkboxWithHelp(
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
            if let subtitle {
                Text(subtitle)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 27)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - GitHubSettingsViewModel

@MainActor @Observable
final class GitHubSettingsViewModel {
    // MARK: Lifecycle

    init(
        credentialStorage: any GitHubCredentialStorage = KeychainGitHubCredentialStorage(),
        authService: GitHubAuthService = GitHubAuthService()
    ) {
        self.credentialStorage = credentialStorage
        self.authService = authService
        self.metadata = GitHubSettingsStore.loadMetadata()
    }

    // MARK: Internal

    private(set) var metadata: GitHubAuthMetadata?
    var personalAccessToken = ""
    var errorMessage: String?

    var isConnected: Bool {
        metadata != nil
    }

    var canUseOAuth: Bool {
        authService.configuredOAuthClientID != nil
    }

    var connectionTitle: String {
        guard let metadata else {
            return String(localized: "Not Authorized Yet!", bundle: RockxyLocalization.bundle)
        }
        if let login = metadata.login, !login.isEmpty {
            return String(localized: "Authorized as \(login)", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Authorized ••••\(metadata.tokenSuffix)", bundle: RockxyLocalization.bundle)
    }

    var oauthClientID: String? {
        authService.configuredOAuthClientID
    }

    func savePersonalAccessToken() {
        do {
            let credential = try authService.credentialForPersonalAccessToken(personalAccessToken)
            try credentialStorage.save(credential)
            let metadata = credential.metadata
            GitHubSettingsStore.saveMetadata(metadata)
            self.metadata = metadata
            personalAccessToken = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOAuthCredential(_ credential: GitHubCredential) {
        do {
            try credentialStorage.save(credential)
            let metadata = credential.metadata
            GitHubSettingsStore.saveMetadata(metadata)
            self.metadata = metadata
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeviceCode() async throws -> GitHubAuthService.DeviceCode {
        guard let oauthClientID else {
            throw GitHubAuthService.AuthError.clientIDMissing
        }
        return try await authService.requestDeviceCode(clientID: oauthClientID)
    }

    func pollDeviceToken(deviceCode: String) async throws -> GitHubCredential {
        guard let oauthClientID else {
            throw GitHubAuthService.AuthError.clientIDMissing
        }
        return try await authService.pollDeviceToken(clientID: oauthClientID, deviceCode: deviceCode)
    }

    func disconnect() {
        do {
            try credentialStorage.delete()
            GitHubSettingsStore.deleteMetadata()
            metadata = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openManageAccess() {
        let urlString = switch metadata?.method {
        case .deviceCode:
            "https://github.com/settings/applications"
        case .personalAccessToken,
             nil:
            "https://github.com/settings/tokens"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openHelp() {
        if let url = URL(string: "https://docs.proxyman.com/advanced-features/publish-to-gist") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private let credentialStorage: any GitHubCredentialStorage
    private let authService: GitHubAuthService
}

// MARK: - PersonalAccessTokenFallbackSheet

private struct PersonalAccessTokenFallbackSheet: View {
    // MARK: Internal

    @Bindable var viewModel: GitHubSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Personal Access Token", bundle: RockxyLocalization.bundle))
                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))

            Text(String(
                localized: "Paste a GitHub token with Gist access. Rockxy stores the token in Keychain.",
                bundle: RockxyLocalization.bundle
            ))
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SecureField(
                String(localized: "GitHub token", bundle: RockxyLocalization.bundle),
                text: $viewModel.personalAccessToken
            )
            .textFieldStyle(.roundedBorder)
            .font(settingsMetrics.font(monospaced: true))
            .frame(minHeight: settingsMetrics.controlHeight)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String(localized: "Create Token", bundle: RockxyLocalization.bundle)) {
                    if let url = URL(string: "https://github.com/settings/tokens/new?scopes=gist&description=Rockxy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle)) {
                    dismiss()
                }
                Button(String(localized: "Save", bundle: RockxyLocalization.bundle)) {
                    viewModel.savePersonalAccessToken()
                    if viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(viewModel.personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(settingsMetrics.font())
        .padding(settingsMetrics.contentPadding)
        .frame(width: settingsMetrics.fieldWidth(430))
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - GitHubDeviceCodeAuthorizationSheet

private struct GitHubDeviceCodeAuthorizationSheet: View {
    // MARK: Internal

    @Bindable var viewModel: GitHubSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Authorize GitHub", bundle: RockxyLocalization.bundle))
                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))

            if let deviceCode {
                Text(String(localized: "Enter this code on GitHub:", bundle: RockxyLocalization.bundle))
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Text(deviceCode.userCode)
                    .font(.system(size: max(28, settingsMetrics.bodyFontSize + 15), weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                HStack {
                    Button(String(localized: "Open GitHub", bundle: RockxyLocalization.bundle)) {
                        if let url = URL(string: deviceCode.verificationURI) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button(String(localized: "I Authorized", bundle: RockxyLocalization.bundle)) {
                        Task { await poll() }
                    }
                    .disabled(isLoading)
                }
            } else {
                Text(String(
                    localized: "Rockxy will request GitHub Gist permission using OAuth device authorization.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Start Authorization", bundle: RockxyLocalization.bundle)) {
                    Task { await start() }
                }
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "Done", bundle: RockxyLocalization.bundle)) {
                    dismiss()
                }
            }
        }
        .font(settingsMetrics.font())
        .padding(settingsMetrics.contentPadding)
        .frame(width: settingsMetrics.fieldWidth(430))
        .task {
            if deviceCode == nil {
                await start()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var deviceCode: GitHubAuthService.DeviceCode?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private func start() async {
        isLoading = true
        defer { isLoading = false }
        do {
            deviceCode = try await viewModel.requestDeviceCode()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func poll() async {
        guard let deviceCode else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try await viewModel.pollDeviceToken(deviceCode: deviceCode.deviceCode)
            viewModel.saveOAuthCredential(credential)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
