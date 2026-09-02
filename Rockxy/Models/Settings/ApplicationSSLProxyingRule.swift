import Crypto
import Foundation

// MARK: - ClientApplicationIdentity

/// A stable, privacy-preserving identity for the local application that originated a
/// proxied connection. Preferred identity is a bundle identifier resolved from a running
/// application or an owning `.app` bundle; when no bundle identity is available the fallback
/// is a deterministic digest of the normalized executable path so no raw personal filesystem
/// path is ever persisted or logged.
///
/// Matching is always performed on `identifier` (stable), never on `displayName`.
struct ClientApplicationIdentity: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bundle
        case executable
    }

    /// The stable identifier used for rule matching. For `.bundle` identities this is the
    /// bundle identifier; for `.executable` identities it is `exec:<sha256(normalizedPath)>`.
    let identifier: String
    let displayName: String
    let kind: Kind
    let bundleIdentifier: String?

    /// Builds a bundle-backed identity. The bundle identifier is the matching key.
    static func bundle(identifier: String, displayName: String) -> ClientApplicationIdentity {
        ClientApplicationIdentity(
            identifier: identifier,
            displayName: displayName.isEmpty ? identifier : displayName,
            kind: .bundle,
            bundleIdentifier: identifier
        )
    }

    /// Builds an executable-backed identity keyed to a SHA-256 digest of the normalized path.
    /// The raw path is never stored — only its digest and a human-readable display name.
    static func executable(normalizedPath: String, displayName: String) -> ClientApplicationIdentity {
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return ClientApplicationIdentity(
            identifier: "exec:\(hex)",
            displayName: displayName.isEmpty ? "exec:\(hex.prefix(12))" : displayName,
            kind: .executable,
            bundleIdentifier: nil
        )
    }

    /// Returns the outermost owning `.app` bundle path for an executable path. Helper
    /// executables live in nested `.app` bundles (e.g. `Foo.app/…/Foo Helper.app/…/Foo Helper`);
    /// the reliable owning application is the *first* (outermost) `.app` in the path.
    static func outerAppBundlePath(forExecutablePath path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return nil
        }
        var bundlePath = String(path[path.startIndex ..< range.upperBound])
        if bundlePath.hasSuffix("/") {
            bundlePath.removeLast()
        }
        return bundlePath
    }

    /// Derives a display name from an `.app` bundle path (basename without extension).
    static func appName(fromBundlePath path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

// MARK: - ApplicationSSLProxyingRule

/// An application-scoped SSL proxying rule. Mirrors `SSLProxyingRule`'s Include (Decrypt) vs
/// Exclude (Tunnel) semantics, but matches against a resolved `ClientApplicationIdentity`
/// rather than a hostname. Matching uses the stable `applicationIdentifier`.
struct ApplicationSSLProxyingRule: Codable, Identifiable, Hashable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        applicationIdentifier: String,
        displayName: String,
        bundleIdentifier: String? = nil,
        isEnabled: Bool = true,
        listType: SSLProxyingListType = .include
    ) {
        self.id = id
        self.applicationIdentifier = applicationIdentifier
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.isEnabled = isEnabled
        self.listType = listType
    }

    init(identity: ClientApplicationIdentity, isEnabled: Bool = true, listType: SSLProxyingListType = .include) {
        self.init(
            applicationIdentifier: identity.identifier,
            displayName: identity.displayName,
            bundleIdentifier: identity.bundleIdentifier,
            isEnabled: isEnabled,
            listType: listType
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        applicationIdentifier = try container.decode(String.self, forKey: .applicationIdentifier)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? applicationIdentifier
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        listType = try container.decodeIfPresent(SSLProxyingListType.self, forKey: .listType) ?? .include
    }

    // MARK: Internal

    let id: UUID
    var applicationIdentifier: String
    var displayName: String
    var bundleIdentifier: String?
    var isEnabled: Bool
    var listType: SSLProxyingListType

    /// Matches on the stable identifier, never the display name.
    func matches(_ identity: ClientApplicationIdentity) -> Bool {
        applicationIdentifier == identity.identifier
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case id
        case applicationIdentifier
        case displayName
        case bundleIdentifier
        case isEnabled
        case listType
    }
}
