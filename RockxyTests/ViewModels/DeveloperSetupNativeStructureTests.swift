import Foundation
import Testing

/// Source-readability checks for the Developer Setup shell. Runtime SwiftUI view
/// tests are impractical here, so these assert the structural + copy contract by
/// scanning the view source: native adaptive structure, Rockxy font helpers,
/// accessibility, and the absence of forbidden future/fixed-layout patterns.
struct DeveloperSetupNativeStructureTests {
    // MARK: Internal

    @Test("Hub uses native adaptive split structure, not a fixed dashboard shell")
    func hubUsesNativeAdaptiveStructure() throws {
        let source = try readFeatureFile("Rockxy/Views/DeveloperSetup/DeveloperSetupWindowView.swift")
        let appSource = try readFeatureFile("Rockxy/RockxyApp.swift")
        let sceneStart = try #require(
            appSource.range(of: "private struct DeveloperSetupWindowScene: Scene")
        )
        let sceneTail = appSource[sceneStart.lowerBound...]
        let sceneEnd = try #require(
            sceneTail.range(of: "// MARK: - ComposeWindowScene")
        )
        let sceneSource = sceneTail[..<sceneEnd.lowerBound]

        #expect(source.contains("NavigationSplitView"))
        #expect(source.contains(".searchable("))
        #expect(source.contains(".inspector("))
        #expect(source.contains("setupMetrics.font"))
        #expect(source.contains(".accessibilityLabel"))
        #expect(source.contains(".toolbar"))
        #expect(source.contains(".font(.system") == false)
        #expect(source.contains("cornerRadius: 12") == false)
        #expect(source.contains("cornerRadius: 14") == false)

        // No hardcoded 240 + 280 + 430 dashboard layout.
        #expect(source.contains(".frame(width: 240)") == false)
        #expect(source.contains(".frame(width: 280)") == false)
        #expect(source.contains(".frame(width: 430)") == false)

        // Restrained native chrome: no inflated root font, no navigation subtitle,
        // no card grid, no permanent breadcrumb, inspector hidden by default.
        #expect(source.contains("Developer Setup Hub") == false)
        #expect(source.contains(".navigationSubtitle") == false)
        #expect(source.contains("LazyVGrid") == false)
        #expect(source.contains("bottomStatusText") == false)
        #expect(source.contains("inspectorPresented = false"))

        // Toolbar owns a single Set Up menu with the guide/terminal actions; the
        // old Copy + Start Capture Check toolbar buttons are gone.
        #expect(source.contains("Set Up"))
        #expect(source.contains("Open Setup Guide"))
        #expect(source.contains("Open Configured Terminal"))
        #expect(source.contains("Start Capture Check") == false)

        // Copy ownership lives with the content tabs, not the toolbar.
        #expect(source.contains("Copy Snippet"))
        #expect(source.contains("Copy Command"))
        #expect(source.contains("Start Check"))
        #expect(source.contains("viewModel.activeIssue != nil"))

        // The setup utility opens materially smaller than the 1,200 x 760 main
        // workspace and ignores stale restored geometry on supported systems.
        #expect(sceneSource.contains(".defaultSize(width: 1_000, height: 640)"))
        #expect(sceneSource.contains(".restorationBehavior(.disabled)"))
    }

    @Test("Source list uses native List selection with restrained rows")
    func sourceListUsesNativeSelection() throws {
        let source = try readFeatureFile("Rockxy/Views/DeveloperSetup/DeveloperSetupSourceList.swift")

        #expect(source.contains("List(selection:"))
        #expect(source.contains(".listStyle(.sidebar)"))
        #expect(source.contains("setupMetrics"))
        #expect(source.contains(".accessibilityLabel"))
        #expect(source.contains(".font(.system") == false)

        // Subtitle is a muted exception for guide-only targets, not on every row.
        #expect(source.contains("target.supportStatus == .guideOnly"))
        // Pin accessory only shows when pinned or selected.
        #expect(source.contains("isPinned(target) || selection == target.id"))
    }

    @Test("Inspector is a compact readiness panel without setup modes or duplicate actions")
    func inspectorIsCompactReadinessPanel() throws {
        let source = try readFeatureFile("Rockxy/Views/DeveloperSetup/DeveloperSetupInspector.swift")

        #expect(source.contains("Readiness"))
        #expect(source.contains("setupMetrics"))
        #expect(source.contains("ViewThatFits"))
        #expect(source.contains("Reveal in Main Window"))
        #expect(source.contains(".font(.system") == false)

        // Removed: setup modes, the duplicate Start Check, and always-visible
        // certificate/proxy settings buttons.
        #expect(source.contains("Setup Modes") == false)
        #expect(source.contains("Start Check") == false)
        #expect(source.contains("Start Capture Check") == false)
        #expect(source.contains("Open Proxy Settings") == false)
        #expect(source.contains("Open Certificate Settings") == false)
    }

    @Test("Manual and Automatic windows are scrollable and resizable")
    func auxiliaryWindowsScrollAndResize() throws {
        for path in [
            "Rockxy/Views/DeveloperSetup/DeveloperSetupManualWindowView.swift",
            "Rockxy/Views/DeveloperSetup/DeveloperSetupAutomaticWindowView.swift",
        ] {
            let source = try readFeatureFile(path)
            #expect(source.contains("ScrollView"))
            #expect(source.contains("minWidth:"))
            #expect(source.contains("setupMetrics.font"))
            #expect(source.contains(".font(.system") == false)
            // Fixed content-size framing forbids resize; must not be present.
            #expect(source.contains(".frame(width: 780, height: 540)") == false)
            #expect(source.contains(".frame(width: 760, height: 500)") == false)
        }
    }

    @Test("Developer Setup views carry no forbidden future or duplicate-action copy")
    func viewsAvoidForbiddenCopy() throws {
        let forbidden = [
            "coming soon",
            "not shipped",
            "long-term",
            "How does it work?",
        ]

        for path in developerSetupViewFiles {
            let source = try readFeatureFile(path).lowercased()
            for phrase in forbidden {
                #expect(source.contains(phrase.lowercased()) == false)
            }
        }
    }

    @Test("Custom terminal action uses honest copy semantics")
    func customTerminalCopyIsHonest() throws {
        let source = try readFeatureFile("Rockxy/Views/DeveloperSetup/DeveloperSetupAutomaticWindowView.swift")
        #expect(source.contains("Copy Setup Command"))
    }

    // MARK: Private

    private enum ResolveError: Error, CustomStringConvertible {
        case rootNotFound(filePath: String)

        // MARK: Internal

        var description: String {
            switch self {
            case let .rootNotFound(filePath):
                "Could not locate RockxyTests directory from \(filePath)"
            }
        }
    }

    private let developerSetupViewFiles = [
        "Rockxy/Views/DeveloperSetup/DeveloperSetupWindowView.swift",
        "Rockxy/Views/DeveloperSetup/DeveloperSetupSourceList.swift",
        "Rockxy/Views/DeveloperSetup/DeveloperSetupInspector.swift",
        "Rockxy/Views/DeveloperSetup/DeveloperSetupManualWindowView.swift",
        "Rockxy/Views/DeveloperSetup/DeveloperSetupAutomaticWindowView.swift",
    ]

    private func readFeatureFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
