import Foundation

// MARK: - ProjectCatalogValidationError

/// Structural rejection reasons for a decoded or mutated catalog. These are
/// integrity failures (fail closed), not user-facing capacity messaging.
enum ProjectCatalogValidationError: Error, Equatable {
    case projectCountOutOfRange(count: Int)
    case duplicateProjectID(UUID)
    case duplicateProjectName(foldedKey: String)
    case projectNameInvalid(ProjectNameNormalizationError)
    case unresolvedActiveProjectID
    case tabCountOutOfRange(projectID: UUID, count: Int)
    case duplicateTabID(UUID)
    case missingNonClosableTab(projectID: UUID)
    case unresolvedActiveTabID(projectID: UUID)
    case tabSnapshotInvalid(ProjectSnapshotValidationError)
}

// MARK: - Project

/// A durable, local Project: a stable identity plus the serializable configuration
/// of its traffic tabs. Runtime capture is logically routed by this identity but is
/// not embedded in the bounded catalog; rules, secrets, favorites, and focus-set
/// definitions remain app-level libraries or references.
struct Project: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        updatedAt: Date,
        activeTabID: UUID,
        tabs: [ProjectTabSnapshot]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeTabID = activeTabID
        self.tabs = tabs
    }

    // MARK: Internal

    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var activeTabID: UUID
    var tabs: [ProjectTabSnapshot]

    /// Builds a valid Project with a single guaranteed non-closable default tab.
    static func makeDefault(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        updatedAt: Date
    )
        -> Project
    {
        let tab = ProjectTabSnapshot.makeDefaultAllTraffic()
        return Project(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            activeTabID: tab.id,
            tabs: [tab]
        )
    }

    /// Guarantees the tab invariants for an arbitrary snapshot list, returning the
    /// repaired tabs and a valid active ID.
    static func normalizedTabs(
        _ snapshots: [ProjectTabSnapshot],
        activeTabID desiredActiveTabID: UUID,
        maxTabs: Int
    )
        -> (tabs: [ProjectTabSnapshot], activeTabID: UUID)
    {
        let capacity = max(maxTabs, ProjectStructuralLimits.tabCountRange.lowerBound)
        var tabs = snapshots

        // Drop duplicate IDs, preserving first occurrence.
        var seen = Set<UUID>()
        tabs = tabs.filter { seen.insert($0.id).inserted }

        if tabs.isEmpty {
            tabs = [ProjectTabSnapshot.makeDefaultAllTraffic()]
        } else if !tabs.contains(where: { !$0.isClosable }) {
            tabs.insert(ProjectTabSnapshot.makeDefaultAllTraffic(), at: 0)
        }

        if tabs.count > capacity {
            let defaultIndex = tabs.firstIndex { !$0.isClosable } ?? 0
            let keeper = tabs.remove(at: defaultIndex)
            tabs = [keeper] + tabs.prefix(capacity - 1)
        }

        let activeTabID = tabs.contains { $0.id == desiredActiveTabID }
            ? desiredActiveTabID
            : tabs[0].id
        return (tabs, activeTabID)
    }

    func validate() throws {
        do {
            try ProjectNormalization.requireCanonical(name)
        } catch let error as ProjectNameNormalizationError {
            throw ProjectCatalogValidationError.projectNameInvalid(error)
        }

        guard ProjectStructuralLimits.tabCountRange.contains(tabs.count) else {
            throw ProjectCatalogValidationError.tabCountOutOfRange(projectID: id, count: tabs.count)
        }

        var seen = Set<UUID>()
        for tab in tabs {
            guard seen.insert(tab.id).inserted else {
                throw ProjectCatalogValidationError.duplicateTabID(tab.id)
            }
            do {
                try tab.validate()
            } catch let error as ProjectSnapshotValidationError {
                throw ProjectCatalogValidationError.tabSnapshotInvalid(error)
            }
        }

        guard tabs.contains(where: { !$0.isClosable }) else {
            throw ProjectCatalogValidationError.missingNonClosableTab(projectID: id)
        }
        guard tabs.contains(where: { $0.id == activeTabID }) else {
            throw ProjectCatalogValidationError.unresolvedActiveTabID(projectID: id)
        }
    }
}

// MARK: - ProjectCatalog

/// The versioned root persisted document. Owns 1...N Projects, the active Project
/// reference, a schema version, and a monotonic revision that lets the repository
/// reject stale out-of-order writes.
struct ProjectCatalog: Codable, Equatable {
    // MARK: Lifecycle

    init(
        schemaVersion: Int = ProjectCatalog.currentSchemaVersion,
        revision: UInt64 = 1,
        activeProjectID: UUID,
        projects: [Project]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.activeProjectID = activeProjectID
        self.projects = projects
    }

    // MARK: Internal

    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var revision: UInt64
    var activeProjectID: UUID
    var projects: [Project]

    var activeProject: Project? {
        projects.first { $0.id == activeProjectID }
    }

    /// A valid one-Project catalog used for a missing file or a fresh install.
    static func makeDefault(
        name: String = ProjectStructuralLimits.defaultProjectName,
        now: Date
    )
        -> ProjectCatalog
    {
        let project = Project.makeDefault(name: name, createdAt: now, updatedAt: now)
        return ProjectCatalog(
            schemaVersion: currentSchemaVersion,
            revision: 1,
            activeProjectID: project.id,
            projects: [project]
        )
    }

    /// Validates every structural invariant. Does not check the schema version:
    /// that is the repository's decode-time concern.
    func validate() throws {
        guard ProjectStructuralLimits.projectCountRange.contains(projects.count) else {
            throw ProjectCatalogValidationError.projectCountOutOfRange(count: projects.count)
        }

        var seenIDs = Set<UUID>()
        var seenNameKeys = Set<String>()
        for project in projects {
            guard seenIDs.insert(project.id).inserted else {
                throw ProjectCatalogValidationError.duplicateProjectID(project.id)
            }
            try project.validate()
            let key = ProjectNormalization.foldedKey(for: project.name)
            guard seenNameKeys.insert(key).inserted else {
                throw ProjectCatalogValidationError.duplicateProjectName(foldedKey: key)
            }
        }

        guard projects.contains(where: { $0.id == activeProjectID }) else {
            throw ProjectCatalogValidationError.unresolvedActiveProjectID
        }
    }
}
