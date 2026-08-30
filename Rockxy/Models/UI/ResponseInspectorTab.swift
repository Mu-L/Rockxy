import Foundation

/// Tabs for the response half of the split inspector panel.
enum ResponseInspectorTab: String, CaseIterable {
    case ai
    case headers
    case body
    case setCookie
    case auth
    case timeline

    // MARK: Internal

    static func availableTabs() -> [ResponseInspectorTab] {
        allCases.filter { tab in
            tab != .ai
        }
    }

    var displayName: String {
        switch self {
        // "AI" is a product/acronym token; "Set-Cookie" is an HTTP header name — both verbatim.
        case .ai: "AI"
        case .headers: String(localized: "Headers", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .setCookie: "Set-Cookie"
        case .auth: String(localized: "Auth", bundle: RockxyLocalization.bundle)
        case .timeline: String(localized: "Timeline", bundle: RockxyLocalization.bundle)
        }
    }
}
