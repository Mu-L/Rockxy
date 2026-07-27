import Foundation
@testable import Rockxy
import Testing

// Regression tests for `PreviewTabStore` in the models ui layer.

@Suite(.serialized)
@MainActor
struct PreviewTabStoreTests {
    // MARK: Internal

    // MARK: - Initialization

    @Test("Store initializes with empty tabs")
    func defaultInit() {
        let freshStore = makeCleanStore()
        #expect(freshStore.requestTabs.isEmpty)
        #expect(freshStore.responseTabs.isEmpty)
        #expect(freshStore.autoBeautify == true)
    }

    // MARK: - Enable/Disable

    @Test("Enable tab adds to correct panel")
    func enableTab() {
        let store = makeCleanStore()
        let tab = store.enableTab(renderMode: .jsonTree, panel: .request)
        #expect(store.requestTabs.count == 1)
        #expect(store.responseTabs.isEmpty)
        #expect(tab.renderMode == .jsonTree)
        #expect(tab.panel == .request)
        #expect(tab.name == "JSON Treeview")
        #expect(tab.isBuiltIn == true)
    }

    @Test("Enable same tab twice does not duplicate")
    func enableTabNoDuplicate() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .hex, panel: .response)
        store.enableTab(renderMode: .hex, panel: .response)
        #expect(store.responseTabs.count == 1)
    }

    @Test("Disable tab removes from panel")
    func disableTab() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .html, panel: .request)
        #expect(store.requestTabs.count == 1)
        store.disableTab(renderMode: .html, panel: .request)
        #expect(store.requestTabs.isEmpty)
    }

    @Test("Disable non-existent tab is no-op")
    func disableNonExistent() {
        let store = makeCleanStore()
        store.disableTab(renderMode: .hex, panel: .request)
        #expect(store.requestTabs.isEmpty)
    }

    // MARK: - Toggle

    @Test("Toggle enables then disables")
    func toggleTab() {
        let store = makeCleanStore()
        store.toggleTab(renderMode: .css, panel: .response)
        #expect(store.isEnabled(renderMode: .css, panel: .response))
        store.toggleTab(renderMode: .css, panel: .response)
        #expect(!store.isEnabled(renderMode: .css, panel: .response))
    }

    // MARK: - isEnabled

    @Test("isEnabled returns correct state")
    func isEnabledCheck() {
        let store = makeCleanStore()
        #expect(!store.isEnabled(renderMode: .json, panel: .request))
        store.enableTab(renderMode: .json, panel: .request)
        #expect(store.isEnabled(renderMode: .json, panel: .request))
        #expect(!store.isEnabled(renderMode: .json, panel: .response))
    }

    // MARK: - Multiple Tabs

    @Test("Multiple tabs in both panels")
    func multipleTabs() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .json, panel: .request)
        store.enableTab(renderMode: .hex, panel: .request)
        store.enableTab(renderMode: .jsonTree, panel: .response)
        store.enableTab(renderMode: .html, panel: .response)
        store.enableTab(renderMode: .raw, panel: .response)
        #expect(store.requestTabs.count == 2)
        #expect(store.responseTabs.count == 3)
    }

    @Test("Re-enabled tabs return to canonical format order")
    func canonicalTabOrder() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .raw, panel: .request)
        store.enableTab(renderMode: .json, panel: .request)
        store.disableTab(renderMode: .json, panel: .request)
        store.enableTab(renderMode: .json, panel: .request)

        #expect(store.requestTabs.map(\.renderMode) == [.json, .raw])
    }

    // MARK: - Panel Independence

    @Test("Same render mode can be in both panels independently")
    func panelIndependence() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .hex, panel: .request)
        store.enableTab(renderMode: .hex, panel: .response)
        #expect(store.requestTabs.count == 1)
        #expect(store.responseTabs.count == 1)
        store.disableTab(renderMode: .hex, panel: .request)
        #expect(store.requestTabs.isEmpty)
        #expect(store.responseTabs.count == 1)
    }

    @Test("Persisted custom raw tabs are ignored")
    func persistedCustomTabsIgnored() throws {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let tabs = [
            PreviewTab(name: "Legacy Raw", renderMode: .raw, panel: .response, isBuiltIn: false),
            PreviewTab(name: "Raw (Old Locale)", renderMode: .raw, panel: .response),
        ]
        environment.defaults.set(
            try JSONEncoder().encode(tabs),
            forKey: RockxyIdentity.current.defaultsKey("previewTabs")
        )

        let store = PreviewTabStore(defaults: environment.defaults)

        #expect(store.responseTabs.count == 1)
        #expect(store.responseTabs.first?.isBuiltIn == true)
        #expect(store.responseTabs.first?.name == "Raw")
    }

    @Test("Auto beautify preference persists when toggled")
    func autoBeautifyPersistsWhenToggled() {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = PreviewTabStore(defaults: environment.defaults)
        store.autoBeautify = false

        let freshStore = PreviewTabStore(defaults: environment.defaults)

        #expect(freshStore.autoBeautify == false)
    }

    @Test("Built-in request and response tabs persist across store instances")
    func builtInTabsPersistAcrossStoreInstances() {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = PreviewTabStore(defaults: environment.defaults)
        store.enableTab(renderMode: .jsonTree, panel: .request)
        store.enableTab(renderMode: .hex, panel: .response)

        let freshStore = PreviewTabStore(defaults: environment.defaults)

        #expect(freshStore.isEnabled(renderMode: .jsonTree, panel: .request))
        #expect(!freshStore.isEnabled(renderMode: .jsonTree, panel: .response))
        #expect(freshStore.isEnabled(renderMode: .hex, panel: .response))
        #expect(!freshStore.isEnabled(renderMode: .hex, panel: .request))
    }

    @Test("Inspector selection retains only an available preview tab")
    func inspectorSelectionReconciliation() {
        let selected = PreviewTab(renderMode: .json, panel: .request)

        #expect(
            InspectorPreviewSelectionReconciler.retainedSelection(
                selected,
                availableTabIDs: [selected.id]
            ) == selected
        )
        #expect(
            InspectorPreviewSelectionReconciler.retainedSelection(
                selected,
                availableTabIDs: []
            ) == nil
        )
        #expect(
            InspectorPreviewSelectionReconciler.retainedSelection(
                nil,
                availableTabIDs: [selected.id]
            ) == nil
        )
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeCleanStore() -> PreviewTabStore {
        PreviewTabStore(defaults: TestFixtures.makeIsolatedDefaults())
    }
}
