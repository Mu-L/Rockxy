import Foundation

// MARK: - AdvancedProxySettingsDraft

/// Pure, validated snapshot of the proxy listener configuration edited in the
/// Advanced Proxy Settings window. Kept separate from `AppSettings` so the window
/// can present explicit Cancel / Apply / Restore Defaults semantics and reject an
/// invalid port before it ever reaches persisted storage.
///
/// The listener fields covered here are the *next-start* configuration: applying
/// them persists new values, but a running proxy keeps its live endpoint until it
/// restarts. The view is responsible for surfacing that distinction.
///
/// IPv6 dual-stack is intentionally not modeled here — the proxy binds a single
/// IPv4 address, so exposing an IPv6 control would be dishonest. `AppSettings`
/// still stores `listenIPv6` for compatibility; ``applied(to:changedFrom:)``
/// preserves whatever value is already persisted.
struct AdvancedProxySettingsDraft: Equatable {
    // MARK: Lifecycle

    init(
        portText: String = "\(Self.defaultPort)",
        autoSelectPort: Bool = true,
        onlyListenOnLocalhost: Bool = true
    ) {
        self.portText = portText
        self.autoSelectPort = autoSelectPort
        self.onlyListenOnLocalhost = onlyListenOnLocalhost
    }

    init(settings: AppSettings) {
        self.init(
            portText: "\(settings.proxyPort)",
            autoSelectPort: settings.autoSelectPort,
            onlyListenOnLocalhost: settings.onlyListenOnLocalhost
        )
    }

    // MARK: Internal

    static let defaultPort = 9_090
    static let minPort = 1
    static let maxPort = 65_535

    /// The listener configuration Rockxy ships with.
    static let `default` = AdvancedProxySettingsDraft()

    var portText: String
    var autoSelectPort: Bool
    var onlyListenOnLocalhost: Bool

    /// The parsed port, or `nil` when the text is not a valid 1–65535 integer.
    var parsedPort: Int? {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        guard (Self.minPort ... Self.maxPort).contains(value) else {
            return nil
        }
        return value
    }

    var isPortValid: Bool {
        parsedPort != nil
    }

    /// Applying is only possible with a valid port.
    var canApply: Bool {
        isPortValid
    }

    /// The listen address implied by `onlyListenOnLocalhost`.
    var effectiveListenAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }

    /// Returns `settings` with only the listener fields the user actually changed
    /// (relative to `baseline`) overwritten, or `nil` when the port is invalid so
    /// callers can never persist a bad configuration.
    ///
    /// Merging against the baseline means a listener field changed elsewhere while
    /// this window was open is not blindly overwritten by an unrelated edit here.
    /// `listenIPv6` is never touched, preserving stored compatibility.
    func applied(to settings: AppSettings, changedFrom baseline: AdvancedProxySettingsDraft) -> AppSettings? {
        guard let port = parsedPort else {
            return nil
        }
        var updated = settings
        if parsedPort != baseline.parsedPort {
            updated.proxyPort = port
        }
        if autoSelectPort != baseline.autoSelectPort {
            updated.autoSelectPort = autoSelectPort
        }
        if onlyListenOnLocalhost != baseline.onlyListenOnLocalhost {
            updated.onlyListenOnLocalhost = onlyListenOnLocalhost
        }
        return updated
    }
}
