import AppKit
import SwiftUI

// MARK: - DeveloperSetupAutomaticWindowView

struct DeveloperSetupAutomaticWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _viewModel = State(initialValue: DeveloperSetupSessionSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    var body: some View {
        setupLayout
        .frame(minWidth: 620, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .font(setupMetrics.font())
        .centerOverRockxyMainWindowOnAppear()
        .task {
            viewModel.applyRoute(routeStore.consumeAutomaticRoute(), destination: .automatic)
            viewModel.refresh()
        }
        .onChange(of: routeStore.automaticRoute) { _, _ in
            viewModel.applyRoute(routeStore.consumeAutomaticRoute(), destination: .automatic)
        }
    }

    // MARK: Private

    @State private var viewModel: DeveloperSetupSessionSetupViewModel
    @State private var routeStore = DeveloperSetupRouteStore.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var openTerminalTitle: String {
        viewModel.selectedTerminalApp == .custom
            ? String(localized: "Copy Setup Command")
            : String(localized: "Open Prepared Terminal…")
    }

    @ViewBuilder private var setupLayout: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ScrollView {
                terminalSection
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        } else {
            legacySetupLayout
        }
        #else
        legacySetupLayout
        #endif
    }

    private var legacySetupLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                terminalSection
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(setupMetrics.font(size: setupMetrics.prominentIconFontSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Automatic Setup"))
                        .font(setupMetrics.font(size: setupMetrics.titleFontSize, weight: .semibold))
                    Text(viewModel.target.title)
                        .font(setupMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isRuntimeTerminalTarget {
                Text(
                    String(
                        localized: "Rockxy prepares a scoped shell for \(viewModel.target.title) pointed at the local proxy."
                    )
                )
                .font(setupMetrics.font())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "\(viewModel.target.title) terminal session"))
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    String(
                        localized: "Open a prepared terminal that points \(viewModel.target.title) at Rockxy before you run your app or script."
                    )
                )
                .font(setupMetrics.font())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(String(localized: "Use"))
                            .foregroundStyle(.secondary)
                        terminalPicker
                        terminalActionButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        terminalPicker
                        terminalActionButton
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

    private var terminalPicker: some View {
        Picker(String(localized: "Terminal app"), selection: $viewModel.selectedTerminalApp) {
            ForEach(SetupTerminalApp.allCases) { terminalApp in
                Text(terminalApp.title).tag(terminalApp)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(String(localized: "Terminal app"))
    }

    private var terminalActionButton: some View {
        Button(openTerminalTitle) {
            Task { await viewModel.openPreparedTerminal() }
        }
        .keyboardShortcut(.defaultAction)
        .rockxyGlassButtonStyle(prominent: true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel
                .statusMessage ?? String(localized: "Rockxy generates a scoped setup script before launching."))
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Proxy: \(viewModel.proxyEndpointText). \(viewModel.certificateStatusText)"))
                .font(setupMetrics.font(size: setupMetrics.metadataFontSize))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
