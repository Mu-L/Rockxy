import Foundation

/// Defines the criteria a request must satisfy for a `ProxyRule` to fire.
/// All non-nil fields must match (AND logic). URL patterns use regex matching.
struct RuleMatchCondition: Codable, Equatable {
    // MARK: Lifecycle

    init(
        urlPattern: String? = nil,
        sourceURLPattern: String? = nil,
        method: String? = nil,
        headerName: String? = nil,
        headerValue: String? = nil,
        matchType: RuleMatchType? = nil,
        includeSubpaths: Bool? = nil
    ) {
        self.urlPattern = urlPattern
        self.sourceURLPattern = sourceURLPattern
        self.method = method
        self.headerName = headerName
        self.headerValue = headerValue
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
    }

    // MARK: Internal

    var urlPattern: String?
    /// Optional user-authored pattern retained for editors when `urlPattern`
    /// contains the compiled regex used by the runtime.
    var sourceURLPattern: String?
    var method: String?
    var headerName: String?
    var headerValue: String?
    var matchType: RuleMatchType?
    var includeSubpaths: Bool?

    func matches(
        method requestMethod: String,
        url: URL,
        headers: [HTTPHeader],
        compiledPattern: NSRegularExpression? = nil
    )
        -> Bool
    {
        if let regex = compiledPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            let range = NSRange(urlString.startIndex..., in: urlString)
            guard regex.firstMatch(in: urlString, range: range) != nil else {
                return false
            }
        } else if let pattern = runtimeURLPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            guard urlString.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }
        if let requiredMethod = method {
            guard requestMethod.uppercased() == requiredMethod.uppercased() else {
                return false
            }
        }
        if let name = headerName, let value = headerValue {
            guard headers.contains(where: { $0.name.lowercased() == name.lowercased() && $0.value == value }) else {
                return false
            }
        }
        return true
    }

    private var runtimeURLPattern: String? {
        guard let urlPattern else {
            return nil
        }
        guard let matchType else {
            return urlPattern
        }
        let authoredPattern = sourceURLPattern ?? urlPattern
        return RulePatternBuilder.regexSource(
            rawPattern: authoredPattern,
            matchType: matchType,
            includeSubpaths: matchType == .wildcard ? includeSubpaths ?? false : false
        )
    }
}
