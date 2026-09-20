import NIOHTTP1
import os

/// Shared header mutation logic used by HTTPProxyHandler, HTTPSProxyRelayHandler,
/// and UpstreamResponseHandler. Preserves existing header order except where
/// remove/replace intentionally changes it.
///
/// Operations that would produce an unencodable header — a name that is not an RFC 7230
/// token, or a value carrying CR/LF/NUL — are skipped with a warning instead of being
/// written. NIO rejects such headers at encode time, which closes the connection and
/// leaves the client with an empty reply and no indication that a rule was the cause.
enum HeaderMutator {
    // MARK: Internal

    /// Apply a list of header operations to Rockxy's `[HTTPHeader]` model (request-side).
    /// Operations are applied in order — later operations can overwrite earlier ones.
    static func apply(_ operations: [HeaderOperation], to headers: inout [HTTPHeader]) {
        for op in operations where isApplicable(op) {
            switch op.type {
            case .add:
                if let value = op.headerValue {
                    headers.append(HTTPHeader(name: op.headerName, value: value))
                }
            case .remove:
                headers.removeAll { $0.name.lowercased() == op.headerName.lowercased() }
            case .replace:
                headers.removeAll { $0.name.lowercased() == op.headerName.lowercased() }
                if let value = op.headerValue {
                    headers.append(HTTPHeader(name: op.headerName, value: value))
                }
            }
        }
    }

    /// Apply a list of header operations to NIO `HTTPHeaders` (response-side).
    /// Operations are applied in order — later operations can overwrite earlier ones.
    static func apply(_ operations: [HeaderOperation], to headers: inout HTTPHeaders) {
        for op in operations where isApplicable(op) {
            switch op.type {
            case .add:
                if let value = op.headerValue {
                    headers.add(name: op.headerName, value: value)
                }
            case .remove:
                headers.remove(name: op.headerName)
            case .replace:
                headers.remove(name: op.headerName)
                if let value = op.headerValue {
                    headers.add(name: op.headerName, value: value)
                }
            }
        }
    }

    /// Whether an operation can be written to the wire. Removals only need a token name;
    /// additions and replacements also need a control-character-free value.
    static func isApplicable(_ operation: HeaderOperation) -> Bool {
        guard BreakpointRequestData.isValidHTTPHeaderName(operation.headerName) else {
            logger.warning("Skipped header operation with an invalid header name")
            return false
        }
        if operation.type != .remove, let value = operation.headerValue,
           !BreakpointRequestData.isValidHTTPHeaderValue(value)
        {
            logger.warning("Skipped header operation with a control character in its value")
            return false
        }
        return true
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HeaderMutator"
    )
}
