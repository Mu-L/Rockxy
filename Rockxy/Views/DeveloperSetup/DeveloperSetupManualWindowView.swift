import AppKit
import SwiftUI

// MARK: - DeveloperSetupManualWindowView

struct DeveloperSetupManualWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _viewModel = State(initialValue: DeveloperSetupSessionSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                if viewModel.isRuntimeTerminalTarget {
                    terminalCard
                } else {
                    targetManualCard
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .font(setupMetrics.font())
        .centerOverRockxyMainWindowOnAppear()
        .task {
            viewModel.applyRoute(routeStore.consumeManualRoute(), destination: .manual)
            viewModel.refresh()
            if viewModel.isRuntimeTerminalTarget {
                viewModel.prepareScriptForDisplay()
            }
        }
        .onChange(of: routeStore.manualRoute) { _, _ in
            viewModel.applyRoute(routeStore.consumeManualRoute(), destination: .manual)
            if viewModel.isRuntimeTerminalTarget {
                viewModel.prepareScriptForDisplay()
            }
        }
    }

    // MARK: Private

    @State private var viewModel: DeveloperSetupSessionSetupViewModel
    @State private var routeStore = DeveloperSetupRouteStore.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: viewModel.target.iconName)
                    .font(setupMetrics.font(size: setupMetrics.prominentIconFontSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Manual Setup"))
                        .font(setupMetrics.font(size: setupMetrics.titleFontSize, weight: .semibold))
                    Text(viewModel.target.title)
                        .font(setupMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
            }

            Text(viewModel.target.manualSummary)
                .font(setupMetrics.font())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Terminal-runtime targets get the scoped-shell source-command flow.
    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Terminal session"))
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 16) {
                instructionStep(
                    title: String(localized: "1. Open your favorite Terminal app"),
                    caption: String(localized: "Supports Terminal, iTerm2, Ghostty, Hyper, and Bash/Zsh/Fish shells.")
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "2. Copy and paste this command into that terminal"))
                        .font(setupMetrics.font(weight: .semibold))

                    commandBox(viewModel.manualSourceCommand)

                    Button(String(localized: "Copy Setup Command")) {
                        viewModel.copyManualCommand()
                    }
                    .controlSize(.regular)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }

                instructionStep(
                    title: String(localized: "3. Run \(viewModel.target.title) in that terminal session"),
                    caption: String(localized: "Start your server or scripts there so Rockxy can capture the traffic."),
                    trailingSystemImage: "checkmark"
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    /// Device / browser / client / framework / environment targets show their own
    /// manual workflow snippet and guide, never the generic localhost terminal flow.
    private var targetManualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "\(viewModel.target.title) manual setup"))
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.target.currentSupportSummary)
                    .font(setupMetrics.font())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let snippet = viewModel.targetSnippetText {
                    commandBox(snippet, minHeight: 120)

                    Button(String(localized: "Copy Setup Command")) {
                        viewModel.copyTargetSnippet()
                    }
                    .controlSize(.regular)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }

                if let guide = viewModel.guideContent, !guide.setupTips.isEmpty {
                    ForEach(guide.setupTips) { tip in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(setupMetrics.font(weight: .semibold))
                            Text(tip.message)
                                .font(setupMetrics.secondaryFont())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            if viewModel.isRuntimeTerminalTarget {
                Button(String(localized: "Show Setup Script in Finder")) {
                    revealSetupScript()
                }
                .help(String(localized: "Reveal the generated setup script so you can inspect exactly what it exports"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandBox(_ text: String, minHeight: CGFloat = 64) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(setupMetrics.font(size: setupMetrics.snippetFontSize, monospaced: true))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: minHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(String(localized: "Generated setup command"))
        .accessibilityValue(text)
    }

    private func instructionStep(
        title: String,
        caption: String,
        trailingSystemImage: String? = nil
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(setupMetrics.font(weight: .semibold))

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(setupMetrics.font(size: setupMetrics.iconFontSize, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .accessibilityHidden(true)
                }
            }

            Text(caption)
                .font(setupMetrics.font())
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func revealSetupScript() {
        do {
            try viewModel.prepareScript()
            NSWorkspace.shared.activateFileViewerSelecting([viewModel.scriptURL])
        } catch {
            viewModel
                .statusMessage = String(localized: "Could not prepare the setup script: \(error.localizedDescription)")
        }
    }
}
