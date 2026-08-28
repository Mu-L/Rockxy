import Foundation

// Defines `ExportScope` and the immutable review context the SwiftUI export
// sheet renders. Membership, order, and counts are frozen at presentation time
// so an in-flight capture, filter change, selection change, or workspace switch
// can never widen or alter what actually gets exported.

// MARK: - TrafficExportFormat

/// User-facing traffic export formats available from the main capture workspace.
enum TrafficExportFormat: String, CaseIterable {
    case har
    case openAPIYAML
    case openAPIHTML

    // MARK: Internal

    var title: String {
        switch self {
        case .har:
            String(localized: "Export as HAR")
        case .openAPIYAML:
            String(localized: "Export as OpenAPI YAML")
        case .openAPIHTML:
            String(localized: "Export as OpenAPI HTML")
        }
    }

    var isOpenAPI: Bool {
        switch self {
        case .har:
            false
        case .openAPIYAML,
             .openAPIHTML:
            true
        }
    }

    var privacyNote: String {
        switch self {
        case .har:
            String(
                localized: "HAR files can include captured URLs, headers, cookies, authorization and query values, and request/response bodies. Review the file before sharing."
            )
        case .openAPIYAML,
             .openAPIHTML:
            String(
                localized: """
                OpenAPI infers schemas, hosts, and paths. Captured sensitive header and example values aren't \
                exported; recognized sensitive query and body fields are omitted.
                """
            )
        }
    }

    var subtitle: String {
        switch self {
        case .har:
            String(localized: "Choose which captured transactions to save in this HAR archive.")
        case .openAPIYAML,
             .openAPIHTML:
            String(localized: "Choose which eligible HTTP requests to use for the inferred OpenAPI document.")
        }
    }

    var defaultFileName: String {
        switch self {
        case .har:
            "rockxy-export.har"
        case .openAPIYAML:
            "rockxy-openapi.yaml"
        case .openAPIHTML:
            "rockxy-openapi.html"
        }
    }

    var successLabel: String {
        switch self {
        case .har:
            "HAR"
        case .openAPIYAML:
            "OpenAPI YAML"
        case .openAPIHTML:
            "OpenAPI HTML"
        }
    }

    /// Whether a single captured transaction can appear in this format's output.
    /// HAR carries every transaction verbatim; OpenAPI only accepts requests it
    /// can infer a schema from.
    func isEligible(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case .har:
            true
        case .openAPIYAML,
             .openAPIHTML:
            OpenAPIExporter.isEligible(transaction)
        }
    }
}

// MARK: - ExportScope

/// Determines which transactions are included when exporting captured traffic.
enum ExportScope: String, CaseIterable {
    case all
    case filtered
    case selected
}

// MARK: - ExportScopeSnapshot

/// Immutable, ordered membership captured for a single scope at the moment the
/// review sheet opens. Owns the reviewed transactions plus the format-eligible
/// subset so every count the UI shows — and every request the export writes —
/// derives from this frozen list, never from live coordinator state.
struct ExportScopeSnapshot {
    // MARK: Lifecycle

    init(transactions: [HTTPTransaction], format: TrafficExportFormat) {
        self.transactions = transactions
        eligibleTransactions = transactions.filter(format.isEligible)
    }

    // MARK: Internal

    /// Reviewed membership, in the order it was resolved. Reference identity is
    /// intentionally preserved (this freezes membership/order/count, not payload
    /// content — see the checkpoint contract).
    let transactions: [HTTPTransaction]

    /// The subset of `transactions` this format can actually export.
    let eligibleTransactions: [HTTPTransaction]

    var total: Int {
        transactions.count
    }

    var eligibleCount: Int {
        eligibleTransactions.count
    }

    var skippedCount: Int {
        total - eligibleCount
    }

    var orderedIDs: [UUID] {
        transactions.map(\.id)
    }

    var eligibleOrderedIDs: [UUID] {
        eligibleTransactions.map(\.id)
    }
}

// MARK: - ExportScopeContext

/// Immutable review context handed to `ExportScopeSheet`. Identifiable so the
/// sheet is driven by `.sheet(item:)` — presence of a context is the only
/// presentation state. Everything the sheet and the execution plan need is
/// frozen here at presentation time.
struct ExportScopeContext: Identifiable {
    // MARK: Lifecycle

    init(
        format: TrafficExportFormat,
        originWorkspaceID: UUID,
        originWorkspaceTitle: String,
        allTransactions: [HTTPTransaction],
        filteredTransactions: [HTTPTransaction],
        selectedTransactions: [HTTPTransaction],
        hasActiveFilter: Bool,
        restrictsToSelection: Bool = false
    ) {
        self.format = format
        self.originWorkspaceID = originWorkspaceID
        self.originWorkspaceTitle = originWorkspaceTitle
        allSnapshot = ExportScopeSnapshot(transactions: allTransactions, format: format)
        filteredSnapshot = ExportScopeSnapshot(transactions: filteredTransactions, format: format)
        selectedSnapshot = ExportScopeSnapshot(transactions: selectedTransactions, format: format)
        self.hasActiveFilter = hasActiveFilter
        self.restrictsToSelection = restrictsToSelection
        initialScope = Self.resolveInitialScope(
            restrictsToSelection: restrictsToSelection,
            hasActiveFilter: hasActiveFilter,
            selectedSnapshot: selectedSnapshot,
            filteredSnapshot: filteredSnapshot
        )
    }

    // MARK: Internal

    let id = UUID()
    let format: TrafficExportFormat
    let originWorkspaceID: UUID
    let originWorkspaceTitle: String
    let allSnapshot: ExportScopeSnapshot
    let filteredSnapshot: ExportScopeSnapshot
    let selectedSnapshot: ExportScopeSnapshot
    let hasActiveFilter: Bool
    let restrictsToSelection: Bool
    let initialScope: ExportScope

    var hasSelection: Bool {
        selectedSnapshot.total > 0
    }

    /// Scopes offered as native radio options — enabled ones only. In a
    /// restricted context this is always just `.selected`.
    var availableScopes: [ExportScope] {
        ExportScope.allCases.filter(isEnabled)
    }

    /// Disabled scopes worth explaining to the user, with their reasons. Never
    /// surfaced in a restricted context, where the locked summary stands alone.
    var unavailableScopes: [ExportScope] {
        guard !restrictsToSelection else {
            return []
        }
        return ExportScope.allCases.filter { !isEnabled($0) && reason(for: $0) != nil }
    }

    /// One-line locked summary shown when the context is pinned to the user's
    /// selection (Assistant / Context Dock handoffs) instead of a scope picker.
    var lockedSelectionSummary: String {
        countSummary(for: .selected)
    }

    func snapshot(for scope: ExportScope) -> ExportScopeSnapshot {
        switch scope {
        case .all:
            allSnapshot
        case .filtered:
            filteredSnapshot
        case .selected:
            selectedSnapshot
        }
    }

    func count(for scope: ExportScope) -> Int {
        snapshot(for: scope).total
    }

    func eligibleCount(for scope: ExportScope) -> Int {
        snapshot(for: scope).eligibleCount
    }

    func skippedCount(for scope: ExportScope) -> Int {
        snapshot(for: scope).skippedCount
    }

    func isEnabled(_ scope: ExportScope) -> Bool {
        if restrictsToSelection, scope != .selected {
            return false
        }
        return switch scope {
        case .all:
            allSnapshot.eligibleCount > 0
        case .filtered:
            hasActiveFilter && filteredSnapshot.eligibleCount > 0
        case .selected:
            hasSelection && selectedSnapshot.eligibleCount > 0
        }
    }

    func label(for scope: ExportScope) -> String {
        switch (format.isOpenAPI, scope) {
        case (false, .all):
            String(localized: "All Transactions")
        case (false, .filtered):
            String(localized: "Visible / Filtered")
        case (false, .selected):
            String(localized: "Selected")
        case (true, .all):
            String(localized: "All Captured Requests")
        case (true, .filtered):
            String(localized: "Visible / Filtered Requests")
        case (true, .selected):
            String(localized: "Selected Requests")
        }
    }

    /// Honest count line for a scope. HAR reports transaction counts; OpenAPI
    /// always exposes included and skipped counts.
    func countSummary(for scope: ExportScope) -> String {
        let snapshot = snapshot(for: scope)
        if !format.isOpenAPI {
            return String(AttributedString(localized: "^[\(snapshot.total) transaction](inflect: true)").characters)
        }
        return String(localized: "\(snapshot.eligibleCount) included · \(snapshot.skippedCount) skipped")
    }

    /// Extra skipped-detail note for OpenAPI scopes that drop ineligible rows.
    func skippedNote(for scope: ExportScope) -> String? {
        let skipped = skippedCount(for: scope)
        guard format.isOpenAPI, skipped > 0 else {
            return nil
        }
        return String(
            AttributedString(
                localized: "^[\(skipped) request](inflect: true) can't be inferred and will be skipped"
            ).characters
        )
    }

    /// Truthful reason a scope is unavailable, or `nil` when it is selectable.
    func reason(for scope: ExportScope) -> String? {
        if isEnabled(scope) {
            return nil
        }
        switch scope {
        case .all:
            return allSnapshot.total == 0
                ? String(localized: "No captured traffic to export")
                : String(localized: "No OpenAPI-eligible requests captured")
        case .filtered:
            if !hasActiveFilter {
                return String(localized: "No active filter")
            }
            return filteredSnapshot.total == 0
                ? String(localized: "The active filter matches no requests")
                : String(localized: "No OpenAPI-eligible requests in the active filter")
        case .selected:
            if !hasSelection {
                return String(localized: "No requests selected")
            }
            return String(localized: "No OpenAPI-eligible requests selected")
        }
    }

    // MARK: Private

    private static func resolveInitialScope(
        restrictsToSelection: Bool,
        hasActiveFilter: Bool,
        selectedSnapshot: ExportScopeSnapshot,
        filteredSnapshot: ExportScopeSnapshot
    )
        -> ExportScope
    {
        if restrictsToSelection {
            return .selected
        }
        if selectedSnapshot.total > 0, selectedSnapshot.eligibleCount > 0 {
            return .selected
        }
        if hasActiveFilter, filteredSnapshot.eligibleCount > 0 {
            return .filtered
        }
        return .all
    }
}

// MARK: - ExportExecutionPlan

/// Pure, testable result of validating a chosen scope against a frozen context.
/// Export execution consumes only this — never live coordinator state — so what
/// gets written is exactly what the user reviewed.
struct ExportExecutionPlan {
    let format: TrafficExportFormat
    let scope: ExportScope

    /// Full reviewed membership for the chosen scope, retained for auditability
    /// and tests even when the format exports only its frozen eligible subset.
    let reviewedSource: [HTTPTransaction]

    /// The eligible transactions this format will actually emit.
    let eligibleTransactions: [HTTPTransaction]

    /// Count of reviewed transactions this format cannot emit.
    let skippedCount: Int
}
