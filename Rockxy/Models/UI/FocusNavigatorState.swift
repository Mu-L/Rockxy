import Foundation

// MARK: - FocusNavigatorMode

enum FocusNavigatorMode: String, CaseIterable, Identifiable {
    case browse
    case focus
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .browse: String(localized: "Browse")
        case .focus: String(localized: "Focus")
        case .library: String(localized: "Library")
        }
    }

    /// Monochrome symbols keep the compact navigator switcher aligned with Xcode's native
    /// navigator and inspector controls. The localized title remains the help and accessibility
    /// label, so the icon-only presentation never removes meaning.
    var systemImage: String {
        switch self {
        case .browse: "list.bullet.rectangle"
        case .focus: "scope"
        case .library: "books.vertical"
        }
    }
}

// MARK: - TrafficSignal

enum TrafficSignal: String, CaseIterable, Identifiable {
    case errors
    case slow
    case webSocket
    case graphQL
    case rulesHit

    var id: Self { self }

    var title: String {
        switch self {
        case .errors: String(localized: "Errors")
        case .slow: String(localized: "Slow")
        case .webSocket: String(localized: "WebSocket")
        case .graphQL: String(localized: "GraphQL")
        case .rulesHit: String(localized: "Rules Hit")
        }
    }

    var systemImage: String {
        switch self {
        case .errors: "exclamationmark.triangle"
        case .slow: "hourglass"
        case .webSocket: "arrow.left.arrow.right"
        case .graphQL: "point.3.connected.trianglepath.dotted"
        case .rulesHit: "wand.and.stars"
        }
    }

    var explanation: String {
        switch self {
        case .errors:
            String(localized: "HTTP 4xx/5xx responses and failed transports")
        case .slow:
            String(localized: "Requests taking at least one second")
        case .webSocket:
            String(localized: "WebSocket sessions and valid upgrade handshakes")
        case .graphQL:
            String(localized: "GraphQL operations confirmed from captured request data")
        case .rulesHit:
            String(localized: "Requests affected by a matching debugging rule")
        }
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case .errors:
            return transaction.state == .failed
                || transaction.response.map { (400 ... 599).contains($0.statusCode) } == true
        case .slow:
            guard let duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration else {
                return false
            }
            return duration >= Self.slowThreshold
        case .webSocket:
            return isWebSocket(transaction)
        case .graphQL:
            return transaction.graphQLInfo != nil
        case .rulesHit:
            return transaction.matchedRuleID != nil
                || transaction.matchedRuleName != nil
                || transaction.matchedRuleActionSummary != nil
                || transaction.matchedRulePattern != nil
        }
    }

    private static let slowThreshold: TimeInterval = 1

    private func isWebSocket(_ transaction: HTTPTransaction) -> Bool {
        if transaction.webSocketConnection != nil {
            return true
        }
        let scheme = transaction.request.url.scheme?.lowercased()
        if scheme == "ws" || scheme == "wss" {
            return true
        }
        let upgrade = transaction.request.headers.contains {
            $0.name.caseInsensitiveCompare("Upgrade") == .orderedSame
                && $0.value.caseInsensitiveCompare("websocket") == .orderedSame
        }
        let connection = transaction.request.headers.contains {
            $0.name.caseInsensitiveCompare("Connection") == .orderedSame
                && $0.value.lowercased().split(separator: ",").contains {
                    $0.trimmingCharacters(in: .whitespaces) == "upgrade"
                }
        }
        return upgrade && connection
    }
}

// MARK: - FocusSet

/// A compact, reusable traffic scope. Empty fields are wildcards; exclusions always win.
struct FocusSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var appName: String
    var domain: String
    var pathPrefix: String
    var excludedDomain: String
    var excludedPathPrefix: String

    init(
        id: UUID = UUID(),
        name: String,
        appName: String = "",
        domain: String = "",
        pathPrefix: String = "",
        excludedDomain: String = "",
        excludedPathPrefix: String = ""
    ) {
        self.id = id
        self.name = name
        self.appName = appName
        self.domain = domain
        self.pathPrefix = pathPrefix
        self.excludedDomain = excludedDomain
        self.excludedPathPrefix = excludedPathPrefix
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        let host = transaction.request.host
        let path = transaction.request.path
        if !excludedDomain.isEmpty, DomainGrouping.host(host, matchesDomain: excludedDomain) {
            return false
        }
        if !excludedPathPrefix.isEmpty, DomainGrouping.path(path, matchesPrefix: excludedPathPrefix) {
            return false
        }
        if !appName.isEmpty, transaction.clientApp != appName {
            return false
        }
        if !domain.isEmpty, !DomainGrouping.host(host, matchesDomain: domain) {
            return false
        }
        if !pathPrefix.isEmpty, !DomainGrouping.path(path, matchesPrefix: pathPrefix) {
            return false
        }
        return true
    }

    var ruleCount: Int {
        [appName, domain, pathPrefix, excludedDomain, excludedPathPrefix].count { !$0.isEmpty }
    }

    /// Keeps older automatically named Focus Sets useful without rewriting persisted user data.
    /// Explicit names always win; only the app-generated placeholder is replaced in the sidebar.
    var displayName: String {
        usesGeneratedName ? suggestedName : name
    }

    /// A meaningful starting name for a Focus Set created from the current traffic scope.
    var suggestedName: String {
        if let includedScopeName {
            return includedScopeName
        }
        if let excludedScopeName {
            return String(localized: "Hide \(excludedScopeName)")
        }
        return String(localized: "New Focus Set")
    }

    /// A collapsed-row summary for user-named sets. Expanded rows expose the same information
    /// structurally, so the sidebar can hide this sentence instead of repeating every rule.
    var scopeSummary: String {
        let included = includedScopeName
        let excluded = excludedScopeName
        switch (included, excluded) {
        case let (.some(included), .some(excluded)):
            return String(localized: "\(included). Hide \(excluded).")
        case let (.some(included), .none):
            return included
        case let (.none, .some(excluded)):
            return String(localized: "Hide \(excluded)")
        case (.none, .none):
            return String(localized: "No conditions")
        }
    }

    var includedRules: [FocusSetRuleDescriptor] {
        var rules: [FocusSetRuleDescriptor] = []
        if !appName.isEmpty {
            rules.append(FocusSetRuleDescriptor(scope: .include, kind: .application, pattern: appName))
        }
        if !domain.isEmpty {
            rules.append(FocusSetRuleDescriptor(scope: .include, kind: .domain, pattern: domain))
        }
        if !pathPrefix.isEmpty {
            rules.append(FocusSetRuleDescriptor(scope: .include, kind: .pathPrefix, pattern: pathPrefix))
        }
        return rules
    }

    var excludedRules: [FocusSetRuleDescriptor] {
        var rules: [FocusSetRuleDescriptor] = []
        if !excludedDomain.isEmpty {
            rules.append(FocusSetRuleDescriptor(scope: .exclude, kind: .domain, pattern: excludedDomain))
        }
        if !excludedPathPrefix.isEmpty {
            rules.append(FocusSetRuleDescriptor(scope: .exclude, kind: .pathPrefix, pattern: excludedPathPrefix))
        }
        return rules
    }

    /// Rules that still add information after the row title has represented a complete scope.
    /// For example, a title of “Google Chrome” should not expand into “Application Google Chrome”.
    var sidebarIncludedRules: [FocusSetRuleDescriptor] {
        titleRepresentsIncludedScope ? [] : includedRules
    }

    var sidebarExcludedRules: [FocusSetRuleDescriptor] {
        titleRepresentsExcludedScope ? [] : excludedRules
    }

    var hasSidebarRuleDetails: Bool {
        !sidebarIncludedRules.isEmpty || !sidebarExcludedRules.isEmpty
    }

    /// Summarizes only the conditions that are not already expressed by the row title.
    var sidebarScopeSummary: String? {
        let included = sidebarIncludedRules.isEmpty ? nil : includedScopeName
        let excluded = sidebarExcludedRules.isEmpty ? nil : excludedScopeName
        switch (included, excluded) {
        case let (.some(included), .some(excluded)):
            return String(localized: "\(included). Hide \(excluded).")
        case let (.some(included), .none):
            return included
        case let (.none, .some(excluded)):
            return String(localized: "Hide \(excluded)")
        case (.none, .none):
            return nil
        }
    }

    // MARK: Private

    private var titleRepresentsIncludedScope: Bool {
        guard let includedScopeName else {
            return false
        }
        return displayName == includedScopeName
    }

    private var titleRepresentsExcludedScope: Bool {
        guard let excludedScopeName else {
            return false
        }
        return displayName == String(localized: "Hide \(excludedScopeName)")
    }

    private var usesGeneratedName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [String(localized: "New Focus Set"), "New Focus Set"]
        return candidates.contains { baseName in
            if trimmed == baseName {
                return true
            }
            let numberedPrefix = baseName + " "
            guard trimmed.hasPrefix(numberedPrefix) else {
                return false
            }
            let suffix = trimmed.dropFirst(numberedPrefix.count)
            return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
        }
    }

    private var includedScopeName: String? {
        let target: String? = if !domain.isEmpty {
            pathPrefix.isEmpty ? domain : domain + pathPrefix
        } else if !pathPrefix.isEmpty {
            pathPrefix
        } else {
            nil
        }

        switch (appName.isEmpty ? nil : appName, target) {
        case let (.some(application), .some(target)):
            return String(localized: "\(application) on \(target)")
        case let (.some(application), .none):
            return application
        case let (.none, .some(target)):
            return target
        case (.none, .none):
            return nil
        }
    }

    private var excludedScopeName: String? {
        switch (excludedDomain.isEmpty ? nil : excludedDomain,
                excludedPathPrefix.isEmpty ? nil : excludedPathPrefix)
        {
        case let (.some(domain), .some(path)):
            return String(localized: "\(domain) and paths under \(path)")
        case let (.some(domain), .none):
            return domain
        case let (.none, .some(path)):
            return String(localized: "paths under \(path)")
        case (.none, .none):
            return nil
        }
    }
}

// MARK: - FocusSetRuleDescriptor

struct FocusSetRuleDescriptor: Identifiable, Equatable {
    enum Scope: String {
        case include
        case exclude
    }

    enum Kind: String {
        case application
        case domain
        case pathPrefix
    }

    let scope: Scope
    let kind: Kind
    let pattern: String

    var id: String {
        "\(scope.rawValue):\(kind.rawValue):\(pattern)"
    }
}

// MARK: - FocusSetPersistence

enum FocusSetPersistence {
    static func load() -> [FocusSet] {
        guard !RockxyIdentity.isRunningTests,
              let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([FocusSet].self, from: data) else
        {
            return []
        }
        return values
    }

    static func save(_ focusSets: [FocusSet]) {
        guard !RockxyIdentity.isRunningTests,
              let data = try? JSONEncoder().encode(focusSets) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let storageKey = RockxyIdentity.current.defaultsKey("focusNavigator.focusSets")
}

// MARK: - MutedTrafficSource

enum MutedTrafficSource: Hashable, Identifiable {
    case host(String)
    case pathPrefix(String)

    var id: String {
        switch self {
        case let .host(value): "host:\(value)"
        case let .pathPrefix(value): "path:\(value)"
        }
    }

    var title: String {
        switch self {
        case let .host(value), let .pathPrefix(value): value
        }
    }

    var systemImage: String {
        switch self {
        case .host: "network.slash"
        case .pathPrefix: "eye.slash"
        }
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case let .host(value):
            DomainGrouping.host(transaction.request.host, matchesDomain: value)
        case let .pathPrefix(value):
            DomainGrouping.path(transaction.request.path, matchesPrefix: value)
        }
    }
}
