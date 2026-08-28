import SwiftUI

// Root Settings window using the same native sidebar/detail hierarchy as
// Developer Setup. macOS owns the title bar, sidebar toggle, and navigation;
// the detail column stays an opaque, high-contrast configuration surface.

// MARK: - RockxySettingsTab

enum RockxySettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case privacy
    case assistant
    case tools
    case github
    case plugins
    case mcp
    case advanced

    // MARK: Internal

    static let defaultsKey = RockxyIdentity.current.defaultsKey("selectedSettingsTab")

    var id: RockxySettingsTab {
        self
    }

    var title: String {
        switch self {
        case .general: String(localized: "General", bundle: RockxyLocalization.bundle)
        case .appearance: String(localized: "Appearance", bundle: RockxyLocalization.bundle)
        case .privacy: String(localized: "Privacy", bundle: RockxyLocalization.bundle)
        case .assistant: String(localized: "AI Assistant", bundle: RockxyLocalization.bundle)
        case .tools: String(localized: "Tools", bundle: RockxyLocalization.bundle)
        case .github: String(localized: "GitHub", bundle: RockxyLocalization.bundle)
        case .plugins: String(localized: "Plugins", bundle: RockxyLocalization.bundle)
        case .mcp: String(localized: "MCP", bundle: RockxyLocalization.bundle)
        case .advanced: String(localized: "Advanced", bundle: RockxyLocalization.bundle)
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .appearance: "sparkles"
        case .privacy: "person.badge.shield.checkmark"
        case .assistant: "sparkles.rectangle.stack"
        case .tools: "wrench.and.screwdriver"
        case .github: "link"
        case .plugins: "puzzlepiece.extension"
        case .mcp: "network"
        case .advanced: "ellipsis.circle"
        }
    }

    var paneDescription: String {
        switch self {
        case .general:
            String(
                localized: "Proxy port, launch behavior, and the root CA certificate.",
                bundle: RockxyLocalization.bundle
            )
        case .appearance:
            String(
                localized: "Language, theme, font, and layout density for the debugging workspace.",
                bundle: RockxyLocalization.bundle
            )
        case .privacy:
            String(localized: "Local storage, exports, and data-handling details.", bundle: RockxyLocalization.bundle)
        case .assistant:
            String(
                localized: "Model providers and data handling for the AI Assistant.",
                bundle: RockxyLocalization.bundle
            )
        case .tools:
            String(localized: "Defaults for built-in debugging tools.", bundle: RockxyLocalization.bundle)
        case .github:
            String(localized: "Connect a GitHub account for Gist publishing.", bundle: RockxyLocalization.bundle)
        case .plugins:
            String(localized: "Manage installed plugins and available extensions.", bundle: RockxyLocalization.bundle)
        case .mcp:
            String(localized: "Connect compatible local clients to Rockxy over MCP.", bundle: RockxyLocalization.bundle)
        case .advanced:
            String(
                localized: "Diagnostics, updates, and lower-level proxy controls.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    /// Resolve a persisted raw value, falling back to `.general` for any
    /// missing or unknown selection so the window always opens on a valid pane.
    static func resolve(_ rawValue: String) -> RockxySettingsTab {
        RockxySettingsTab(rawValue: rawValue) ?? .general
    }

    static func select(
        _ tab: RockxySettingsTab,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(tab.rawValue, forKey: defaultsKey)
    }
}

// MARK: - RockxySettingsSidebarSection

private enum RockxySettingsSidebarSection: String, CaseIterable, Identifiable {
    case application
    case integrations
    case system

    // MARK: Internal

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .application: String(localized: "Application", bundle: RockxyLocalization.bundle)
        case .integrations: String(localized: "Integrations", bundle: RockxyLocalization.bundle)
        case .system: String(localized: "System", bundle: RockxyLocalization.bundle)
        }
    }

    var tabs: [RockxySettingsTab] {
        switch self {
        case .application: [.general, .appearance, .privacy]
        case .integrations: [.assistant, .github, .plugins, .mcp]
        case .system: [.tools, .advanced]
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    // MARK: Internal

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            detailContent(for: selectedTab)
                .font(settingsMetrics.font())
                .frame(
                    minWidth: settingsMetrics.contentMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .navigationTitle(selectedTab.title)
        .onAppear {
            loadedTabs.insert(selectedTab)
        }
        .onChange(of: selectedTab) { _, newValue in
            loadedTabs.insert(newValue)
        }
        .frame(
            minWidth: settingsMetrics.windowMinWidth,
            idealWidth: settingsMetrics.windowIdealWidth,
            maxWidth: .infinity,
            minHeight: settingsMetrics.windowMinHeight,
            idealHeight: settingsMetrics.windowIdealHeight,
            maxHeight: .infinity
        )
    }

    // MARK: Private

    @AppStorage(RockxySettingsTab.defaultsKey) private var selectedTabID = RockxySettingsTab.general.rawValue
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var loadedTabs: Set<RockxySettingsTab> = []

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var selectedTab: RockxySettingsTab {
        RockxySettingsTab.resolve(selectedTabID)
    }

    /// Bridges the namespaced `@AppStorage` string to the sidebar's typed
    /// selection. Reads resolve invalid persisted values to `.general`; a nil
    /// write (deselection) keeps the current tab so the detail is never empty.
    private var selectionBinding: Binding<RockxySettingsTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue {
                    selectedTabID = newValue.rawValue
                }
            }
        )
    }

    private var loadedPaneTabs: [RockxySettingsTab] {
        RockxySettingsTab.allCases.filter { loadedTabs.contains($0) || $0 == selectedTab }
    }

    @ViewBuilder private var settingsSidebar: some View {
        let list = List(selection: selectionBinding) {
            ForEach(RockxySettingsSidebarSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.symbol)
                        }
                        .font(settingsMetrics.font(weight: selectedTab == tab ? .semibold : .regular))
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: settingsMetrics.sidebarMinWidth,
            ideal: settingsMetrics.sidebarIdealWidth,
            max: settingsMetrics.sidebarMaxWidth
        )
        .accessibilityLabel(String(localized: "Settings categories", bundle: RockxyLocalization.bundle))

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            list.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            list
        }
        #else
        list
        #endif
    }

    /// Keeps panes alive after their first visit so sidebar navigation does not
    /// discard in-progress text, selection, or feedback held in local view state.
    /// Unvisited panes remain lazy, avoiding eager credential and service loads.
    private var persistentPaneStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(loadedPaneTabs) { tab in
                let isSelected = tab == selectedTab

                pane(for: tab)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .disabled(!isSelected)
                    .accessibilityHidden(!isSelected)
                    .zIndex(isSelected ? 1 : 0)
            }
        }
    }

    private func detailContent(for tab: RockxySettingsTab) -> some View {
        persistentPaneStack
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .accessibilityLabel(tab.title)
    }

    /// A concrete switch keeps the pane types explicit without type erasure.
    @ViewBuilder
    private func pane(for tab: RockxySettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .appearance: AppearanceSettingsTab()
        case .privacy: PrivacySettingsTab()
        case .assistant: AssistantSettingsTab()
        case .tools: ToolsSettingsTab()
        case .github: GitHubSettingsTab()
        case .plugins: PluginsSettingsTab()
        case .mcp: MCPSettingsTab()
        case .advanced: AdvancedSettingsTab()
        }
    }
}
