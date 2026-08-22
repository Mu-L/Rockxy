import Foundation
@testable import Rockxy
import Testing

// Regression tests for `WorkspaceStore` in the models ui layer.

@MainActor
struct WorkspaceStoreTests {
    // MARK: - Initialization

    @Test("Store initializes with one default unclosable workspace")
    func defaultInit() {
        let store = WorkspaceStore()
        #expect(store.workspaces.count == 1)
        #expect(store.workspaces[0].isClosable == false)
        #expect(store.activeWorkspaceID == store.workspaces[0].id)
    }

    // MARK: - Create

    @Test("Create workspace adds tab and activates it")
    func createWorkspace() {
        let store = WorkspaceStore()
        let ws = store.createWorkspace(title: "New")
        #expect(store.workspaces.count == 2)
        #expect(store.activeWorkspaceID == ws.id)
        #expect(ws.title == "New")
        #expect(ws.isClosable == true)
    }

    @Test("Create workspace with filter sets initial filter")
    func createWithFilter() {
        let store = WorkspaceStore()
        var filter = FilterCriteria.empty
        filter.sidebarDomain = "api.example.com"
        let ws = store.createWorkspace(title: "API", filter: filter)
        #expect(ws.filterCriteria.sidebarDomain == "api.example.com")
    }

    @Test("Create workspace respects max limit")
    func maxWorkspacesGuard() {
        let store = WorkspaceStore()
        for i in 1 ..< store.maxWorkspaces {
            store.createWorkspace(title: "Tab \(i)")
        }
        #expect(store.workspaces.count == store.maxWorkspaces)

        let extra = store.createWorkspace(title: "Over limit")
        // Should return active workspace, not create new one
        #expect(store.workspaces.count == store.maxWorkspaces)
        #expect(extra.title != "Over limit")
    }

    // MARK: - Close

    @Test("Close workspace removes it and selects adjacent")
    func closeWorkspace() {
        let store = WorkspaceStore()
        let ws1 = store.createWorkspace(title: "Tab 1")
        let ws2 = store.createWorkspace(title: "Tab 2")

        store.selectWorkspace(id: ws1.id)
        store.closeWorkspace(id: ws1.id)

        #expect(store.workspaces.count == 2) // default + ws2
        #expect(!store.workspaces.contains { $0.id == ws1.id })
        // Should select ws2 (next available at same index)
        #expect(store.activeWorkspaceID == ws2.id)
    }

    @Test("Cannot close default workspace")
    func cannotCloseDefault() {
        let store = WorkspaceStore()
        let defaultID = store.workspaces[0].id
        store.closeWorkspace(id: defaultID)
        #expect(store.workspaces.count == 1)
        #expect(store.workspaces[0].id == defaultID)
    }

    @Test("Closing last closable tab falls back to default")
    func closeLastClosable() {
        let store = WorkspaceStore()
        let ws = store.createWorkspace(title: "Only Tab")
        store.closeWorkspace(id: ws.id)
        #expect(store.workspaces.count == 1)
        #expect(store.activeWorkspaceID == store.workspaces[0].id)
    }

    @Test("Closing active tab selects previous when at end")
    func closeActiveAtEnd() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        let ws2 = store.createWorkspace(title: "Tab 2")
        // ws2 is active (last created)
        store.closeWorkspace(id: ws2.id)
        // Should select Tab 1 (previous)
        #expect(store.activeWorkspace.title == "Tab 1")
    }

    // MARK: - Select

    @Test("Select workspace by ID")
    func selectByID() {
        let store = WorkspaceStore()
        let defaultID = store.workspaces[0].id
        let ws = store.createWorkspace(title: "New")
        store.selectWorkspace(id: defaultID)
        #expect(store.activeWorkspaceID == defaultID)
        store.selectWorkspace(id: ws.id)
        #expect(store.activeWorkspaceID == ws.id)
    }

    @Test("Select workspace by index")
    func selectByIndex() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")
        store.selectWorkspace(at: 0)
        #expect(store.activeWorkspaceIndex == 0)
        store.selectWorkspace(at: 2)
        #expect(store.activeWorkspaceIndex == 2)
    }

    @Test("Select by invalid index does nothing")
    func selectInvalidIndex() {
        let store = WorkspaceStore()
        let originalID = store.activeWorkspaceID
        store.selectWorkspace(at: 99)
        #expect(store.activeWorkspaceID == originalID)
        store.selectWorkspace(at: -1)
        #expect(store.activeWorkspaceID == originalID)
    }

    @Test("Select by invalid ID does nothing")
    func selectInvalidID() {
        let store = WorkspaceStore()
        let originalID = store.activeWorkspaceID
        store.selectWorkspace(id: UUID())
        #expect(store.activeWorkspaceID == originalID)
    }

    // MARK: - Navigation

    @Test("Previous workspace wraps around")
    func previousWraps() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")

        store.selectWorkspace(at: 0)
        store.selectPreviousWorkspace()
        #expect(store.activeWorkspaceIndex == store.workspaces.count - 1)
    }

    @Test("Next workspace wraps around")
    func nextWraps() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")

        store.selectWorkspace(at: store.workspaces.count - 1)
        store.selectNextWorkspace()
        #expect(store.activeWorkspaceIndex == 0)
    }

    @Test("Previous and next cycle through all tabs")
    func fullCycle() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")

        store.selectWorkspace(at: 0)
        var visited = [0]
        for _ in 0 ..< store.workspaces.count {
            store.selectNextWorkspace()
            visited.append(store.activeWorkspaceIndex)
        }
        // Should visit 0 -> 1 -> 2 -> 0 (cycle back)
        #expect(visited == [0, 1, 2, 0])
    }

    // MARK: - Reorder

    @Test("Move workspace reorders correctly")
    func moveWorkspace() {
        let store = WorkspaceStore()
        let ws1 = store.createWorkspace(title: "A")
        _ = store.createWorkspace(title: "B")

        // Move "A" (index 1) to end (index 2)
        store.moveWorkspace(from: 1, to: 2)
        #expect(store.workspaces[2].id == ws1.id)
    }

    @Test("Move with invalid indices does nothing")
    func moveInvalid() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "A")
        let titles = store.workspaces.map(\.title)
        store.moveWorkspace(from: -1, to: 0)
        #expect(store.workspaces.map(\.title) == titles)
        store.moveWorkspace(from: 0, to: 99)
        #expect(store.workspaces.map(\.title) == titles)
    }

    @Test("Reorder workspaces follows native tab order")
    func reorderWorkspacesToIDs() {
        let store = WorkspaceStore()
        let defaultID = store.workspaces[0].id
        let ws1 = store.createWorkspace(title: "A")
        let ws2 = store.createWorkspace(title: "B")
        let ws3 = store.createWorkspace(title: "C")

        store.reorderWorkspaces(toWorkspaceIDs: [ws2.id, defaultID, ws3.id, ws1.id])

        #expect(store.workspaces.map(\.id) == [ws2.id, defaultID, ws3.id, ws1.id])
        #expect(store.activeWorkspaceID == ws3.id)
    }

    @Test("Partial native reorder keeps remaining workspaces stable")
    func partialReorderKeepsRemainder() {
        let store = WorkspaceStore()
        let defaultID = store.workspaces[0].id
        let ws1 = store.createWorkspace(title: "A")
        let ws2 = store.createWorkspace(title: "B")
        let ws3 = store.createWorkspace(title: "C")

        store.reorderWorkspaces(toWorkspaceIDs: [ws3.id, ws1.id])

        #expect(store.workspaces.map(\.id) == [ws3.id, ws1.id, defaultID, ws2.id])
    }

    // MARK: - Duplicate

    @Test("Duplicate creates copy with same filter and tab state")
    func duplicateWorkspace() throws {
        let store = WorkspaceStore()
        var filter = FilterCriteria.empty
        filter.sidebarDomain = "test.com"
        let original = store.createWorkspace(title: "Original", filter: filter)
        original.activeMainTab = .logs
        original.isFilterBarVisible = true
        original.contextDockTab = .aiAssistant

        let copy = try #require(store.duplicateWorkspace(id: original.id))
        #expect(copy.id != original.id)
        #expect(copy.filterCriteria.sidebarDomain == "test.com")
        #expect(copy.activeMainTab == .logs)
        #expect(copy.contextDockTab == .aiAssistant)
        #expect(copy.isFilterBarVisible == true)
        #expect(copy.isClosable == true)
        #expect(store.activeWorkspaceID == copy.id)
    }

    @Test("Duplicate inserts after source workspace")
    func duplicatePosition() throws {
        let store = WorkspaceStore()
        let ws1 = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")

        let copy = try #require(store.duplicateWorkspace(id: ws1.id))
        // Copy should be right after ws1
        let ws1Index = try #require(store.workspaces.firstIndex { $0.id == ws1.id })
        let copyIndex = try #require(store.workspaces.firstIndex { $0.id == copy.id })
        #expect(copyIndex == ws1Index + 1)
    }

    // MARK: - Close Others

    @Test("Close others removes all closable except specified")
    func closeOthers() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        let ws2 = store.createWorkspace(title: "Tab 2")
        _ = store.createWorkspace(title: "Tab 3")

        store.closeOtherWorkspaces(except: ws2.id)
        #expect(store.workspaces.count == 2) // default (unclosable) + ws2
        #expect(store.workspaces.contains { $0.id == ws2.id })
        #expect(store.workspaces.contains { !$0.isClosable }) // default still there
    }

    // MARK: - Rename

    @Test("Rename updates workspace title")
    func rename() {
        let store = WorkspaceStore()
        let ws = store.createWorkspace(title: "Old Name")
        store.renameWorkspace(id: ws.id, to: "New Name")
        #expect(ws.title == "New Name")
    }

    @Test("Rename with invalid ID does nothing")
    func renameInvalid() {
        let store = WorkspaceStore()
        store.renameWorkspace(id: UUID(), to: "Ghost")
        #expect(store.workspaces[0].title == String(localized: "All Traffic"))
    }

    // MARK: - Active Workspace Computed Properties

    @Test("activeWorkspace returns correct workspace")
    func activeWorkspaceComputed() {
        let store = WorkspaceStore()
        let ws = store.createWorkspace(title: "Active")
        #expect(store.activeWorkspace.id == ws.id)
    }

    @Test("activeWorkspaceIndex returns correct index")
    func activeWorkspaceIndexComputed() {
        let store = WorkspaceStore()
        _ = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")
        #expect(store.activeWorkspaceIndex == 2)
        store.selectWorkspace(at: 0)
        #expect(store.activeWorkspaceIndex == 0)
    }

    // MARK: - Default Capacity

    @Test("default workspace tab limit is 8")
    func defaultWorkspaceTabLimit() {
        let store = WorkspaceStore()
        #expect(store.maxWorkspaces == 8)
    }

    // MARK: - Hydration retention vs creation capacity

    @Test("hydration retains tabs above the creation limit up to the structural bound")
    func hydrationRetainsOverCreationCapacity() {
        let store = WorkspaceStore(maxWorkspaces: 8)
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let extras = (0 ..< 12).map { ProjectTabSnapshot(title: "Tab \($0)", isClosable: true) }

        store.applyTabSnapshots([base] + extras, activeTabID: base.id)

        // 13 tabs exceed the creation limit of 8 but sit under the structural bound,
        // so every one is retained rather than truncated to the creation limit.
        #expect(store.workspaces.count == 13)
        #expect(store.workspaces.count > store.maxWorkspaces)
        #expect(store.activeWorkspaceID == base.id)
    }

    @Test("hydration never exceeds the structural tab upper bound")
    func hydrationClampsToStructuralBound() {
        let store = WorkspaceStore(maxWorkspaces: 8)
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let extras = (0 ..< 40).map { ProjectTabSnapshot(title: "Tab \($0)", isClosable: true) }

        store.applyTabSnapshots([base] + extras, activeTabID: base.id)

        #expect(store.workspaces.count == ProjectStructuralLimits.tabCountRange.upperBound)
        #expect(store.workspaces.contains { !$0.isClosable })
    }

    // MARK: - Runtime capacity refresh

    @Test("lowering capacity at runtime keeps existing tabs and only blocks new creation")
    func refreshCapacityDecreaseRetainsTabs() {
        let store = WorkspaceStore(maxWorkspaces: 8)
        _ = store.createWorkspace(title: "Tab 1")
        _ = store.createWorkspace(title: "Tab 2")
        #expect(store.workspaces.count == 3)

        store.refreshCapacity(maxWorkspaces: 2)

        #expect(store.maxWorkspaces == 2)
        // No hydrated/created tab is closed by a lower limit.
        #expect(store.workspaces.count == 3)
        #expect(!store.canCreateWorkspace)
        let extra = store.createWorkspace(title: "Blocked")
        #expect(store.workspaces.count == 3)
        #expect(extra.title != "Blocked")
    }

    @Test("raising capacity at runtime re-enables creation")
    func refreshCapacityIncreaseReenablesCreation() {
        let store = WorkspaceStore(maxWorkspaces: 1)
        #expect(!store.canCreateWorkspace)

        store.refreshCapacity(maxWorkspaces: 3)

        #expect(store.maxWorkspaces == 3)
        #expect(store.canCreateWorkspace)
        _ = store.createWorkspace(title: "Now Allowed")
        #expect(store.workspaces.count == 2)
    }

    @Test("capacity refresh clamps to at least one")
    func refreshCapacityClampsToMinimum() {
        let store = WorkspaceStore(maxWorkspaces: 4)
        store.refreshCapacity(maxWorkspaces: 0)
        #expect(store.maxWorkspaces == 1)
    }

    @Test("construction clamps into the structural tab range above and below")
    func constructionClampsIntoStructuralRange() {
        #expect(WorkspaceStore(maxWorkspaces: 0).maxWorkspaces == ProjectStructuralLimits.tabCountRange.lowerBound)
        #expect(
            WorkspaceStore(maxWorkspaces: 10_000).maxWorkspaces == ProjectStructuralLimits.tabCountRange.upperBound
        )
    }

    @Test("capacity refresh clamps into the structural tab range above and below")
    func refreshCapacityClampsIntoStructuralRange() {
        let store = WorkspaceStore(maxWorkspaces: 4)
        store.refreshCapacity(maxWorkspaces: 10_000)
        #expect(store.maxWorkspaces == ProjectStructuralLimits.tabCountRange.upperBound)
        store.refreshCapacity(maxWorkspaces: -3)
        #expect(store.maxWorkspaces == ProjectStructuralLimits.tabCountRange.lowerBound)
    }
}
