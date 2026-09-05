import Foundation
import Security

// Shared rules for installing a Rockxy root CA certificate and its admin trust settings. The
// privileged helper owns the Security.framework side effects; everything that decides *what* is
// installed, in which order, and when an installation counts as done lives here so it can be
// exercised without a System keychain, a trusted CA, or the real daemon.
//
// The defining property is that installation is non-destructive. It adds and it trusts; it never
// deletes, never sweeps a label, and never rolls anything back. A previously installed root — this
// app's older one, or somebody else's — survives every outcome, including a failed add, a refused
// trust write, and a postcondition that does not hold.

// MARK: - CertificateAddOutcome

/// What the keychain reported for one add attempt.
///
/// `duplicate` is deliberately not "installed": `errSecDuplicateItem` says an item that collides
/// on the primary key already exists, which is not the same claim as "exactly these bytes are
/// present". Only an exact-DER read decides that, and it runs for both outcomes.
enum CertificateAddOutcome: Equatable {
    case added
    case duplicate
}

// MARK: - RootCertificateInstallOperations

/// The privileged keychain and trust-settings work an installation needs.
///
/// Every method is scoped to one keychain (`System.keychain` in production) and the `.admin`
/// trust domain. Nothing here can delete: the protocol has no removal member, so an installation
/// cannot destroy a certificate even by mistake.
protocol RootCertificateInstallOperations {
    /// Installed candidates narrowed by the indexed serial number. An unknown status or a result
    /// whose shape cannot be read throws — it must never be reported as "nothing is installed".
    ///
    /// Shares its signature with `RootCertificateRemovalOperations` so one adapter can implement
    /// both without duplicating the discovery rules.
    func systemCertificates(serialNumber: Data) throws -> [SystemKeychainCertificate]

    /// Adds exactly these bytes under `label`, without removing anything first.
    func addCertificate(derData: Data, label: String) throws -> CertificateAddOutcome

    /// Whether the `.admin` domain records *positive* trust for exactly this certificate.
    ///
    /// A deny and an unspecified result are "no"; an unreadable result throws. Presence of settings is
    /// not the question — `RootCertificateRemovalOperations.hasAdminTrustSettings` asks that one,
    /// and answering it here would let a deny pass as a successful installation.
    func hasPositiveAdminTrustSettings(derData: Data) throws -> Bool

    /// Records `.admin` trustRoot settings for exactly this certificate, or throws.
    func setAdminTrustRoot(derData: Data) throws
}

// MARK: - RootCertificateInstallError

enum RootCertificateInstallError: LocalizedError, Equatable {
    case certificateNotInstalledAfterAdd(fingerprint: String)
    case duplicateCertificateAbsent(fingerprint: String)
    case certificateAbsentAfterTrustSettings(fingerprint: String)
    case trustNotAppliedAfterInstall(fingerprint: String)
    case keychainFailure(operation: String, status: OSStatus)
    case malformedKeychainResult(operation: String)
    case labelReadbackMismatch
    case trustWriteFailed(detail: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .certificateNotInstalledAfterAdd(fingerprint):
            "Certificate \(fingerprint) is not installed after the keychain reported a successful add"
        case let .duplicateCertificateAbsent(fingerprint):
            "The keychain reported a duplicate item, but certificate \(fingerprint) is not installed"
        case let .certificateAbsentAfterTrustSettings(fingerprint):
            "Certificate \(fingerprint) is no longer installed after its trust settings were applied"
        case let .trustNotAppliedAfterInstall(fingerprint):
            "Trust settings for certificate \(fingerprint) were not applied"
        case let .keychainFailure(operation, status):
            "Keychain \(operation) failed: OSStatus \(status)"
        case let .malformedKeychainResult(operation):
            "Keychain \(operation) returned an unreadable result"
        case .labelReadbackMismatch:
            "The imported certificate could not be labeled"
        case let .trustWriteFailed(detail):
            "Failed to set trust settings: \(detail)"
        }
    }
}

// MARK: - RootCertificateInstaller

/// Installs exactly one Rockxy root CA certificate, identified by its DER bytes, and records
/// admin trust for it.
///
/// Two properties are the point:
///
/// - **Nothing is removed.** Earlier roots this app installed, and roots it did not, are all still
///   there afterwards. A reinstall therefore never "cleans up" historical certificates as a side
///   effect; that is an explicit, separate operation.
/// - **Every step is verified by the bytes.** A successful `SecItemAdd` and an `errSecDuplicateItem`
///   are both followed by an exact-DER read, and the trust write is followed by a positive-trust
///   read. A status code is a report, not a postcondition.
enum RootCertificateInstaller {
    // MARK: Internal

    /// What one installation actually did.
    struct InstallOutcome: Equatable {
        /// False when the exact certificate was already installed.
        let addedCertificate: Bool
        /// False when positive admin trust already existed, so no trust write was attempted.
        let appliedTrustSettings: Bool
    }

    /// Installs and trusts exactly the certificate described by `derData`.
    ///
    /// A partial failure leaves whatever succeeded in place and reports the truth: a certificate
    /// that was added but could not be trusted stays installed and untrusted rather than being
    /// deleted to make the failure look tidy. The caller decides what to tell the user, and the
    /// app's own `SecTrust` evaluation — not this metadata check — is the final word on trust.
    @discardableResult
    static func installTrustedRoot(
        derData: Data,
        label: String,
        using operations: some RootCertificateInstallOperations
    )
        throws -> InstallOutcome
    {
        // Nothing is written before the bytes are known to describe a certificate this helper
        // owns, so malformed, oversized, and unrelated input can never reach a privileged add or
        // a trust write.
        let target = try RootCertificateRemover.validate(derData: derData)

        // Refuse an unreadable keychain or trust domain before even an additive mutation.
        // Postconditions below still re-read after each operation; this is not a cached verdict.
        _ = try isInstalled(target, using: operations)
        _ = try operations.hasPositiveAdminTrustSettings(derData: target.derData)
        let addOutcome = try operations.addCertificate(derData: target.derData, label: label)

        guard try isInstalled(target, using: operations) else {
            throw addOutcome == .duplicate
                ? RootCertificateInstallError.duplicateCertificateAbsent(fingerprint: target.fingerprint)
                : RootCertificateInstallError.certificateNotInstalledAfterAdd(fingerprint: target.fingerprint)
        }

        var appliedTrustSettings = false
        if try !operations.hasPositiveAdminTrustSettings(derData: target.derData) {
            try operations.setAdminTrustRoot(derData: target.derData)
            appliedTrustSettings = true
        }

        // Both postconditions are re-read here, including on the path that wrote nothing at all.
        // Settings may exist and still not be trust — a deny, or an entry nothing can read — so
        // reporting the write's exit status as success is how a root macOS does not trust gets
        // presented as installed.
        guard try operations.hasPositiveAdminTrustSettings(derData: target.derData) else {
            throw RootCertificateInstallError.trustNotAppliedAfterInstall(fingerprint: target.fingerprint)
        }
        // Trust settings are stored independently of the keychain item, and `add-trusted-cert`
        // rewrites that item. Positive trust for bytes that are no longer installed is not an
        // installation, so the exact DER is proved present once more before this returns.
        guard try isInstalled(target, using: operations) else {
            throw RootCertificateInstallError.certificateAbsentAfterTrustSettings(fingerprint: target.fingerprint)
        }

        return InstallOutcome(
            addedCertificate: addOutcome == .added,
            appliedTrustSettings: appliedTrustSettings
        )
    }

    // MARK: Private

    /// Whether the installed items include exactly the target's bytes.
    ///
    /// The serial number is only an index: another issuer can mint a certificate with the same
    /// serial, so the DER comparison is what decides.
    private static func isInstalled(
        _ target: RootCertificateRemover.Target,
        using operations: some RootCertificateInstallOperations
    )
        throws -> Bool
    {
        try operations.systemCertificates(serialNumber: target.serialNumber)
            .contains { $0.derData == target.derData }
    }
}
