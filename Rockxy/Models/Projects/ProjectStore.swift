import Foundation
import os

// MARK: - ProjectMutationError

/// User-actionable rejection reasons for a Project mutation.
enum ProjectMutationError: Error, Equatable {
    case nameInvalid(ProjectNameNormalizationError)
    case duplicateName
    case capacityReached(limit: Int)
    case tabCapacityReached(limit: Int)
    case projectNotFound
    case cannotDeleteFinalProject
    /// A capture clear is crossing an actor boundary. Active-Project transitions
    /// are serialized until it completes so observable state cannot change owner.
    case captureClearInProgress
    /// The store has no confirmed catalog to mutate yet (never loaded, still
    /// loading, or a load failed). Mutations are refused so a failed load cannot
    /// overwrite the invalid on-disk catalog. See ``ProjectLoadState``.
    case storeNotReady
    /// The monotonic revision counter is exhausted. The catalog is left unchanged
    /// rather than wrapping and silently reordering behind a persisted revision.
    case revisionExhausted
    /// A supplied tab snapshot set was corrupt or noncanonical; the active
    /// Project's tabs are left unchanged.
    case invalidTabSnapshot(ProjectCatalogValidationError)
    /// A reconciled set of Project entities violated a structural invariant; the
    /// catalog is left unchanged rather than persisting an invalid state.
    case reconciledProjectsInvalid(ProjectCatalogValidationError)
    /// A reconciliation was attempted against a stale local revision (the catalog
    /// advanced since the candidate was built, e.g. because a live tab edit was
    /// flushed just before the apply). The catalog is left unchanged so the caller
    /// can rebuild against the current state and retry. This is a purely in-process
    /// compare-and-swap guard, never external sync metadata.
    case staleRevision(expected: UInt64, actual: UInt64)
}

// MARK: - ProjectPersistenceStatus

/// Explicit, observable persistence state for the current catalog.
enum ProjectPersistenceStatus: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

// MARK: - ProjectLoadState

/// Explicit load lifecycle for a repository-backed store. Mutations are only
/// permitted in ``ready``; every other state fails closed so an unconfirmed or
/// failed load can never overwrite the on-disk catalog. An in-memory store (no
/// repository) is ``ready`` from construction.
enum ProjectLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

// MARK: - ProjectStore

/// In-memory owner of the Project catalog. Enforces names, capacity, and every
/// structural invariant at each mutation, models an explicit load lifecycle,
/// exposes persistence/load failure state, and delegates durable storage to an
/// injectable repository.
///
/// A `nil` repository keeps the store fully in-memory and immediately mutable, so
/// test hosts perform no Application Support I/O unless they inject a repository.
@MainActor @Observable
final class ProjectStore {
    // MARK: Lifecycle

    init(
        policy: any AppPolicy = DefaultAppPolicy(),
        repository: ProjectCatalogPersisting? = nil,
        catalog: ProjectCatalog? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.now = now
        maxProjects = Self.clamp(policy.maxProjects, into: ProjectStructuralLimits.projectCountRange)
        maxTabsPerProject = Self.clamp(policy.maxWorkspaceTabs, into: ProjectStructuralLimits.tabCountRange)
        self.catalog = catalog ?? ProjectCatalog.makeDefault(now: now())
        // With a repository the in-memory default is provisional until a load
        // confirms (or an explicit reset replaces) it; without one it is durable.
        loadState = repository == nil ? .ready : .idle
    }

    // MARK: Internal

    /// Effective Project *creation* capacity: ``AppPolicy/maxProjects`` clamped
    /// into the structural range. This gates new/imported Projects only; it never
    /// truncates or rejects existing state and can be refreshed at runtime via
    /// ``refreshCapacity(with:)``.
    private(set) var maxProjects: Int
    /// Effective per-Project tab *creation* capacity: ``AppPolicy/maxWorkspaceTabs``
    /// clamped. Gates imported tab counts only; hydrated tabs are retained up to
    /// the structural upper bound regardless of this value.
    private(set) var maxTabsPerProject: Int

    private(set) var catalog: ProjectCatalog
    private(set) var loadState: ProjectLoadState
    private(set) var persistenceStatus: ProjectPersistenceStatus = .idle
    private(set) var loadFailureMessage: String?

    var projects: [Project] {
        catalog.projects
    }

    var activeProjectID: UUID {
        catalog.activeProjectID
    }

    var activeProject: Project {
        catalog.activeProject ?? catalog.projects[0]
    }

    /// Whether ordinary mutations are currently permitted.
    var isMutable: Bool {
        loadState == .ready
    }

    var canCreateProject: Bool {
        isMutable && catalog.projects.count < maxProjects
    }

    /// Loads the persisted catalog, replacing the provisional in-memory default on
    /// success. The loaded catalog is defensively re-validated for structural
    /// integrity even when a repository was injected, but a catalog that merely
    /// exceeds this build's product *creation* capacity is accepted and remains
    /// mutable for non-creation actions — capacity gates new work, not retention.
    /// On a structural (or I/O) failure the safe default is retained, the reason is
    /// exposed via ``loadFailureMessage``, ``loadState`` becomes
    /// ``ProjectLoadState/failed(_:)``, and no mutation or save touches the file.
    func loadPersistedCatalog() async {
        guard let repository else {
            return
        }
        guard loadState != .loading else {
            return
        }
        loadState = .loading
        do {
            let loaded = try await repository.load()
            try loaded.validate()
            catalog = loaded
            loadFailureMessage = nil
            loadState = .ready
        } catch {
            loadFailureMessage = String(describing: error)
            loadState = .failed(String(describing: error))
        }
    }

    /// Re-clamps the effective Project/tab *creation* capacity from a refreshed
    /// policy without touching retained state. Existing Projects and tabs are never
    /// deleted, truncated, or hidden by a capacity change; only future create,
    /// import, and duplicate actions observe the new bound. No revision is bumped
    /// and no save is triggered, because durable catalog contents are unchanged.
    func refreshCapacity(with policy: any AppPolicy) {
        maxProjects = Self.clamp(policy.maxProjects, into: ProjectStructuralLimits.projectCountRange)
        maxTabsPerProject = Self.clamp(policy.maxWorkspaceTabs, into: ProjectStructuralLimits.tabCountRange)
    }

    /// Retries a previously failed (or not-yet-attempted) load. Safe to call from
    /// a recovery affordance after ``loadState`` reports failure.
    func retryLoad() async {
        await loadPersistedCatalog()
    }

    /// Explicit, caller-initiated reset/recovery. Replaces the on-disk catalog with
    /// a fresh default (preserving the prior file as a bounded recovery backup where
    /// safely possible) and returns the store to a mutable state. Intended to sit
    /// behind a deliberate confirmation UI, never on an ordinary code path.
    func resetToDefaultCatalog() async {
        guard let repository else {
            catalog = ProjectCatalog.makeDefault(now: now())
            loadFailureMessage = nil
            loadState = .ready
            return
        }
        do {
            catalog = try await repository.reset()
            loadFailureMessage = nil
            loadState = .ready
            persistenceStatus = .saved
        } catch {
            loadFailureMessage = String(describing: error)
            loadState = .failed(String(describing: error))
        }
    }

    @discardableResult
    func createProject(name: String) throws -> Project {
        try ensureMutable()
        guard catalog.projects.count < maxProjects else {
            throw ProjectMutationError.capacityReached(limit: maxProjects)
        }
        let normalized = try normalized(name)
        guard !nameCollides(with: normalized, excluding: nil) else {
            throw ProjectMutationError.duplicateName
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        let timestamp = now()
        let project = Project.makeDefault(name: normalized, createdAt: timestamp, updatedAt: timestamp)
        catalog.projects.append(project)
        catalog.activeProjectID = project.id
        catalog.revision = revision
        persist()
        return project
    }

    /// Activates an existing Project. Throws rather than silently no-op'ing so a
    /// store-not-ready, unknown-ID, or revision-exhausted selection can never look
    /// successful to the coordinator/UI. Re-selecting the active Project is a
    /// deliberate no-op that neither throws nor bumps the revision.
    func selectProject(id: UUID) throws {
        try ensureMutable()
        guard id != catalog.activeProjectID else {
            return
        }
        guard catalog.projects.contains(where: { $0.id == id }) else {
            throw ProjectMutationError.projectNotFound
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        catalog.activeProjectID = id
        catalog.revision = revision
        persist()
    }

    func renameProject(id: UUID, to newName: String) throws {
        try ensureMutable()
        guard let index = catalog.projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectMutationError.projectNotFound
        }
        let normalized = try normalized(newName)
        guard !nameCollides(with: normalized, excluding: id) else {
            throw ProjectMutationError.duplicateName
        }
        guard catalog.projects[index].name != normalized else {
            return
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        catalog.projects[index].name = normalized
        catalog.projects[index].updatedAt = now()
        catalog.revision = revision
        persist()
    }

    /// Imports a validated, config-only portable document as a new Project. IDs
    /// are always regenerated by the DTO, name conflicts are resolved without
    /// overwriting, and the catalog changes in one revision-bumped commit.
    @discardableResult
    func importProject(_ portable: PortableProject) throws -> Project {
        try ensureMutable()
        guard catalog.projects.count < maxProjects else {
            throw ProjectMutationError.capacityReached(limit: maxProjects)
        }
        try portable.validate()
        guard portable.tabs.count <= maxTabsPerProject else {
            throw ProjectMutationError.tabCapacityReached(limit: maxTabsPerProject)
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }

        let timestamp = now()
        let materialized: Project
        do {
            materialized = try portable.makeProject(now: timestamp, maxTabs: maxTabsPerProject)
        } catch PortableProjectError.tabCapacityExceededAfterDefaultInsertion {
            throw ProjectMutationError.tabCapacityReached(limit: maxTabsPerProject)
        }
        var project = materialized
        project.name = uniqueImportedName(for: project.name)
        do {
            try project.validate()
            var candidate = catalog
            candidate.projects.append(project)
            candidate.activeProjectID = project.id
            candidate.revision = revision
            try candidate.validate()
            catalog = candidate
        } catch let error as ProjectCatalogValidationError {
            throw ProjectMutationError.invalidTabSnapshot(error)
        }
        persist()
        return project
    }

    func deleteProject(id: UUID) throws {
        try ensureMutable()
        guard catalog.projects.count > 1 else {
            throw ProjectMutationError.cannotDeleteFinalProject
        }
        guard let index = catalog.projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectMutationError.projectNotFound
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        if id == catalog.activeProjectID {
            // Deterministically activate the following Project, else the previous.
            let adjacentIndex = index + 1 < catalog.projects.count ? index + 1 : index - 1
            catalog.activeProjectID = catalog.projects[adjacentIndex].id
        }
        catalog.projects.remove(at: index)
        catalog.revision = revision
        persist()
    }

    /// Reorders Projects to `orderedIDs`, tolerating missing/extra IDs (unlisted
    /// Projects keep their relative order at the tail). Throws for a not-ready store
    /// or an exhausted revision; an empty list or a request that reproduces the
    /// current order is a no-op that neither throws nor bumps the revision.
    func reorderProjects(_ orderedIDs: [UUID]) throws {
        try ensureMutable()
        guard !orderedIDs.isEmpty else {
            return
        }
        var remaining = catalog.projects
        var reordered: [Project] = []
        reordered.reserveCapacity(remaining.count)
        for id in orderedIDs {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else {
                continue
            }
            reordered.append(remaining.remove(at: index))
        }
        reordered.append(contentsOf: remaining)
        guard reordered.count == catalog.projects.count,
              reordered.map(\.id) != catalog.projects.map(\.id) else
        {
            return
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        catalog.projects = reordered
        catalog.revision = revision
        persist()
    }

    /// Replaces the active Project's tab configuration with a captured snapshot.
    ///
    /// Titles are canonicalized deliberately and the result is validated *before*
    /// any mutation: a corrupt or noncanonical snapshot (a title that cannot be
    /// canonicalized, or an oversized filter) is rejected with the active Project's
    /// tabs left untouched. Capacity is defensively clamped to the structural upper
    /// bound — never the lower product creation limit — so hydrated tabs retained
    /// above that limit persist intact; a snapshot reproducing the current tabs is
    /// a no-op.
    func updateActiveProjectTabs(_ snapshots: [ProjectTabSnapshot], activeTabID: UUID) throws {
        try ensureMutable()
        guard let index = catalog.projects.firstIndex(where: { $0.id == catalog.activeProjectID }) else {
            throw ProjectMutationError.projectNotFound
        }

        var canonicalSnapshots: [ProjectTabSnapshot] = []
        canonicalSnapshots.reserveCapacity(snapshots.count)
        for var snapshot in snapshots {
            do {
                snapshot.title = try ProjectNormalization.normalizedDisplayName(snapshot.title)
            } catch let error as ProjectNameNormalizationError {
                throw ProjectMutationError.invalidTabSnapshot(.tabSnapshotInvalid(.titleInvalid(error)))
            }
            canonicalSnapshots.append(snapshot)
        }

        // Never trust a caller's capacity, but clamp to the structural upper bound
        // rather than the product creation limit so hydrated tabs above the current
        // creation capacity are retained rather than silently truncated on autosave.
        let capacity = ProjectStructuralLimits.tabCountRange.upperBound
        let (normalizedTabs, resolvedActiveTabID) = Project.normalizedTabs(
            canonicalSnapshots,
            activeTabID: activeTabID,
            maxTabs: capacity
        )

        let current = catalog.projects[index]
        var candidate = current
        candidate.tabs = normalizedTabs
        candidate.activeTabID = resolvedActiveTabID
        do {
            try candidate.validate()
        } catch let error as ProjectCatalogValidationError {
            throw ProjectMutationError.invalidTabSnapshot(error)
        }

        // No-op when the tab set and active tab are unchanged (ignoring timestamps).
        guard normalizedTabs != current.tabs || resolvedActiveTabID != current.activeTabID else {
            return
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        candidate.updatedAt = now()
        catalog.projects[index] = candidate
        catalog.revision = revision
        persist()
    }

    /// Applies an externally reconciled set of Project entities as the new catalog
    /// contents, guarded by an in-process compare-and-swap on the local revision.
    /// This is the single local seam a future reconciliation adapter uses; it accepts
    /// reconciled *entities only* and never an external revision token — the catalog's
    /// revision stays a local monotonic persistence/CAS guard.
    ///
    /// `expectedRevision` is the caller's last-observed local revision. If the catalog
    /// has advanced past it (for example because a live tab edit was flushed just
    /// before this call) the reconciliation is rejected atomically with
    /// ``ProjectMutationError/staleRevision(expected:actual:)`` and the catalog is left
    /// untouched, so a newer local edit is never overwritten and the caller can
    /// rebuild and retry.
    ///
    /// The current local active Project is preserved when it still exists in the
    /// reconciled set; otherwise the first reconciled Project (a deterministic
    /// choice from the supplied order) becomes active. Structural invariants are
    /// validated *before* any mutation, so invalid input throws
    /// ``ProjectMutationError/reconciledProjectsInvalid(_:)`` with the catalog
    /// untouched. A reconciled set identical to the current contents is an accepted
    /// no-op that returns `false` without bumping the local revision or persisting;
    /// an applied change returns `true`.
    @discardableResult
    func reconcile(projects: [Project], expectedRevision: UInt64) throws -> Bool {
        try ensureMutable()
        guard expectedRevision == catalog.revision else {
            throw ProjectMutationError.staleRevision(expected: expectedRevision, actual: catalog.revision)
        }

        let preservesActive = projects.contains { $0.id == catalog.activeProjectID }
        let resolvedActiveID = preservesActive
            ? catalog.activeProjectID
            : (projects.first?.id ?? catalog.activeProjectID)

        var candidate = catalog
        candidate.projects = projects
        candidate.activeProjectID = resolvedActiveID

        guard candidate.projects != catalog.projects || candidate.activeProjectID != catalog.activeProjectID else {
            return false
        }

        do {
            try candidate.validate()
        } catch let error as ProjectCatalogValidationError {
            throw ProjectMutationError.reconciledProjectsInvalid(error)
        }
        guard let revision = nextRevision() else {
            throw ProjectMutationError.revisionExhausted
        }
        candidate.revision = revision
        catalog = candidate
        persist()
        return true
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ProjectStore"
    )

    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    private let repository: ProjectCatalogPersisting?
    private let now: () -> Date

    private static func clamp(_ value: Int, into range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func ensureMutable() throws {
        guard isMutable else {
            throw ProjectMutationError.storeNotReady
        }
    }

    /// The revision the next mutation would persist, or `nil` when the monotonic
    /// counter is exhausted (so the caller can fail without wrapping).
    private func nextRevision() -> UInt64? {
        catalog.revision == UInt64.max ? nil : catalog.revision + 1
    }

    private func normalized(_ raw: String) throws -> String {
        do {
            return try ProjectNormalization.normalizedDisplayName(raw)
        } catch let error as ProjectNameNormalizationError {
            throw ProjectMutationError.nameInvalid(error)
        }
    }

    private func nameCollides(with normalizedName: String, excluding id: UUID?) -> Bool {
        let key = ProjectNormalization.foldedKey(for: normalizedName)
        return catalog.projects.contains {
            $0.id != id && ProjectNormalization.foldedKey(for: $0.name) == key
        }
    }

    private func uniqueImportedName(for normalizedName: String) -> String {
        guard nameCollides(with: normalizedName, excluding: nil) else {
            return normalizedName
        }
        var ordinal = 1
        while true {
            let suffix = ordinal == 1 ? " (Imported)" : " (Imported \(ordinal))"
            let maxBaseCount = max(1, ProjectStructuralLimits.nameGraphemeRange.upperBound - suffix.count)
            let candidate = normalizedName.boundedToGraphemes(maxBaseCount) + suffix
            if !nameCollides(with: candidate, excluding: nil) {
                return candidate
            }
            ordinal += 1
        }
    }

    private func persist() {
        guard let repository else {
            return
        }
        let snapshot = catalog
        persistenceStatus = .saving
        persistenceTask = Task { @MainActor in
            do {
                try await repository.save(snapshot)
                if catalog.revision == snapshot.revision {
                    persistenceStatus = .saved
                }
            } catch {
                guard catalog.revision == snapshot.revision else {
                    // A later in-memory snapshot superseded this write and owns the
                    // observable persistence status.
                    return
                }
                persistenceStatus = .failed(String(describing: error))
                Self.logger.error("Project catalog persistence failed: \(String(describing: error))")
            }
        }
    }
}
