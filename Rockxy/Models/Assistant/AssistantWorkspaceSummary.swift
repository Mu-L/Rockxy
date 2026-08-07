import Foundation

// MARK: - AssistantWorkspaceSummary

/// Immutable, aggregate-only snapshot of the live workspace/session captured at Assistant send time.
///
/// This is **not** selected-traffic investigation data. It carries only bounded scalar counts and a
/// source-backed capture state — never any per-transaction content or identifiers (no URLs, hosts,
/// methods, status codes, headers, query values, bodies, timing, or transaction IDs). It exists so
/// the context-free product-help path can answer basic "how many requests do we have now?" questions
/// from authoritative current state without ever attaching captured traffic.
struct AssistantWorkspaceSummary: Sendable, Equatable {
    // MARK: Internal

    // MARK: - CaptureState

    /// Source-backed capture/proxy state. Derived from the proxy display state; scalar only.
    enum CaptureState: String, Sendable, Equatable {
        case running
        case paused
        case starting
        case stopped
        case unknown

        // MARK: Internal

        /// English fact value for the model `<workspace_facts>` grounding block.
        var factValue: String {
            rawValue
        }

        /// True when traffic could be recording right now, so "no requests yet" reads correctly.
        var isActive: Bool {
            self == .running || self == .starting
        }
    }

    /// Empty session with unknown capture state. Used only as a neutral default for callers that do
    /// not supply live state (e.g. isolated prompt-builder unit tests).
    static let empty = AssistantWorkspaceSummary(
        retainedRequestCount: 0,
        visibleRequestCount: 0,
        selectedRequestCount: 0,
        isScopeNarrowingResults: false,
        captureState: .unknown
    )

    /// Requests currently retained in the live session buffer (post-eviction), workspace-wide.
    let retainedRequestCount: Int
    /// Requests currently shown by the active workspace's filters/focus/noise/sidebar scope.
    let visibleRequestCount: Int
    /// Valid selected requests. Zero on the context-free path, but still source-backed.
    let selectedRequestCount: Int
    /// Whether filtering/scope is currently narrowing the visible set below the retained total.
    let isScopeNarrowingResults: Bool
    /// Source-backed capture/proxy state, when known.
    let captureState: CaptureState

    /// The concise deterministic answer for a current-count question, built only from these scalars.
    /// Never claims a lifetime total — "retained" always means the live buffer's current contents.
    var deterministicAnswer: String {
        guard retainedRequestCount > 0 else {
            switch captureState {
            case .stopped:
                return String(
                    localized: "No requests are currently retained — capture is stopped. Start capture to record traffic."
                )
            case .paused:
                return String(localized: "No requests are currently retained — capture is paused.")
            case .running,
                 .starting:
                return String(localized: "No requests are currently retained yet — capture is running.")
            case .unknown:
                return String(localized: "No requests are currently retained.")
            }
        }
        if visibleRequestCount == retainedRequestCount {
            if retainedRequestCount == 1 {
                return String(localized: "There is 1 request currently retained in this session.")
            }
            return String(
                localized: "There are \(retainedRequestCount) requests currently retained in this session."
            )
        }
        let visibleClause = visibleRequestCount == 1
            ? String(localized: "1 request is showing with the current filters")
            : String(localized: "\(visibleRequestCount) requests are showing with the current filters")
        return String(localized: "\(visibleClause), out of \(retainedRequestCount) retained in this session.")
    }

    /// English aggregate-only grounding for the model `<workspace_facts>` block. Scalars only; no
    /// captured request content or identifiers are ever emitted here.
    var modelFactsText: String {
        [
            "- retained_requests: \(retainedRequestCount) (held right now in the live session buffer)",
            "- visible_requests: \(visibleRequestCount) (shown by the active workspace filters/focus/noise scope)",
            "- selected_requests: \(selectedRequestCount)",
            "- scope_is_narrowing_results: \(isScopeNarrowingResults)",
            "- capture_state: \(captureState.factValue)",
        ].joined(separator: "\n")
    }

    /// Deterministically recognizes natural "how many requests do we have now?" style questions about
    /// the *current* session, while rejecting capability/limit questions ("maximum request limit",
    /// "how many requests can Rockxy handle/process/capture", "how many transactions are supported").
    /// Current-state viewing wording ("how many requests can I see now?") stays recognized. Purely
    /// lexical — no model, no captured traffic.
    static func isCurrentCountQuestion(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        guard !capabilityMarkers.contains(where: { normalized.contains($0) }) else {
            return false
        }
        guard subjectMarkers.contains(where: { normalized.contains($0) }) else {
            return false
        }
        return intentMarkers.contains(where: { normalized.contains($0) })
    }

    // MARK: Private

    /// Count-intent phrases. One must be present for a prompt to read as a current-count question.
    private static let intentMarkers = ["how many", "how much", "number of", "count"]

    /// Traffic-subject nouns the count must be about. Singular "request" also covers "requests".
    private static let subjectMarkers = ["request", "api call", "traffic", "transaction"]

    /// Capability/limit markers that disqualify a prompt from being a current-count question. These
    /// target what the tool *can* do or is designed to support, not what it currently holds. "can i
    /// capture"/"can rockxy" catch capability phrasing without rejecting the viewing verb in
    /// "how many requests can i see now?".
    private static let capabilityMarkers = [
        "maximum", "limit", "capacity", "handle", "supported", "can i capture", "can rockxy",
    ]
}
