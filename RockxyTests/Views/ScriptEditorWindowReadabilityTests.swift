import Foundation
@testable import Rockxy
import Testing

// Structure contract for the redesigned Script Editor window: native tool-window
// chrome, an intent-dependent scene with restoration disabled, adaptive layout,
// and the removal of every dead-end / no-op affordance.

@MainActor
struct ScriptEditorWindowReadabilityTests {
    // MARK: Internal

    @Test("Script Editor window uses the approved native structure and honest actions")
    func scriptEditorUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Scripting/ScriptEditorWindowView.swift")
        let consoleSource = try readProjectFile("Rockxy/Views/Scripting/ScriptConsolePanel.swift")

        // Shared tool-window typography + adaptive, non-clipping shell.
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("minWidth: max(900, min(1_180, toolMetrics.bodyFontSize * 20 + 640))"))
        #expect(source.contains("minHeight: max(620, min(720, toolMetrics.bodyFontSize * 10 + 480))"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("max(150, toolMetrics.bodyFontSize * 8.5)"))

        // Compact matching GroupBox + resizable code/console HSplitView (not a fixed 230 panel).
        #expect(source.contains("GroupBox"))
        #expect(source.contains("HSplitView"))
        #expect(source.contains("String(localized: \"Matching Configuration\")"))
        #expect(!source.contains(".frame(width: 230)"))
        #expect(!source.contains("String(localized: \"Matching Rule\")"))

        // Explicit native unavailable/loading states for the intent-dependent window.
        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains("case .awaitingIntent"))
        #expect(source.contains("String(localized: \"No Script Loaded\")"))
        #expect(source.contains("viewModel.requestLoad(intent:"))

        // User-directed Test URL / Test Match; invalid regex is surfaced honestly.
        #expect(source.contains("String(localized: \"Test URL\")"))
        #expect(source.contains("Text(\"Test Match\")"))
        #expect(source.contains("viewModel.runRuleTest()"))
        #expect(!source.contains("Test your Rule"))

        // Run request/response/mock controls, with mock normalization routed through the VM.
        #expect(source.contains("Text(\"Request\")"))
        #expect(source.contains("Text(\"Response\")"))
        #expect(source.contains("Text(\"Mock API\")"))
        #expect(source.contains("viewModel.setRunAsMock($0)"))
        #expect(source.contains("viewModel.setRunOnRequest($0)"))

        // Save & Activate is the clear primary action with a truthful (label-free) shortcut.
        #expect(source.contains("footerActionLabel(String(localized: \"Save & Activate\"), weight: .semibold)"))
        #expect(source.contains(".rockxyGlassButtonStyle(prominent: true)"))
        #expect(!source.contains("Save & Activate ⌘S"))
        #expect(source.contains(#".keyboardShortcut("s", modifiers: .command)"#))
        #expect(source.contains(#".keyboardShortcut("r", modifiers: .command)"#))
        #expect(source.contains(#".keyboardShortcut("c", modifiers: [.command, .shift])"#))

        // Truthful editing helpers, no fictional templates.
        #expect(source.contains("footerActionLabel(String(localized: \"Beautify\"))"))
        #expect(source.contains("viewModel.insertHeaderExample()"))
        #expect(!source.contains("Snippet Code"))

        // Three-way unsaved-changes decision + destructive reset confirmation.
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("String(localized: \"Save & Switch\")"))
        #expect(source.contains("String(localized: \"Discard Changes\")"))
        #expect(source.contains("String(localized: \"Reset Shared State\")"))
        #expect(source.contains("isShowingResetConfirmation"))

        // Every dead-end / no-op affordance is gone.
        #expect(!source.contains("Open with…"))
        #expect(!source.contains("Import JSON or Other File…"))
        #expect(!source.contains("Environment Variables"))
        #expect(!source.contains("Menu(\"Configs\")"))
        #expect(!source.contains("Documentations"))

        // Console distinguishes truly empty from filtered-empty output.
        #expect(consoleSource.contains("viewModel.consoleEmptyState"))
        #expect(consoleSource.contains("case .filtered"))
        #expect(consoleSource.contains("No Matching Output"))
        #expect(consoleSource.contains("viewModel.visibleConsoleEntries"))
    }

    @Test("Script Editor scene is intent-dependent with restoration disabled and a native default size")
    func scriptEditorSceneDisablesRestorationAndUsesNativeShell() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")

        let sceneStart = try #require(
            appSource.range(of: "Window(String(localized: \"Script Editor\"), id: \"scriptEditor\")")
        )
        let scenesAfter = appSource[sceneStart.lowerBound...]
        let nextScene = try #require(
            scenesAfter.range(of: "Window(String(localized: \"Inspector Preview Tabs\"), id: \"bodyPreviewerTabs\")")
        )
        let sceneSource = scenesAfter[..<nextScene.lowerBound]

        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(sceneSource.contains(".windowResizability(.contentMinSize)"))
        #expect(sceneSource.contains(".defaultSize(width: 1_120, height: 720)"))
        #expect(sceneSource.contains(".rockxyDisablingRestorationOnModernMacOS()"))
        #expect(appSource.contains("func rockxyDisablingRestorationOnModernMacOS()"))
        #expect(appSource.contains(".restorationBehavior(.disabled)"))
        #expect(!sceneSource.contains(".defaultSize(width: 1_120, height: 690)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}
