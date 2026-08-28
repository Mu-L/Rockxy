import Foundation

// MARK: - UpstreamProxyType

enum UpstreamProxyType: String, Codable, CaseIterable {
    case automatic
    case http
    case https
    case socks5

    // MARK: Internal

    var displayName: String {
        switch self {
        case .automatic:
            String(localized: "Automatic", bundle: RockxyLocalization.bundle)
        case .http:
            String(localized: "HTTP", bundle: RockxyLocalization.bundle)
        case .https:
            String(localized: "HTTPS", bundle: RockxyLocalization.bundle)
        case .socks5:
            String(localized: "SOCKS5", bundle: RockxyLocalization.bundle)
        }
    }
}
