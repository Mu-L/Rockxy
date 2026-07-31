import Foundation
@testable import Rockxy
import Testing

// MARK: - SettingsWindowReadabilityTests

/// Contracts for the native sidebar/content Settings shell: the navigation model,
/// safe fallback for invalid persisted selection, and the resizable window shell.
struct SettingsWindowReadabilityTests {
    // MARK: Internal

    @Test("Settings navigation model is stable and complete")
    func settingsNavigationModelIsStableAndComplete() {
        // All nine categories are preserved, in order, with their persisted raw values.
        #expect(RockxySettingsTab.allCases.count == 9)
        #expect(RockxySettingsTab.allCases.map(\.rawValue) == [
            "general",
            "appearance",
            "privacy",
            "assistant",
            "tools",
            "github",
            "plugins",
            "mcp",
            "advanced",
        ])

        for tab in RockxySettingsTab.allCases {
            #expect(tab.id == tab)
            #expect(!tab.title.isEmpty)
            #expect(!tab.symbol.isEmpty)
            #expect(!tab.paneDescription.isEmpty)
        }
    }

    @Test("Invalid persisted selection resolves to general")
    func invalidPersistedSelectionResolvesToGeneral() {
        #expect(RockxySettingsTab.resolve("not-a-tab") == .general)
        #expect(RockxySettingsTab.resolve("") == .general)
        for tab in RockxySettingsTab.allCases {
            #expect(RockxySettingsTab.resolve(tab.rawValue) == tab)
        }
    }

    @Test("Programmatic selection writes the namespaced defaults key")
    func programmaticSelectionWritesNamespacedDefaultsKey() throws {
        let suiteName = "SettingsWindowReadabilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RockxySettingsTab.select(.assistant, defaults: defaults)
        #expect(defaults.string(forKey: RockxySettingsTab.defaultsKey) == "assistant")
        #expect(RockxySettingsTab.resolve(
            defaults.string(forKey: RockxySettingsTab.defaultsKey) ?? ""
        ) == .assistant)

        RockxySettingsTab.select(.general, defaults: defaults)
        #expect(defaults.string(forKey: RockxySettingsTab.defaultsKey) == "general")
    }

    @Test("Settings shell is a resizable native sidebar/content window")
    func settingsShellIsResizableNativeSidebarContentWindow() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/SettingsView.swift")
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")

        // NavigationSplitView owns the columns. Rockxy removes the system
        // toggle because Settings can otherwise host it in a second toolbar row.
        #expect(source.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        #expect(source.contains("List(RockxySettingsTab.allCases, selection: selectionBinding)"))
        #expect(source.contains("Binding<RockxySettingsTab?>"))
        #expect(source.contains("min: settingsMetrics.sidebarMinWidth"))
        #expect(source.contains("ideal: settingsMetrics.sidebarIdealWidth"))
        #expect(source.contains("max: settingsMetrics.sidebarMaxWidth"))
        #expect(source.contains(".navigationSplitViewStyle(.balanced)"))
        #expect(source.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!source.contains("titlebarContentInset"))

        // Settings uses a real AppKit toolbar item followed by a
        // sidebar-tracking separator. It stays unbordered so the native glyph
        // does not gain a capsule that overlaps the rounded sidebar edge.
        #expect(source.contains(
            "@State private var columnVisibility: NavigationSplitViewVisibility = .all"
        ))
        #expect(source.contains("SettingsChromeMetrics.sidebarContentTopInset"))
        #expect(source.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        #expect(source.contains("static let sidebarContentTopInset: CGFloat = 14"))
        #expect(source.contains("SettingsWindowToolbarInstaller("))
        #expect(source.contains("SettingsWindowToolbar: NSObject, NSToolbarDelegate"))
        #expect(source.contains("managedToolbar = NSToolbar(identifier: Self.toolbarIdentifier)"))
        #expect(source.contains("window.styleMask.insert(.fullSizeContentView)"))
        #expect(source.contains("window.toolbarStyle = .unifiedCompact"))
        #expect(source.contains("withAnimation(.easeInOut(duration: 0.26))"))
        #expect(source.contains(".sidebarTrackingSeparator"))
        #expect(source.contains("let item = NSToolbarItem(itemIdentifier: itemIdentifier)"))
        #expect(source.contains("systemSymbolName: \"sidebar.leading\""))
        #expect(source.contains("item.target = self"))
        #expect(source.contains("item.action = #selector(toggleSidebar(_:))"))
        #expect(source.contains("item.isBordered = false"))
        #expect(!source.contains("item.isBordered = true"))
        #expect(!source.contains("toolbarControlDownwardOffset"))
        #expect(!source.contains("button.layer?.setAffineTransform("))
        #expect(source.contains("columnVisibility == .detailOnly"))

        // Font scaling belongs to pane content. Applying it at the split root
        // also scales native toolbar controls and can create a second toolbar row.
        #expect(source.contains(".font(settingsMetrics.font())\n                .tag(tab)"))
        #expect(!source.contains(".listStyle(.sidebar)\n            .font(settingsMetrics.font())"))
        #expect(source.contains("detailContent(for: selectedTab)\n                .font(settingsMetrics.font())"))

        // Visited panes remain mounted so local drafts survive sidebar navigation.
        #expect(source.contains("@State private var loadedTabs: Set<RockxySettingsTab> = []"))
        #expect(source.contains("private var persistentPaneStack: some View"))
        #expect(source.contains("ForEach(loadedPaneTabs)"))
        #expect(source.contains(".allowsHitTesting(isSelected)"))
        #expect(source.contains(".accessibilityHidden(!isSelected)"))

        // Pane types stay explicit without type erasure.
        #expect(source.contains("switch tab {"))
        #expect(!source.contains("AnyView"))

        // One compact native pane header precedes the selected pane.
        #expect(source.contains("private func paneHeader(for tab: RockxySettingsTab)"))
        #expect(source.contains("tab.paneDescription"))

        // The fixed 820x600 shell is gone; geometry is adaptive and resizable.
        #expect(!source.contains(".frame(width: settingsMetrics.windowWidth, height: settingsMetrics.windowHeight)"))
        #expect(source.contains("minWidth: settingsMetrics.windowMinWidth"))
        #expect(source.contains("idealWidth: settingsMetrics.windowIdealWidth"))
        #expect(source.contains("minHeight: settingsMetrics.windowMinHeight"))
        #expect(source.contains("maxWidth: .infinity"))

        // The Settings scene inherits Appearance metrics and resizes to content min size.
        #expect(appSource.contains("Settings {\n            AppUIDisplayMetricsProvider"))
        #expect(appSource.contains(".windowResizability(.contentMinSize)"))
        #expect(appSource.contains(".windowToolbarStyle(.unifiedCompact)"))
    }

    @Test("Settings panes share one outer layout contract")
    func settingsPanesShareOuterLayoutContract() throws {
        let componentSource = try readProjectFile("Rockxy/Views/Settings/SettingsSectionComponents.swift")
        #expect(componentSource.contains("struct SettingsPane<Content: View>: View"))
        #expect(componentSource.contains(".padding(.horizontal, settingsMetrics.contentPadding)"))
        #expect(componentSource.contains(".padding(.vertical, settingsMetrics.paneContentPadding)"))

        let standardPanePaths = [
            "Rockxy/Views/Settings/GeneralSettingsTab.swift",
            "Rockxy/Views/Settings/AppearanceSettingsTab.swift",
            "Rockxy/Views/Settings/PrivacySettingsTab.swift",
            "Rockxy/Views/Settings/AssistantSettingsTab.swift",
            "Rockxy/Views/Settings/ToolsSettingsTab.swift",
            "Rockxy/Views/Settings/GitHubSettingsTab.swift",
            "Rockxy/Views/Settings/MCPSettingsTab.swift",
            "Rockxy/Views/Settings/AdvancedSettingsTab.swift",
        ]

        for path in standardPanePaths {
            let paneSource = try readProjectFile(path)
            #expect(
                paneSource.contains("SettingsPane {"),
                "Expected \(path) to use the shared Settings pane scaffold"
            )
        }

        let privacySource = try readProjectFile("Rockxy/Views/Settings/PrivacySettingsTab.swift")
        #expect(!privacySource.contains("Form {"))

        let appearanceSource = try readProjectFile("Rockxy/Views/Settings/AppearanceSettingsTab.swift")
        #expect(!appearanceSource.contains(".padding(.horizontal, 18)"))

        // Plugins intentionally keeps a full-bleed master/detail surface; it
        // still lives under the same shell header and does not add outer insets.
        let pluginsSource = try readProjectFile("Rockxy/Views/Settings/PluginsSettingsTab.swift")
        #expect(pluginsSource.contains("VStack(spacing: 0)"))
        #expect(pluginsSource.contains("pluginListPanel"))
        #expect(!pluginsSource.contains(".padding(.horizontal, settingsMetrics.contentPadding)"))
    }

    @Test("MCP configuration remains readable without wrapping long paths")
    func mcpConfigurationUsesScrollableCodeSurface() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/MCPSettingsTab.swift")

        #expect(source.contains("SettingsSectionCard(String(localized: \"Client Configuration\"))"))
        #expect(source.contains("ScrollView(.horizontal)"))
        #expect(source.contains(".fixedSize(horizontal: true, vertical: true)"))
        #expect(source.contains(".textSelection(.enabled)"))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
