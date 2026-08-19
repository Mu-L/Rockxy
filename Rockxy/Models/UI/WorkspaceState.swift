import Foundation
import os

// MARK: - ContextDockTab

// Defines the UI state for a single workspace tab.

enum ContextDockTab: Equatable {
    case details
    case aiAssistant
}

// MARK: - WorkspaceState

@MainActor @Observable
final class WorkspaceState: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String = String(localized: "All Traffic"),
        isClosable: Bool = true,
        initialFilter: FilterCriteria = .empty,
        inspectorLayout: InspectorLayout = .hidden,
        isContextDockVisible: Bool = false,
        allowsAutomaticInspectorReveal: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isClosable = isClosable
        self.filterCriteria = initialFilter
        self.inspectorLayout = inspectorLayout
        self.isContextDockVisible = isContextDockVisible
        self.allowsAutomaticInspectorReveal = allowsAutomaticInspectorReveal
        self.focusSets = FocusSetPersistence.load()
    }

    // MARK: Internal

    static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceState")

    let id: UUID
    var title: String
    var isClosable: Bool

    // Navigation
    var activeMainTab: MainTab = .traffic
    var sidebarSelection: SidebarItem?
    var inspectorTab: InspectorTab = .headers
    var inspectorLayout: InspectorLayout
    var isContextDockVisible: Bool
    var contextDockTab: ContextDockTab = .details
    var allowsAutomaticInspectorReveal: Bool
    var debugAssistantState: DebugAssistantState = .idle
    var modelInvestigationState: ModelInvestigationState = .idle
    var debugAssistantProductHelpState: DebugAssistantProductHelpState = .idle
    var debugAssistantMessages: [DebugAssistantMessage] = []
    var debugAssistantDraft = ""
    var debugAssistantConversationID = UUID()
    var debugAssistantConversationTitle = String(localized: "New Conversation")
    var debugAssistantConversationCreatedAt = Date()
    var debugAssistantConversationUpdatedAt = Date()
    var debugAssistantConversationContext: DebugAssistantConversationContext?
    var debugAssistantConversations: [DebugAssistantConversation] = []
    var debugAssistantUsesConfiguredModel = true
    var debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
    var debugAssistantReviewPack: InvestigationContextPack?
    var debugAssistantReviewRequest: AssistantCompletionRequest?
    var debugAssistantReviewConfiguration: AssistantProviderConfiguration?
    var debugAssistantReviewTrafficScope: AssistantTrafficScope?
    var debugAssistantReviewModelAccessEnabled = false
    var debugAssistantReviewSummary: DebugAssistantReviewSummary?
    var debugAssistantRequestedContextCount = 0
    var isPreparingDebugAssistantReview = false
    var isPreparingDebugAssistantReviewOverride = false
    var isDebugAssistantComposerFocusRequested = false
    var focusNavigatorMode: FocusNavigatorMode = .browse
    var activeTrafficSignal: TrafficSignal?
    var focusSets: [FocusSet] = []
    var activeFocusSetID: UUID?
    var mutedTrafficSources: Set<MutedTrafficSource> = []

    // Selection
    var selectedTransaction: HTTPTransaction?
    var selectedLogEntry: LogEntry?
    var selectedTransactionIDs: Set<UUID> = []

    /// Opt-in live-tail mode for this workspace. New visible traffic becomes the primary
    /// selection until the user deliberately selects a row, at which point the mode yields.
    /// Owned per-workspace so an inactive workspace can keep advancing independently.
    var isFollowingLiveTraffic = false

    // Filtering
    var filterCriteria: FilterCriteria = .empty
    var filterRules: [FilterRule] = [FilterRule()]
    var isFilterBarVisible: Bool = false
    var filteredTransactions: [HTTPTransaction] = []

    // Table-facing derived state (derived from filteredTransactions via deriveFilteredRows)
    var filteredRows: [RequestListRow] = []
    var refreshToken: Int = 0

    /// Set true only by the genuine append fast-path in appendFilteredTransactions, and
    /// cleared by deriveFilteredRows (and reset) once a full derivation replaces the rows.
    /// The table reads this as the coarse "the last mutation only appended rows" signal.
    var lastDeriveWasAppendOnly: Bool = false

    /// Provenance for the append fast-path: the refreshToken of the base state that the
    /// current unbroken run of pure appends builds on. `nil` whenever the last row mutation
    /// was not a pure append (recompute, sort, enrichment, eviction, delete, reset). The
    /// first append of a chain records the pre-append token and later coalesced appends
    /// preserve it, so the request table can insert rows incrementally only when this origin
    /// is <= the token it has already applied — otherwise a non-append mutation was coalesced
    /// ahead of the append and the displayed prefix no longer matches the model.
    var appendChainOriginToken: Int?

    /// Sort state (user preference, persists across session clears)
    var activeSortDescriptors: [NSSortDescriptor] = []

    // Sidebar (per-workspace view of captured data)
    var domainTree: [DomainNode] = []
    var totalDomainCount = 0
    var domainIndexMap: [String: Int] = [:]
    var domainGroupingIndex = DomainGroupingIndex()
    var appNodes: [AppInfo] = []
    var appNodeIndexMap: [String: Int] = [:]
    var appGroupingIndex = AppGroupingIndex()

    var activeFocusSet: FocusSet? {
        focusSets.first { $0.id == activeFocusSetID }
    }

    func reset() {
        filteredTransactions.removeAll()
        filteredRows.removeAll()
        lastDeriveWasAppendOnly = false
        appendChainOriginToken = nil
        refreshToken += 1
        // activeSortDescriptors intentionally preserved — sort is a user preference
        selectedTransaction = nil
        selectedLogEntry = nil
        selectedTransactionIDs.removeAll()
        debugAssistantState = .idle
        modelInvestigationState = .idle
        debugAssistantProductHelpState = .idle
        debugAssistantMessages.removeAll()
        debugAssistantDraft = ""
        debugAssistantConversationID = UUID()
        debugAssistantConversationTitle = String(localized: "New Conversation")
        debugAssistantConversationCreatedAt = Date()
        debugAssistantConversationUpdatedAt = Date()
        debugAssistantConversationContext = nil
        debugAssistantConversations.removeAll()
        debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
        debugAssistantReviewPack = nil
        debugAssistantReviewRequest = nil
        debugAssistantReviewConfiguration = nil
        debugAssistantReviewTrafficScope = nil
        debugAssistantReviewModelAccessEnabled = false
        debugAssistantReviewSummary = nil
        debugAssistantRequestedContextCount = 0
        isPreparingDebugAssistantReview = false
        isPreparingDebugAssistantReviewOverride = false
        isDebugAssistantComposerFocusRequested = false
        domainTree.removeAll()
        totalDomainCount = 0
        domainIndexMap.removeAll()
        domainGroupingIndex.removeAll()
        appNodes.removeAll()
        appNodeIndexMap.removeAll()
        appGroupingIndex.removeAll()
    }
}
