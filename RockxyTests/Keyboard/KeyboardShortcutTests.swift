import Foundation
@testable import Rockxy
import Testing

@Suite("Keyboard shortcuts")
struct KeyboardShortcutTests {
    // MARK: Internal

    @Test("KS convention row is documented", arguments: KeyboardShortcutCatalog.allShortcuts)
    func conventionRowIsDocumented(shortcut: KeyboardShortcutReference) throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(Self.shortcutIsDocumented(shortcut.shortcut, in: reference))
        #expect(reference.localizedCaseInsensitiveContains(shortcut.action))
    }

    @Test("KS_MENU_01 discoverable menu shortcuts are listed with menu locations")
    func menuShortcutsHaveMenuLocation() {
        let menuBacked = KeyboardShortcutCatalog.allShortcuts.filter { $0.menu != nil }
        #expect(!menuBacked.isEmpty)
        #expect(menuBacked.allSatisfy { $0.menu?.isEmpty == false })
    }

    @Test("KS_CONFLICT_01 no duplicate shortcut in the same documented context")
    func noDuplicateShortcutInSameContext() {
        let grouped = Dictionary(grouping: KeyboardShortcutCatalog.allShortcuts) { shortcut in
            "\(shortcut.window)|\(shortcut.context)|\(shortcut.shortcut)"
        }
        let duplicates = grouped.filter { _, rows in rows.count > 1 }
        #expect(duplicates.isEmpty)
    }

    @Test("KS_FOCUS_01 rules lists document immediate toggle focus")
    func rulesListToggleFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("`↵` / `Space`"))
        #expect(reference.localizedCaseInsensitiveContains("list has focus"))
    }

    @Test("HTTPS Decryption documents only shortcuts implemented by its window")
    func httpsDecryptionShortcutsMatchWindow() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        let httpsShortcuts = KeyboardShortcutCatalog.allShortcuts.filter { $0.window == "HTTPS Decryption" }

        #expect(Set(httpsShortcuts.map(\.shortcut)) == Set(["⌘↩", "⌘⌫", "Space", "⌘F"]))
        #expect(!httpsShortcuts.contains { $0.action.localizedCaseInsensitiveContains("add") })
        #expect(reference.contains("Applies to the HTTPS Decryption window."))
    }

    @Test("KS_FOCUS_02 Compose documents URL autofocus and focus shortcut")
    func composeURLFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("Focus the URL field"))
        #expect(reference.contains("`⌘L`"))
        #expect(reference.contains("Cancel the active request"))
        #expect(reference.contains("`⌘.`"))
    }

    @Test("KS_FOCUS_03 Breakpoint Queue documents execute without an extra click")
    func breakpointQueueExecuteFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("Apply changes and continue the selected paused item"))
        #expect(reference.contains("`⌘↩`"))
    }

    @Test("Help sheet is backed by the same shortcut catalog")
    func helpSheetUsesCatalog() {
        let allRows = KeyboardShortcutCatalog.allShortcuts
        #expect(allRows.count >= 40)
        #expect(KeyboardShortcutCatalog.filtered(by: "compose").contains { $0.title == "Compose" })
        #expect(KeyboardShortcutCatalog.filtered(by: "breakpoint").contains { $0.title == "Breakpoint Queue" })
        #expect(KeyboardShortcutCatalog.filtered(by: "compare").contains { $0.title == "Basic Compare" })
    }

    @Test("Main capture shortcuts do not collide with Context Dock or Protobuf")
    func mainCaptureShortcutsDoNotCollide() throws {
        let app = try Self.projectFile(named: "Rockxy/RockxyApp.swift")
        let contextDock = try Self.projectFile(named: "Rockxy/Views/Inspector/ContextDockView.swift")

        #expect(Self.occurrences(of: #".keyboardShortcut("u", modifiers: [.command, .option])"#, in: app) == 1)
        #expect(Self.occurrences(of: #".keyboardShortcut("r", modifiers: [.command, .option])"#, in: app) == 1)
        #expect(!app.contains(#".keyboardShortcut("p", modifiers: [.command])"#))
        #expect(!contextDock.contains(#".keyboardShortcut("k", modifiers: .command)"#))
    }

    @Test("Clear does not render in the workspace footer")
    func clearDoesNotRenderInWorkspaceFooter() throws {
        let footer = try Self.projectFile(named: "Rockxy/Views/RequestList/StatusBarView.swift")
        let app = try Self.projectFile(named: "Rockxy/RockxyApp.swift")

        #expect(!footer.contains(#"title: String(localized: "Clear", bundle: RockxyLocalization.bundle)"#))
        #expect(!footer.contains("var onClear:"))
        #expect(app.contains(#"Button(String(localized: "Clear Session", bundle: RockxyLocalization.bundle))"#))
        #expect(app.contains(#".keyboardShortcut("k", modifiers: [.command])"#))
        #expect(KeyboardShortcutCatalog.allShortcuts.contains {
            $0.action == "Clear session" && $0.shortcut == "⌘K"
        })
    }

    @Test("Traffic command strip reuses menu shortcuts instead of registering duplicates")
    func trafficCommandStripDoesNotOwnShortcuts() throws {
        let app = try Self.projectFile(named: "Rockxy/RockxyApp.swift")
        let commandBar = try Self.projectFile(named: "Rockxy/Views/Toolbar/TrafficCommandBar.swift")

        #expect(!commandBar.contains(".keyboardShortcut"))
        #expect(!app.contains(#".keyboardShortcut(.upArrow, modifiers: [.command])"#))
        #expect(!app.contains(#".keyboardShortcut(.downArrow, modifiers: [.command])"#))
        #expect(commandBar.contains("Jump to First Request"))
        #expect(commandBar.contains("Jump to Last Request"))
        #expect(KeyboardShortcutCatalog.allShortcuts.contains {
            $0.action == "Follow the newest visible request" && $0.shortcut == "⇧⌘L"
        })
    }

    @Test("Recording has one visible command-bar owner instead of an overflow duplicate")
    func recordingDoesNotRemainInTrafficActions() throws {
        let commandBar = try Self.projectFile(named: "Rockxy/Views/Toolbar/TrafficCommandBar.swift")

        #expect(commandBar.contains("private var recordingButton"))
        #expect(Self.occurrences(of: "actions.toggleRecording()", in: commandBar) == 1)
        #expect(!commandBar.contains("bolt.circle"))
    }

    @Test("Session and row commands have one truthful owner")
    func sessionAndContextMenuOwnership() throws {
        let app = try Self.projectFile(named: "Rockxy/RockxyApp.swift")
        let actions = try Self.projectFile(named: "Rockxy/Views/Main/MainContentCommandActions.swift")
        let requestTable = try Self.projectFile(named: "Rockxy/Views/RequestList/RequestTableView.swift")

        // File owns Save Session; Flow owns Clear Session. Neither gets a misleading alias.
        #expect(Self.occurrences(
            of: #"Button(String(localized: "Save Session…", bundle: RockxyLocalization.bundle))"#,
            in: app
        ) == 1)
        #expect(!app.contains(#"Button(String(localized: "Save Requests", bundle: RockxyLocalization.bundle))"#))
        #expect(!app.contains(#"Button(String(localized: "Delete All", bundle: RockxyLocalization.bundle))"#))
        #expect(!actions.contains("func deleteAll()"))

        // Context menus reuse actions but never display or register keyboard shortcuts.
        #expect(!requestTable.contains("keyEquivalentModifierMask"))
    }

    // MARK: Private

    private static func documentation(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("docs").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func projectFile(named path: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private static func shortcutIsDocumented(_ shortcut: String, in reference: String) -> Bool {
        let parts = shortcut.components(separatedBy: " / ")
        return parts.allSatisfy { reference.contains("`\($0)`") }
    }
}
