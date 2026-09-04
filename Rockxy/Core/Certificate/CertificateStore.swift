import Crypto
import Foundation
import os
import SwiftASN1
import X509

// Root CA Private Key Storage Model:
// Primary: macOS Keychain (kSecAttrAccessibleWhenUnlocked) — OS-level encryption at rest,
//          protected by login session. Key material never written to disk in plaintext.
// Recovery: Disk PEM file (.bak suffix) — only exists after migration from older versions.
//          Read-only: it is still loaded once and migrated into the Keychain, but Rockxy
//          never writes a new plaintext key file.
// Rationale: Keychain provides OS-level encryption and login-session protection.
//          Plaintext PEM on disk (even with 0o600) is vulnerable to disk imaging and swap dumps.

/// Handles persistence of the root CA certificate (disk PEM) and private key (Keychain-only,
/// with read-only disk recovery for older installs). Files are stored under the shared
/// Rockxy support directory.
nonisolated enum CertificateStore {
    // MARK: Internal

    // MARK: Internal — Test Overrides

    /// Override for test isolation. When set, used instead of the production Keychain label.
    /// Protected by lock for parallel test safety.
    static var keychainKeyLabelOverride: String? {
        get { overrideLock.withLock { _keychainKeyLabelOverride } }
        set { overrideLock.withLock { _keychainKeyLabelOverride = newValue } }
    }

    /// Override for test isolation. When set, used instead of the production storage directory.
    /// Protected by lock for parallel test safety.
    static var storageDirectoryOverride: URL? {
        get { overrideLock.withLock { _storageDirectoryOverride } }
        set { overrideLock.withLock { _storageDirectoryOverride = newValue } }
    }

    static var rootCACertificateURL: URL {
        storageDirectory.appendingPathComponent(rootCACertFilename)
    }

    /// The Keychain label this store reads and writes right now, honouring the test
    /// override. Deletion must target the same label the key was written under.
    static var activeKeychainKeyLabel: String {
        keychainKeyLabel
    }

    static func ensureDirectoryExists() throws {
        let directory = storageDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Created certificate storage directory")
        }
    }

    static func saveRootCACertificate(_ certificate: Certificate) throws {
        try ensureDirectoryExists()

        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let derBytes = Array(serializer.serializedBytes)

        let pemDocument = PEMDocument(type: "CERTIFICATE", derBytes: derBytes)
        let pemString = pemDocument.pemString

        let filePath = rootCACertificateURL
        try Data(pemString.utf8).write(to: filePath, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
        logger.info("Saved root CA certificate to disk")
    }

    /// Persists the root CA private key to the Keychain. There is deliberately no disk
    /// fallback: writing a plaintext PEM would trade a visible failure for key material on
    /// disk, and a silently unpersisted key means the next launch regenerates the CA and
    /// invalidates the fingerprint the user already approved. A failure propagates so the
    /// caller never adopts a root CA that cannot survive relaunch. Legacy disk PEM / `.bak`
    /// files stay readable for one-time migration; new ones are never created.
    static func saveRootCAPrivateKey(_ key: P256.Signing.PrivateKey) throws {
        let keyData = Data(key.x963Representation)

        do {
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
        } catch {
            logger.error("Failed to persist root CA private key to Keychain: \(error.localizedDescription)")
            throw error
        }

        logger.info("Saved root CA private key to Keychain (primary)")
    }

    static func loadRootCACertificate() throws -> Certificate? {
        let filePath = rootCACertificateURL

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let pemData = try Data(contentsOf: filePath)
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            logger.warning("Persisted root CA certificate is not valid UTF-8 — regeneration required")
            return nil
        }
        do {
            let pemDocument = try PEMDocument(pemString: pemString)
            let certificate = try Certificate(derEncoded: pemDocument.derBytes)
            logger.debug("Loaded root CA certificate from disk")
            return certificate
        } catch {
            // The file was readable, but its contents are not a usable certificate. Treat
            // that as an absent persisted CA so ensureRootCA can replace it once. Genuine
            // filesystem access failures still propagate from Data(contentsOf:) above.
            logger.warning(
                "Persisted root CA certificate is invalid — regeneration required: \(error.localizedDescription)"
            )
            return nil
        }
    }

    static func loadRootCAPrivateKey() throws -> P256.Signing.PrivateKey? {
        // 1. Try Keychain first (primary storage)
        if let keyData = try KeychainHelper.loadPrivateKey(
            label: keychainKeyLabel,
            isUsable: { (try? P256.Signing.PrivateKey(x963Representation: $0)) != nil }
        ) {
            let key = try P256.Signing.PrivateKey(x963Representation: keyData)
            logger.info("Loaded root CA private key from Keychain (primary)")
            return key
        }

        // 2. Fall back to disk PEM for migration from older versions
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if let key = try loadPrivateKeyPEM(at: filePath, sourceDescription: "primary disk PEM") {
            logger.info("Loaded root CA private key from disk (migration fallback)")

            // Migrate: store to Keychain, rename the valid primary disk copy to .bak.
            migrateKeyToKeychain(key: key, source: .primary)
            return key
        }

        // 3. Last resort: check for .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if let key = try loadPrivateKeyPEM(at: backupPath, sourceDescription: ".bak recovery file") {
            logger.warning("Loaded root CA private key from .bak recovery file — re-migrating to Keychain")
            migrateKeyToKeychain(key: key, source: .backup)
            return key
        }

        return nil
    }

    /// Loads the root CA private key from disk PEM only, skipping Keychain lookup.
    /// Used as a fallback when the Keychain key does not match the certificate on disk
    /// (cert-key mismatch scenario), to check whether the disk copy is still consistent.
    static func loadRootCAPrivateKeyFromDisk() throws -> P256.Signing.PrivateKey? {
        // Check primary disk PEM file
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if let key = try loadPrivateKeyPEM(at: filePath, sourceDescription: "primary disk PEM") {
            logger.info("Loaded root CA private key from disk PEM (direct, no Keychain)")
            return key
        }

        // Check .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if let key = try loadPrivateKeyPEM(at: backupPath, sourceDescription: ".bak recovery file") {
            logger.info("Loaded root CA private key from .bak recovery file (direct, no Keychain)")
            return key
        }

        return nil
    }

    static func deleteAll() throws {
        let directory = storageDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
            logger.info("Deleted all stored certificates")
        }
    }

    /// Removes plaintext migration sources only after `CertificateManager` has verified
    /// that the Keychain key matches the persisted certificate. Keeping this out of the
    /// raw Keychain load path preserves the disk recovery key when a stale or mismatched
    /// Keychain item is encountered.
    static func cleanupLegacyDiskKeys(matching expectedKey: P256.Signing.PrivateKey) {
        let expectedData = Data(expectedKey.x963Representation)
        let persistedData = try? KeychainHelper.loadPrivateKey(
            label: keychainKeyLabel,
            isUsable: { $0 == expectedData }
        )
        guard persistedData == expectedData else {
            logger.debug("Skipping legacy disk-key cleanup — Keychain does not hold the verified key")
            return
        }

        let legacyPaths = [
            storageDirectory.appendingPathComponent(rootCAKeyFilename),
            storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        ]
        var removedAny = false
        for path in legacyPaths where FileManager.default.fileExists(atPath: path.path) {
            do {
                try FileManager.default.removeItem(at: path)
                removedAny = true
            } catch {
                logger.warning("Failed to remove legacy private key file: \(error.localizedDescription)")
            }
        }
        if removedAny {
            logger.info("Cleaned up verified legacy private key files — Keychain is primary")
        }
    }

    // MARK: Private

    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var _keychainKeyLabelOverride: String?
    nonisolated(unsafe) private static var _storageDirectoryOverride: URL?

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateStore")

    private static let rootCACertFilename = "rootCA.pem"
    private static let rootCAKeyFilename = "rootCA-key.pem"

    private enum DiskKeySource {
        case primary
        case backup
    }

    private static var keychainKeyLabel: String {
        keychainKeyLabelOverride ?? RockxyIdentity.current.rootCAKeyLabel
    }

    private static var storageDirectory: URL {
        if let override = storageDirectoryOverride {
            return override
        }
        return RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
    }

    /// Migrates a private key from disk PEM to Keychain. On success, renames the disk
    /// file to `.bak` so it is no longer used as the primary source but remains available
    /// for manual recovery.
    private static func loadPrivateKeyPEM(
        at filePath: URL,
        sourceDescription: String
    ) throws -> P256.Signing.PrivateKey? {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // Read/access errors are operational failures and must propagate. Only readable but
        // malformed contents are skipped so another recovery source can be attempted.
        let pemData = try Data(contentsOf: filePath)
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            logger.warning("Root CA private key \(sourceDescription) is not valid UTF-8 — skipping")
            return nil
        }

        do {
            let pemDocument = try PEMDocument(pemString: pemString)
            return try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
        } catch {
            logger.warning(
                "Root CA private key \(sourceDescription) is invalid — skipping: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private static func migrateKeyToKeychain(key: P256.Signing.PrivateKey, source: DiskKeySource) {
        do {
            let keyData = Data(key.x963Representation)
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
            logger.info("Migration: stored private key in Keychain")

            let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
            let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")

            // Only a primary file that was successfully decoded may replace `.bak`. When
            // recovery came from `.bak`, keep it intact even if a corrupt primary file also
            // exists; CertificateManager removes both only after cert/key matching succeeds.
            if source == .primary, FileManager.default.fileExists(atPath: filePath.path) {
                if FileManager.default.fileExists(atPath: backupPath.path) {
                    try FileManager.default.removeItem(at: backupPath)
                }
                try FileManager.default.moveItem(at: filePath, to: backupPath)
                logger.info("Migration: renamed disk PEM to .bak (recovery-only)")
            } else {
                logger.info("Migration: primary PEM not present, keeping .bak as recovery")
            }
        } catch {
            logger
                .warning(
                    "Migration: failed to migrate key to Keychain — disk PEM retained: \(error.localizedDescription)"
                )
        }
    }
}
