import Foundation

/// The authored matching intent a Map Local directory rule needs to resolve the
/// request subpath. Threading this instead of a compiled regex string lets the
/// resolver reproduce the exact suffix the editor implied when the rule was saved.
struct MapLocalMatchContext: Sendable, Equatable {
    // MARK: Lifecycle

    init(
        authoredPattern: String?,
        compiledURLPattern: String?,
        matchType: RuleMatchType?,
        includeSubpaths: Bool?
    ) {
        self.authoredPattern = authoredPattern
        self.compiledURLPattern = compiledURLPattern
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
    }

    init(matchCondition: RuleMatchCondition) {
        authoredPattern = matchCondition.sourceURLPattern ?? matchCondition.urlPattern
        compiledURLPattern = matchCondition.urlPattern
        matchType = matchCondition.matchType
        includeSubpaths = matchCondition.includeSubpaths
    }

    // MARK: Internal

    /// The human-authored pattern (e.g. `https://cdn.example.com/static/*`) when the
    /// editor persisted it, otherwise the stored `urlPattern`.
    let authoredPattern: String?
    /// The compiled regex `urlPattern` kept for legacy rules that carry no authored
    /// metadata.
    let compiledURLPattern: String?
    let matchType: RuleMatchType?
    let includeSubpaths: Bool?
}
