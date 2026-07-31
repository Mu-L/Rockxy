import AppKit
import SwiftUI

// Root settings window using a native macOS sidebar/content layout.
// The sidebar lists the nine categories; the content column shows a compact
// pane header followed by the selected category's existing settings pane.

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
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .privacy: String(localized: "Privacy")
        case .assistant: String(localized: "AI Assistant")
        case .tools: String(localized: "Tools")
        case .github: String(localized: "GitHub")
        case .plugins: String(localized: "Plugins")
        case .mcp: String(localized: "MCP")
        case .advanced: String(localized: "Advanced")
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
            String(localized: "Proxy port, launch behavior, and the root CA certificate.")
        case .appearance:
            String(localized: "Theme, font, and layout density for the debugging workspace.")
        case .privacy:
            String(localized: "Local storage, exports, and data-handling details.")
        case .assistant:
            String(localized: "Model providers and data handling for the AI Assistant.")
        case .tools:
            String(localized: "Defaults for built-in debugging tools.")
        case .github:
            String(localized: "Connect a GitHub account for Gist publishing.")
        case .plugins:
            String(localized: "Manage installed plugins and available extensions.")
        case .mcp:
            String(localized: "Connect compatible local clients to Rockxy over MCP.")
        case .advanced:
            String(localized: "Diagnostics, updates, and lower-level proxy controls.")
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

// MARK: - SettingsView

struct SettingsView: View {
    // MARK: Internal

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(RockxySettingsTab.allCases, selection: selectionBinding) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    Image(systemName: tab.symbol)
                }
                .font(settingsMetrics.font())
                .tag(tab)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: SettingsChromeMetrics.sidebarContentTopInset)
                    .accessibilityHidden(true)
            }
            .navigationSplitViewColumnWidth(
                min: settingsMetrics.sidebarMinWidth,
                ideal: settingsMetrics.sidebarIdealWidth,
                max: settingsMetrics.sidebarMaxWidth
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContent(for: selectedTab)
                .font(settingsMetrics.font())
                .frame(
                    minWidth: settingsMetrics.contentMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .navigationSplitViewStyle(.balanced)
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
        .background {
            SettingsWindowToolbarInstaller(
                onToggleSidebar: toggleSidebar
            )
        }
    }

    // MARK: Private

    @AppStorage(RockxySettingsTab.defaultsKey) private var selectedTabID = RockxySettingsTab.general.rawValue
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.26)) {
            columnVisibility = columnVisibility == .detailOnly
                ? .all
                : .detailOnly
        }
    }

    private func detailContent(for tab: RockxySettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(for: tab)
            Divider()
            persistentPaneStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

    private var loadedPaneTabs: [RockxySettingsTab] {
        RockxySettingsTab.allCases.filter { loadedTabs.contains($0) || $0 == selectedTab }
    }

    private func paneHeader(for tab: RockxySettingsTab) -> some View {
        VStack(alignment: .leading, spacing: settingsMetrics.paneHeaderSpacing) {
            Text(tab.title)
                .font(settingsMetrics.font(weight: .semibold))
            Text(tab.paneDescription)
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, settingsMetrics.contentPadding)
        .padding(.vertical, 14)
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

// MARK: - SettingsChromeMetrics

private enum SettingsChromeMetrics {
    static let sidebarContentTopInset: CGFloat = 14
}

// MARK: - SettingsWindowToolbarInstaller

/// Installs the same native toolbar-item structure as Rockxy's main workspace:
/// an icon-only sidebar item followed by AppKit's sidebar-tracking separator.
private struct SettingsWindowToolbarInstaller: NSViewRepresentable {
    // MARK: Internal

    let onToggleSidebar: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggleSidebar: onToggleSidebar)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        installToolbar(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(onToggleSidebar: onToggleSidebar)
        installToolbar(for: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeToolbar()
    }

    // MARK: Private

    private func installToolbar(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let window = view?.window,
                  let coordinator
            else {
                return
            }
            coordinator.installToolbarIfNeeded(in: window)
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        // MARK: Lifecycle

        init(onToggleSidebar: @escaping () -> Void) {
            toolbar = SettingsWindowToolbar(onToggleSidebar: onToggleSidebar)
            super.init()
        }

        // MARK: Internal

        func update(onToggleSidebar: @escaping () -> Void) {
            toolbar.onToggleSidebar = onToggleSidebar
        }

        func installToolbarIfNeeded(in window: NSWindow) {
            guard installedWindow !== window || window.toolbar !== toolbar.managedToolbar else {
                return
            }

            if installedWindow !== window {
                previousToolbar = window.toolbar
            }

            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.toolbar = toolbar.managedToolbar
            installedWindow = window
        }

        func removeToolbar() {
            if let installedWindow,
               installedWindow.toolbar === toolbar.managedToolbar
            {
                installedWindow.toolbar = previousToolbar
            }
            installedWindow = nil
            previousToolbar = nil
        }

        // MARK: Private

        private let toolbar: SettingsWindowToolbar
        private weak var installedWindow: NSWindow?
        private var previousToolbar: NSToolbar?
    }
}

// MARK: - SettingsWindowToolbar

@MainActor
private final class SettingsWindowToolbar: NSObject, NSToolbarDelegate {
    // MARK: Lifecycle

    init(onToggleSidebar: @escaping () -> Void) {
        self.onToggleSidebar = onToggleSidebar
        managedToolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        super.init()

        managedToolbar.delegate = self
        managedToolbar.displayMode = .iconOnly
        managedToolbar.allowsUserCustomization = false
        managedToolbar.autosavesConfiguration = false
    }

    // MARK: Internal

    static let toolbarIdentifier = NSToolbar.Identifier(
        "\(RockxyIdentity.current.logSubsystem).settings.toolbar"
    )
    static let sidebarToggleIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).settings.toolbar.toggleSidebar"
    )

    let managedToolbar: NSToolbar
    var onToggleSidebar: () -> Void

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Self.sidebarToggleIdentifier,
            .sidebarTrackingSeparator,
            .flexibleSpace,
        ]
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.sidebarToggleIdentifier else {
            return nil
        }

        let label = String(localized: "Toggle Settings Sidebar")
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = #selector(toggleSidebar(_:))
        item.image = NSImage(
            systemSymbolName: "sidebar.leading",
            accessibilityDescription: label
        )
        // Keep the native toolbar item icon-only at rest. A bordered item adds
        // a persistent bezel that visually overlaps the sidebar's rounded edge.
        item.isBordered = false
        return item
    }

    // MARK: Private

    @objc
    private func toggleSidebar(_ sender: Any?) {
        onToggleSidebar()
    }
}
