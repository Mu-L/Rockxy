import Foundation
import Observation
import Security

// MARK: - BabylonPairingCredentialStorage

protocol BabylonPairingCredentialStorage: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
}

// MARK: - BabylonKeychainPairingCredentialStorage

struct BabylonKeychainPairingCredentialStorage: BabylonPairingCredentialStorage {
    // MARK: Internal

    func load() throws -> String? {
        guard let data = try KeychainHelper.loadSecureData(service: service, account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        try KeychainHelper.saveSecureData(Data(token.utf8), service: service, account: account)
    }

    // MARK: Private

    private let service = "\(RockxyIdentity.current.familyNamespace).babylon"
    private let account = "pairing-token-v1"
}

// MARK: - BabylonEphemeralPairingCredentialStorage

/// Keeps the app-hosted XCTest process away from the user's production Keychain.
///
/// SwiftUI constructs every declared window while the test host is attaching, including the
/// Babylon windows. Reading the login Keychain from that construction path can wait for Keychain
/// UI before XCTest has completed its handshake, leaving the entire test run stuck at
/// `AcquiredPID`. Tests that exercise persistence inject their own storage explicitly.
private struct BabylonEphemeralPairingCredentialStorage: BabylonPairingCredentialStorage {
    func load() throws -> String? {
        nil
    }

    func save(_: String) throws {
        // Intentionally ephemeral in the app-hosted test process.
    }
}

// MARK: - BabylonPairingStore

@MainActor @Observable
final class BabylonPairingStore {
    // MARK: Lifecycle

    init(storage: (any BabylonPairingCredentialStorage)? = nil) {
        let resolvedStorage: any BabylonPairingCredentialStorage = storage ?? Self.defaultStorage()
        self.storage = resolvedStorage
        do {
            let storedToken = try resolvedStorage.load()
            let resolvedToken = try storedToken.flatMap(Self.validToken) ?? Self.generateToken()
            if resolvedToken != storedToken {
                try resolvedStorage.save(resolvedToken)
            }
            token = resolvedToken
            snapshot.update(resolvedToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Internal

    static let shared = BabylonPairingStore()

    private(set) var token = ""
    private(set) var errorMessage: String?

    nonisolated func currentToken() -> String {
        snapshot.value
    }

    func regenerate() {
        do {
            let replacement = try Self.generateToken()
            try storage.save(replacement)
            token = replacement
            snapshot.update(replacement)
            errorMessage = nil
            NotificationCenter.default.post(name: .babylonPairingTokenDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    private final class TokenSnapshot: @unchecked Sendable {
        // MARK: Internal

        var value: String {
            lock.withLock { token }
        }

        func update(_ value: String) {
            lock.withLock { token = value }
        }

        // MARK: Private

        private let lock = NSLock()
        private var token = ""
    }

    private let storage: any BabylonPairingCredentialStorage
    private let snapshot = TokenSnapshot()

    private static func defaultStorage() -> any BabylonPairingCredentialStorage {
        if RockxyIdentity.isRunningTests {
            return BabylonEphemeralPairingCredentialStorage()
        }
        return BabylonKeychainPairingCredentialStorage()
    }

    private static func generateToken() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else {
            throw BabylonPairingStoreError.randomGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func validToken(_ token: String) -> String? {
        guard token.utf8.count == 64,
              token.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
              }) else
        {
            return nil
        }
        return token
    }
}

// MARK: - BabylonPairingStoreError

enum BabylonPairingStoreError: LocalizedError {
    case randomGenerationFailed(OSStatus)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .randomGenerationFailed(status):
            "Could not generate a Babylon pairing token (\(status))."
        }
    }
}

extension Notification.Name {
    static let babylonPairingTokenDidChange = RockxyIdentity.current.notificationName("babylonPairingTokenDidChange")
}
