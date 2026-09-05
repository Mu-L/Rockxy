import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// The last step of a removal runs after the one authorization phase is over: the trust settings
// were cleared in this process, and the privileged helper has already deleted what it owns. Going
// back through `SecTrustSettingsRemoveTrustSettings` there is what could raise a second macOS
// dialog — trust settings live independently of the keychain item, so settings that reappeared
// between the two steps would send the cleanup back through Authorization Services for an approval
// the user already answered.
//
// So the cleanup only deletes, and only what it can prove is untrusted. Settings that are present,
// and a domain that cannot be read, are both "not proved absent" and both keep the certificate
// installed: the item is the only thing that still addresses those settings from the UI.
//
// No host trust settings are created or removed anywhere here — the presence read is injected.

// MARK: - AppSideCertificateCleanupTests

struct AppSideCertificateCleanupTests {
    @Test("trust settings that are still present stop the deletion instead of being cleared again")
    func presentTrustSettingsBlockDeletion() throws {
        let der = try cleanupCertificateDER(RootCAGenerator.generate().certificate)
        let label = "\(TestIdentity.keychainProbeLabel).cleanup.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: label)
        defer { try? KeychainHelper.removeCertificate(label: label) }

        let failure = #expect(throws: KeychainError.self) {
            // Models settings restored after the authorization phase — by another tool, or by a
            // helper delete that raced the trust clearing.
            try KeychainHelper.removeExactCertificateItems(
                certData: der,
                trustSettingsPresent: { _ in true }
            )
        }

        #expect(failure?.errorDescription?.contains("trust settings") == true)
        // Nothing was deleted, so the settings are still addressable by the certificate itself.
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
    }

    @Test("a trust domain that cannot be read is not a licence to delete")
    func unreadableTrustDomainBlocksDeletion() throws {
        let der = try cleanupCertificateDER(RootCAGenerator.generate().certificate)
        let label = "\(TestIdentity.keychainProbeLabel).cleanup.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: label)
        defer { try? KeychainHelper.removeCertificate(label: label) }

        #expect(throws: KeychainError.self) {
            try KeychainHelper.removeExactCertificateItems(
                certData: der,
                trustSettingsPresent: { _ in throw KeychainError.trustSettingsUnreadable(errSecAuthFailed) }
            )
        }

        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
    }

    @Test("absent trust settings allow the exact cleanup, and only for the exact certificate")
    func absentTrustSettingsAllowExactCleanup() throws {
        let namespace = "\(TestIdentity.keychainProbeLabel).cleanup.\(UUID().uuidString)"
        let sentinel = try cleanupCertificateDER(RootCAGenerator.generate().certificate)
        try KeychainHelper.installCertificate(sentinel, label: namespace + ".sentinel")
        defer { try? KeychainHelper.removeCertificate(label: namespace + ".sentinel") }

        let der = try cleanupCertificateDER(RootCAGenerator.generate().certificate)
        try KeychainHelper.installCertificate(der, label: namespace + ".target")
        defer { try? KeychainHelper.removeCertificate(label: namespace + ".target") }

        // The real presence read runs here: a freshly generated fixture carries no settings, so
        // the cleanup proceeds without any trust API being reachable from it.
        try KeychainHelper.removeExactCertificateItems(certData: der)

        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: sentinel))

        // Repeating it is a no-op, which is what covers a copy discovered only after the first pass.
        try KeychainHelper.removeExactCertificateItems(certData: der)
    }

    @Test("the standalone removal still clears trust settings before deleting the item")
    func standaloneRemovalKeepsItsOrder() throws {
        let der = try cleanupCertificateDER(RootCAGenerator.generate().certificate)
        let label = "\(TestIdentity.keychainProbeLabel).cleanup.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: label)
        defer { try? KeychainHelper.removeCertificate(label: label) }

        // Composed from both halves, so a caller that owns the whole removal is unchanged: the
        // untrusted fixture needs no approval and is gone afterwards.
        try KeychainHelper.removeRootCATrust(certData: der)

        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try !KeychainHelper.hasAnyTrustSettings(certData: der))
    }
}

// MARK: - AppSideCleanupFailClosedTests

/// The manager's side of the same rule: a cleanup that cannot prove the trust settings are gone
/// reports an incomplete removal, keeps every byte, and asks for no second approval.
@Suite(.serialized)
struct AppSideCleanupFailClosedTests {
    @Test("a fail-closed app-side cleanup keeps the material and requests no second approval")
    func failClosedCleanupKeepsMaterial() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())
        let originalKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        let approvals = CleanupApprovalCounter()
        await manager.setAppTrustSettingsRemovalOverrideForTests { _ in approvals.record() }
        await manager.setHelperRemovalOverrideForTests { _ in
            throw HelperConnectionError.certRemoveFailed("daemon refused")
        }
        // The failure the non-interactive cleanup reports when the settings it requires to be gone
        // are back — the case that used to re-enter the interactive trust removal.
        await manager.setAppRemovalOverrideForTests { _ in
            throw KeychainError.trustSettingsStillPresent
        }

        let failure = await #expect(throws: CertificateManagerError.self) {
            try await manager.reset()
        }
        guard case .rootRemovalIncomplete? = failure else {
            Issue.record("A cleanup that cannot prove trust is gone must report an incomplete removal")
            return
        }

        // Exactly one authorization phase, whatever the helper and the cleanup then reported.
        #expect(approvals.count == 1)
        // Nothing was deleted, so the certificate that still addresses the settings — and the local
        // pair that identifies it — survive for a retry.
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == originalKey)
    }
}

// MARK: - CleanupApprovalCounter

/// Counts the interactive trust-removal approvals one removal asked for.
private final class CleanupApprovalCounter: @unchecked Sendable {
    // MARK: Internal

    var count: Int {
        lock.withLock { value }
    }

    func record() {
        lock.withLock { value += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

private func cleanupCertificateDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}
