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
        #expect(source.contains(".rockxyGlassButtonStyle()"))
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

    @Test("Sidebar filter uses an expanding native Xcode-style search control")
    func sidebarFilterUsesNativeSearchControl() throws {
        let source = try readProjectFile("Rockxy/Views/Sidebar/SidebarBottomBar.swift")

        #expect(source.contains("NSSearchField()"))
        #expect(source.contains("searchField.sendsSearchStringImmediately = true"))
        #expect(source.contains("func controlTextDidChange"))
        #expect(source.contains("searchField.placeholderString = String(localized: \"Filter\")"))
        #expect(source.contains("systemSymbolName: \"line.3.horizontal.decrease.circle\""))
        #expect(source.contains(".frame(maxWidth: .infinity, minHeight: 28)"))
        #expect(!source.contains("TextField("))
        #expect(!source.contains(".background(Color(nsColor: .quaternaryLabelColor)"))
        #expect(!source.contains(".clipShape(RoundedRectangle"))
        #expect(!source.contains("Filter (\\u{2318}\\u{21E7}F)"))
    }

    @Test("Navigator modes use Xcode-style native icon segments")
    func navigatorModesUseNativeIconSegments() throws {
        let sidebar = try readProjectFile("Rockxy/Views/Sidebar/SidebarView.swift")
        let shared = try readProjectFile("Rockxy/Views/Common/UtilitySegmentedHeader.swift")

        #expect(sidebar.contains("WorkspaceModeSegmentedControl("))
        #expect(sidebar.contains("segments: FocusNavigatorMode.allCases.map"))
        #expect(shared.contains("NSSegmentedControl"))
        #expect(shared.contains("control.segmentStyle = .capsule"))
        #expect(shared.contains("selectedSegmentBezelColor = .controlAccentColor"))
        #expect(shared.contains("accessibilityDescription: segment.title"))
        #expect(shared.contains("control.setToolTip(segment.title, forSegment: index)"))
        #expect(shared.contains("final class EqualWidthSegmentedControl"))
        #expect(!sidebar.contains("Text(mode.title).tag(mode)"))
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
