import Foundation
@testable import Rockxy
import Security
import Testing

// Regression tests for the removal half of the #319 authorization routing defect.
//
// Removing trust is the part of a removal that needs a human. `SecTrustSettingsRemoveTrustSettings`
// in the `.admin` domain goes through interactive Authorization Services, and this headless launchd
// daemon has no GUI session to obtain that authorization in, so the request is denied there even as
// root. The GUI process therefore clears the trust settings first, and only then asks the daemon to
// delete the System keychain item it cannot reach itself. Deleting first would leave admin trust
// settings behind for a certificate no keychain holds any more: still trusted, and addressable only
// through the DER the removal snapshotted.

// MARK: - RootCATrustRemovalOrderingTests

@Suite(.serialized)
struct RootCATrustRemovalOrderingTests {
    @Test("trust settings are cleared in this process before the daemon is asked to delete")
    func trustClearingPrecedesDaemonDelete() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())

        let recorder = RemovalOrderRecorder()
        await manager.setAppTrustSettingsRemovalOverrideForTests { targets in recorder.recordTrust(targets) }
        await manager.setHelperRemovalOverrideForTests { targets in recorder.recordHelper(targets) }

        try await manager.reset()

        #expect(recorder.steps == ["trust", "helper"])
        // Both steps address the same snapshotted certificate — the removal is never widened for
        // one of them and narrowed for the other.
        #expect(recorder.trustTargets == [der])
        #expect(recorder.helperTargets == [der])
    }

    @Test("a refused trust removal blocks the daemon delete and keeps every byte in place")
    func refusedTrustRemovalBlocksDaemonDelete() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        let originalCertificateBytes = try Data(contentsOf: CertificateStore.rootCACertificateURL)

        let recorder = RemovalOrderRecorder()
        await manager.setAppTrustSettingsRemovalOverrideForTests { _ in
            throw KeychainError.trustSettingsFailed(errSecAuthFailed)
        }
        await manager.setHelperRemovalOverrideForTests { targets in recorder.recordHelper(targets) }
        await manager.setAppRemovalOverrideForTests { _ in
            Issue.record("A refused trust removal must not reach any deletion")
        }

        await #expect(throws: CertificateManagerError.self) { try await manager.reset() }

        // Nothing privileged ran, so the certificate the user still trusts is still addressable
        // and the local pair that identifies it is intact.
        #expect(recorder.steps.isEmpty)
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == originalKey)
        #expect(try Data(contentsOf: CertificateStore.rootCACertificateURL) == originalCertificateBytes)
        let message = try #require(await manager.lastValidationErrorMessage)
        #expect(message.contains(String(errSecAuthFailed)))
    }

    @Test("a cancelled approval reports cancellation and removes nothing")
    func cancelledTrustRemovalRemovesNothing() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())

        let recorder = RemovalOrderRecorder()
        await manager.setAppTrustSettingsRemovalOverrideForTests { _ in throw CancellationError() }
        await manager.setHelperRemovalOverrideForTests { targets in recorder.recordHelper(targets) }
        await manager.setAppRemovalOverrideForTests { _ in
            Issue.record("A cancelled approval must not reach any deletion")
        }

        await #expect(throws: CancellationError.self) { try await manager.reset() }

        #expect(recorder.steps.isEmpty)
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) != nil)
    }

    @Test("removing an untrusted root needs no approval at all")
    func untrustedRemovalNeedsNoApproval() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())
        #expect(try !KeychainHelper.hasAnyTrustSettings(certData: der))

        // No trust-settings remover is injected, and a test may never raise a real dialog: the
        // manager's fixture guard fails closed the moment a target carries settings. Completing
        // here is therefore proof that an untrusted root is removed without asking anyone.
        try await manager.reset()

        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try CertificateStore.loadRootCACertificate() == nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == nil)
    }

    @Test("a failed daemon delete cannot broaden the targets or ask for approval again")
    func helperFailureNeitherPromptsAgainNorWidens() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())

        let recorder = RemovalOrderRecorder()
        await manager.setAppTrustSettingsRemovalOverrideForTests { targets in recorder.recordTrust(targets) }
        await manager.setHelperRemovalOverrideForTests { targets in
            recorder.recordHelper(targets)
            throw HelperConnectionError.certRemoveFailed("daemon refused")
        }

        // The app-side removal still clears the login-keychain copy, so the verification passes and
        // the daemon failure is not fatal on its own.
        try await manager.reset()

        // Exactly one approval was requested, for exactly the snapshotted certificate: a failing
        // daemon never turns into a second dialog or a wider removal.
        #expect(recorder.steps == ["trust", "helper"])
        #expect(recorder.trustTargets == [der])
        #expect(recorder.helperTargets == [der])
        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
    }
}

// MARK: - RemovalOrderRecorder

/// Records the order of a removal's privileged steps and the targets each one was given.
private final class RemovalOrderRecorder: @unchecked Sendable {
    // MARK: Internal

    var steps: [String] {
        lock.withLock { recorded }
    }

    var trustTargets: [Data] {
        lock.withLock { trust }
    }

    var helperTargets: [Data] {
        lock.withLock { helper }
    }

    func recordTrust(_ targets: [Data]) {
        lock.withLock {
            recorded.append("trust")
            trust = targets
        }
    }

    func recordHelper(_ targets: [Data]) {
        lock.withLock {
            recorded.append("helper")
            helper = targets
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [String] = []
    private var trust: [Data] = []
    private var helper: [Data] = []
}
