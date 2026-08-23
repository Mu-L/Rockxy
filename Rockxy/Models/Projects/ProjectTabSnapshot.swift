import Foundation

// MARK: - ProjectSnapshotValidationError

/// Rejection reasons for a decoded snapshot that exceeds structural bounds.
enum ProjectSnapshotValidationError: Error, Equatable {
    case titleInvalid(ProjectNameNormalizationError)
    case stringTooLong(field: String)
    case collectionTooLarge(field: String)
}

// MARK: - MutedTrafficSourceSnapshot

/// Durable, resilient reference to a muted traffic source. The live
/// ``MutedTrafficSource`` is a non-`Codable` UI enum; this DTO stores its kind
/// as a stable raw string so unknown future kinds decode without throwing.
struct MutedTrafficSourceSnapshot: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case host
        case pathPrefix
    }

    var kindRawValue: String
    var value: String

    /// Resolves to a live source, dropping unknown kinds.
    var resolved: MutedTrafficSource? {
        switch Kind(rawValue: kindRawValue) {
        case .host: .host(value)
        case .pathPrefix: .pathPrefix(value)
        case nil: nil
        }
    }

    init(kindRawValue: String, value: String) {
        self.kindRawValue = kindRawValue
        self.value = value
    }

    init(_ source: MutedTrafficSource) {
        switch source {
        case let .host(value):
            kindRawValue = Kind.host.rawValue
            self.value = value.boundedToGraphemes(ProjectStructuralLimits.maxFilterStringGraphemes)
        case let .pathPrefix(value):
            kindRawValue = Kind.pathPrefix.rawValue
            self.value = value.boundedToGraphemes(ProjectStructuralLimits.maxFilterStringGraphemes)
        }
    }

    func validate() throws {
        guard value.count <= ProjectStructuralLimits.maxFilterStringGraphemes else {
            throw ProjectSnapshotValidationError.stringTooLong(field: "mutedTrafficSource.value")
        }
    }
}

// MARK: - FilterRuleSnapshot

/// Durable form of a single advanced filter row. Field/operator are stored as
/// raw strings and resolved with safe fallbacks so persisted rows survive enum
/// evolution instead of failing to decode.
struct FilterRuleSnapshot: Codable, Equatable {
    var id: UUID
    var isEnabled: Bool
    var connectorRawValue: String
    var fieldRawValue: String
    var operatorRawValue: String
    var value: String

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        connectorRawValue: String = FilterLogicConnector.and.rawValue,
        fieldRawValue: String = FilterField.url.rawValue,
        operatorRawValue: String = FilterOperator.contains.rawValue,
        value: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.connectorRawValue = connectorRawValue
        self.fieldRawValue = fieldRawValue
        self.operatorRawValue = operatorRawValue
        self.value = value
    }

    init(_ rule: FilterRule) {
        id = rule.id
        isEnabled = rule.isEnabled
        connectorRawValue = rule.connector.rawValue
        fieldRawValue = rule.field.rawValue
        operatorRawValue = rule.filterOperator.rawValue
        value = rule.value.boundedToGraphemes(ProjectStructuralLimits.maxFilterStringGraphemes)
    }

    var resolved: FilterRule {
        FilterRule(
            id: id,
            isEnabled: isEnabled,
            connector: FilterLogicConnector(rawValue: connectorRawValue) ?? .and,
            field: FilterField(rawValue: fieldRawValue) ?? .url,
            filterOperator: FilterOperator(rawValue: operatorRawValue) ?? .contains,
            value: value
        )
    }

    func validate() throws {
        guard value.count <= ProjectStructuralLimits.maxFilterStringGraphemes else {
            throw ProjectSnapshotValidationError.stringTooLong(field: "filterRule.value")
        }
    }
}

// MARK: - FilterCriteriaSnapshot

/// Bounded, durable subset of ``FilterCriteria``. Excludes `exactTransactionID`
/// because it points into live captured traffic that the catalog never persists.
/// Enum-valued fields are stored as raw strings/ints and resolved with fallbacks.
struct FilterCriteriaSnapshot: Codable, Equatable {
    var searchText: String
    var methods: [String]
    var statusCodes: [Int]
    var contentTypeRawValues: [String]
    var domains: [String]
    var logLevelRawValues: [Int]
    var protocolFilterRawValues: [String]
    var searchFieldRawValue: String
    var isSearchEnabled: Bool
    var sidebarDomain: String?
    var sidebarPathPrefix: String?
    var sidebarApp: String?
    var sidebarScopeRawValue: String

    static let empty = FilterCriteriaSnapshot(FilterCriteria.empty)

    init(
        searchText: String = "",
        methods: [String] = [],
        statusCodes: [Int] = [],
        contentTypeRawValues: [String] = [],
        domains: [String] = [],
        logLevelRawValues: [Int] = [],
        protocolFilterRawValues: [String] = [],
        searchFieldRawValue: String = FilterField.url.rawValue,
        isSearchEnabled: Bool = true,
        sidebarDomain: String? = nil,
        sidebarPathPrefix: String? = nil,
        sidebarApp: String? = nil,
        sidebarScopeRawValue: String = SidebarScopeCoding.allTraffic
    ) {
        self.searchText = searchText
        self.methods = methods
        self.statusCodes = statusCodes
        self.contentTypeRawValues = contentTypeRawValues
        self.domains = domains
        self.logLevelRawValues = logLevelRawValues
        self.protocolFilterRawValues = protocolFilterRawValues
        self.searchFieldRawValue = searchFieldRawValue
        self.isSearchEnabled = isSearchEnabled
        self.sidebarDomain = sidebarDomain
        self.sidebarPathPrefix = sidebarPathPrefix
        self.sidebarApp = sidebarApp
        self.sidebarScopeRawValue = sidebarScopeRawValue
    }

    init(_ criteria: FilterCriteria) {
        let maxString = ProjectStructuralLimits.maxFilterStringGraphemes
        let maxCount = ProjectStructuralLimits.maxFilterCollectionCount

        searchText = criteria.searchText.boundedToGraphemes(maxString)
        methods = criteria.methods
            .filter { $0.count <= maxString }
            .sorted()
            .boundedCount(maxCount)
        statusCodes = criteria.statusCodes.sorted().boundedCount(maxCount)
        contentTypeRawValues = criteria.contentTypes
            .map(\.rawValue)
            .sorted()
            .boundedCount(maxCount)
        domains = criteria.domains
            .filter { $0.count <= maxString }
            .sorted()
            .boundedCount(maxCount)
        logLevelRawValues = criteria.logLevels
            .map(\.rawValue)
            .sorted()
            .boundedCount(maxCount)
        protocolFilterRawValues = criteria.activeProtocolFilters
            .map(\.rawValue)
            .sorted()
            .boundedCount(maxCount)
        searchFieldRawValue = criteria.searchField.rawValue
        isSearchEnabled = criteria.isSearchEnabled
        sidebarDomain = criteria.sidebarDomain?.boundedToGraphemes(maxString)
        sidebarPathPrefix = criteria.sidebarPathPrefix?.boundedToGraphemes(maxString)
        sidebarApp = criteria.sidebarApp?.boundedToGraphemes(maxString)
        sidebarScopeRawValue = SidebarScopeCoding.rawValue(for: criteria.sidebarScope)
    }

    var resolved: FilterCriteria {
        var criteria = FilterCriteria()
        criteria.searchText = searchText
        criteria.methods = Set(methods)
        criteria.statusCodes = Set(statusCodes)
        criteria.contentTypes = Set(contentTypeRawValues.compactMap { ContentType(rawValue: $0) })
        criteria.domains = Set(domains)
        criteria.logLevels = Set(logLevelRawValues.compactMap { LogLevel(rawValue: $0) })
        criteria.activeProtocolFilters = Set(protocolFilterRawValues.compactMap { ProtocolFilter(rawValue: $0) })
        criteria.searchField = FilterField(rawValue: searchFieldRawValue) ?? .url
        criteria.isSearchEnabled = isSearchEnabled
        criteria.sidebarDomain = sidebarDomain
        criteria.sidebarPathPrefix = sidebarPathPrefix
        criteria.sidebarApp = sidebarApp
        criteria.sidebarScope = SidebarScopeCoding.scope(for: sidebarScopeRawValue)
        // exactTransactionID is deliberately not restored: it references live traffic.
        return criteria
    }

    func validate() throws {
        func checkString(_ value: String, _ field: String) throws {
            guard value.count <= ProjectStructuralLimits.maxFilterStringGraphemes else {
                throw ProjectSnapshotValidationError.stringTooLong(field: field)
            }
        }
        func checkCount(_ count: Int, _ field: String) throws {
            guard count <= ProjectStructuralLimits.maxFilterCollectionCount else {
                throw ProjectSnapshotValidationError.collectionTooLarge(field: field)
            }
        }

        try checkString(searchText, "filter.searchText")
        try checkCount(methods.count, "filter.methods")
        try checkCount(statusCodes.count, "filter.statusCodes")
        try checkCount(contentTypeRawValues.count, "filter.contentTypes")
        try checkCount(domains.count, "filter.domains")
        try checkCount(logLevelRawValues.count, "filter.logLevels")
        try checkCount(protocolFilterRawValues.count, "filter.protocolFilters")
        for method in methods { try checkString(method, "filter.method") }
        for domain in domains { try checkString(domain, "filter.domain") }
        if let sidebarDomain { try checkString(sidebarDomain, "filter.sidebarDomain") }
        if let sidebarPathPrefix { try checkString(sidebarPathPrefix, "filter.sidebarPathPrefix") }
        if let sidebarApp { try checkString(sidebarApp, "filter.sidebarApp") }
    }
}

// MARK: - SidebarScopeCoding

/// Stable string coding for ``SidebarScope`` (which is `Codable` but not
/// `RawRepresentable`), with a safe fallback for unknown values.
enum SidebarScopeCoding {
    static let allTraffic = "allTraffic"

    static func rawValue(for scope: SidebarScope) -> String {
        switch scope {
        case .allTraffic: "allTraffic"
        case .saved: "saved"
        case .pinned: "pinned"
        case .notes: "notes"
        }
    }

    static func scope(for rawValue: String) -> SidebarScope {
        switch rawValue {
        case "saved": .saved
        case "pinned": .pinned
        case "notes": .notes
        default: .allTraffic
        }
    }
}

// MARK: - ProjectTabSnapshot

/// Durable, bounded snapshot of a single traffic tab's serializable view intent.
///
/// Captures only durable configuration from ``WorkspaceState`` and deliberately
/// excludes transactions, rows, selections, sort descriptors, sidebar derived
/// indexes, logs, assistant messages/review payloads/tasks, and captured
/// headers/bodies. Enum-valued presentation preferences are stored as stable
/// raw strings and resolved with safe fallbacks.
struct ProjectTabSnapshot: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var isClosable: Bool
    var filter: FilterCriteriaSnapshot
    var advancedFilterRows: [FilterRuleSnapshot]
    var isFilterBarVisible: Bool
    var mainTabRawValue: String
    var inspectorLayoutRawValue: String
    var isContextDockVisible: Bool
    var contextDockTabRawValue: String
    var focusNavigatorModeRawValue: String
    var activeTrafficSignalRawValue: String?
    var activeFocusSetID: UUID?
    var mutedTrafficSources: [MutedTrafficSourceSnapshot]

    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String,
        isClosable: Bool,
        filter: FilterCriteriaSnapshot = .empty,
        advancedFilterRows: [FilterRuleSnapshot] = [FilterRuleSnapshot()],
        isFilterBarVisible: Bool = false,
        mainTabRawValue: String = MainTab.traffic.rawValue,
        inspectorLayoutRawValue: String = InspectorLayoutCoding.hidden,
        isContextDockVisible: Bool = false,
        contextDockTabRawValue: String = ContextDockTabCoding.details,
        focusNavigatorModeRawValue: String = FocusNavigatorMode.browse.rawValue,
        activeTrafficSignalRawValue: String? = nil,
        activeFocusSetID: UUID? = nil,
        mutedTrafficSources: [MutedTrafficSourceSnapshot] = []
    ) {
        self.id = id
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
        self.activeFocusSetID = activeFocusSetID
        self.mutedTrafficSources = mutedTrafficSources
    }

    // MARK: Internal

    /// The guaranteed non-closable default tab every Project must contain.
    static func makeDefaultAllTraffic(
        id: UUID = UUID(),
        title: String = ProjectStructuralLimits.defaultTabTitle
    ) -> ProjectTabSnapshot {
        ProjectTabSnapshot(id: id, title: title, isClosable: false)
    }

    /// Validates decoded bounds. The title is normalized (1...80 graphemes,
    /// no control characters); filter strings/collections are bounded.
    func validate() throws {
        do {
            try ProjectNormalization.requireCanonical(title)
        } catch let error as ProjectNameNormalizationError {
            throw ProjectSnapshotValidationError.titleInvalid(error)
        }
        guard advancedFilterRows.count <= ProjectStructuralLimits.maxAdvancedFilterRows else {
            throw ProjectSnapshotValidationError.collectionTooLarge(field: "tab.advancedFilterRows")
        }
        guard mutedTrafficSources.count <= ProjectStructuralLimits.maxMutedTrafficSources else {
            throw ProjectSnapshotValidationError.collectionTooLarge(field: "tab.mutedTrafficSources")
        }
        try filter.validate()
        for row in advancedFilterRows { try row.validate() }
        for source in mutedTrafficSources { try source.validate() }
    }
}

// MARK: - InspectorLayoutCoding

/// Stable string coding for the non-`RawRepresentable` ``InspectorLayout`` enum.
enum InspectorLayoutCoding {
    static let hidden = "hidden"
    static let bottom = "bottom"

    static func rawValue(for layout: InspectorLayout) -> String {
        switch layout {
        case .hidden: hidden
        case .bottom: bottom
        }
    }

    static func layout(for rawValue: String) -> InspectorLayout {
        rawValue == bottom ? .bottom : .hidden
    }
}

// MARK: - ContextDockTabCoding

/// Stable string coding for the non-`RawRepresentable` ``ContextDockTab`` enum.
enum ContextDockTabCoding {
    static let details = "details"
    static let aiAssistant = "aiAssistant"

    static func rawValue(for tab: ContextDockTab) -> String {
        switch tab {
        case .details: details
        case .aiAssistant: aiAssistant
        }
    }

    static func tab(for rawValue: String) -> ContextDockTab {
        rawValue == aiAssistant ? .aiAssistant : .details
    }
}

// MARK: - String + bounds

extension String {
    /// Returns a copy limited to `maxGraphemes` grapheme clusters.
    func boundedToGraphemes(_ maxGraphemes: Int) -> String {
        guard count > maxGraphemes else {
            return self
        }
        return String(prefix(maxGraphemes))
    }
}

// MARK: - Array + bounds

extension Array {
    /// Returns a copy limited to `maxCount` elements.
    func boundedCount(_ maxCount: Int) -> [Element] {
        count > maxCount ? Array(prefix(maxCount)) : self
    }
}
