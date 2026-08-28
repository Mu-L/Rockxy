import Foundation

// MARK: - GitHubHTTPDataLoading

protocol GitHubHTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession + GitHubHTTPDataLoading

extension URLSession: GitHubHTTPDataLoading {}

// MARK: - GitHubAuthService

struct GitHubAuthService: Sendable {
    // MARK: Lifecycle

    init(httpClient: any GitHubHTTPDataLoading = URLSession.shared) {
        self.httpClient = httpClient
    }

    // MARK: Internal

    struct DeviceCode: Decodable, Equatable {
        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }

        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let expiresIn: Int
        let interval: Int
    }

    enum AuthError: LocalizedError, Equatable {
        case clientIDMissing
        case accessDenied
        case expired
        case authorizationPending
        case missingGistScope
        case unexpectedStatus(Int)
        case invalidResponse
        case githubError(String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .clientIDMissing:
                String(localized: "GitHub OAuth is not configured for this build.", bundle: RockxyLocalization.bundle)
            case .accessDenied:
                String(localized: "GitHub authorization was denied.", bundle: RockxyLocalization.bundle)
            case .expired:
                String(localized: "The GitHub authorization code expired.", bundle: RockxyLocalization.bundle)
            case .authorizationPending:
                String(localized: "GitHub authorization is still pending.", bundle: RockxyLocalization.bundle)
            case .missingGistScope:
                String(localized: "The token is missing the required gist scope.", bundle: RockxyLocalization.bundle)
            case let .unexpectedStatus(status):
                String(localized: "GitHub returned HTTP \(status).", bundle: RockxyLocalization.bundle)
            case .invalidResponse:
                String(localized: "GitHub returned an unexpected response.", bundle: RockxyLocalization.bundle)
            case let .githubError(message):
                message
            }
        }
    }

    var configuredOAuthClientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RockxyGitHubOAuthClientID") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }

    func requestDeviceCode(clientID: String, scope: String = "gist") async throws -> DeviceCode {
        let request = try formRequest(
            url: URL(string: "https://github.com/login/device/code"),
            fields: ["client_id": clientID, "scope": scope]
        )
        let (data, response) = try await httpClient.data(for: request)
        try validateHTTP(response)
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    func pollDeviceToken(clientID: String, deviceCode: String) async throws -> GitHubCredential {
        let request = try formRequest(
            url: URL(string: "https://github.com/login/oauth/access_token"),
            fields: [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]
        )
        let (data, response) = try await httpClient.data(for: request)
        try validateHTTP(response)

        if let error = try? JSONDecoder().decode(DevicePollError.self, from: data) {
            throw mappedPollError(error.error)
        }

        let token = try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
        let scopes = token.scope
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard scopes.contains("gist") else {
            throw AuthError.missingGistScope
        }
        return GitHubCredential(
            accessToken: token.accessToken,
            authMethod: .deviceCode,
            scopes: scopes,
            login: nil
        )
    }

    func credentialForPersonalAccessToken(_ token: String) throws -> GitHubCredential {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.invalidResponse
        }
        return GitHubCredential(
            accessToken: trimmed,
            authMethod: .personalAccessToken,
            scopes: ["gist"],
            login: nil
        )
    }

    // MARK: Private

    private struct DeviceTokenResponse: Decodable {
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case scope
        }

        let accessToken: String
        let scope: String
    }

    private struct DevicePollError: Decodable {
        let error: String
    }

    private let httpClient: any GitHubHTTPDataLoading

    private func formRequest(url: URL?, fields: [String: String]) throws -> URLRequest {
        guard let url else {
            throw AuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AuthError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    private func mappedPollError(_ error: String) -> AuthError {
        switch error {
        case "authorization_pending",
             "slow_down":
            .authorizationPending
        case "expired_token":
            .expired
        case "access_denied":
            .accessDenied
        default:
            .githubError(error)
        }
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
