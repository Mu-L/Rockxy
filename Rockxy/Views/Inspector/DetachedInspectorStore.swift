import Foundation

// Coordinates the handoff of a single transaction from the main inspector URL bar
// to the standalone detached Inspector window.

// MARK: - DetachedInspectorSelection

/// Tiny value that pins the detached Inspector window to one transaction. Holds a
/// strong reference to the `HTTPTransaction` so the open window keeps live-updating
/// it even after the main-window selection changes or the live buffer evicts it.
struct DetachedInspectorSelection {
    let id = UUID()
    let transaction: HTTPTransaction
    let highlightContext: InspectorHighlightContext
}

// MARK: - DetachedInspectorStore

/// Singleton that handles the handoff of an `HTTPTransaction` from the inspector URL
/// bar to the detached Inspector window. The requested selection stays retained while
/// the window is open so it survives live-buffer eviction and scene reevaluation; each
/// new request retargets the window and bumps `version`.
@MainActor @Observable
final class DetachedInspectorStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = DetachedInspectorStore()

    /// The transaction (plus its highlight context) the detached window should show.
    /// Set by the coordinator before opening the window; observed by
    /// `DetachedInspectorWindowView` to adopt a strong reference of its own.
    private(set) var requestedSelection: DetachedInspectorSelection?

    /// Incremented each time a new selection is requested. The detached window observes
    /// this to detect re-targeting when the window is already open.
    private(set) var version: UInt64 = 0

    func present(transaction: HTTPTransaction, highlightContext: InspectorHighlightContext) {
        requestedSelection = DetachedInspectorSelection(
            transaction: transaction,
            highlightContext: highlightContext
        )
        version &+= 1
    }

    /// Releases a closed window's retained transaction without clearing a newer
    /// request that may already have re-targeted the singleton window.
    func dismiss(selectionID: UUID) {
        guard requestedSelection?.id == selectionID else {
            return
        }
        requestedSelection = nil
    }
}
