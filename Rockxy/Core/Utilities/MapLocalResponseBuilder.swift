import Foundation
import os

/// Builds the response headers a Map Local rule serves. Shared by the plain-HTTP and
/// intercepted-HTTPS handlers so both apply identical sanitization and framing rules.
///
/// Guarantees:
/// - `Content-Length` is always recomputed from the served bytes; a persisted value is
///   never trusted.
/// - `Content-Type` uses the configured header when present, otherwise MIME inference.
/// - Hop-by-hop and framing headers are dropped; header-name/value CRLF injection is
///   rejected. Useful end-to-end headers (including repeated `Set-Cookie`) are preserved.
enum MapLocalResponseBuilder {
    // MARK: Internal

    /// Constructs the final response header list for a Map Local response.
    /// - Parameters:
    ///   - configured: Headers the user authored on the rule.
    ///   - bodyByteCount: The exact number of bytes being served.
    ///   - inferredContentType: MIME type inferred from the served file, used only when the
    ///     configured headers do not already specify a `Content-Type`.
    static func responseHeaders(
        configured: [HTTPHeader],
        bodyByteCount: Int,
        inferredContentType: String
    )
        -> [HTTPHeader]
    {
        var result: [HTTPHeader] = []
        var hasContentType = false

        for header in configured {
            guard let sanitized = sanitize(header) else {
                logger.warning("SECURITY: Dropped invalid Map Local response header")
                continue
            }
            if isFramingOrHopByHop(sanitized.name) {
                continue
            }
            if sanitized.name.caseInsensitiveCompare("Content-Type") == .orderedSame {
                hasContentType = true
            }
            result.append(sanitized)
        }

        if !hasContentType {
            result.append(HTTPHeader(name: "Content-Type", value: inferredContentType))
        }
        // Always recomputed — a persisted Content-Length is never trusted.
        result.append(HTTPHeader(name: "Content-Length", value: "\(bodyByteCount)"))
        return result
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MapLocalResponseBuilder"
    )

    /// Hop-by-hop headers (RFC 7230 §6.1) plus response framing headers Rockxy owns.
    /// These must never be copied from an authored rule onto the served response.
    private static let disallowedHeaderNames: Set<String> = [
        "content-length",
        "transfer-encoding",
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "upgrade",
    ]

    private static func isFramingOrHopByHop(_ name: String) -> Bool {
        disallowedHeaderNames.contains(name.lowercased())
    }

    /// Validates a single authored header. Returns `nil` when the name is not a valid RFC
    /// 7230 token or the name/value carries CR/LF (header-injection) or control characters.
    private static func sanitize(_ header: HTTPHeader) -> HTTPHeader? {
        let name = header.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, isValidHeaderName(name) else {
            return nil
        }
        guard isValidHeaderValue(header.value) else {
            return nil
        }
        return HTTPHeader(name: name, value: header.value)
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        // RFC 7230 token: no separators, no control characters, no CR/LF.
        let separators = Set("()<>@,;:\\\"/[]?={} \t")
        for scalar in name.unicodeScalars {
            if scalar.value <= 0x20 || scalar.value == 0x7F {
                return false
            }
            if separators.contains(Character(scalar)) {
                return false
            }
        }
        return true
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        // Reject every C0 control (0x00–0x1F) except horizontal tab (0x09), and reject
        // DEL (0x7F). This covers CR/LF (response splitting) and NUL while blocking other
        // control bytes; horizontal tab and printable bytes (including obs-text) are allowed.
        for scalar in value.unicodeScalars {
            if scalar.value == 0x09 {
                continue
            }
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return false
            }
        }
        return true
    }
}
