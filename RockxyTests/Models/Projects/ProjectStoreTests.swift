import Foundation
@testable import Rockxy
import Testing

// MARK: - ProjectStoreTests

@MainActor
@Suite("ProjectStore")
struct ProjectStoreTests {
    // MARK: Internal

    // MARK: Creation & naming

    @Test("creates a project, normalizes its name, and activates it")
    func createsAndActivates() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let project = try store.createProject(name: "  Staging  ")
        #expect(project.name == "Staging")
        #expect(store.activeProjectID == project.id)
        #expect(store.projects.count == 2)
        try project.validate()
    }

    @Test("rejects a name that collides after folding")
    func rejectsDuplicateName() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        _ = try store.createProject(name: "Café")
        #expect(throws: ProjectMutationError.duplicateName) {
            _ = try store.createProject(name: "cafe")
        }
    }

    @Test("rejects an invalid name")
    func rejectsInvalidName() {
        let store = ProjectStore(now: { Self.fixedDate })
        #expect(throws: ProjectMutationError.self) {
            _ = try store.createProject(name: "   ")
        }
    }

    // MARK: Capacity & clamping

    @Test("enforces the effective project capacity")
    func enforcesCapacity() throws {
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 2), now: { Self.fixedDate })
        // Default catalog already holds one project.
        _ = try store.createProject(name: "Second")
        #expect(!store.canCreateProject)
        #expect(throws: ProjectMutationError.capacityReached(limit: 2)) {
            _ = try store.createProject(name: "Third")
        }
    }

    @Test("clamps policy capacity into the structural range")
    func clampsCapacity() {
        #expect(ProjectStore(policy: CapacityPolicy(maxProjects: 500)).maxProjects == 128)
        #expect(ProjectStore(policy: CapacityPolicy(maxProjects: 0)).maxProjects == 1)
        #expect(ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 100)).maxTabsPerProject == 32)
        #expect(ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 0)).maxTabsPerProject == 1)
    }

    // MARK: Portable import

    @Test("portable import creates and activates a new project with fresh identifiers")
    func importsPortableProjectAsNew() throws {
        let source = Self.makeProject(name: "Imported API")
        let store = ProjectStore(now: { Self.fixedDate })

        let imported = try store.importProject(PortableProject(exporting: source))

        #expect(store.activeProjectID == imported.id)
        #expect(imported.id != source.id)
        #expect(Set(imported.tabs.map(\.id)).isDisjoint(with: Set(source.tabs.map(\.id))))
        #expect(store.projects.contains { $0.id == imported.id })
    }

    @Test("portable import resolves name collisions without replacing existing projects")
    func importDeduplicatesName() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let original = store.activeProject
        let imported = try store.importProject(PortableProject(exporting: original))

        #expect(store.projects.count == 2)
        #expect(store.projects.contains { $0.id == original.id && $0.name == original.name })
        #expect(imported.name == "My Project (Imported)")
    }

    @Test("capacity refusal leaves the project catalog unchanged")
    func importCapacityFailureIsAtomic() {
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 1), now: { Self.fixedDate })
        let before = store.catalog
        let portable = PortableProject(exporting: Self.makeProject(name: "Extra"))

        #expect(throws: ProjectMutationError.capacityReached(limit: 1)) {
            _ = try store.importProject(portable)
        }
        #expect(store.catalog == before)
    }

    @Test("portable import rejects excess tabs without silently truncating")
    func importTabCapacityFailureIsAtomic() {
        let store = ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 2), now: { Self.fixedDate })
        let before = store.catalog
        let portable = PortableProject(
            name: "Too Many Tabs",
            activeTabIndex: 0,
            tabs: (0 ..< 3).map {
                PortableProjectTab(title: "Tab \($0)", isClosable: $0 != 0)
            }
        )

        #expect(throws: ProjectMutationError.tabCapacityReached(limit: 2)) {
            _ = try store.importProject(portable)
        }
        #expect(store.catalog == before)
    }

    @Test("portable import rejects default insertion above the tab policy atomically")
    func importRejectsLossyDefaultInsertion() {
        let store = ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 2), now: { Self.fixedDate })
        let before = store.catalog
        let portable = PortableProject(
            name: "Closable Only",
            activeTabIndex: 1,
            tabs: [
                PortableProjectTab(title: "One", isClosable: true),
                PortableProjectTab(title: "Two", isClosable: true),
            ]
        )

        #expect(throws: ProjectMutationError.tabCapacityReached(limit: 2)) {
            _ = try store.importProject(portable)
        }
        #expect(store.catalog == before)
    }

    // MARK: Rename & select

    @Test("renames a project and rejects unknown IDs")
    func renames() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let project = try store.createProject(name: "Staging")
        try store.renameProject(id: project.id, to: "  Production ")
        #expect(store.projects.first { $0.id == project.id }?.name == "Production")
        #expect(throws: ProjectMutationError.projectNotFound) {
            try store.renameProject(id: UUID(), to: "Nope")
        }
    }

    @Test("rename rejects a colliding name")
    func renameRejectsCollision() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let a = try store.createProject(name: "Alpha")
        _ = try store.createProject(name: "Beta")
        #expect(throws: ProjectMutationError.duplicateName) {
            try store.renameProject(id: a.id, to: "beta")
        }
    }

    @Test("renaming to the identical canonical name is a no-op")
    func renameNoOpKeepsRevision() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let project = try store.createProject(name: "Staging")
        let revisionBefore = store.catalog.revision
        try store.renameProject(id: project.id, to: "  Staging  ")
        #expect(store.catalog.revision == revisionBefore)
    }

    @Test("selects an existing project and rejects unknown IDs")
    func selects() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let first = store.activeProjectID
        let project = try store.createProject(name: "Staging")
        try store.selectProject(id: first)
        #expect(store.activeProjectID == first)
        #expect(throws: ProjectMutationError.projectNotFound) {
            try store.selectProject(id: UUID())
        }
        #expect(store.activeProjectID == first)
        try store.selectProject(id: project.id)
        #expect(store.activeProjectID == project.id)
    }

    @Test("re-selecting the active project is a no-op that does not bump the revision")
    func selectActiveIsNoOp() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let active = store.activeProjectID
        let revisionBefore = store.catalog.revision
        try store.selectProject(id: active)
        #expect(store.catalog.revision == revisionBefore)
    }

    // MARK: Deletion

    @Test("cannot delete the final project")
    func cannotDeleteFinal() {
        let store = ProjectStore(now: { Self.fixedDate })
        #expect(throws: ProjectMutationError.cannotDeleteFinalProject) {
            try store.deleteProject(id: store.activeProjectID)
        }
        #expect(store.projects.count == 1)
    }

    @Test("deleting the active project activates the following, then the previous")
    func deleteActivatesAdjacent() throws {
        let projects = (0 ..< 3).map { Self.makeProject(name: "P\($0)") }
        let catalog = ProjectCatalog(activeProjectID: projects[1].id, projects: projects)
        let store = ProjectStore(catalog: catalog, now: { Self.fixedDate })

        try store.deleteProject(id: projects[1].id)
        #expect(store.activeProjectID == projects[2].id)

        try store.deleteProject(id: projects[2].id)
        #expect(store.activeProjectID == projects[0].id)
        #expect(store.projects.count == 1)
    }

    // MARK: Reorder

    @Test("reorders projects to the requested order")
    func reorders() throws {
        let projects = (0 ..< 3).map { Self.makeProject(name: "P\($0)") }
        let catalog = ProjectCatalog(activeProjectID: projects[0].id, projects: projects)
        let store = ProjectStore(catalog: catalog, now: { Self.fixedDate })

        try store.reorderProjects([projects[2].id, projects[0].id, projects[1].id])
        #expect(store.projects.map(\.id) == [projects[2].id, projects[0].id, projects[1].id])
    }

    @Test("reordering to the current order is a no-op")
    func reorderNoOpKeepsRevision() throws {
        let projects = (0 ..< 3).map { Self.makeProject(name: "P\($0)") }
        let catalog = ProjectCatalog(activeProjectID: projects[0].id, projects: projects)
        let store = ProjectStore(catalog: catalog, now: { Self.fixedDate })
        let revisionBefore = store.catalog.revision
        try store.reorderProjects(projects.map(\.id))
        #expect(store.catalog.revision == revisionBefore)
    }

    // MARK: Active tab updates

    @Test("updating active tabs re-establishes tab invariants")
    func updatesActiveTabsWithInvariants() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let closable = ProjectTabSnapshot(title: "One", isClosable: true)
        try store.updateActiveProjectTabs([closable], activeTabID: closable.id)

        let tabs = store.activeProject.tabs
        #expect(tabs.contains { !$0.isClosable })
        #expect(tabs.contains { $0.id == store.activeProject.activeTabID })
    }

    @Test("updating active tabs clamps to the structural upper bound, not the creation limit")
    func updatesActiveTabsClampsCapacity() throws {
        // A low product creation limit must not truncate captured tabs: retention is
        // bounded only by the structural upper bound.
        let store = ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 4), now: { Self.fixedDate })
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let extras = (0 ..< 40).map { ProjectTabSnapshot(title: "Tab \($0)", isClosable: true) }
        try store.updateActiveProjectTabs([base] + extras, activeTabID: base.id)
        #expect(store.activeProject.tabs.count == ProjectStructuralLimits.tabCountRange.upperBound)
        #expect(store.activeProject.tabs.count > store.maxTabsPerProject)
    }

    @Test("updating active tabs canonicalizes a merely-untrimmed title")
    func updatesActiveTabsCanonicalizesTitle() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let tab = ProjectTabSnapshot(title: "Payments ", isClosable: true)
        try store.updateActiveProjectTabs([tab], activeTabID: tab.id)
        #expect(store.activeProject.tabs.contains { $0.title == "Payments" })
    }

    @Test("a corrupt tab snapshot is rejected and leaves the tabs unchanged")
    func rejectsCorruptTabSnapshotWithoutMutating() {
        let store = ProjectStore(now: { Self.fixedDate })
        let before = store.activeProject.tabs
        let oversized = String(repeating: "y", count: ProjectStructuralLimits.maxFilterStringGraphemes + 1)
        let corrupt = ProjectTabSnapshot(
            title: "Bad",
            isClosable: true,
            filter: FilterCriteriaSnapshot(searchText: oversized)
        )
        #expect(throws: ProjectMutationError.self) {
            try store.updateActiveProjectTabs([corrupt], activeTabID: corrupt.id)
        }
        #expect(store.activeProject.tabs == before)
    }

    @Test("a noncanonical tab title is rejected and leaves the tabs unchanged")
    func rejectsNoncanonicalTabTitleWithoutMutating() {
        let store = ProjectStore(now: { Self.fixedDate })
        let before = store.activeProject.tabs
        let corrupt = ProjectTabSnapshot(title: "Bad\nTitle", isClosable: true)
        #expect(throws: ProjectMutationError.self) {
            try store.updateActiveProjectTabs([corrupt], activeTabID: corrupt.id)
        }
        #expect(store.activeProject.tabs == before)
    }

    // MARK: Revision exhaustion

    @Test("a mutation at the maximum revision fails without changing the catalog")
    func revisionExhaustionFailsClosed() {
        var catalog = ProjectCatalog.makeDefault(now: Self.fixedDate)
        catalog.revision = UInt64.max
        let store = ProjectStore(catalog: catalog, now: { Self.fixedDate })
        #expect(throws: ProjectMutationError.revisionExhausted) {
            _ = try store.createProject(name: "Staging")
        }
        #expect(store.catalog.revision == UInt64.max)
        #expect(store.projects.count == 1)
    }

    // MARK: Load lifecycle & mutation gates

    @Test("an in-memory store is mutable immediately")
    func inMemoryStoreIsReady() {
        let store = ProjectStore(now: { Self.fixedDate })
        #expect(store.loadState == .ready)
        #expect(store.isMutable)
    }

    @Test("a repository-backed store is not mutable before loading")
    func mutationsRefusedBeforeLoad() {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        #expect(store.loadState == .idle)
        #expect(!store.isMutable)
        #expect(!store.canCreateProject)
        #expect(throws: ProjectMutationError.storeNotReady) {
            _ = try store.createProject(name: "Staging")
        }
        let revisionBefore = store.catalog.revision
        #expect(throws: ProjectMutationError.storeNotReady) {
            try store.selectProject(id: UUID())
        }
        #expect(throws: ProjectMutationError.storeNotReady) {
            try store.reorderProjects([UUID()])
        }
        #expect(store.catalog.revision == revisionBefore)
        #expect(throws: ProjectMutationError.storeNotReady) {
            try store.updateActiveProjectTabs([], activeTabID: UUID())
        }
    }

    @Test("a successful load makes the store mutable and adopts the catalog")
    func loadMakesStoreMutable() async throws {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        #expect(store.loadState == .ready)
        #expect(store.isMutable)
        _ = try store.createProject(name: "Staging")
        #expect(store.projects.count == 2)
    }

    @Test("mutations remain refused after a failed load, and no save is attempted")
    func mutationsRefusedAfterFailedLoad() async {
        let repo = FakeCatalogRepository(loadResult: .failure(FakeError.boom))
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        #expect(store.loadState == .failed(String(describing: FakeError.boom)))
        #expect(!store.isMutable)
        #expect(throws: ProjectMutationError.storeNotReady) {
            _ = try store.createProject(name: "Staging")
        }
        #expect(await repo.saveCount == 0)
    }

    @Test("a loaded catalog above project-count capacity loads and stays mutable for non-creation actions")
    func loadRetainsOverProjectCapacity() async throws {
        let projects = (0 ..< 3).map { Self.makeProject(name: "P\($0)") }
        let over = ProjectCatalog(activeProjectID: projects[0].id, projects: projects)
        let repo = FakeCatalogRepository(loadResult: .success(over))
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 2), repository: repo, now: { Self.fixedDate })

        await store.loadPersistedCatalog()

        #expect(store.loadState == .ready)
        #expect(store.isMutable)
        #expect(store.loadFailureMessage == nil)
        // Existing over-capacity Projects are retained, never truncated.
        #expect(store.projects.count == 3)
        // Creation is blocked while over capacity, but other mutations remain allowed.
        #expect(!store.canCreateProject)
        #expect(throws: ProjectMutationError.capacityReached(limit: 2)) {
            _ = try store.createProject(name: "Blocked")
        }
        try store.renameProject(id: projects[2].id, to: "Renamed")
        #expect(store.projects.contains { $0.name == "Renamed" })
        try store.deleteProject(id: projects[2].id)
        #expect(store.projects.count == 2)
    }

    @Test("a loaded project above per-project tab capacity retains all of its tabs")
    func loadRetainsOverTabCapacity() async {
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let tabs = [base]
            + (0 ..< 4).map { ProjectTabSnapshot(title: "Tab \($0)", isClosable: true) }
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: base.id,
            tabs: tabs
        )
        let over = ProjectCatalog(activeProjectID: project.id, projects: [project])
        let repo = FakeCatalogRepository(loadResult: .success(over))
        let store = ProjectStore(policy: CapacityPolicy(maxWorkspaceTabs: 2), repository: repo, now: { Self.fixedDate })

        await store.loadPersistedCatalog()

        #expect(store.loadState == .ready)
        #expect(store.isMutable)
        #expect(store.activeProject.tabs.count == 5)
    }

    @Test("a structurally invalid loaded catalog is rejected even from an injected repository")
    func loadRejectsStructurallyInvalidCatalog() async {
        // Two Projects sharing one folded name violate a structural invariant and
        // must fail closed regardless of the injected repository.
        let duplicate = [Self.makeProject(name: "Same"), Self.makeProject(name: "same")]
        let invalid = ProjectCatalog(activeProjectID: duplicate[0].id, projects: duplicate)
        let repo = FakeCatalogRepository(loadResult: .success(invalid))
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })

        await store.loadPersistedCatalog()

        #expect(!store.isMutable)
        #expect(store.loadFailureMessage != nil)
        #expect(store.projects.count == 1)
    }

    // MARK: Runtime capacity refresh

    @Test("lowering capacity at runtime keeps existing state and only blocks new creation")
    func capacityDecreaseRetainsState() throws {
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 4), now: { Self.fixedDate })
        _ = try store.createProject(name: "Second")
        _ = try store.createProject(name: "Third")
        #expect(store.projects.count == 3)

        store.refreshCapacity(with: CapacityPolicy(maxProjects: 2))

        #expect(store.maxProjects == 2)
        #expect(store.projects.count == 3)
        #expect(!store.canCreateProject)
        #expect(throws: ProjectMutationError.capacityReached(limit: 2)) {
            _ = try store.createProject(name: "Blocked")
        }
    }

    @Test("raising capacity at runtime re-enables creation without disturbing state")
    func capacityIncreaseReenablesCreation() throws {
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 1), now: { Self.fixedDate })
        #expect(!store.canCreateProject)
        let activeBefore = store.activeProjectID

        store.refreshCapacity(with: CapacityPolicy(maxProjects: 3))

        #expect(store.maxProjects == 3)
        #expect(store.activeProjectID == activeBefore)
        #expect(store.canCreateProject)
        _ = try store.createProject(name: "Second")
        #expect(store.projects.count == 2)
    }

    @Test("a capacity refresh clamps into the structural range and bumps no revision")
    func capacityRefreshClampsAndKeepsRevision() {
        let store = ProjectStore(policy: CapacityPolicy(maxProjects: 2), now: { Self.fixedDate })
        let revisionBefore = store.catalog.revision
        store.refreshCapacity(with: CapacityPolicy(maxWorkspaceTabs: 0, maxProjects: 999))
        #expect(store.maxProjects == 128)
        #expect(store.maxTabsPerProject == 1)
        #expect(store.catalog.revision == revisionBefore)
    }

    // MARK: Reconciliation

    @Test("reconciliation accepts a matching revision, adopts entities, preserves active, and bumps the revision")
    func reconcileAdoptsAndPreservesActive() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let active = store.activeProject
        let revisionBefore = store.catalog.revision
        let added = Self.makeProject(name: "Reconciled")

        let changed = try store.reconcile(projects: [active, added], expectedRevision: revisionBefore)

        #expect(changed)
        #expect(store.projects.map(\.id) == [active.id, added.id])
        #expect(store.activeProjectID == active.id)
        #expect(store.catalog.revision == revisionBefore + 1)
    }

    @Test("reconciliation selects a deterministic active project when the local one is gone")
    func reconcileFallsBackToFirstWhenActiveRemoved() throws {
        let store = ProjectStore(now: { Self.fixedDate })
        let replacement = Self.makeProject(name: "First")
        let second = Self.makeProject(name: "Second")

        try store.reconcile(projects: [replacement, second], expectedRevision: store.catalog.revision)

        #expect(store.activeProjectID == replacement.id)
        #expect(store.projects.map(\.id) == [replacement.id, second.id])
    }

    @Test("reconciliation with identical entities is an accepted no-op under a matching revision")
    func reconcileIdenticalIsNoOp() async throws {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        let revisionBefore = store.catalog.revision

        let changed = try store.reconcile(projects: store.projects, expectedRevision: revisionBefore)

        #expect(!changed)
        #expect(store.catalog.revision == revisionBefore)
        await store.waitForPendingPersistence()
        #expect(await repo.saveCount == 0)
    }

    @Test("reconciliation rejects a stale revision atomically and writes nothing")
    func reconcileRejectsStaleRevisionAtomically() async throws {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        let staleRevision = store.catalog.revision
        // Advance the catalog so the captured revision is now stale.
        _ = try store.createProject(name: "Advancing")
        await store.waitForPendingPersistence()
        let before = store.catalog
        let savesBefore = await repo.saveCount

        #expect(throws: ProjectMutationError.staleRevision(expected: staleRevision, actual: store.catalog.revision)) {
            _ = try store.reconcile(
                projects: [store.activeProject, Self.makeProject(name: "Rejected")],
                expectedRevision: staleRevision
            )
        }
        #expect(store.catalog == before)
        await store.waitForPendingPersistence()
        #expect(await repo.saveCount == savesBefore)
    }

    @Test("reconciliation rejects structurally invalid entities atomically")
    func reconcileRejectsInvalidAtomically() {
        let store = ProjectStore(now: { Self.fixedDate })
        let before = store.catalog
        let clash = [Self.makeProject(name: "Same"), Self.makeProject(name: "same")]

        #expect(throws: ProjectMutationError.self) {
            _ = try store.reconcile(projects: clash, expectedRevision: store.catalog.revision)
        }
        #expect(store.catalog == before)
    }

    @Test("reconciliation rejects an empty entity set without mutating state")
    func reconcileRejectsEmptySet() {
        let store = ProjectStore(now: { Self.fixedDate })
        let before = store.catalog
        #expect(throws: ProjectMutationError.self) {
            _ = try store.reconcile(projects: [], expectedRevision: store.catalog.revision)
        }
        #expect(store.catalog == before)
    }

    @Test("reconciliation persists atomically with the incremented local revision")
    func reconcilePersistsWithLocalRevision() async throws {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        let active = store.activeProject

        try store.reconcile(
            projects: [active, Self.makeProject(name: "Extra")],
            expectedRevision: store.catalog.revision
        )
        await store.waitForPendingPersistence()

        #expect(await repo.saveCount == 1)
        #expect(await repo.lastSaved?.revision == 2)
        #expect(await repo.lastSaved?.projects.count == 2)
    }

    @Test("reconciliation is refused on a not-ready store and writes nothing")
    func reconcileRefusedBeforeLoad() async {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        #expect(throws: ProjectMutationError.storeNotReady) {
            _ = try store.reconcile(
                projects: [Self.makeProject(name: "Nope")],
                expectedRevision: store.catalog.revision
            )
        }
        #expect(await repo.saveCount == 0)
    }

    // MARK: Persistence status

    @Test("a mutation persists the catalog with an incremented revision")
    func mutationPersists() async throws {
        let repo = FakeCatalogRepository()
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        _ = try store.createProject(name: "Staging")
        for _ in 0 ..< 1_000 where store.persistenceStatus != .saved {
            await Task.yield()
        }
        #expect(await repo.lastSaved?.revision == 2)
        #expect(store.persistenceStatus == .saved)
    }

    @Test("a save failure is surfaced as explicit persistence state")
    func persistenceFailureSurfaced() async throws {
        let repo = FakeCatalogRepository(saveError: FakeError.boom)
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        _ = try store.createProject(name: "Staging")
        for _ in 0 ..< 1_000 where store.persistenceStatus == .saving || store.persistenceStatus == .idle {
            await Task.yield()
        }
        #expect(store.persistenceStatus == .failed(String(describing: FakeError.boom)))
    }

    @Test("a load failure keeps the safe default and exposes the reason")
    func loadFailureSurfaced() async {
        let repo = FakeCatalogRepository(loadResult: .failure(FakeError.boom))
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        #expect(store.loadFailureMessage != nil)
        #expect(store.projects.count == 1)
    }

    // MARK: Reset / recovery

    @Test("explicit reset recovers a failed load into a mutable default")
    func resetRecoversFailedLoad() async throws {
        let repo = FakeCatalogRepository(loadResult: .failure(FakeError.boom))
        let store = ProjectStore(repository: repo, now: { Self.fixedDate })
        await store.loadPersistedCatalog()
        #expect(!store.isMutable)

        await store.resetToDefaultCatalog()
        #expect(store.loadState == .ready)
        #expect(store.isMutable)
        #expect(store.loadFailureMessage == nil)
        #expect(await repo.resetCount == 1)

        _ = try store.createProject(name: "Fresh")
        #expect(store.projects.count == 2)
    }

    // MARK: Private

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static func makeProject(name: String) -> Project {
        Project.makeDefault(name: name, createdAt: fixedDate, updatedAt: fixedDate)
    }
}

// MARK: - FakeCatalogRepository

/// Actor-isolated persistence double. It mirrors the real repository's actor
/// isolation so the store's `Sendable` seam is exercised faithfully rather than
/// relaxed to satisfy the compiler.
private actor FakeCatalogRepository: ProjectCatalogPersisting {
    // MARK: Lifecycle

    init(
        loadResult: Result<ProjectCatalog, Error> = .success(
            ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000))
        ),
        saveError: Error? = nil
    ) {
        self.loadResult = loadResult
        self.saveError = saveError
    }

    // MARK: Internal

    private(set) var savedCatalogs: [ProjectCatalog] = []
    private(set) var resetCount = 0

    var saveCount: Int {
        savedCatalogs.count
    }

    var lastSaved: ProjectCatalog? {
        savedCatalogs.last
    }

    func load() async throws -> ProjectCatalog {
        try loadResult.get()
    }

    func save(_ catalog: ProjectCatalog) async throws {
        if let saveError {
            throw saveError
        }
        savedCatalogs.append(catalog)
    }

    func reset() async throws -> ProjectCatalog {
        resetCount += 1
        let fresh = ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000))
        savedCatalogs.append(fresh)
        return fresh
    }

    // MARK: Private

    private let loadResult: Result<ProjectCatalog, Error>
    private let saveError: Error?
}

// MARK: - FakeError

private enum FakeError: Error, Equatable {
    case boom
}

// MARK: - CapacityPolicy

private struct CapacityPolicy: AppPolicy {
    var maxWorkspaceTabs = 8
    var maxProjects = 32
    var maxDomainFavorites = 5
    var maxActiveRulesPerTool = 10
    var maxEnabledScripts = 10
    var maxLiveHistoryEntries = 1_000
}
