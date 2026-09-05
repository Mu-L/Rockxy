import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Drives the real Security.framework adapter — the native add, the persistent-reference label
// update and readback, the exact-DER discovery, and the delete with its absence check — against a
// keychain the test creates and destroys itself.
//
// Two boundaries make that safe, and both are asserted rather than assumed:
//
// - The keychain is a disposable password keychain whose filename contains neither `login.keychain`
//   nor `login.keychain-db`. macOS silently adds those names to the user's search list; a fixture
//   carrying one would leak into every keychain search the machine performs afterwards. Each suite
//   also compares the search list before and after its work.
// - Trust settings are injected. Nothing here can reach the real `.admin` domain, so no test can
//   write, or remove, a system-wide trust decision on the developer's machine.

// MARK: - SystemKeychainCertificateAdapterTests

@Suite(.serialized)
struct SystemKeychainCertificateAdapterTests {
    // MARK: Internal

    @Test("inconsistent trust snapshots throw instead of licensing another trust write")
    func malformedTrustSnapshotIsUnavailable() {
        for snapshot in [
            AdminTrustSettingsSnapshot(exists: true, entries: nil),
            AdminTrustSettingsSnapshot(exists: false, entries: []),
        ] {
            let adapter = SystemKeychainCertificateOperations(
                keychainPath: "/unused-test-keychain",
                trust: MalformedAdminTrustSettings(snapshot: snapshot)
            )
            #expect(throws: RootCertificateRemovalError.malformedKeychainResult(operation: "read positive admin trust")) {
                _ = try adapter.hasPositiveAdminTrustSettings(derData: Data())
            }
        }
    }

    @Test("a native add labels exactly the new item and reads back by serial and exact DER")
    func addLabelsAndReadsBackTheExactItem() throws {
        let fixture = try KeychainFixture()
        defer { fixture.destroy() }

        let der = try adapterTestRootDER()
        #expect(try fixture.adapter.addCertificate(derData: der, label: "rockxy-fixture") == .added)

        let found = try fixture.adapter.systemCertificates(serialNumber: adapterTestSerialNumber(of: der))
        #expect(found.map(\.derData) == [der])
        // Discovery hands back the *persistent* reference, which is what a delete can address
        // after a transient SecCertificate has stopped resolving.
        #expect((found.first?.reference as? Data)?.isEmpty == false)

        let byLabel = try fixture.adapter.systemCertificates(label: "rockxy-fixture")
        #expect(byLabel.map(\.derData) == [der])
        #expect(try fixture.searchListIsUnchanged)
    }

    @Test("a second add of the same certificate reports a duplicate and installs nothing new")
    func duplicateAddInstallsNothingNew() throws {
        let fixture = try KeychainFixture()
        defer { fixture.destroy() }

        let der = try adapterTestRootDER()
        #expect(try fixture.adapter.addCertificate(derData: der, label: "rockxy-fixture") == .added)
        #expect(try fixture.adapter.addCertificate(derData: der, label: "rockxy-fixture") == .duplicate)

        #expect(try fixture.adapter.systemCertificates(serialNumber: adapterTestSerialNumber(of: der)).count == 1)
        #expect(try fixture.searchListIsUnchanged)
    }

    @Test("a certificate sharing the serial number is neither confused with nor removed with the target")
    func sameSerialSentinelSurvives() throws {
        let fixture = try KeychainFixture()
        defer { fixture.destroy() }

        let root = try RootCAGenerator.generate()
        let targetDER = try adapterTestDER(root.certificate)
        let sentinelDER = try adapterTestSameSerialCertificateDER(serialNumber: root.certificate.serialNumber)

        _ = try fixture.adapter.addCertificate(derData: targetDER, label: "rockxy-fixture.target")
        _ = try fixture.adapter.addCertificate(derData: sentinelDER, label: "rockxy-fixture.sentinel")

        let serial = try adapterTestSerialNumber(of: targetDER)
        #expect(try adapterTestSerialNumber(of: sentinelDER) == serial)
        // The serial number only narrows the search; the bytes decide.
        #expect(try fixture.adapter.systemCertificates(serialNumber: serial).count == 2)

        try RootCertificateRemover.removeExactCertificate(derData: targetDER, using: fixture.adapter)

        let remaining = try fixture.adapter.systemCertificates(serialNumber: serial).map(\.derData)
        #expect(remaining == [sentinelDER])
        #expect(fixture.trust.writes.isEmpty)
        #expect(try fixture.searchListIsUnchanged)
    }

    @Test("add and exact delete repeat without a spurious not-found, and preserve a sentinel")
    func repeatedAddAndDeleteIsStable() throws {
        let fixture = try KeychainFixture()
        defer { fixture.destroy() }

        let sentinelDER = try adapterTestRootDER()
        _ = try fixture.adapter.addCertificate(derData: sentinelDER, label: "rockxy-fixture.sentinel")

        // A transient SecCertificate can stop addressing its item while the item is still
        // installed, which surfaced as `errSecItemNotFound` (-25300) from the delete and then as a
        // failed absence check. Repetition is what exposed it.
        for index in 0 ..< 15 {
            let der = try adapterTestRootDER()
            _ = try fixture.adapter.addCertificate(derData: der, label: "rockxy-fixture.\(index)")

            let outcome = try RootCertificateRemover.removeExactCertificate(derData: der, using: fixture.adapter)
            #expect(outcome.removedCertificateCount == 1)
            #expect(try fixture.adapter.systemCertificates(serialNumber: adapterTestSerialNumber(of: der)).isEmpty)

            // Removing it again is an idempotent no-op, not a failure.
            let repeated = try RootCertificateRemover.removeExactCertificate(derData: der, using: fixture.adapter)
            #expect(repeated.removedCertificateCount == 0)
        }

        #expect(try fixture.adapter.systemCertificates(
            serialNumber: adapterTestSerialNumber(of: sentinelDER)
        ).map(\.derData) == [sentinelDER])
        #expect(try fixture.searchListIsUnchanged)
    }

    @Test("the installer over the native adapter adds, trusts, and stays idempotent")
    func nativeInstallIsAdditiveAndIdempotent() throws {
        let fixture = try KeychainFixture()
        defer { fixture.destroy() }

        let older = try adapterTestRootDER()
        _ = try fixture.adapter.addCertificate(derData: older, label: "rockxy-fixture")
        fixture.trust.markPositivelyTrusted(older)

        let target = try adapterTestRootDER()
        let first = try RootCertificateInstaller.installTrustedRoot(
            derData: target, label: "rockxy-fixture", using: fixture.adapter
        )
        let second = try RootCertificateInstaller.installTrustedRoot(
            derData: target, label: "rockxy-fixture", using: fixture.adapter
        )

        #expect(first.addedCertificate)
        #expect(first.appliedTrustSettings)
        #expect(second.addedCertificate == false)
        #expect(second.appliedTrustSettings == false)
        // One trust write in total, and the older root is still installed and still trusted.
        #expect(fixture.trust.writes == [target])
        #expect(fixture.trust.removals.isEmpty)
        #expect(try fixture.adapter.hasPositiveAdminTrustSettings(derData: older))
        #expect(try fixture.adapter.systemCertificates(
            serialNumber: adapterTestSerialNumber(of: older)
        ).map(\.derData) == [older])
        #expect(try fixture.searchListIsUnchanged)
    }

    // MARK: Private

    private struct MalformedAdminTrustSettings: AdminTrustSettingsAccess {
        let snapshot: AdminTrustSettingsSnapshot

        func adminTrustSettings(derData _: Data) throws -> AdminTrustSettingsSnapshot { snapshot }
        func setAdminTrustRoot(derData _: Data) throws { Issue.record("Unexpected trust write") }
        func removeAdminTrustSettings(derData _: Data) throws { Issue.record("Unexpected trust removal") }
    }

    /// A disposable password keychain plus the adapter bound to it.
    private final class KeychainFixture {
        // MARK: Lifecycle

        init() throws {
            let originalSearchList = try Self.searchListPaths()
            // Deliberately not `*login.keychain*`: macOS adds those paths to the user's search
            // list on sight, and a fixture that did so would outlive the test.
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("RockxyKeychainFixture-\(UUID().uuidString).kc")
                .path
            #expect(path.contains("login.keychain") == false)

            let password = Array("rockxy-fixture-\(UUID().uuidString)".utf8)
            var created: SecKeychain?
            let status = SecKeychainCreate(path, UInt32(password.count), password, false, nil, &created)
            try #require(status == errSecSuccess, "SecKeychainCreate failed with \(status)")
            keychain = try #require(created)
            searchListAtCreation = originalSearchList

            trust = RecordingAdminTrustSettings()
            adapter = SystemKeychainCertificateOperations(keychainPath: path, trust: trust)
            do {
                try #require(try Self.searchListPaths() == originalSearchList)
            } catch {
                #expect(SecKeychainDelete(keychain) == errSecSuccess)
                throw error
            }
        }

        // MARK: Internal

        let adapter: SystemKeychainCertificateOperations
        let trust: RecordingAdminTrustSettings

        /// The fixture must never join the user's keychain search list.
        var searchListIsUnchanged: Bool {
            get throws {
                try Self.searchListPaths() == searchListAtCreation
            }
        }

        static func searchListPaths() throws -> [String] {
            var list: CFArray?
            let status = SecKeychainCopySearchList(&list)
            try #require(status == errSecSuccess, "Search list read failed: \(status)")
            let keychains = try #require(list as? [SecKeychain])
            return try keychains.map { keychain in
                var length = UInt32(PATH_MAX)
                var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
                let pathStatus = SecKeychainGetPath(keychain, &length, &buffer)
                try #require(pathStatus == errSecSuccess, "Keychain path read failed: \(pathStatus)")
                return String(cString: buffer)
            }
        }

        func destroy() {
            #expect(SecKeychainDelete(keychain) == errSecSuccess)
            do {
                #expect(try Self.searchListPaths() == searchListAtCreation)
            } catch {
                Issue.record(error)
            }
        }

        // MARK: Private

        private let keychain: SecKeychain
        private let searchListAtCreation: [String]
    }

    /// Injected `.admin` trust settings. Nothing here reaches the real trust domain.
    private final class RecordingAdminTrustSettings: AdminTrustSettingsAccess {
        // MARK: Internal

        private(set) var writes: [Data] = []
        private(set) var removals: [Data] = []

        func markPositivelyTrusted(_ derData: Data) {
            // An empty settings array is the SDK's "always trust this certificate".
            settings[derData] = []
        }

        func adminTrustSettings(derData: Data) throws -> AdminTrustSettingsSnapshot {
            guard let entries = settings[derData] else {
                return .absent
            }
            return AdminTrustSettingsSnapshot(exists: true, entries: entries)
        }

        func setAdminTrustRoot(derData: Data) throws {
            writes.append(derData)
            markPositivelyTrusted(derData)
        }

        func removeAdminTrustSettings(derData: Data) throws {
            removals.append(derData)
            settings[derData] = nil
        }

        // MARK: Private

        private var settings: [Data: [[String: Any]]] = [:]
    }
}

// MARK: - Shared Helpers

private func adapterTestDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}

private func adapterTestRootDER() throws -> Data {
    try adapterTestDER(RootCAGenerator.generate().certificate)
}

private func adapterTestSerialNumber(of derData: Data) throws -> Data {
    let certificate = try #require(SecCertificateCreateWithData(nil, derData as CFData))
    return try #require(SecCertificateCopySerialNumberData(certificate, nil) as Data?)
}

/// Another issuer's certificate carrying the same serial number, so the indexed lookup returns
/// both and only the exact bytes can tell them apart.
private func adapterTestSameSerialCertificateDER(serialNumber: Certificate.SerialNumber) throws -> Data {
    let key = P256.Signing.PrivateKey()
    let name = try DistinguishedName { CommonName("Adapter Sentinel \(UUID().uuidString)") }
    let certificate = try Certificate(
        version: .v3,
        serialNumber: serialNumber,
        publicKey: Certificate.PublicKey(key.publicKey),
        notValidBefore: Date().addingTimeInterval(-3_600),
        notValidAfter: Date().addingTimeInterval(3_600),
        issuer: name,
        subject: name,
        signatureAlgorithm: .ecdsaWithSHA256,
        extensions: Certificate.Extensions(),
        issuerPrivateKey: Certificate.PrivateKey(key)
    )
    return try adapterTestDER(certificate)
}
