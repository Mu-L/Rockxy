import Foundation

/// Testable helper that builds breakpoint editor context from transaction or domain quick-create entrypoints.
enum BreakpointEditorContextBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> BreakpointEditorContext {
        let host = transaction.request.host
        let patternHost = wildcardHost(host)
        let normalizedPath = normalizePath(transaction.request.path)
        let method = transaction.request.method.uppercased()

        let httpMethod = HTTPMethodFilter.allCases.first {
            $0.rawValue == method
        } ?? .any

        return BreakpointEditorContext(
            origin: .selectedTransaction,
            suggestedName: "Breakpoint — \(method) \(host)\(normalizedPath)",
            sourceURL: transaction.request.url,
            sourceHost: host,
            sourcePath: normalizedPath,
            sourceMethod: method,
            defaultPattern: "*://\(patternHost)\(normalizedPath)",
            defaultMatchType: .wildcard,
            httpMethod: httpMethod,
            includeSubpaths: false,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    static func fromDomain(_ domain: String) -> BreakpointEditorContext {
        let patternHost = wildcardHost(domain)
        return BreakpointEditorContext(
            origin: .domainQuickCreate,
            suggestedName: "Breakpoint — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil,
            defaultPattern: "*://\(patternHost)/*",
            defaultMatchType: .wildcard,
            httpMethod: .any,
            includeSubpaths: false,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private static func wildcardHost(_ host: String) -> String {
        let colonCount = host.count(where: { $0 == ":" })
        guard colonCount > 1, !host.hasPrefix("[") else {
            return host
        }
        return "[\(host)]"
    }
}
