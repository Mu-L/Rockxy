import Foundation

// MARK: - ExternalProxyProtocolSelection

enum ExternalProxyProtocolSelection: CaseIterable, Hashable, Identifiable {
    case automatic
    case http
    case https
    case socks5

    // MARK: Lifecycle

    init(_ type: UpstreamProxyType) {
        switch type {
        case .automatic:
            self = .automatic
        case .http:
            self = .http
        case .https:
            self = .https
        case .socks5:
            self = .socks5
        }
    }

    // MARK: Internal

    var id: String {
        rawIdentifier
    }

    var rawIdentifier: String {
        switch self {
        case .automatic:
            "automatic"
        case .http:
            "http"
        case .https:
            "https"
        case .socks5:
            "socks5"
        }
    }

    var displayName: String {
        switch self {
        case .automatic:
            String(localized: "Automatic Proxy Configuration", bundle: RockxyLocalization.bundle)
        case .http:
            String(localized: "Web Proxy (HTTP)", bundle: RockxyLocalization.bundle)
        case .https:
            String(localized: "Secure Web Proxy (HTTPS)", bundle: RockxyLocalization.bundle)
        case .socks5:
            String(localized: "SOCKS Proxy", bundle: RockxyLocalization.bundle)
        }
    }

    var proxyType: UpstreamProxyType? {
        switch self {
        case .automatic:
            .automatic
        case .http:
            .http
        case .https:
            .https
        case .socks5:
            .socks5
        }
    }

    func canPersist(using policy: any AppPolicy) -> Bool {
        switch self {
        case .automatic:
            true
        case .socks5:
            policy.upstreamProxyAllowsSOCKS5
        case .http,
             .https:
            true
        }
    }
}

// MARK: - ExternalProxySettingsDraft

struct ExternalProxySettingsDraft: Equatable {
    // MARK: Lifecycle

    init(
        isEnabled: Bool = false,
        selectedProtocol: ExternalProxyProtocolSelection = .http,
        host: String = "",
        portText: String = "8080",
        pacURL: String = "",
        usesAuthentication: Bool = false,
        username: String = "",
        password: String = "",
        hasStoredCredentials: Bool = false,
        storedUsername: String = "",
        bypassText: String = "",
        bypassLocalhost: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.selectedProtocol = selectedProtocol
        self.host = host
        self.portText = portText
        self.pacURL = pacURL
        self.usesAuthentication = usesAuthentication
        self.username = username
        self.password = password
        self.hasStoredCredentials = hasStoredCredentials
        self.storedUsername = storedUsername
        self.bypassText = bypassText
        self.bypassLocalhost = bypassLocalhost
    }

    init(
        configuration: UpstreamProxyConfiguration,
        storedCredentialUsername: String?
    ) {
        let configuredUsername = configuration.username ?? ""
        self.init(
            isEnabled: configuration.isEnabled,
            selectedProtocol: ExternalProxyProtocolSelection(configuration.type),
            host: configuration.host,
            portText: "\(configuration.port)",
            pacURL: configuration.pacURL ?? "",
            usesAuthentication: configuration.hasCredentials,
            username: configuredUsername,
            hasStoredCredentials: storedCredentialUsername != nil,
            storedUsername: storedCredentialUsername ?? "",
            bypassText: configuration.bypassHostPatterns.joined(separator: ", "),
            bypassLocalhost: configuration.bypassLocalhost
        )
    }

    // MARK: Internal

    var isEnabled = false
    var selectedProtocol: ExternalProxyProtocolSelection = .http
    var host = ""
    var portText = "8080"
    var pacURL = ""
    var usesAuthentication = false
    var username = ""
    var password = ""
    var hasStoredCredentials = false
    var storedUsername = ""
    var bypassText = ""
    var bypassLocalhost = true

    var parsedBypassPatterns: [String] {
        var seen: Set<String> = []
        return bypassText
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { pattern in
                !pattern.isEmpty && seen.insert(pattern).inserted
            }
    }

    var bypassEntriesUsed: Int {
        parsedBypassPatterns.count
    }

    var needsReplacementPassword: Bool {
        guard usesAuthentication else {
            return false
        }
        if !hasStoredCredentials {
            return password.isEmpty
        }
        return username != storedUsername && password.isEmpty
    }

    func configuration() throws -> UpstreamProxyConfiguration {
        let type = selectedProtocol.proxyType ?? .http
        let parsedPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return UpstreamProxyConfiguration(
            isEnabled: isEnabled,
            type: type,
            host: host,
            port: parsedPort,
            pacURL: selectedProtocol == .automatic ? pacURL : nil,
            hasCredentials: usesAuthentication && (hasStoredCredentials || !password.isEmpty),
            username: usesAuthentication ? username : nil,
            bypassHostPatterns: parsedBypassPatterns,
            bypassLocalhost: bypassLocalhost
        )
    }

    func credentials() -> UpstreamProxyCredentials? {
        guard usesAuthentication, !password.isEmpty else {
            return nil
        }
        return UpstreamProxyCredentials(username: username, password: password)
    }
}
