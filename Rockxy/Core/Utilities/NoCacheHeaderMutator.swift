import Foundation
import NIOHTTP1

// Applies anti-cache header mutations when the global no-caching mode is enabled.

// MARK: - NoCacheHeaderMutator

/// Applies anti-cache header mutations when the global "No Caching" toggle is active.
///
/// Requests gain `Cache-Control` and `Pragma` directives and lose their conditional
/// validators (`If-Modified-Since`, `If-None-Match`) so origin servers return fresh
/// responses. Relayed responses lose their freshness/validator headers (`Expires`,
/// `Last-Modified`, `ETag`) and are marked uncacheable, so the client does not serve
/// the next load from its own cache and skip the proxy entirely.
enum NoCacheHeaderMutator {
    /// The UserDefaults key matching the `@AppStorage` toggle in ToolsSettingsTab.
    static let userDefaultsKey = RockxyIdentity.current.defaultsKey("noCaching")

    /// Returns `true` when the user has enabled the No Caching toggle.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Mutates an array of `HTTPHeader` values by injecting anti-cache directives
    /// and removing conditional request headers. Returns the modified array.
    static func apply(to headers: [HTTPHeader]) -> [HTTPHeader] {
        var result = headers.filter {
            $0.name.caseInsensitiveCompare("If-Modified-Since") != .orderedSame
                && $0.name.caseInsensitiveCompare("If-None-Match") != .orderedSame
        }

        result.removeAll { $0.name.caseInsensitiveCompare("Cache-Control") == .orderedSame }
        result.append(HTTPHeader(name: "Cache-Control", value: "no-cache, no-store, must-revalidate"))

        result.removeAll { $0.name.caseInsensitiveCompare("Pragma") == .orderedSame }
        result.append(HTTPHeader(name: "Pragma", value: "no-cache"))

        return result
    }

    /// Response-side counterpart of `apply(to:)`: strips freshness and validator headers
    /// the client would otherwise use to reuse or revalidate the response, then marks it
    /// uncacheable. Applied to the relayed head only, never to WebSocket upgrades.
    static func applyToResponse(_ headers: inout HTTPHeaders) {
        for name in ["Expires", "Last-Modified", "ETag", "Cache-Control", "Pragma"] {
            headers.remove(name: name)
        }
        headers.add(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")
        headers.add(name: "Pragma", value: "no-cache")
        headers.add(name: "Expires", value: "0")
    }
}
