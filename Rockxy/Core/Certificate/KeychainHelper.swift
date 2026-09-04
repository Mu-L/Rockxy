import Crypto
import Foundation
import os
import Security

// Implements keychain helper behavior for the certificate and trust pipeline.

// MARK: - KeychainReadOutcome

/// How a Keychain read status must be interpreted when looking for the root CA private key.
/// Only `absent` may advance to the next storage shape or report "no key at all"; every other
/// failure has to propagate, so a locked or otherwise unavailable Keychain can never be
/// mistaken for an absent key and silently rotate the root the user already trusted.
nonisolated enum KeychainReadOutcome: Equatable {
    case found
    case absent
    case failure
}

// MARK: - KeychainHelper

/// Thin wrapper around Security.framework's keychain APIs for storing the root CA
/// private key and installing the root CA certificate. Root key material is stored as a
/// generic-password item in the user's login Keychain.
///
/// Certificate trust uses the `.admin` domain (system-wide) so all TLS clients
/// (Safari, URLSession, system services) honor the trust setting. This requires
/// admin authorization via macOS authentication dialog.
nonisolated enum KeychainHelper {
    // MARK: Internal

    // MARK: - Private Key Operations

    /// Classifies a `SecItemCopyMatching` status for the root CA private key.
    ///
    /// Anything that is not an outright "no such item" describes the Keychain's availability
    /// rather than the key's existence, so it must surface as `failure`. Reading such a status
    /// as absence is what would silently regenerate a trusted root CA.
    ///
    /// - Parameter toleratesMalformedShape: set only for the historical `kSecClassKey` shapes.
    ///   Security.framework rejects that attribute combination outright on some systems, and
    ///   that rejection describes the query shape, not the Keychain, so it means "this shape
    ///   holds nothing".
    static func classifyReadStatus(
        _ status: OSStatus,
        toleratesMalformedShape: Bool = false
    )
        -> KeychainReadOutcome
    {
        if status == errSecSuccess {
            return .found
        }
        if status == errSecItemNotFound {
            return .absent
        }
        if toleratesMalformedShape, status == errSecNoSuchAttr || status == errSecParam {
            return .absent
        }
        return .failure
    }

    /// Stores the serialized root CA private key as generic-password data in the login
    /// Keychain.
    ///
    /// Two earlier shapes are superseded here. A `kSecClassKey` item carrying a raw X9.63 EC
    /// blob and a string `kSecAttrApplicationLabel` is rejected by Security.framework with
    /// `errSecNoSuchAttr`, so the root CA key never actually persisted and every relaunch
    /// generated a new CA. A generic-password item in the login Keychain persists for both
    /// development and Developer ID builds. Do not opt this item into the Data Protection
    /// keychain: the shipped non-sandboxed signing configuration receives
    /// `errSecMissingEntitlement` for that API and would fail certificate initialization.
    ///
    /// The service and account are derived from the same label callers already pass, so the
    /// storage identity stays stable across launches.
    static func savePrivateKey(_ keyData: Data, label: String) throws {
        try writePrivateKeyItem(keyData, label: label)

        // Superseded copies are removed only once the new item has been read back and compared
        // byte for byte. Deleting before that could destroy the only surviving copy of the
        // root CA private key.
        guard try readPrivateKeyItem(label: label, shape: .genericPassword) == keyData else {
            logger.error("Root CA private key readback did not match the value just written")
            throw KeychainError.readbackMismatch
        }

        logger.debug("Saved private key for label: \(label)")
        deleteSupersededPrivateKeyItems(label: label)
    }

    static func loadPrivateKey(label: String) throws -> Data? {
        try loadPrivateKey(label: label, isUsable: { !$0.isEmpty })
    }

    /// Reads the root CA private key, preferring generic-password storage and then falling
    /// through every shape an older build could have written. Anything found in a legacy
    /// shape is migrated before it is returned, so the next launch has a single source of
    /// truth.
    ///
    /// - Parameter isUsable: rejects blobs that cannot produce a working key. An unusable item
    ///   is neither adopted nor deleted — the search simply continues with the remaining
    ///   sources. Reporting `nil` when nothing usable exists lets the caller regenerate exactly
    ///   once instead of failing on every launch.
    static func loadPrivateKey(label: String, isUsable: (Data) -> Bool) throws -> Data? {
        if let data = try readPrivateKeyItem(label: label, shape: .genericPassword) {
            if isUsable(data) {
                return data
            }
            logger.error("Root CA private key in generic-password storage is unusable — trying recovery sources")
        }

        for shape in PrivateKeyShape.migrationSources {
            guard let data = try readPrivateKeyItem(label: label, shape: shape), isUsable(data) else {
                continue
            }

            do {
                try savePrivateKey(data, label: label)
                logger.info("Migrated root CA private key (\(shape.rawValue)) into generic-password storage")
            } catch {
                // The migration source is untouched, so this launch stays usable and the next
                // one retries. Never drop a recoverable key just because the copy failed.
                logger.error("Failed to migrate root CA private key: \(error.localizedDescription)")
            }
            return data
        }

        return nil
    }

    static func deletePrivateKey(label: String) throws {
        var firstFailure: OSStatus?
        let shapes = [PrivateKeyShape.genericPassword] + PrivateKeyShape.migrationSources

        // Reset must cover every shape an older build could have written. Attempt them all
        // even after one failure so a partially cleaned reset cannot resurrect a legacy key
        // on the next launch, then surface the first real Security.framework failure.
        for shape in shapes {
            let status = SecItemDelete(privateKeyQuery(label: label, shape: shape) as CFDictionary)
            let isAbsent = status == errSecItemNotFound
                || (shape.toleratesMalformedShape && (status == errSecNoSuchAttr || status == errSecParam))
            guard status == errSecSuccess || isAbsent else {
                logger.error("Failed to delete private key (\(shape.rawValue)): \(status)")
                if firstFailure == nil {
                    firstFailure = status
                }
                continue
            }
        }

        if let firstFailure {
            throw KeychainError.deleteFailed(firstFailure)
        }
    }

    // MARK: - Generic Secure Data Operations

    static func saveSecureData(_ data: Data, service: String, account: String) throws {
        try deleteSecureData(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save secure data: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadSecureData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Failed to load secure data: \(status)")
            throw KeychainError.loadFailed(status)
        }

        return result as? Data
    }

    static func deleteSecureData(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete secure data: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Certificate Operations

    static func installCertificate(_ certData: Data, label: String) throws {
        try removeCertificate(label: label)

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueData as String: certData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to install certificate: \(status)")
            throw KeychainError.saveFailed(status)
        }

        logger.info("Installed certificate with label: \(label)")
    }

    static func isCertificateInstalled(label: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    static func removeCertificate(label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to remove certificate: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Certificate Trust Operations

    /// Installs the root CA certificate in the login keychain and marks it as a
    /// trusted root for TLS using the admin trust domain (system-wide). This triggers
    /// a macOS authentication dialog — unavoidable by Apple's design, as modifying
    /// admin-level trust settings requires authorization.
    static func installRootCAWithTrust(_ certData: Data, label: String) throws {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            logger.error("Failed to create SecCertificate from DER data")
            throw KeychainError.invalidCertificateData
        }

        // Try to remove existing cert (best-effort — may be in system keychain we can't touch)
        do {
            try removeCertificate(label: label)
        } catch let KeychainError.deleteFailed(status) where status == errSecWrPerm {
            logger.info(
                "Root CA exists in a non-writable keychain; continuing with trust update instead of deleting"
            )
        }

        // Add certificate to the login keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: secCert
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Certificate already exists in another keychain (e.g. system) — this is fine,
            // proceed to apply trust settings to the existing copy
            logger.info("Root CA already in keychain — applying trust settings to existing copy")
        } else if addStatus != errSecSuccess {
            logger.error("Failed to add root CA certificate to login keychain: \(addStatus)")
            throw KeychainError.saveFailed(addStatus)
        }

        // Set trust settings to mark as trusted root CA.
        // Uses .admin domain (system-wide trust) so all TLS clients honor the setting.
        // macOS prompts for admin password to authorize this change.
        let trustSettings: [[String: Any]] = [
            [kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue]
        ]

        let trustStatus = SecTrustSettingsSetTrustSettings(
            secCert,
            .admin,
            trustSettings as CFTypeRef
        )

        guard trustStatus == errSecSuccess else {
            logger.error("Failed to set trust settings: \(trustStatus)")
            throw KeychainError.trustSettingsFailed(trustStatus)
        }

        logger.info("Installed and trusted root CA certificate")

        // Verify trust was actually applied (catches dismissed auth dialog)
        var verifyTrustSettings: CFArray?
        let verifyStatus = SecTrustSettingsCopyTrustSettings(secCert, .admin, &verifyTrustSettings)
        if verifyStatus == errSecSuccess {
            logger.info("Post-install verification: admin trust settings confirmed")
        } else {
            logger.warning(
                "Post-install verification: admin trust settings NOT found (status: \(verifyStatus)) — user may have dismissed auth dialog"
            )
        }
    }

    /// Removes trust settings and the certificate from the keychain.
    static func removeRootCATrust(label: String) throws {
        // Find the SecCertificate reference first for trust removal
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &result)

        if findStatus == errSecSuccess, let secCert = result {
            // swiftlint:disable:next force_cast
            let cert = secCert as! SecCertificate
            let trustStatus = SecTrustSettingsRemoveTrustSettings(cert, .admin)
            if trustStatus != errSecSuccess, trustStatus != errSecItemNotFound {
                logger.warning("Failed to remove trust settings: \(trustStatus)")
            }
        }

        try removeCertificate(label: label)
        logger.info("Removed root CA trust and certificate")
    }

    /// Checks whether the root CA certificate has been marked as a trusted root
    /// in the admin (system-wide) trust settings domain. Returns true ONLY for
    /// admin domain trust, which is required for production use.
    static func isRootCATrusted(label: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &result)

        guard findStatus == errSecSuccess, let secCert = result else {
            return false
        }

        // swiftlint:disable:next force_cast
        let cert = secCert as! SecCertificate

        // Check .admin domain first (system-wide trust — required for production)
        if hasTrustRootInDomain(cert, domain: .admin) {
            logger.debug("Root CA trusted in .admin domain (system-wide)")
            return true
        }

        // Check .user domain for diagnostic logging only — not sufficient for production
        if hasTrustRootInDomain(cert, domain: .user) {
            logger.warning("Root CA trusted at .user level only — re-trust needed for system-wide .admin domain")
        }

        return false
    }

    /// Checks if certificate exists in any searched keychain using its DER data directly,
    /// bypassing label-based lookup. Works for certs in the system keychain.
    static func isCertificateInstalled(certData: Data) -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// Checks trust using certificate DER data directly — works regardless of which
    /// keychain holds the certificate or what label it has. Returns true ONLY for
    /// admin (system-wide) domain trust, which is required for production use.
    static func isRootCATrusted(certData: Data) -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return false
        }

        // Check .admin domain first (system-wide trust — required for production)
        var adminTrustSettings: CFArray?
        let adminStatus = SecTrustSettingsCopyTrustSettings(secCert, .admin, &adminTrustSettings)

        if adminStatus == errSecSuccess, let settings = adminTrustSettings as? [[String: Any]] {
            for entry in settings {
                if let resultValue = entry[kSecTrustSettingsResult as String] as? UInt32,
                   resultValue == SecTrustSettingsResult.trustRoot.rawValue
                {
                    logger.debug("Root CA trusted in .admin domain (system-wide)")
                    return true
                }
            }
        }

        // Check .user domain for diagnostic logging only — not sufficient for production
        var userTrustSettings: CFArray?
        let userStatus = SecTrustSettingsCopyTrustSettings(secCert, .user, &userTrustSettings)
        if userStatus == errSecSuccess {
            logger.warning("Root CA trusted at .user level only — re-trust needed for system-wide .admin domain")
        }

        return false
    }

    /// Returns trust presence in both admin and user domains for diagnostic purposes.
    /// Admin trust = system-wide (required for production). User trust = per-user only
    /// (insufficient for all TLS clients to honor it).
    static func trustDomainDiagnostic(certData: Data) -> (adminTrust: Bool, userTrust: Bool) {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return (adminTrust: false, userTrust: false)
        }

        let adminTrust = hasTrustRootInDomain(secCert, domain: .admin)
        let userTrust = hasTrustRootInDomain(secCert, domain: .user)

        logger.info("Trust domain diagnostic: admin=\(adminTrust), user=\(userTrust)")
        return (adminTrust: adminTrust, userTrust: userTrust)
    }

    // MARK: - Fingerprint & Stale Certificate Cleanup

    static func computeFingerprintSHA256(_ certData: Data) -> String {
        let digest = SHA256.hash(data: certData)
        return digest.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func enumerateRockxyCertificates(
        label: String
    )
        -> [(certificate: SecCertificate, derData: Data, fingerprint: String)]
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        var certs: [(certificate: SecCertificate, derData: Data, fingerprint: String)] = []
        for item in items {
            guard let certData = item[kSecValueData as String] as? Data else {
                continue
            }
            // swiftlint:disable:next force_cast
            let certRef = item[kSecValueRef as String] as! SecCertificate
            let fingerprint = computeFingerprintSHA256(certData)
            certs.append((certificate: certRef, derData: certData, fingerprint: fingerprint))
        }
        return certs
    }

    static func cleanupStaleRockxyCerts(activeFingerprint: String, label: String) {
        let certs = enumerateRockxyCertificates(label: label)
        var removedCount = 0

        for entry in certs where entry.fingerprint != activeFingerprint {
            let trustStatus = SecTrustSettingsRemoveTrustSettings(entry.certificate, .admin)
            if trustStatus != errSecSuccess, trustStatus != errSecItemNotFound {
                logger.warning("Failed to remove trust for stale cert \(entry.fingerprint): \(trustStatus)")
            }

            let userTrustStatus = SecTrustSettingsRemoveTrustSettings(entry.certificate, .user)
            if userTrustStatus != errSecSuccess, userTrustStatus != errSecItemNotFound {
                logger.debug("No user-level trust to remove for stale cert \(entry.fingerprint)")
            }

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: entry.certificate
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus == errSecSuccess {
                removedCount += 1
                logger.info("Removed stale Rockxy root cert: \(entry.fingerprint)")
            } else if deleteStatus != errSecItemNotFound {
                logger.warning("Failed to delete stale cert \(entry.fingerprint): \(deleteStatus)")
            }
        }

        if removedCount > 0 {
            logger.info("Cleaned up \(removedCount) stale Rockxy root certificate(s)")
        }
    }

    /// Removes ALL Rockxy root CA certificates from the login keychain.
    /// Called after helper successfully installs + trusts in System.keychain, to prevent
    /// duplicate copies from confusing SecTrust chain evaluation.
    static func removeAllRockxyCertsFromLoginKeychain(label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return
        }

        var removedCount = 0
        for item in items {
            guard let certRef = item[kSecValueRef as String] else {
                continue
            }

            // Only delete from login keychain — system keychain certs return errSecWrPerm
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: certRef,
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus == errSecSuccess {
                removedCount += 1
            }
            // errSecWrPerm means system keychain — expected, skip silently
        }

        if removedCount > 0 {
            logger.info("Removed \(removedCount) stale Rockxy root cert(s) from login keychain")
        }
    }

    // MARK: Private

    /// Every storage shape the root CA private key has ever been written under, in read and
    /// cleanup priority order.
    nonisolated private enum PrivateKeyShape: String {
        /// Current shape: generic password in the user's login Keychain.
        case genericPassword = "generic-password"
        /// `kSecClassKey` with a string `kSecAttrApplicationLabel`.
        case legacyKeyStringLabel = "legacy-key-string-label"
        /// `kSecClassKey` with a data `kSecAttrApplicationLabel`. Both label encodings produce
        /// a separately addressable item, so both have to be searched and cleaned up.
        case legacyKeyDataLabel = "legacy-key-data-label"

        // MARK: Internal

        /// Everything that is not the current shape, in the order it is migrated from.
        static let migrationSources: [PrivateKeyShape] = [
            .legacyKeyStringLabel,
            .legacyKeyDataLabel
        ]

        /// `kSecClassKey` items combine attributes Security.framework rejects on some systems.
        var toleratesMalformedShape: Bool {
            self == .legacyKeyStringLabel || self == .legacyKeyDataLabel
        }
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "KeychainHelper")

    /// Account component for the root CA private key item. The service component is the
    /// caller's label, so one label always maps to exactly one stored key.
    private static let privateKeyAccount = "root-ca-private-key"

    private static func privateKeyQuery(label: String, shape: PrivateKeyShape) -> [String: Any] {
        switch shape {
        case .genericPassword:
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: label,
                kSecAttrAccount as String: privateKeyAccount
            ]
        case .legacyKeyStringLabel:
            [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: label
            ]
        case .legacyKeyDataLabel:
            [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: Data(label.utf8)
            ]
        }
    }

    private static func writePrivateKeyItem(_ keyData: Data, label: String) throws {
        let query = privateKeyQuery(label: label, shape: .genericPassword)

        // Update-or-add, never delete-then-add: a failed add after a delete would destroy
        // the only copy of the root CA private key.
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: keyData] as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = keyData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(addQuery as CFDictionary, nil)

            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: keyData] as CFDictionary)
            }
        }

        guard status == errSecSuccess else {
            logger.error("Failed to save private key: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    /// Reads one storage shape. `nil` means that shape holds nothing; a transient Keychain
    /// failure throws instead, so it can never be confused with absence.
    private static func readPrivateKeyItem(label: String, shape: PrivateKeyShape) throws -> Data? {
        var query = privateKeyQuery(label: label, shape: shape)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch classifyReadStatus(status, toleratesMalformedShape: shape.toleratesMalformedShape) {
        case .found:
            return result as? Data
        case .absent:
            return nil
        case .failure:
            logger.error("Failed to load private key (\(shape.rawValue)): \(status)")
            throw KeychainError.loadFailed(status)
        }
    }

    /// Best-effort cleanup of superseded storage shapes. Only reached once the generic-password
    /// item has been read back and byte-compared, and a failure here never blocks the
    /// authoritative copy.
    private static func deleteSupersededPrivateKeyItems(label: String) {
        for shape in PrivateKeyShape.migrationSources {
            let status = SecItemDelete(privateKeyQuery(label: label, shape: shape) as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                logger.debug("Superseded private key delete (\(shape.rawValue)) returned \(status)")
            }
        }
    }

    /// Checks whether a SecCertificate has trustRoot settings in the specified domain.
    private static func hasTrustRootInDomain(
        _ secCert: SecCertificate,
        domain: SecTrustSettingsDomain
    )
        -> Bool
    {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(secCert, domain, &trustSettings)

        guard status == errSecSuccess, let settings = trustSettings as? [[String: Any]] else {
            return false
        }

        for entry in settings {
            if let resultValue = entry[kSecTrustSettingsResult as String] as? UInt32,
               resultValue == SecTrustSettingsResult.trustRoot.rawValue
            {
                return true
            }
        }
        return false
    }
}

// MARK: - KeychainError

nonisolated enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case readbackMismatch
    case invalidCertificateData
    case trustSettingsFailed(OSStatus)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .saveFailed(status):
            "Keychain save failed with status: \(status)"
        case let .loadFailed(status):
            "Keychain load failed with status: \(status)"
        case let .deleteFailed(status):
            "Keychain delete failed with status: \(status)"
        case .readbackMismatch:
            "Keychain readback did not match the value that was just written"
        case .invalidCertificateData:
            "Invalid certificate data — could not create SecCertificate"
        case let .trustSettingsFailed(status):
            "Failed to set certificate trust settings with status: \(status)"
        }
    }
}
