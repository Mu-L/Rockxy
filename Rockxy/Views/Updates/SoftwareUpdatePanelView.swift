import SwiftUI

// MARK: - SoftwareUpdatePanelView

struct SoftwareUpdatePanelView: View {
    // MARK: Internal

    @ObservedObject var controller: SoftwareUpdateController

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(
            minWidth: SoftwareUpdateWindowPositioning.minimumContentSize.width,
            maxWidth: .infinity,
            minHeight: SoftwareUpdateWindowPositioning.minimumContentSize.height,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            controller.requestInteractiveClose()
        }
    }

    // MARK: Private

    @ObservedObject private var updater = AppUpdater.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var supportingText: String? {
        switch controller.phase {
        case .checking:
            String(localized: "You can cancel this check at any time.", bundle: RockxyLocalization.bundle)
        case .available,
             .readyToInstall:
            String(
                localized: "Updates are signed and verified before Rockxy installs them.",
                bundle: RockxyLocalization.bundle
            )
        case .downloading:
            String(localized: "Downloading the signed update.", bundle: RockxyLocalization.bundle)
        case .extracting:
            String(localized: "Preparing the update on your Mac.", bundle: RockxyLocalization.bundle)
        case .installing:
            String(localized: "Rockxy will relaunch after installation completes.", bundle: RockxyLocalization.bundle)
        case .noUpdate:
            String(localized: "You can still review the full release history.", bundle: RockxyLocalization.bundle)
        case .error:
            String(localized: "No captured traffic is sent with update reports.", bundle: RockxyLocalization.bundle)
        case .hidden:
            nil
        }
    }

    private var detailURL: URL? {
        switch controller.phase {
        case let .available(context),
             let .downloading(context, _, _),
             let .extracting(context, _),
             let .readyToInstall(context),
             let .installing(context, _):
            context.detailURL
        case let .noUpdate(context):
            context.detailURL
        case .error:
            AppUpdater.fullChangelogURL
        case .checking,
             .hidden:
            nil
        }
    }

    private var primaryActionTitle: String {
        switch controller.phase {
        case let .available(context):
            if context.isInformationOnly {
                String(localized: "Learn More", bundle: RockxyLocalization.bundle)
            } else {
                String(localized: "Install Update", bundle: RockxyLocalization.bundle)
            }
        default:
            String(localized: "Continue", bundle: RockxyLocalization.bundle)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var heroTitleFont: Font {
        appMetrics.swiftUIFont(size: max(22, appMetrics.primaryFontSize + 7), weight: .semibold)
    }

    private var sectionTitleFont: Font {
        appMetrics.swiftUIFont(size: max(18, appMetrics.primaryFontSize + 4), weight: .semibold)
    }

    private var badgeSymbolFont: Font {
        appMetrics.swiftUIFont(size: max(15, appMetrics.primaryFontSize + 4), weight: .semibold)
    }

    private var badgeDiameter: CGFloat {
        max(26, appMetrics.primaryFontSize + 15)
    }

    private var appIconSize: CGFloat {
        max(56, min(appMetrics.primaryFontSize + 51, 72))
    }

    private var releaseNotesFont: SoftwareUpdateReleaseNotesFont {
        SoftwareUpdateReleaseNotesFont(
            bodySize: appMetrics.primaryFontSize,
            usesMonospacedFamily: appMetrics.settings.useMonospacedFont
        )
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .hidden:
            Color.clear

        case .checking:
            checkingContent

        case let .available(context):
            updateDialog(
                symbol: "arrow.down.circle.fill",
                symbolTint: .accentColor,
                title: String(localized: "A new version of Rockxy is available.", bundle: RockxyLocalization.bundle),
                summary: context.summary,
                notesLabel: String(localized: "Release Notes", bundle: RockxyLocalization.bundle),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: context.buildNumber,
                    fallback: String(localized: "Latest", bundle: RockxyLocalization.bundle)
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .downloading(context, bytesReceived, expectedBytes):
            progressDialog(
                context: context,
                title: String(
                    localized: "Downloading Rockxy \(context.latestVersion)…",
                    bundle: RockxyLocalization.bundle
                ),
                summary: String(
                    localized: "Rockxy is downloading the signed update and verifying it before installation.",
                    bundle: RockxyLocalization.bundle
                ),
                detailLabel: String(localized: "Download Details", bundle: RockxyLocalization.bundle),
                detailMessage: downloadProgressDescription(received: bytesReceived, expected: expectedBytes),
                progressLabel: String(localized: "Downloading update…", bundle: RockxyLocalization.bundle),
                progress: progressValue(received: bytesReceived, expected: expectedBytes)
            )

        case let .extracting(context, progress):
            progressDialog(
                context: context,
                title: String(
                    localized: "Preparing Rockxy \(context.latestVersion)…",
                    bundle: RockxyLocalization.bundle
                ),
                summary: String(
                    localized: "Rockxy is extracting the update and preparing the app bundle for installation.",
                    bundle: RockxyLocalization.bundle
                ),
                detailLabel: String(localized: "Preparation Details", bundle: RockxyLocalization.bundle),
                detailMessage: String(
                    localized: "Preparing the app bundle and installation metadata.",
                    bundle: RockxyLocalization.bundle
                ),
                progressLabel: String(localized: "Preparing update…", bundle: RockxyLocalization.bundle),
                progress: progress
            )

        case let .readyToInstall(context):
            updateDialog(
                symbol: "checkmark.circle.fill",
                symbolTint: .green,
                title: String(
                    localized: "Rockxy \(context.latestVersion) is ready to install.",
                    bundle: RockxyLocalization.bundle
                ),
                summary: String(
                    localized: "The update has been downloaded and verified. Install now to relaunch into the latest version.",
                    bundle: RockxyLocalization.bundle
                ),
                notesLabel: String(localized: "Release Notes", bundle: RockxyLocalization.bundle),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: context.buildNumber,
                    fallback: String(localized: "Ready", bundle: RockxyLocalization.bundle)
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .installing(context, applicationTerminated):
            progressDialog(
                context: context,
                title: String(
                    localized: "Installing Rockxy \(context.latestVersion)…",
                    bundle: RockxyLocalization.bundle
                ),
                summary: applicationTerminated
                    ? String(
                        localized: "Rockxy is finishing the installation and will relaunch automatically.",
                        bundle: RockxyLocalization.bundle
                    )
                    :
                    String(
                        localized: "Rockxy is waiting for the app to terminate so installation can finish safely.",
                        bundle: RockxyLocalization.bundle
                    ),
                detailLabel: String(localized: "Installation Details", bundle: RockxyLocalization.bundle),
                detailMessage: applicationTerminated
                    ? String(
                        localized: "Installing the new version and preparing to relaunch.",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(
                        localized: "Waiting for the running app process to exit before replacing the bundle.",
                        bundle: RockxyLocalization.bundle
                    ),
                progressLabel: String(localized: "Installing update…", bundle: RockxyLocalization.bundle),
                progress: applicationTerminated ? 0.8 : nil
            )

        case let .noUpdate(context):
            updateDialog(
                symbol: "checkmark.circle.fill",
                symbolTint: .green,
                title: String(localized: "Rockxy is up to date.", bundle: RockxyLocalization.bundle),
                summary: context.summary,
                notesLabel: String(localized: "Release Notes", bundle: RockxyLocalization.bundle),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: nil,
                    fallback: context.currentVersion
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .error(context):
            errorContent(context)
        }
    }

    private var checkingContent: some View {
        VStack(spacing: 14) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(String(localized: "Checking for updates", bundle: RockxyLocalization.bundle))
                .font(sectionTitleFont)

            Text(String(
                localized: "Rockxy is comparing your current build against the signed update feed.",
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.font())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var appIcon: some View {
        Image(nsImage: AppIconProvider.appIcon)
            .resizable()
            .scaledToFit()
            .frame(width: appIconSize, height: appIconSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        Group {
            if toolMetrics.bodyFontSize >= 20 {
                VStack(alignment: .leading, spacing: 12) {
                    footerLeadingContent
                    HStack {
                        Spacer()
                        footerButtons
                    }
                }
            } else {
                HStack(spacing: 12) {
                    footerLeadingContent
                    Spacer()
                    footerButtons
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .rockxyFunctionalBar()
    }

    @ViewBuilder private var footerLeadingContent: some View {
        switch controller.phase {
        case .available:
            if updater.supportsAutomaticChecks, updater.allowsAutomaticUpdates {
                Toggle(
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }
                    )
                ) {
                    Text(String(localized: "Automatically download future updates", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font())
                }
                .toggleStyle(.checkbox)
            } else if let supportingText {
                Text(supportingText)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

        default:
            if let supportingText {
                Text(supportingText)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var footerButtons: some View {
        switch controller.phase {
        case .checking:
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle)) {
                controller.chooseLater()
            }
            .keyboardShortcut(.cancelAction)

        case let .available(context):
            if toolMetrics.bodyFontSize >= 20 {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(String(localized: "Skip This Version", bundle: RockxyLocalization.bundle)) {
                            controller.chooseSkip()
                        }
                        Button(String(localized: "Later", bundle: RockxyLocalization.bundle)) {
                            controller.chooseLater()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    HStack(spacing: 8) {
                        if let url = detailURL {
                            Button(String(localized: "View Full Change Log", bundle: RockxyLocalization.bundle)) {
                                controller.openDetailURL(url)
                            }
                        }
                        Button(primaryActionTitle) {
                            performAvailablePrimaryAction(context)
                        }
                        .keyboardShortcut(.defaultAction)
                        .rockxyGlassButtonStyle(prominent: true)
                        .controlSize(.large)
                    }
                }
            } else {
                Button(String(localized: "Skip This Version", bundle: RockxyLocalization.bundle)) {
                    controller.chooseSkip()
                }
                Button(String(localized: "Later", bundle: RockxyLocalization.bundle)) {
                    controller.chooseLater()
                }
                .keyboardShortcut(.cancelAction)
                if let url = detailURL {
                    Button(String(localized: "View Full Change Log", bundle: RockxyLocalization.bundle)) {
                        controller.openDetailURL(url)
                    }
                }
                Button(primaryActionTitle) {
                    performAvailablePrimaryAction(context)
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .controlSize(.large)
            }

        case .downloading:
            Button(String(localized: "Cancel Download", bundle: RockxyLocalization.bundle)) {
                controller.chooseLater()
            }
            .keyboardShortcut(.cancelAction)

        case .extracting:
            EmptyView()

        case .readyToInstall:
            if toolMetrics.bodyFontSize >= 20 {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(String(localized: "Later", bundle: RockxyLocalization.bundle)) {
                            controller.chooseLater()
                        }
                        .keyboardShortcut(.cancelAction)
                        if let url = detailURL {
                            Button(String(localized: "View Full Change Log", bundle: RockxyLocalization.bundle)) {
                                controller.openDetailURL(url)
                            }
                        }
                    }
                    Button(String(localized: "Install and Relaunch", bundle: RockxyLocalization.bundle)) {
                        controller.chooseInstall()
                    }
                    .keyboardShortcut(.defaultAction)
                    .rockxyGlassButtonStyle(prominent: true)
                    .controlSize(.large)
                }
            } else {
                Button(String(localized: "Later", bundle: RockxyLocalization.bundle)) {
                    controller.chooseLater()
                }
                .keyboardShortcut(.cancelAction)
                if let url = detailURL {
                    Button(String(localized: "View Full Change Log", bundle: RockxyLocalization.bundle)) {
                        controller.openDetailURL(url)
                    }
                }
                Button(String(localized: "Install and Relaunch", bundle: RockxyLocalization.bundle)) {
                    controller.chooseInstall()
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .controlSize(.large)
            }

        case let .installing(_, applicationTerminated):
            if !applicationTerminated {
                Button(String(localized: "Retry Termination", bundle: RockxyLocalization.bundle)) {
                    controller.retryTermination()
                }
            }

        case .noUpdate:
            if let url = detailURL {
                Button(String(localized: "View Full Change Log", bundle: RockxyLocalization.bundle)) {
                    controller.openDetailURL(url)
                }
            }
            Button(String(localized: "Done", bundle: RockxyLocalization.bundle)) {
                controller.acknowledgeAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .controlSize(.large)

        case .error:
            if let url = detailURL {
                Button(String(localized: "Open Change Log", bundle: RockxyLocalization.bundle)) {
                    controller.openDetailURL(url)
                }
            }
            Button(String(localized: "Done", bundle: RockxyLocalization.bundle)) {
                controller.acknowledgeAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .controlSize(.large)

        case .hidden:
            EmptyView()
        }
    }

    private func updateDialog(
        symbol: String,
        symbolTint: Color,
        title: String,
        summary: String,
        notesLabel: String,
        notesVersionLabel: String,
        notes: SoftwareUpdateReleaseNotesContent,
        progress: ProgressPresentation?
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: symbol, symbolTint: symbolTint, title: title, summary: summary)

            releaseNotesGroup(
                label: notesLabel,
                versionLabel: notesVersionLabel,
                content: notes
            )
            .layoutPriority(1)

            if let progress {
                progressStrip(progress)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func progressDialog(
        context: SoftwareUpdateController.UpdateContext,
        title: String,
        summary: String,
        detailLabel: String,
        detailMessage: String,
        progressLabel: String,
        progress: Double?
    )
        -> some View
    {
        updateDialog(
            symbol: "clock.arrow.circlepath",
            symbolTint: .secondary,
            title: title,
            summary: summary,
            notesLabel: detailLabel,
            notesVersionLabel: versionPanelLabel(
                version: context.latestVersion,
                buildNumber: context.buildNumber,
                fallback: String(localized: "Installing", bundle: RockxyLocalization.bundle)
            ),
            notes: .plainText(detailMessage),
            progress: ProgressPresentation(
                label: progressLabel,
                detail: progressDetail(for: controller.phase),
                value: progress
            )
        )
    }

    private func errorContent(_ context: SoftwareUpdateController.ErrorContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(
                symbol: "exclamationmark.triangle.fill",
                symbolTint: .orange,
                title: context.title,
                summary: context.summary
            )

            if let recoverySuggestion = context.recoverySuggestion {
                releaseNotesGroup(
                    label: String(localized: "Recovery Suggestion", bundle: RockxyLocalization.bundle),
                    versionLabel: String(localized: "Error Details", bundle: RockxyLocalization.bundle),
                    content: .plainText(recoverySuggestion)
                )
                .layoutPriority(1)
            } else {
                releaseNotesGroup(
                    label: String(localized: "Update Details", bundle: RockxyLocalization.bundle),
                    versionLabel: String(localized: "Error Details", bundle: RockxyLocalization.bundle),
                    content: .unavailable(
                        String(
                            localized: "No additional recovery guidance is available for this error.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                )
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func hero(
        symbol: String,
        symbolTint: Color,
        title: String,
        summary: String
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 16) {
            appIcon

            statusBadge(symbol: symbol, tint: symbolTint)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(heroTitleFont)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary)
                    .font(toolMetrics.font())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private func statusBadge(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(badgeSymbolFont)
            .foregroundStyle(tint)
            .frame(width: badgeDiameter, height: badgeDiameter)
            .background(tint.opacity(0.12), in: Circle())
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }

    private func releaseNotesGroup(
        label: String,
        versionLabel: String,
        content: SoftwareUpdateReleaseNotesContent
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(toolMetrics.secondaryFont(weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text(versionLabel)
                        .font(toolMetrics.metadataFont(weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                releaseNotesView(content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func releaseNotesView(_ content: SoftwareUpdateReleaseNotesContent) -> some View {
        switch content {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "Loading release notes…", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

        case .html,
             .plainText:
            if let attributedText = content.nativeDisplayAttributedString(
                fallbackMessage: String(
                    localized: "Release notes are unavailable for this update.",
                    bundle: RockxyLocalization.bundle
                ),
                font: releaseNotesFont
            ) {
                NativeReleaseNotesTextView(attributedText: attributedText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(
                        localized: "Release notes are unavailable for this update.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.font())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)
            }

        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(toolMetrics.font())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let detailURL {
                    Button(String(localized: "Open Full Change Log", bundle: RockxyLocalization.bundle)) {
                        controller.openDetailURL(detailURL)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
    }

    private func progressStrip(_ progress: ProgressPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progress.label)
                .font(toolMetrics.font(weight: .medium))

            if let value = progress.value {
                ProgressView(value: value)
                    .controlSize(.large)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            if let detail = progress.detail {
                Text(detail)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func versionPanelLabel(version: String?, buildNumber: String?, fallback: String) -> String {
        if let version, let buildNumber, !buildNumber.isEmpty {
            return String(localized: "Version \(version) (\(buildNumber))", bundle: RockxyLocalization.bundle)
        }
        if let version, !version.isEmpty {
            return String(localized: "Version \(version)", bundle: RockxyLocalization.bundle)
        }
        return fallback
    }

    private func progressValue(received: Int64, expected: Int64?) -> Double? {
        guard let expected, expected > 0 else {
            return nil
        }
        return min(max(Double(received) / Double(expected), 0), 1)
    }

    private func downloadProgressDescription(received: Int64, expected: Int64?) -> String {
        if let expected, expected > 0 {
            return "\(formattedSize(received)) / \(formattedSize(expected))"
        }
        return formattedSize(received)
    }

    private func progressDetail(for phase: SoftwareUpdateController.Phase) -> String? {
        switch phase {
        case let .downloading(_, bytesReceived, expectedBytes):
            downloadProgressDescription(received: bytesReceived, expected: expectedBytes)
        case .extracting:
            String(
                localized: "Preparing the new app bundle and installation metadata.",
                bundle: RockxyLocalization.bundle
            )
        case let .installing(_, applicationTerminated):
            if applicationTerminated {
                String(localized: "Finishing installation and relaunch preparation.", bundle: RockxyLocalization.bundle)
            } else {
                String(
                    localized: "Waiting for the running app process to terminate safely.",
                    bundle: RockxyLocalization.bundle
                )
            }
        default:
            nil
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func performAvailablePrimaryAction(_ context: SoftwareUpdateController.UpdateContext) {
        if context.isInformationOnly {
            if let url = context.detailURL {
                controller.openDetailURL(url)
            }
            controller.chooseLater()
            return
        }

        controller.chooseInstall()
    }
}

// MARK: - ProgressPresentation

private struct ProgressPresentation {
    let label: String
    let detail: String?
    let value: Double?
}

// MARK: - NativeReleaseNotesTextView

private struct NativeReleaseNotesTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.usesDefaultHyphenation = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        guard let textStorage = textView.textStorage else {
            return
        }
        if textStorage.isEqual(to: attributedText) {
            return
        }
        textStorage.setAttributedString(attributedText)
    }
}
