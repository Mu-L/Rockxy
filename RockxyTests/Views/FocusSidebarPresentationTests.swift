import Foundation
@testable import Rockxy
import Testing

// MARK: - FocusSidebarPresentationTests

struct FocusSidebarPresentationTests {
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

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
