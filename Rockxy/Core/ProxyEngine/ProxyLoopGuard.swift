import Foundation

// Detects requests whose destination is Rockxy's own listener.

// MARK: - ProxyLoopGuard

/// A request aimed at the proxy's own listen port would be forwarded back into the proxy,
/// creating a new connection and transaction on every hop until the per-destination
/// connection cap trips. Rejecting it at the first hop keeps a misconfigured client, a Map
/// Remote rule pointing at Rockxy, or a hostile request from amplifying into dozens of rows.
enum ProxyLoopGuard {
    /// `true` when `host:port` resolves to the listener that accepted the connection.
    /// `proxyHost` is the local address the client connected to; `localAddresses` are the
    /// machine's other interface addresses (a device on the LAN can name the Mac by IP).
    nonisolated static func targetsOwnListener(
        host: String,
        port: Int,
        proxyPort: Int,
        proxyHost: String?,
        localAddresses: [String] = RootCADownloadServer.lanIPv4Addresses()
    )
        -> Bool
    {
        guard port == proxyPort else {
            return false
        }
        let normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !normalized.isEmpty else {
            return false
        }
        if HostPatternMatcher.isLocalhost(normalized) || normalized == "0.0.0.0" || normalized == "::" {
            return true
        }
        if let proxyHost,
           normalized == proxyHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        {
            return true
        }
        return localAddresses.contains { $0.lowercased() == normalized }
    }
}
