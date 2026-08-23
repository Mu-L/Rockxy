import SwiftUI

// MARK: - GistPublishReviewSummary

/// Pure, testable description of what a Gist publish will send off the Mac.
/// Mirrors the files `GistPublishPayloadBuilder` generates so the review copy
/// stays honest without building (or uploading) the payload before the user
/// presses Publish.
struct GistPublishReviewSummary: Equatable {
    // MARK: Lifecycle

    init(transactions: [HTTPTransaction]) {
        requestCount = transactions.count

        var seen = Set<String>()
        var ordered: [String] = []
        for transaction in transactions {
            let host = transaction.request.host
            let normalized = host.isEmpty ? String(localized: "Unknown host") : host
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        hosts = ordered
        hasWebSocketFrames = transactions.contains { ($0.webSocketConnection?.frames.isEmpty == false) }
    }

    // MARK: Internal

    let requestCount: Int
    let hosts: [String]
    let hasWebSocketFrames: Bool

    var uniqueHostCount: Int {
        hosts.count
    }

    /// README + HAR + one readable transaction file per request + optional WebSocket frames file.
    var fileCount: Int {
        2 + requestCount + (hasWebSocketFrames ? 1 : 0)
    }

    var requestSummary: String {
        String(localized: "\(requestCount) request\(requestCount == 1 ? "" : "s") selected")
    }

    /// Compact host line: names for one or two hosts, then a "+N more" overflow.
    var hostSummary: String {
        switch hosts.count {
        case 0:
            return String(localized: "No hosts")
        case 1:
            return hosts[0]
        case 2:
            return "\(hosts[0]), \(hosts[1])"
        default:
            let remaining = hosts.count - 2
            return String(localized: "\(hosts[0]), \(hosts[1]) +\(remaining) more")
        }
    }

    var hostCountLabel: String {
        String(localized: "\(uniqueHostCount) host\(uniqueHostCount == 1 ? "" : "s")")
    }

    var fileSummary: String {
        var parts = [String(localized: "README"), String(localized: "HAR")]
        parts.append(String(localized: "\(requestCount) transaction file\(requestCount == 1 ? "" : "s")"))
        if hasWebSocketFrames {
            parts.append(String(localized: "WebSocket frames"))
        }
        return parts.joined(separator: ", ")
    }

    var fileCountLabel: String {
        String(localized: "\(fileCount) file\(fileCount == 1 ? "" : "s")")
    }
}

// MARK: - GistPublishCopy

/// Truthful, testable copy for the confirmation surface. GitHub calls non-public
/// Gists "secret": they are unlisted, but anyone with the URL can read them.
enum GistPublishCopy {
    static let redactionDescription = String(
        localized: "Redacts recognized sensitive headers, URLs, and body values (Authorization, Cookie, API keys) before upload. Best-effort, not a guarantee."
    )

    static let redactionOffWarning = String(
        localized: "Redaction is off. Captured headers, URLs, and bodies upload exactly as recorded."
    )

    static let publicWarning = String(
        localized: "Public Gists are discoverable and searchable on GitHub. Anyone can find this traffic."
    )

    static func visibilityTitle(_ visibility: GitHubGistVisibility) -> String {
        visibility.title
    }

    static func visibilityDescription(_ visibility: GitHubGistVisibility) -> String {
        visibility.sharingDescription
    }
}

// MARK: - GistPublishConfirmationSheet

struct GistPublishConfirmationSheet: View {
    // MARK: Lifecycle

    init(
        context: GistPublishContext,
        onPublish: @escaping (GistPublishOptions) async throws -> GistPublishResult,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.onPublish = onPublish
        self.onCancel = onCancel
        summary = GistPublishReviewSummary(transactions: context.transactions)

        let settings = AppSettingsManager.shared.settings
        _visibility = State(initialValue: settings.githubGistVisibility)
        _redactSensitiveData = State(initialValue: settings.githubGistRedactSensitiveData)
        _openInBrowser = State(initialValue: settings.githubGistOpenInBrowser)
        _copyURLToClipboard = State(initialValue: settings.githubGistCopyURLToClipboard)
    }

    // MARK: Internal

    let context: GistPublishContext
    let onPublish: (GistPublishOptions) async throws -> GistPublishResult
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            reviewSummary
            visibilitySection
            privacyControls
            warnings
            if let errorMessage {
                errorRow(errorMessage)
            }
            footer
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .font(toolMetrics.font())
        .frame(width: max(460, toolMetrics.fieldWidth(460)))
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("gistPublish.sheet")
    }

    // MARK: Private

    @State private var visibility: GitHubGistVisibility
    @State private var redactSensitiveData: Bool
    @State private var openInBrowser: Bool
    @State private var copyURLToClipboard: Bool
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private let summary: GistPublishReviewSummary

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var title: String {
        summary.requestCount == 1
            ? String(localized: "Publish to GitHub Gist")
            : String(localized: "Publish Selected to GitHub Gist")
    }

    private var publishButtonTitle: String {
        isPublishing
            ? String(localized: "Publishing\u{2026}")
            : String(localized: "Publish")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(toolMetrics.font(weight: .semibold))
            Text(String(localized: "Review what leaves this Mac before uploading to GitHub."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewSummary: some View {
        VStack(spacing: 0) {
            summaryRow(
                icon: "arrow.up.arrow.down",
                title: summary.requestSummary,
                detail: nil,
                identifier: "gistPublish.summary.requests"
            )
            dividerLine
            summaryRow(
                icon: "network",
                title: summary.hostSummary,
                detail: summary.hostCountLabel,
                identifier: "gistPublish.summary.hosts"
            )
            dividerLine
            summaryRow(
                icon: "doc.text",
                title: summary.fileSummary,
                detail: summary.fileCountLabel,
                identifier: "gistPublish.summary.files"
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(String(localized: "Publish as"), selection: $visibility) {
                Text(GistPublishCopy.visibilityTitle(.secret)).tag(GitHubGistVisibility.secret)
                Text(GistPublishCopy.visibilityTitle(.public)).tag(GitHubGistVisibility.public)
            }
            .pickerStyle(.radioGroup)
            .disabled(isPublishing)
            .accessibilityIdentifier("gistPublish.visibility")

            Text(GistPublishCopy.visibilityDescription(visibility))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "Redact recognized sensitive data"), isOn: $redactSensitiveData)
                .toggleStyle(.checkbox)
                .disabled(isPublishing)
                .accessibilityIdentifier("gistPublish.redactToggle")

            Text(GistPublishCopy.redactionDescription)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            Toggle(String(localized: "Open Gist in default web browser"), isOn: $openInBrowser)
                .toggleStyle(.checkbox)
                .disabled(isPublishing)
                .accessibilityIdentifier("gistPublish.openInBrowserToggle")

            Toggle(String(localized: "Copy Gist URL to clipboard"), isOn: $copyURLToClipboard)
                .toggleStyle(.checkbox)
                .disabled(isPublishing)
                .accessibilityIdentifier("gistPublish.copyURLToggle")
        }
    }

    @ViewBuilder private var warnings: some View {
        if !redactSensitiveData {
            warningRow(GistPublishCopy.redactionOffWarning, identifier: "gistPublish.redactionWarning")
        }
        if visibility == .public {
            warningRow(GistPublishCopy.publicWarning, identifier: "gistPublish.publicWarning")
        }
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()

            Button {
                onCancel()
            } label: {
                Text(String(localized: "Cancel"))
                    .frame(width: footerActionWidth)
                    .frame(minHeight: toolMetrics.formControlHeight)
            }
            .rockxyGlassButtonStyle()
            .keyboardShortcut(.cancelAction)
            .disabled(isPublishing)
            .accessibilityIdentifier("gistPublish.cancelButton")

            Button {
                Task { await publish() }
            } label: {
                HStack(spacing: 6) {
                    if isPublishing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(publishButtonTitle)
                }
                .frame(width: footerActionWidth)
                .frame(minHeight: toolMetrics.formControlHeight)
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isPublishing)
            .accessibilityIdentifier("gistPublish.publishButton")
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }

    private var footerActionWidth: CGFloat {
        max(120, toolMetrics.bodyFontSize * 6.5)
    }

    private func summaryRow(
        icon: String,
        title: String,
        detail: String?,
        identifier: String
    )
        -> some View
    {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(toolMetrics.font())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: toolMetrics.bodyFontSize + 4)

            Text(title)
                .font(toolMetrics.font())
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail {
                Text(detail)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: toolMetrics.tableRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func warningRow(_ message: String, identifier: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("gistPublish.error")
    }

    private func publish() async {
        guard !isPublishing else {
            return
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }
        do {
            _ = try await onPublish(GistPublishOptions(
                visibility: visibility,
                redactSensitiveData: redactSensitiveData,
                openInBrowser: openInBrowser,
                copyURLToClipboard: copyURLToClipboard,
                askBeforePublishing: true
            ))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
