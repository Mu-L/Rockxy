import Foundation
@testable import Rockxy
import Testing

// Regression tests for the detached Inspector window handoff store and its wiring.

// MARK: - DetachedInspectorStoreTests

@MainActor
struct DetachedInspectorStoreTests {
    @Test("Presenting a selection pins the exact transaction reference and highlight context")
    func presentPinsExactReferenceAndContext() {
        let store = DetachedInspectorStore.shared
        let transaction = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/pin")
        let context = InspectorHighlightContext(literalTerms: ["token"], regexPatterns: ["[0-9]+"])

        store.present(transaction: transaction, highlightContext: context)

        #expect(store.requestedSelection?.transaction === transaction)
        #expect(store.requestedSelection?.highlightContext == context)
    }

    @Test("Each present bumps the version monotonically")
    func presentIncrementsVersion() {
        let store = DetachedInspectorStore.shared
        let previousVersion = store.version

        store.present(
            transaction: TestFixtures.makeTransaction(url: "https://api.example.com/v1"),
            highlightContext: .empty
        )

        #expect(store.version == previousVersion &+ 1)
    }

    @Test("Re-presenting retargets the window to a new transaction and bumps the version again")
    func presentRetargetsSelection() {
        let store = DetachedInspectorStore.shared
        let first = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/first")
        let second = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/second")

        store.present(transaction: first, highlightContext: .empty)
        let afterFirst = store.version
        #expect(store.requestedSelection?.transaction === first)

        store.present(transaction: second, highlightContext: .empty)

        #expect(store.requestedSelection?.transaction === second)
        #expect(store.version == afterFirst &+ 1)
    }

    @Test("Dismissing releases only the matching retained selection")
    func dismissReleasesOnlyMatchingSelection() throws {
        let store = DetachedInspectorStore.shared
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/retained")
        store.present(transaction: transaction, highlightContext: .empty)
        let selectionID = try #require(store.requestedSelection?.id)

        store.dismiss(selectionID: UUID())
        #expect(store.requestedSelection?.transaction === transaction)

        store.dismiss(selectionID: selectionID)
        #expect(store.requestedSelection == nil)
    }
}

// MARK: - DetachedInspectorWiringTests

/// Source contract locking the detached Inspector window id, the pop-out affordance, and
/// the non-recursive detached window rendering. Actual SwiftUI window presentation is not
/// exercised here — these assertions read source to keep the handoff wiring aligned.
struct DetachedInspectorWiringTests {
    // MARK: Internal

    @Test("The pop-out affordance is restrained, labeled, and only shown when a callback is supplied")
    func urlBarPopOutButtonIsGatedAndLabeled() throws {
        let urlBar = try readProjectFile("Rockxy/Views/Inspector/InspectorURLBar.swift")

        #expect(urlBar.contains("var onOpenDetachedInspector: (() -> Void)?"))
        #expect(urlBar.contains("if let onOpenDetachedInspector {"))
        #expect(urlBar.contains("Image(systemName: \"macwindow.on.rectangle\")"))
        #expect(urlBar.contains(".help(String(localized: \"Open Inspector in New Window\"))"))
        #expect(urlBar.contains(".accessibilityLabel(String(localized: \"Open Inspector in New Window\"))"))
    }

    @Test("The main panel opens the detached window only in its single-selection branch")
    func panelWiresDetachedHandoff() throws {
        let panel = try readProjectFile("Rockxy/Views/Inspector/InspectorPanelView.swift")

        #expect(panel.contains("onOpenDetachedInspector:"))
        #expect(panel.contains("DetachedInspectorStore.shared.present("))
        #expect(panel.contains("openWindow(id: \"detachedInspector\")"))
    }

    @Test("The app declares one detached Inspector window scene bound to that id")
    func appDeclaresDetachedInspectorWindow() throws {
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(app.contains("id: \"detachedInspector\""))
        #expect(app.contains("DetachedInspectorWindowView(coordinator:"))
    }

    @Test("The detached window renders the URL bar without re-offering the pop-out affordance")
    func detachedWindowDoesNotRecurse() throws {
        let window = try readProjectFile("Rockxy/Views/Inspector/DetachedInspectorWindowView.swift")

        #expect(window.contains("InspectorURLBar("))
        #expect(!window.contains("onOpenDetachedInspector"))
        #expect(window.contains("onOpenToolWindow: { id in openWindow(id: id) }"))
        #expect(window.contains("previewTabStore: coordinator.previewTabStore"))
        #expect(window.contains("@State private var selection: DetachedInspectorSelection?"))
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
