import Foundation

// Portable, config-only Project transfer DTO for the `.rockxyproject` format.
//
// This is a deliberately *external* contract, distinct from the internal on-disk
// ``ProjectCatalog`` document: it carries only a Project name plus explicitly
// allowlisted traffic-tab filter/layout intent. It is default-deny — it has no
// field for captured transactions, bodies, headers, cookies, logs, credential
// stores, local file paths, scripts, project/tab UUIDs, or machine-local focus-set
// IDs. User-authored filter text is intentionally portable and may itself be
// sensitive, so the export UI warns users to review it before sharing. Importing
// regenerates fresh identifiers and drops machine-local focus references.

// MARK: - PortableProjectError

/// Rejection reasons for a decoded portable Project. All fail closed.
enum PortableProjectError: Error, Equatable {
    case unsupportedFormatVersion(found: Int)
    case nameInvalid(ProjectNameNormalizationError)
    case tabCountOutOfRange(count: Int)
    case activeTabIndexOutOfRange(index: Int)
    case tabCapacityExceededAfterDefaultInsertion(required: Int, limit: Int)
    case tabInvalid(ProjectSnapshotValidationError)
}

// MARK: - PortableFilterRule

/// Portable form of a single advanced filter row. Unlike ``FilterRuleSnapshot``
/// it deliberately carries no `id`: portable files never encode UUIDs, and a
/// fresh identifier is minted when the row is materialized on import.
struct PortableFilterRule: Codable, Equatable {
    // MARK: Lifecycle

    init(
        isEnabled: Bool = true,
        connectorRawValue: String = FilterLogicConnector.and.rawValue,
        fieldRawValue: String = FilterField.url.rawValue,
        operatorRawValue: String = FilterOperator.contains.rawValue,
        value: String = ""
    ) {
        self.isEnabled = isEnabled
        self.connectorRawValue = connectorRawValue
        self.fieldRawValue = fieldRawValue
        self.operatorRawValue = operatorRawValue
        self.value = value
    }

    init(_ snapshot: FilterRuleSnapshot) {
        isEnabled = snapshot.isEnabled
        connectorRawValue = snapshot.connectorRawValue
        fieldRawValue = snapshot.fieldRawValue
        operatorRawValue = snapshot.operatorRawValue
        value = snapshot.value.boundedToGraphemes(ProjectStructuralLimits.maxFilterStringGraphemes)
    }

    // MARK: Internal

    var isEnabled: Bool
    var connectorRawValue: String
    var fieldRawValue: String
    var operatorRawValue: String
    var value: String

    /// Materializes a durable snapshot row with a freshly minted identifier.
    func makeSnapshot() -> FilterRuleSnapshot {
        FilterRuleSnapshot(
            id: UUID(),
            isEnabled: isEnabled,
            connectorRawValue: connectorRawValue,
            fieldRawValue: fieldRawValue,
            operatorRawValue: operatorRawValue,
            value: value
        )
    }

    func validate() throws {
        guard value.count <= ProjectStructuralLimits.maxFilterStringGraphemes else {
            throw ProjectSnapshotValidationError.stringTooLong(field: "portableFilterRule.value")
        }
    }
}

// MARK: - PortableProjectTab

/// Portable, allowlisted view intent of a single traffic tab.
///
/// Every field here is an explicit copy from ``ProjectTabSnapshot``. The tab `id`
/// and `activeFocusSetID` are intentionally omitted so they cannot leave the
/// machine; importing mints a fresh tab identifier and leaves the focus reference
/// nil until the user re-selects one locally.
struct PortableProjectTab: Codable, Equatable {
    // MARK: Lifecycle

    init(
        title: String,
        isClosable: Bool,
        filter: FilterCriteriaSnapshot = .empty,
        advancedFilterRows: [PortableFilterRule] = [],
        isFilterBarVisible: Bool = false,
        mainTabRawValue: String = MainTab.traffic.rawValue,
        inspectorLayoutRawValue: String = InspectorLayoutCoding.hidden,
        isContextDockVisible: Bool = false,
        contextDockTabRawValue: String = ContextDockTabCoding.details,
        focusNavigatorModeRawValue: String = FocusNavigatorMode.browse.rawValue,
        activeTrafficSignalRawValue: String? = nil,
        mutedTrafficSources: [MutedTrafficSourceSnapshot] = []
    ) {
        self.title = title
        self.isClosable = isClosable
        self.filter = filter
        self.advancedFilterRows = advancedFilterRows
        self.isFilterBarVisible = isFilterBarVisible
        self.mainTabRawValue = mainTabRawValue
        self.inspectorLayoutRawValue = inspectorLayoutRawValue
        self.isContextDockVisible = isContextDockVisible
        self.contextDockTabRawValue = contextDockTabRawValue
        self.focusNavigatorModeRawValue = focusNavigatorModeRawValue
        self.activeTrafficSignalRawValue = activeTrafficSignalRawValue
        self.mutedTrafficSources = mutedTrafficSources
    }

    /// Copies the portable, allowlisted subset of a durable tab snapshot, dropping
    /// its identifier and machine-local focus-set reference.
    init(_ snapshot: ProjectTabSnapshot) {
        title = snapshot.title
        isClosable = snapshot.isClosable
        filter = snapshot.filter
        advancedFilterRows = snapshot.advancedFilterRows.map { PortableFilterRule($0) }
        isFilterBarVisible = snapshot.isFilterBarVisible
        mainTabRawValue = snapshot.mainTabRawValue
        inspectorLayoutRawValue = snapshot.inspectorLayoutRawValue
        isContextDockVisible = snapshot.isContextDockVisible
        contextDockTabRawValue = snapshot.contextDockTabRawValue
        focusNavigatorModeRawValue = snapshot.focusNavigatorModeRawValue
        activeTrafficSignalRawValue = snapshot.activeTrafficSignalRawValue
        mutedTrafficSources = snapshot.mutedTrafficSources
    }

    // MARK: Internal

    var title: String
    var isClosable: Bool
    var filter: FilterCriteriaSnapshot
    var advancedFilterRows: [PortableFilterRule]
    var isFilterBarVisible: Bool
    var mainTabRawValue: String
    var inspectorLayoutRawValue: String
    var isContextDockVisible: Bool
    var contextDockTabRawValue: String
    var focusNavigatorModeRawValue: String
    var activeTrafficSignalRawValue: String?
    var mutedTrafficSources: [MutedTrafficSourceSnapshot]

    /// Materializes a durable tab snapshot with a fresh identifier, a canonical
    /// title, freshly identified filter rows, and no focus-set reference.
    func makeTabSnapshot() -> ProjectTabSnapshot {
        ProjectTabSnapshot(
            id: UUID(),
            title: (try? ProjectNormalization.normalizedDisplayName(title)) ?? title,
            isClosable: isClosable,
            filter: filter,
            advancedFilterRows: advancedFilterRows.map { $0.makeSnapshot() },
            isFilterBarVisible: isFilterBarVisible,
            mainTabRawValue: mainTabRawValue,
            inspectorLayoutRawValue: inspectorLayoutRawValue,
            isContextDockVisible: isContextDockVisible,
            contextDockTabRawValue: contextDockTabRawValue,
            focusNavigatorModeRawValue: focusNavigatorModeRawValue,
            activeTrafficSignalRawValue: activeTrafficSignalRawValue,
            activeFocusSetID: nil,
            mutedTrafficSources: mutedTrafficSources
        )
    }

    /// Validates decoded bounds. The title need only be *normalizable* (imports may
    /// arrive in a non-canonical Unicode form); ``makeTabSnapshot()`` canonicalizes
    /// it. Filter strings and collections are bounded exactly as the durable form.
    func validate() throws {
        do {
            _ = try ProjectNormalization.normalizedDisplayName(title)
        } catch let error as ProjectNameNormalizationError {
            throw ProjectSnapshotValidationError.titleInvalid(error)
        }
        guard advancedFilterRows.count <= ProjectStructuralLimits.maxAdvancedFilterRows else {
            throw ProjectSnapshotValidationError.collectionTooLarge(field: "portableTab.advancedFilterRows")
        }
        guard mutedTrafficSources.count <= ProjectStructuralLimits.maxMutedTrafficSources else {
            throw ProjectSnapshotValidationError.collectionTooLarge(field: "portableTab.mutedTrafficSources")
        }
        try filter.validate()
        for row in advancedFilterRows {
            try row.validate()
        }
        for source in mutedTrafficSources {
            try source.validate()
        }
    }
}

// MARK: - PortableProject

/// Versioned, config-only portable Project document (`.rockxyproject`).
///
/// `formatVersion` is the *external* transfer contract version and is deliberately
/// independent of ``ProjectCatalog/currentSchemaVersion`` (the internal on-disk
/// document). The active tab is referenced by ``activeTabIndex`` rather than a
/// persisted UUID so no identifier crosses the machine boundary.
struct PortableProject: Codable, Equatable {
    // MARK: Lifecycle

    init(
        formatVersion: Int = PortableProject.currentFormatVersion,
        name: String,
        activeTabIndex: Int,
        tabs: [PortableProjectTab]
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.activeTabIndex = activeTabIndex
        self.tabs = tabs
    }

    /// Captures the portable, allowlisted subset of a durable ``Project``. Traffic,
    /// identifiers, and focus-set references are never copied.
    init(exporting project: Project) {
        formatVersion = Self.currentFormatVersion
        name = project.name
        activeTabIndex = project.tabs.firstIndex { $0.id == project.activeTabID } ?? 0
        tabs = project.tabs.map { PortableProjectTab($0) }
    }

    // MARK: Internal

    /// External transfer-format version. Independent of the internal catalog schema.
    static let currentFormatVersion = 1

    var formatVersion: Int
    var name: String
    var activeTabIndex: Int
    var tabs: [PortableProjectTab]

    /// Materializes a valid, live ``Project`` with freshly minted identifiers.
    ///
    /// The name/titles are canonicalized, every tab receives a new UUID, filter
    /// rows are re-identified, focus-set references are dropped, and the tab
    /// invariants (a guaranteed non-closable default, unique IDs, capacity) are
    /// re-established through ``Project/normalizedTabs(_:activeTabID:maxTabs:)``.
    func makeProject(
        id: UUID = UUID(),
        now: Date,
        maxTabs: Int = ProjectStructuralLimits.tabCountRange.upperBound
    )
        throws -> Project
    {
        let snapshots = tabs.map { $0.makeTabSnapshot() }
        let requiredCount = snapshots.count + (snapshots.contains { !$0.isClosable } ? 0 : 1)
        guard requiredCount <= maxTabs else {
            throw PortableProjectError.tabCapacityExceededAfterDefaultInsertion(
                required: requiredCount,
                limit: maxTabs
            )
        }
        let desiredActiveTabID = snapshots.indices.contains(activeTabIndex)
            ? snapshots[activeTabIndex].id
            : (snapshots.first?.id ?? UUID())
        let normalized = Project.normalizedTabs(snapshots, activeTabID: desiredActiveTabID, maxTabs: maxTabs)
        return Project(
            id: id,
            name: (try? ProjectNormalization.normalizedDisplayName(name)) ?? name,
            createdAt: now,
            updatedAt: now,
            activeTabID: normalized.activeTabID,
            tabs: normalized.tabs
        )
    }

    /// Validates every decoded bound and fails closed on an unsupported version,
    /// an unnormalizable name, an out-of-range tab count or active index, or any
    /// invalid tab. Unknown JSON keys are ignored by the decoder before this runs.
    func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw PortableProjectError.unsupportedFormatVersion(found: formatVersion)
        }
        do {
            _ = try ProjectNormalization.normalizedDisplayName(name)
        } catch let error as ProjectNameNormalizationError {
            throw PortableProjectError.nameInvalid(error)
        }
        guard ProjectStructuralLimits.tabCountRange.contains(tabs.count) else {
            throw PortableProjectError.tabCountOutOfRange(count: tabs.count)
        }
        guard tabs.indices.contains(activeTabIndex) else {
            throw PortableProjectError.activeTabIndexOutOfRange(index: activeTabIndex)
        }
        for tab in tabs {
            do {
                try tab.validate()
            } catch let error as ProjectSnapshotValidationError {
                throw PortableProjectError.tabInvalid(error)
            }
        }
    }
}
