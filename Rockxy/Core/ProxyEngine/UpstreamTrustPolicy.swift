import Foundation
import NIOSSL
import os

// Decides how strictly upstream server certificates are validated during HTTPS interception.

// MARK: - UpstreamTrustPolicy

/// Rockxy verifies upstream certificates against the system trust store by default, so a
/// forged origin cannot hide behind the proxy. Staging and internal servers often run on
/// self-signed or private-CA certificates that only the mobile app trusts; the opt-in
/// policy lets those connections be decrypted instead of failing the handshake. It is a
/// user-visible setting (Settings > Tools) and never changes the client-facing certificate.
enum UpstreamTrustPolicy {
    /// The UserDefaults key matching the `@AppStorage` toggle in ToolsSettingsTab.
    static let userDefaultsKey = RockxyIdentity.current.defaultsKey("acceptUntrustedUpstreamCertificates")

    /// `true` when the user chose to accept upstream certificates that fail validation.
    nonisolated static var acceptsUntrustedCertificates: Bool {
        if let override = overrideStorage.withLock({ $0 }) {
            return override
        }
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Test seam: pins the policy for this process so parallel test processes that share the
    /// defaults domain cannot flip each other's upstream verification mid-handshake.
    nonisolated static func setOverrideForTesting(_ value: Bool?) {
        overrideStorage.withLock { $0 = value }
    }

    private static let overrideStorage = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// The verification mode to apply to a client TLS configuration under the current policy.
    nonisolated static func certificateVerification(acceptingUntrusted: Bool) -> CertificateVerification {
        acceptingUntrusted ? .none : .fullVerification
    }
}
