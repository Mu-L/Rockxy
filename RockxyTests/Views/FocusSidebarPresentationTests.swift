import Foundation
@testable import Rockxy
import Testing

// MARK: - FocusSidebarPresentationTests

struct FocusSidebarPresentationTests {
    // MARK: Internal

    @Test("Focus section actions use visible native buttons")
    func focusSectionActionsUseVisibleNativeButtons() throws {
        let source = try readProjectFile("Rockxy/Views/Sidebar/SidebarView.swift")

        #expect(source.contains("actionLabel: String(localized: \"Create Focus Set\")"))
        #expect(source.contains("actionLabel: String(localized: \"Configure Noise Control\")"))
        #expect(source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains(".controlSize(.small)"))
        #expect(source.contains(".accessibilityLabel(actionLabel)"))
    }

    @Test("Browse reveals captured apps and domains without extra disclosure clicks")
    func browseGroupsStartExpanded() {
        #expect(SidebarDisclosureDefaults.appsExpanded)
        #expect(SidebarDisclosureDefaults.domainsExpanded)
    }

    @Test("Sidebar delegates modern glass bars to the system")
    func sidebarUsesSystemOwnedLiquidGlassBars() throws {
        let source = try readProjectFile("Rockxy/Views/Sidebar/SidebarView.swift")
        let bottomBar = try readProjectFile("Rockxy/Views/Sidebar/SidebarBottomBar.swift")

        #expect(source.contains("if #available(macOS 26.0, *)"))
        #expect(source.contains(".scrollEdgeEffectStyle(.soft, for: .vertical)"))
        #expect(source.contains(".safeAreaBar(edge: .top, spacing: 0)"))
        #expect(source.contains(".safeAreaBar(edge: .bottom, spacing: 0)"))
        #expect(!source.contains(".rockxyGlassEffect"))
        #expect(!bottomBar.contains(".rockxyGlassEffect"))
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
