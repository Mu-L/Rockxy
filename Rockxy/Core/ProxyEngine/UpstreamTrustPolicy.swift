import Foundation
import NIOSSL

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
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// The verification mode to apply to a client TLS configuration under the current policy.
    nonisolated static func certificateVerification(acceptingUntrusted: Bool) -> CertificateVerification {
        acceptingUntrusted ? .none : .fullVerification
    }
}
