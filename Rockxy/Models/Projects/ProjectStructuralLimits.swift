import Foundation

// MARK: - ProjectStructuralLimits

/// Structural safety bounds for the persisted Project catalog.
///
/// These are storage-integrity limits, not product entitlement logic: they cap
/// allocation and reject hostile or corrupt input regardless of edition. Product
/// capacity (how many Projects a build offers) lives in ``AppPolicy/maxProjects``
/// and is clamped into ``projectCountRange`` before use.
enum ProjectStructuralLimits {
    /// Public default number of Projects offered by ``DefaultAppPolicy``.
    static let defaultProjectCapacity = 3

    /// Hard structural range for the number of Projects in a catalog.
    static let projectCountRange = 1 ... 128

    /// Hard structural range for the number of traffic tabs in a Project.
    /// The effective per-Project tab capacity is ``AppPolicy/maxWorkspaceTabs``
    /// clamped into this range.
    static let tabCountRange = 1 ... 32

    /// Allowed grapheme-cluster count for a normalized Project name or tab title.
    static let nameGraphemeRange = 1 ... 80

    /// Maximum grapheme length of any single persisted filter string.
    static let maxFilterStringGraphemes = 512

    /// Maximum element count of any persisted filter collection.
    static let maxFilterCollectionCount = 64

    /// Maximum number of persisted advanced filter rows per tab.
    static let maxAdvancedFilterRows = 64

    /// Maximum number of persisted muted-traffic-source references per tab.
    static let maxMutedTrafficSources = 128

    /// Default Project name used when creating a fresh catalog.
    static let defaultProjectName = "My Project"

    /// Title of the guaranteed non-closable default tab.
    static let defaultTabTitle = "All Traffic"
}
