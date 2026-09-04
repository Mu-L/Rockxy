import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CALifecycleTests

/// Tests use shared CertificateStore overrides, so must run serially.
@Suite(.serialized)
struct CALifecycleTests {
    @Test("new root CA validity is 2 years")
    func rootCAValidityIsTwoYears() throws {
        let result = try RootCAGenerator.generate()
        let cert = result.certificate

        let now = Date()
        let expectedEnd = try #require(Calendar.current.date(byAdding: .year, value: 2, to: now))

        let tolerance: TimeInterval = 7 * 24 * 60 * 60
        let diff = abs(cert.notValidAfter.timeIntervalSince(expectedEnd))
        #expect(
            diff < tolerance,
            "Certificate validity should be ~2 years, got \(diff / (365.25 * 24 * 60 * 60)) years difference"
        )

        let twoDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -2, to: now))
        let startDiff = abs(cert.notValidBefore.timeIntervalSince(twoDaysAgo))
        #expect(startDiff < tolerance, "Certificate start should be ~2 days ago")
    }

    @Test("root CA validity is NOT 10 years")
    func rootCAValidityIsNotTenYears() throws {
        let result = try RootCAGenerator.generate()
        let cert = result.certificate

        let now = Date()
        let tenYears = try #require(Calendar.current.date(byAdding: .year, value: 10, to: now))

        let diff = tenYears.timeIntervalSince(cert.notValidAfter)
        #expect(diff > 7 * 365.25 * 24 * 60 * 60, "Validity should not be 10 years")
    }

    @Test("cleanupLegacyDiskKeys removes verified primary and backup files when Keychain has key")
    func cleanupRemovesLegacyFilesWithKeychainKey() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        // The Keychain must hold a key for cleanup to consider the .bak file redundant.
        let probeKey = P256.Signing.PrivateKey()
        try KeychainHelper.savePrivateKey(Data(probeKey.x963Representation), label: overrides.label)

        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        let primaryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)
        try "legacy primary key data".write(to: primaryPath, atomically: true, encoding: .utf8)
        try "legacy key data".write(to: bakPath, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: primaryPath.path))
        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        CertificateStore.cleanupLegacyDiskKeys(matching: probeKey)

        #expect(!FileManager.default.fileExists(atPath: primaryPath.path))
        #expect(!FileManager.default.fileExists(atPath: bakPath.path))
    }

    @Test("cleanupLegacyDiskKeys preserves .bak when Keychain is empty")
    func cleanupPreservesBakWithoutKeychainKey() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)
        try "legacy key data".write(to: bakPath, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        CertificateStore.cleanupLegacyDiskKeys(matching: P256.Signing.PrivateKey())

        #expect(FileManager.default.fileExists(atPath: bakPath.path))
    }

    @Test("cleanupLegacyDiskKeys preserves recovery when Keychain key is corrupt")
    func cleanupPreservesRecoveryWithCorruptKeychainKey() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        let verifiedKey = P256.Signing.PrivateKey()
        try KeychainHelper.savePrivateKey(Data([0x01, 0x02, 0x03]), label: overrides.label)

        let primaryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)
        try "valid recovery placeholder".write(to: primaryPath, atomically: true, encoding: .utf8)
        try "valid backup placeholder".write(to: backupPath, atomically: true, encoding: .utf8)

        CertificateStore.cleanupLegacyDiskKeys(matching: verifiedKey)

        #expect(FileManager.default.fileExists(atPath: primaryPath.path))
        #expect(FileManager.default.fileExists(atPath: backupPath.path))
    }

    @Test("bak migration preserves recovery when no primary PEM exists")
    func bakMigrationPreservesRecoveryWhenNoPrimaryPEM() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        // Start from a Keychain with no key for this label so the .bak file is the only source.
        try KeychainHelper.deletePrivateKey(label: overrides.label)

        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)

        let key = P256.Signing.PrivateKey()
        let derBytes = Array(key.x963Representation)
        let pemDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: derBytes)
        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try Data(pemDocument.pemString.utf8).write(to: bakPath)

        let primaryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        #expect(!FileManager.default.fileExists(atPath: primaryPath.path))

        let loaded = try CertificateStore.loadRootCAPrivateKey()
        #expect(loaded != nil)

        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        let keychainKey = try KeychainHelper.loadPrivateKey(label: overrides.label)
        #expect(keychainKey != nil)
    }

    @Test("root CA generation that cannot persist leaves no volatile root behind")
    func generationFailurePropagatesWithoutAdoptingRoot() async throws {
        let manager = CertificateManager.shared
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        // Establish a persisted root so a failed regeneration can be shown not to replace it.
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalPersistedKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        // Point storage at a path whose parent is a regular file, so persisting a newly
        // generated CA fails deterministically.
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-blocked-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        CertificateStore.storageDirectoryOverride = blockingFile
            .appendingPathComponent("Certificates", isDirectory: true)

        await #expect(throws: (any Error).self) {
            try await manager.generateRootCA()
        }

        // The volatile root from the failed attempt was never adopted.
        let fingerprintAfter = await manager.getActiveRootFingerprint()
        #expect(fingerprintAfter == originalFingerprint)

        // The failed PEM write must also roll the Keychain back to the original key;
        // otherwise the next process launch would see a cert/key mismatch and rotate.
        let persistedKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        #expect(persistedKey == originalPersistedKey)
    }

    @Test("mismatched Keychain key is repaired from the disk key matching the certificate")
    func mismatchRecoveryRepairsKeychainAndCleansDisk() async throws {
        let manager = CertificateManager.shared
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        try await manager.reset()

        let validCA = try RootCAGenerator.generate()
        let staleKey = P256.Signing.PrivateKey()
        try CertificateStore.saveRootCACertificate(validCA.certificate)
        try KeychainHelper.savePrivateKey(Data(staleKey.x963Representation), label: overrides.label)

        try CertificateStore.ensureDirectoryExists()
        let recoveryDocument = PEMDocument(
            type: "EC PRIVATE KEY",
            derBytes: Array(validCA.privateKey.x963Representation)
        )
        let recoveryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        try Data(recoveryDocument.pemString.utf8).write(to: recoveryPath)

        #expect(try await manager.loadExistingRootCA())

        let repairedData = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        let repairedKey = try P256.Signing.PrivateKey(x963Representation: repairedData)
        #expect(repairedKey.rawRepresentation == validCA.privateKey.rawRepresentation)
        #expect(!FileManager.default.fileExists(atPath: recoveryPath.path))

        try await manager.reset()
    }

    @Test("mismatch recovery propagates unreadable disk source instead of rotating")
    func mismatchRecoveryPropagatesDiskReadFailure() async throws {
        let manager = CertificateManager.shared
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        try await manager.reset()

        let validCA = try RootCAGenerator.generate()
        let staleKey = P256.Signing.PrivateKey()
        try CertificateStore.saveRootCACertificate(validCA.certificate)
        try KeychainHelper.savePrivateKey(Data(staleKey.x963Representation), label: overrides.label)

        let recoveryDocument = PEMDocument(
            type: "EC PRIVATE KEY",
            derBytes: Array(validCA.privateKey.x963Representation)
        )
        let recoveryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        try Data(recoveryDocument.pemString.utf8).write(to: recoveryPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: recoveryPath.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryPath.path)
        }

        await #expect(throws: (any Error).self) {
            try await manager.loadExistingRootCA()
        }

        #expect(await manager.getActiveRootFingerprint() == nil)
    }

    @Test("CertificateManager clearFreshlyInstalledFlag resets flag")
    func clearFreshlyInstalledFlag() async {
        let manager = CertificateManager.shared
        await manager.clearFreshlyInstalledFlag()
        let flag = await manager.rootCAFreshlyInstalled
        #expect(flag == false)
    }
}
