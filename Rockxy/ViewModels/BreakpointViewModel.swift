import Foundation

// Defines the breakpoint request, response, and decision types shared across breakpoint
// workflows.

// MARK: - BreakpointPhase

/// Whether the breakpoint fires on the outgoing request or the incoming response.
enum BreakpointPhase {
    case request
    case response
}

// MARK: - BreakpointDecision

/// The user's chosen action when a breakpoint-paused request is presented.
enum BreakpointDecision {
    /// Forward the (potentially modified) request to the upstream server.
    case execute
    /// Drop the request and return a 503 Service Unavailable response.
    case abort
    /// Forward the original paused message without applying the current draft.
    case cancel
}

// MARK: - BreakpointRequestData

/// Editable snapshot of an intercepted HTTP request/response shown in the breakpoint sheet.
struct BreakpointRequestData {
    var method: String
    var url: String
    var headers: [EditableHeader]
    var body: String
    var statusCode: Int
    var phase: BreakpointPhase = .request
    var isBodyEditable = true
    var fixedHTTPSAuthority: String?

    /// Whether the original request uses HTTPS. Used by the breakpoint editor to constrain
    /// the URL editor so the user can only modify path and query — the host is fixed by the
    /// TLS tunnel and cannot be changed mid-connection.
    var isHTTPS: Bool {
        url.lowercased().hasPrefix("https://")
    }

    /// Projects captured bytes into the text-only breakpoint editor without
    /// claiming that a lossy conversion is editable.
    static func editableBodyProjection(from data: Data?) -> (text: String, isEditable: Bool) {
        guard let data else {
            return ("", true)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("", false)
        }
        return (text, true)
    }

    /// Applies an origin-form request target while preserving its percent-
    /// encoded delimiters and the current connection authority.
    static func applyingOriginForm(_ value: String, to currentURL: String) -> String? {
        let normalized = value.hasPrefix("/") ? value : "/\(value)"
        guard let editedTarget = URLComponents(string: normalized),
              var components = URLComponents(string: currentURL)
        else {
            return nil
        }
        components.percentEncodedPath = editedTarget.percentEncodedPath
        components.percentEncodedQuery = editedTarget.percentEncodedQuery
        return components.string
    }
}

// MARK: - EditableHeader

/// A mutable header name-value pair for the breakpoint editor table.
struct EditableHeader: Identifiable {
    let id = UUID()
    var name: String
    var value: String
}
