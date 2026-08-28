import Foundation

// MARK: - UpstreamProxyConfigurationError

enum UpstreamProxyConfigurationError: LocalizedError, Equatable {
    case hostInvalid
    case portOutOfRange
    case usernameTooLong
    case passwordTooLong
    case bypassPatternInvalid(String)
    case tooManyBypassEntries(limit: Int)
    case pacURLRequired
    case pacURLInvalid
    case pacURLUnsupportedScheme

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .hostInvalid:
            String(localized: "Upstream proxy host is invalid.", bundle: RockxyLocalization.bundle)
        case .portOutOfRange:
            String(localized: "Upstream proxy port must be between 1 and 65535.", bundle: RockxyLocalization.bundle)
        case .usernameTooLong:
            String(localized: "Upstream proxy username must be 255 bytes or fewer.", bundle: RockxyLocalization.bundle)
        case .passwordTooLong:
            String(localized: "Upstream proxy password must be 255 bytes or fewer.", bundle: RockxyLocalization.bundle)
        case let .bypassPatternInvalid(pattern):
            String(localized: "Upstream proxy bypass pattern is invalid: \(pattern)", bundle: RockxyLocalization.bundle)
        case let .tooManyBypassEntries(limit):
            String(
                localized: "Upstream proxy bypass list is limited to \(limit) entries.",
                bundle: RockxyLocalization.bundle
            )
        case .pacURLRequired:
            String(localized: "Automatic proxy configuration requires a PAC URL.", bundle: RockxyLocalization.bundle)
        case .pacURLInvalid:
            String(localized: "Automatic proxy configuration URL is invalid.", bundle: RockxyLocalization.bundle)
        case .pacURLUnsupportedScheme:
            String(
                localized: "Automatic proxy configuration URL must use HTTP or HTTPS.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
