import Foundation

// MARK: - RequestListEmptyState

/// The reason the main request list has no visible rows.
///
/// Kept as a pure decision so the overlay copy stays honest about capture, scope, and
/// filter state without embedding branching logic in the view. Resolves to `nil` whenever
/// visible rows exist — the table renders normally in that case.
enum RequestListEmptyState: Equatable {
    /// Candidate requests exist in the current scope but active filters hide every one.
    /// Carries the available (non-TLS-failure) candidate count for truthful copy.
    case filtered(availableCount: Int)
    /// A Library collection (Saved / Pinned / Notes) is scoped but holds no requests.
    case emptyCollection(SidebarScope)
    /// The proxy is starting up; requests cannot arrive yet.
    case proxyStarting
    /// The proxy is stopped and nothing has been captured.
    case proxyStopped
    /// The proxy is running but recording is paused, so new requests are dropped from view.
    case recordingPaused
    /// The proxy is running and recording, but no traffic has arrived yet.
    case waitingForTraffic

    // MARK: Internal

    /// Resolves the empty-state reason from current coordinator state.
    ///
    /// Precedence, top to bottom:
    /// 1. Visible rows → `nil` (table renders).
    /// 2. Empty Library collection (Saved / Pinned / Notes with zero candidates) — takes
    ///    precedence over proxy state so an empty collection never claims "no matches" or
    ///    "waiting for traffic".
    /// 3. Filtered empty — candidates exist (>0) and active filters hide all of them.
    /// 4. Proxy state (starting / stopped / paused / waiting).
    ///
    /// - Parameters:
    ///   - hasVisibleRows: at least one row survives the active scope + filters.
    ///   - availableCount: candidate (non-TLS-failure) request count for the current scope.
    ///   - hasActiveFilters: any workspace filter, advanced rule, signal, focus set, or mute is active.
    ///   - scope: the active sidebar scope.
    ///   - proxyState: the live proxy display state.
    static func resolve(
        hasVisibleRows: Bool,
        availableCount: Int,
        hasActiveFilters: Bool,
        scope: SidebarScope,
        proxyState: ProxyDisplayState
    )
        -> RequestListEmptyState?
    {
        if hasVisibleRows {
            return nil
        }

        // An empty Library collection is more specific than proxy state: never report
        // "no matches" or "waiting" when the collection itself is simply empty.
        if scope != .allTraffic, availableCount == 0 {
            return .emptyCollection(scope)
        }

        // Only claim "no matches" when there are genuine candidates to match against.
        if availableCount > 0, hasActiveFilters {
            return .filtered(availableCount: availableCount)
        }

        switch proxyState {
        case .starting:
            return .proxyStarting
        case .stopped:
            return .proxyStopped
        case .paused:
            return .recordingPaused
        case .running:
            return .waitingForTraffic
        }
    }
}

// MARK: - RequestListEmptyStateAction

/// The single safe recovery action offered for an empty state, if any. Every action routes
/// through the coordinator so behavior cannot drift from the filter-summary reset.
enum RequestListEmptyStateAction: Equatable {
    case clearFilters
    case showAllTraffic
    case startProxy
    case resumeRecording
}

// MARK: - RequestListEmptyStateCopy

/// User-facing copy and recovery action for a `RequestListEmptyState`, rendered through a
/// native `ContentUnavailableView`.
struct RequestListEmptyStateCopy: Equatable {
    // MARK: Lifecycle

    init(_ state: RequestListEmptyState) {
        switch state {
        case let .filtered(availableCount):
            title = String(localized: "No Matching Requests")
            systemImage = "line.3.horizontal.decrease.circle"
            description = Self.filteredDescription(availableCount: availableCount)
            action = .clearFilters
            actionTitle = String(localized: "Clear Filters")
            actionHelp = String(localized: "Clear the active filters to show all captured traffic.")

        case let .emptyCollection(scope):
            let collection = Self.collectionCopy(for: scope)
            title = collection.title
            systemImage = collection.systemImage
            description = collection.description
            action = .showAllTraffic
            actionTitle = String(localized: "Show All Traffic")
            actionHelp = String(localized: "Leave this collection and show all captured traffic.")

        case .proxyStarting:
            title = String(localized: "Starting Proxy")
            systemImage = "hourglass"
            description = String(localized: "Rockxy is starting the proxy. Captured requests will appear here.")
            action = nil
            actionTitle = nil
            actionHelp = nil

        case .proxyStopped:
            title = String(localized: "No Traffic Captured")
            systemImage = "network.slash"
            description = String(localized: "The proxy is stopped. Start it to begin capturing requests.")
            action = .startProxy
            actionTitle = String(localized: "Start Proxy")
            actionHelp = String(localized: "Start the proxy to begin capturing network traffic.")

        case .recordingPaused:
            title = String(localized: "Recording Paused")
            systemImage = "pause.circle"
            description = String(
                localized: "New requests are not being recorded. Resume recording to capture traffic."
            )
            action = .resumeRecording
            actionTitle = String(localized: "Resume Recording")
            actionHelp = String(localized: "Resume recording so new requests are captured.")

        case .waitingForTraffic:
            title = String(localized: "Waiting for Requests")
            systemImage = "dot.radiowaves.left.and.right"
            description = String(
                localized: "Rockxy is capturing. Send a request through the proxy and it will appear here."
            )
            action = nil
            actionTitle = nil
            actionHelp = nil
        }
    }

    // MARK: Internal

    let title: String
    let systemImage: String
    let description: String
    let action: RequestListEmptyStateAction?
    let actionTitle: String?
    let actionHelp: String?

    // MARK: Private

    private struct CollectionCopy {
        let title: String
        let systemImage: String
        let description: String
    }

    private static func filteredDescription(availableCount: Int) -> String {
        if availableCount == 1 {
            return String(localized: "No requests match the active filters. 1 request is available before filtering.")
        }
        return String(
            localized: "No requests match the active filters. \(availableCount) requests are available before filtering."
        )
    }

    private static func collectionCopy(for scope: SidebarScope) -> CollectionCopy {
        switch scope {
        case .saved:
            CollectionCopy(
                title: String(localized: "No Saved Requests"),
                systemImage: "bookmark",
                description: String(
                    localized: "Requests you save appear here. Save a request from its menu to keep it across sessions."
                )
            )
        case .pinned:
            CollectionCopy(
                title: String(localized: "No Pinned Requests"),
                systemImage: "pin",
                description: String(localized: "Pin a request to keep it at hand. Pinned requests appear here.")
            )
        case .notes:
            CollectionCopy(
                title: String(localized: "No Requests with Notes"),
                systemImage: "note.text",
                description: String(localized: "Requests with notes appear here. Add a note to a request to track it.")
            )
        case .allTraffic:
            // Not reachable — `.emptyCollection` is only resolved for Library scopes.
            CollectionCopy(
                title: String(localized: "No Requests"),
                systemImage: "tray",
                description: String(localized: "No requests to show.")
            )
        }
    }
}
