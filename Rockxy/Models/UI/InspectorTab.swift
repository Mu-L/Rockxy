import Foundation

/// Tabs available in the combined request/response inspector panel.
/// Protocol-specific tabs (WebSocket, GraphQL, Certificates) are shown conditionally
/// based on the selected transaction's type.
enum InspectorTab: String, CaseIterable {
    case headers
    case body
    case cookies
    case timing
    case raw
    case certificates
    case websocket
    case graphql

    // MARK: Internal

    var displayName: String {
        switch self {
        case .headers: String(localized: "Headers", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .cookies: String(localized: "Cookies", bundle: RockxyLocalization.bundle)
        case .timing: String(localized: "Timing", bundle: RockxyLocalization.bundle)
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        case .certificates: String(localized: "Certs", bundle: RockxyLocalization.bundle)
        // Protocol names render verbatim regardless of language.
        case .websocket: "WebSocket"
        case .graphql: "GraphQL"
        }
    }
}
