import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Behaviour tests for the privileged root CA installation rules, driven through the injected
// keychain/trust boundary. Nothing here trusts a CA, opens `System.keychain`, or addresses the
// production daemon.
//
// The property under test is that installation is purely additive. The fake below has no way to
// delete anything — mirroring `RootCertificateInstallOperations`, which has no removal member —
// so every case also asserts that whatever was installed beforehand is still installed at the end,
// including on the failure paths where the old shape used to sweep the label first.

// MARK: - RootCertificateInstallTests

struct RootCertificateInstallTests {
    // MARK: Internal

    @Test("an unrelated or malformed certificate is refused before anything is written")
    func ownershipIsValidatedBeforeAnyMutation() throws {
        let survivor = try makeRockxyRootDER()

        for candidate in try [
            Data(),
            Data(repeating: 0x30, count: 10_000),
            Data("not a certificate".utf8),
            makeSelfSignedCertificateDER(commonName: "Some Other Root CA"),
            makeImpostorCertificateDER(),
        ] {
            let keychain = FakeInstallKeychain()
            try keychain.preinstall(der: survivor, label: "existing", positivelyTrusted: true)

            #expect(throws: RootCertificateRemovalError.self) {
                try RootCertificateInstaller.installTrustedRoot(
                    derData: candidate,
                    label: "rockxy",
                    using: keychain
                )
            }

            #expect(keychain.hasMutated == false)
            #expect(keychain.installedDERs == [survivor])
            #expect(keychain.positivelyTrustedDERs == [survivor])
        }
    }

    @Test("a successful installation adds, trusts, and leaves every older root in place")
    func successfulInstallPreservesOlderRoots() throws {
        let older = try makeRockxyRootDER()
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        try keychain.preinstall(der: older, label: "rockxy", positivelyTrusted: true)

        let outcome = try RootCertificateInstaller.installTrustedRoot(
            derData: target,
            label: "rockxy",
            using: keychain
        )

        #expect(outcome == RootCertificateInstaller.InstallOutcome(
            addedCertificate: true,
            appliedTrustSettings: true
        ))
        #expect(keychain.addAttempts == ["rockxy"])
        #expect(keychain.trustWriteDERs == [target])
        // The previous root — the one a label sweep used to destroy — is untouched.
        #expect(keychain.installedDERs == [older, target])
        #expect(keychain.positivelyTrustedDERs == [older, target])
    }

    @Test("a failed add reports the failure and removes nothing")
    func addFailureRemovesNothing() throws {
        let older = try makeRockxyRootDER()
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        try keychain.preinstall(der: older, label: "rockxy", positivelyTrusted: true)
        keychain.addFailure = .keychainFailure(operation: "add certificate", status: errSecAuthFailed)

        #expect(throws: RootCertificateInstallError.keychainFailure(
            operation: "add certificate",
            status: errSecAuthFailed
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }

        #expect(keychain.installedDERs == [older])
        #expect(keychain.trustWriteDERs.isEmpty)
    }

    @Test("an add that reports success without installing is not believed")
    func silentlyIgnoredAddIsReported() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        keychain.addIsNoOp = true

        #expect(throws: RootCertificateInstallError.certificateNotInstalledAfterAdd(
            fingerprint: RootCertificateRemover.fingerprint(of: target)
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }

        // A status code is a report, so no trust was written on the strength of one.
        #expect(keychain.trustWriteDERs.isEmpty)
    }

    @Test("a duplicate whose exact bytes are absent is a failure, not an install")
    func duplicateWithoutTheExactBytesIsReported() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        // `errSecDuplicateItem` says something collides on the primary key, which is not the same
        // claim as "exactly these bytes are present".
        keychain.addOutcomeOverride = .duplicate

        #expect(throws: RootCertificateInstallError.duplicateCertificateAbsent(
            fingerprint: RootCertificateRemover.fingerprint(of: target)
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }
        #expect(keychain.trustWriteDERs.isEmpty)
    }

    @Test("a duplicate that really is the target is trusted without a second add")
    func duplicateOfTheTargetIsTrusted() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        try keychain.preinstall(der: target, label: "rockxy", positivelyTrusted: false)
        keychain.addOutcomeOverride = .duplicate

        let outcome = try RootCertificateInstaller.installTrustedRoot(
            derData: target,
            label: "rockxy",
            using: keychain
        )

        #expect(outcome.addedCertificate == false)
        #expect(outcome.appliedTrustSettings)
        #expect(keychain.installedDERs == [target])
    }

    @Test("a refused trust write leaves the added certificate installed and untrusted")
    func trustWriteFailureIsNotRolledBack() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        keychain.trustWriteFailure = .trustWriteFailed(detail: "security exit 1")

        #expect(throws: RootCertificateInstallError.trustWriteFailed(detail: "security exit 1")) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }

        // Deleting it to make the failure look tidy would itself be a destructive act on material
        // nobody asked to remove.
        #expect(keychain.installedDERs == [target])
        #expect(keychain.positivelyTrustedDERs.isEmpty)
    }

    @Test("a trust write that reports success without applying trust is reported")
    func unappliedTrustIsReported() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        keychain.trustWriteIsNoOp = true

        #expect(throws: RootCertificateInstallError.trustNotAppliedAfterInstall(
            fingerprint: RootCertificateRemover.fingerprint(of: target)
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }
        #expect(keychain.installedDERs == [target])
    }

    @Test("existing settings that are a deny are never mistaken for trust")
    func denySettingsAreNotTrust() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        try keychain.preinstall(der: target, label: "rockxy", positivelyTrusted: false)
        keychain.deniedDERs = [target]
        // The deny survives the write, which is exactly the shape a swallowed CLI failure has.
        keychain.trustWriteIsNoOp = true

        #expect(throws: RootCertificateInstallError.trustNotAppliedAfterInstall(
            fingerprint: RootCertificateRemover.fingerprint(of: target)
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }
        // Settings existed, so a presence check would have passed here; a trust write was still
        // attempted, and the postcondition still refused to call it trusted.
        #expect(keychain.trustWriteDERs == [target])
    }

    @Test("a certificate that disappears while trust is applied fails the final check")
    func certificateAbsentAfterTrustIsReported() throws {
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        keychain.trustWriteRemovesCertificate = true

        #expect(throws: RootCertificateInstallError.certificateAbsentAfterTrustSettings(
            fingerprint: RootCertificateRemover.fingerprint(of: target)
        )) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: keychain)
        }
    }

    @Test("an unreadable keychain or trust status is never read as absence")
    func unknownStatusesPropagate() throws {
        let target = try makeRockxyRootDER()

        let queryFailure = FakeInstallKeychain()
        queryFailure.serialQueryFailure = .keychainFailure(operation: "serial number query", status: errSecAuthFailed)
        #expect(throws: RootCertificateInstallError.self) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: queryFailure)
        }
        #expect(queryFailure.trustWriteDERs.isEmpty)
        #expect(queryFailure.hasMutated == false)

        let trustFailure = FakeInstallKeychain()
        trustFailure.trustReadFailure = .keychainFailure(
            operation: "copy admin trust settings",
            status: errSecAuthFailed
        )
        #expect(throws: RootCertificateInstallError.self) {
            try RootCertificateInstaller.installTrustedRoot(derData: target, label: "rockxy", using: trustFailure)
        }
        #expect(trustFailure.trustWriteDERs.isEmpty)
        #expect(trustFailure.hasMutated == false)
    }

    @Test("reinstalling an already-trusted root writes nothing and deletes nothing")
    func installIsIdempotent() throws {
        let older = try makeRockxyRootDER()
        let target = try makeRockxyRootDER()
        let keychain = FakeInstallKeychain()
        try keychain.preinstall(der: older, label: "rockxy", positivelyTrusted: true)

        let first = try RootCertificateInstaller.installTrustedRoot(
            derData: target, label: "rockxy", using: keychain
        )
        let second = try RootCertificateInstaller.installTrustedRoot(
            derData: target, label: "rockxy", using: keychain
        )

        #expect(first.addedCertificate)
        #expect(first.appliedTrustSettings)
        #expect(second.addedCertificate == false)
        #expect(second.appliedTrustSettings == false)
        // The second add is attempted and refused as a duplicate, so exactly one copy exists; the
        // trust write happens once, and both roots are still present and still trusted.
        #expect(keychain.addAttempts == ["rockxy", "rockxy"])
        #expect(keychain.trustWriteDERs == [target])
        #expect(keychain.installedDERs == [older, target])
        #expect(keychain.positivelyTrustedDERs == [older, target])
    }

    // MARK: Private

    private func makeRockxyRootDER() throws -> Data {
        try installTestCertificateDER(RootCAGenerator.generate().certificate)
    }

    /// A self-signed CA that is simply not Rockxy's.
    private func makeSelfSignedCertificateDER(commonName: String) throws -> Data {
        let key = P256.Signing.PrivateKey()
        let name = try DistinguishedName { CommonName(commonName) }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: Date().addingTimeInterval(-3_600),
            notValidAfter: Date().addingTimeInterval(3_600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            },
            issuerPrivateKey: Certificate.PrivateKey(key)
        )
        return try installTestCertificateDER(certificate)
    }

    /// Carries Rockxy's common name but was issued by somebody else.
    private func makeImpostorCertificateDER() throws -> Data {
        let issuerKey = P256.Signing.PrivateKey()
        let subjectKey = P256.Signing.PrivateKey()
        let issuerName = try DistinguishedName { CommonName("Some Other Root CA") }
        let subjectName = try DistinguishedName { CommonName(RootCertificateRemover.expectedCommonName) }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(subjectKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-3_600),
            notValidAfter: Date().addingTimeInterval(3_600),
            issuer: issuerName,
            subject: subjectName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            },
            issuerPrivateKey: Certificate.PrivateKey(issuerKey)
        )
        return try installTestCertificateDER(certificate)
    }
}

// MARK: - FakeInstallKeychain

/// An in-memory stand-in for one keychain and the `.admin` trust domain.
///
/// It deliberately offers no deletion of any kind: `RootCertificateInstallOperations` has none, so
/// an installation that tried to remove something could not even be expressed here.
private final class FakeInstallKeychain: RootCertificateInstallOperations {
    struct Entry {
        let derData: Data
        let serialNumber: Data
        let label: String
    }

    var entries: [Entry] = []

    /// Certificates whose `.admin` settings read as positive trust.
    var positivelyTrustedDERs: [Data] = []

    /// Certificates carrying settings that exist but deny — presence without trust.
    var deniedDERs: [Data] = []

    var addFailure: RootCertificateInstallError?
    var serialQueryFailure: RootCertificateInstallError?
    var trustReadFailure: RootCertificateInstallError?
    var trustWriteFailure: RootCertificateInstallError?

    /// Forces the reported add outcome without changing what is actually installed.
    var addOutcomeOverride: CertificateAddOutcome?

    /// Reports a successful add while installing nothing.
    var addIsNoOp = false

    /// Reports a successful trust write while trust stays negative.
    var trustWriteIsNoOp = false

    /// The keychain item disappears as the trust write rewrites it.
    var trustWriteRemovesCertificate = false

    /// Every add the installer attempted, in order, by the label it asked for.
    private(set) var addAttempts: [String] = []
    private(set) var trustWriteDERs: [Data] = []

    var installedDERs: [Data] {
        entries.map(\.derData)
    }

    /// True once any privileged side effect has been attempted.
    var hasMutated: Bool {
        !addAttempts.isEmpty || !trustWriteDERs.isEmpty
    }

    func preinstall(der: Data, label: String, positivelyTrusted: Bool) throws {
        try entries.append(Entry(derData: der, serialNumber: installTestSerialNumber(of: der), label: label))
        if positivelyTrusted {
            positivelyTrustedDERs.append(der)
        }
    }

    func systemCertificates(serialNumber: Data) throws -> [SystemKeychainCertificate] {
        if let serialQueryFailure {
            throw serialQueryFailure
        }
        return entries
            .filter { $0.serialNumber == serialNumber }
            .map { SystemKeychainCertificate(reference: $0.derData as NSData, derData: $0.derData) }
    }

    func addCertificate(derData: Data, label: String) throws -> CertificateAddOutcome {
        addAttempts.append(label)
        if let addFailure {
            throw addFailure
        }
        if let addOutcomeOverride {
            return addOutcomeOverride
        }
        guard !addIsNoOp else {
            return .added
        }
        // A keychain rejects a certificate it already holds; it does not add a second copy.
        guard !entries.contains(where: { $0.derData == derData }) else {
            return .duplicate
        }
        try entries.append(Entry(
            derData: derData,
            serialNumber: installTestSerialNumber(of: derData),
            label: label
        ))
        return .added
    }

    func hasPositiveAdminTrustSettings(derData: Data) throws -> Bool {
        if let trustReadFailure {
            throw trustReadFailure
        }
        return positivelyTrustedDERs.contains(derData)
    }

    func setAdminTrustRoot(derData: Data) throws {
        trustWriteDERs.append(derData)
        if let trustWriteFailure {
            throw trustWriteFailure
        }
        if trustWriteRemovesCertificate {
            entries.removeAll { $0.derData == derData }
        }
        guard !trustWriteIsNoOp else {
            return
        }
        deniedDERs.removeAll { $0 == derData }
        positivelyTrustedDERs.append(derData)
    }
}

// MARK: - Shared Helpers

private func installTestCertificateDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}

private func installTestSerialNumber(of derData: Data) throws -> Data {
    let certificate = try #require(SecCertificateCreateWithData(nil, derData as CFData))
    return try #require(SecCertificateCopySerialNumberData(certificate, nil) as Data?)
}
