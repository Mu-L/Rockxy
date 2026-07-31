import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - TestStoreError

private enum TestStoreError: Error {
    case injectedDelete
    case injectedPersistence
}

// MARK: - MemorySecureDataStore

private final class MemorySecureDataStore: SecureDataStore, @unchecked Sendable {
    func save(_ data: Data, account: String) throws {
        lock.withLock {
            saveCount += 1
            values[account] = data
        }
    }

    func load(account: String) throws -> Data? {
        lock.withLock {
            loadCount += 1
            return values[account]
        }
    }

    func delete(account: String) throws {
        try lock.withLock {
            deleteCount += 1
            if failingDeleteAccounts.contains(account) {
                throw TestStoreError.injectedDelete
            }
            values.removeValue(forKey: account)
        }
    }

    func failDelete(account: String) {
        lock.withLock {
            _ = failingDeleteAccounts.insert(account)
        }
    }

    func data(account: String) -> Data? {
        lock.withLock { values[account] }
    }

    func accounts() -> Set<String> {
        lock.withLock { Set(values.keys) }
    }

    func operationCounts() -> (save: Int, load: Int, delete: Int) {
        lock.withLock { (saveCount, loadCount, deleteCount) }
    }

    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failingDeleteAccounts = Set<String>()
    private var saveCount = 0
    private var loadCount = 0
    private var deleteCount = 0
}

// MARK: - FaultingMetadataWriter

private final class FaultingMetadataWriter: CustomCertificateMetadataWriter, @unchecked Sendable {
    func write(_ data: Data, to url: URL) throws {
        try lock.withLock {
            writeCount += 1
            if shouldFail {
                throw TestStoreError.injectedPersistence
            }
            if let failingWriteNumber, writeCount == failingWriteNumber {
                throw TestStoreError.injectedPersistence
            }
            try base.write(data, to: url)
        }
    }

    func failWrites() {
        lock.withLock {
            shouldFail = true
        }
    }

    func failAfterSuccessfulWrites(_ count: Int) {
        lock.withLock {
            failingWriteNumber = writeCount + count + 1
        }
    }

    private let lock = NSLock()
    private let base = FileCustomCertificateMetadataWriter()
    private var shouldFail = false
    private var writeCount = 0
    private var failingWriteNumber: Int?
}

// MARK: - CustomCertificateManagerTests

struct CustomCertificateManagerTests {
    @Test("imports custom root certificate and exposes it as active issuer")
    func importsCustomRootIssuer() throws {
        let manager = makeManager()
        let root = try RootCAGenerator.generate()

        let metadata = try manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: try pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )

        let issuer = try #require(try manager.activeRootIssuer())
        #expect(issuer.certificate.subject == root.certificate.subject)
        #expect(issuer.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)

        let snapshot = try #require(try manager.activeRootIssuerSnapshot())
        #expect(snapshot.certificate.subject == root.certificate.subject)
        #expect(snapshot.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)
        #expect(snapshot.fingerprintSHA256 == metadata.fingerprintSHA256)
    }

    @Test("normalizes DER certificate imports into PEM identity material")
    func normalizesDERCertificateImports() throws {
        let root = try RootCAGenerator.generate()
        let certificateDER = try der(root.certificate)

        let identity = try CustomCertificateImportIdentity.fromCertificateAndPrivateKey(
            certificateData: certificateDER,
            privateKeyData: Data(root.privateKey.pemRepresentation.utf8),
            displayName: "DER Root"
        )

        let certificate = try Certificate(pemEncoded: identity.certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: identity.privateKeyPEM)
        #expect(identity.displayName == "DER Root")
        #expect(certificate.subject == root.certificate.subject)
        #expect(privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)
    }

    @Test("normalizes P12 imports into PEM identity material")
    func normalizesPKCS12Imports() throws {
        let data = try #require(Data(base64Encoded: Self.pkcs12FixtureBase64, options: .ignoreUnknownCharacters))

        let identity = try CustomCertificateImportIdentity.fromPKCS12(
            data: data,
            displayName: "P12 Root",
            passphrase: "rockxy"
        )

        let certificate = try Certificate(pemEncoded: identity.certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: identity.privateKeyPEM)
        #expect(identity.displayName == "P12 Root")
        #expect(String(describing: certificate.subject).contains("Rockxy Test P12"))
        #expect(privateKey.publicKey.subjectPublicKeyInfoBytes == certificate.publicKey.subjectPublicKeyInfoBytes)
    }

    @Test("matches exact and wildcard server certificate hosts")
    func matchesServerHostPatterns() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "api.example.com")

        try manager.importServerIdentity(
            hostPattern: "*.example.com",
            displayName: "Pinned Server",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.serverIdentity(for: "api.example.com") != nil)
        #expect(manager.serverIdentity(for: "example.com") == nil)
        #expect(manager.serverIdentity(for: "api.example.net") == nil)
    }

    @Test("matches client certificates only for configured hosts")
    func matchesClientHostPatterns() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "mtls.example.com")

        try manager.importClientIdentity(
            hostPattern: "mtls.example.com",
            displayName: "mTLS Client",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.clientIdentity(for: "mtls.example.com") != nil)
        #expect(manager.clientIdentity(for: "www.example.com") == nil)
    }

    @Test("rejects invalid certificate key pairs")
    func rejectsInvalidCertificateKeyPairs() throws {
        let manager = makeManager()
        let first = try makeLeafIdentity(host: "one.example.com")
        let second = try makeLeafIdentity(host: "two.example.com")

        #expect(throws: CustomCertificateError.invalidCertificateKeyPair) {
            try manager.importServerIdentity(
                hostPattern: "one.example.com",
                displayName: "Invalid",
                certificatePEM: first.certificatePEM,
                privateKeyPEM: second.privateKeyPEM
            )
        }
    }

    @Test("delete and revert remove custom certificate behavior")
    func deleteAndRevert() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "delete.example.com")
        let entry = try manager.importServerIdentity(
            hostPattern: "delete.example.com",
            displayName: "Delete Me",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.serverIdentity(for: "delete.example.com") != nil)
        try manager.delete(id: entry.id)
        #expect(manager.serverIdentity(for: "delete.example.com") == nil)
    }

    @Test("replacing an exact normalized host removes the superseded private key")
    func replacementRemovesSupersededPrivateKey() throws {
        let fixture = makeFixture()
        let firstIdentity = try makeLeafIdentity(host: "api.example.com")
        let secondIdentity = try makeLeafIdentity(host: "api.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: " API.Example.com ",
            displayName: "First",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )

        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Second",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )

        #expect(fixture.manager.metadata(kind: .server) == [secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) == nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)
    }

    @Test("replacement persistence failure preserves old metadata and removes the new private key")
    func replacementPersistenceFailureRollsBack() throws {
        let writer = FaultingMetadataWriter()
        let fixture = makeFixture(metadataWriter: writer)
        let firstIdentity = try makeLeafIdentity(host: "api.example.com")
        let secondIdentity = try makeLeafIdentity(host: "api.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "First",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let accountsBeforeReplacement = fixture.store.accounts()
        writer.failWrites()

        #expect(throws: TestStoreError.self) {
            try fixture.manager.importServerIdentity(
                hostPattern: "API.EXAMPLE.COM",
                displayName: "Second",
                certificatePEM: secondIdentity.certificatePEM,
                privateKeyPEM: secondIdentity.privateKeyPEM
            )
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry])
        #expect(fixture.store.accounts() == accountsBeforeReplacement)
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
    }

    @Test("delete-all key failure restores prior keys, metadata, and persisted snapshot")
    func deleteAllFailureDoesNotPartiallyPublish() throws {
        let fixture = makeFixture()
        let firstIdentity = try makeLeafIdentity(host: "one.example.com")
        let secondIdentity = try makeLeafIdentity(host: "two.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "one.example.com",
            displayName: "One",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "two.example.com",
            displayName: "Two",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )
        fixture.store.failDelete(account: secondEntry.keychainAccount)

        #expect(throws: TestStoreError.self) {
            try fixture.manager.deleteAll(kind: .server)
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry, secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)

        let reloaded = CustomCertificateManager(
            storageURL: fixture.storageURL,
            secureStore: fixture.store
        )
        #expect(reloaded.metadata(kind: .server) == [firstEntry, secondEntry])
    }

    @Test("rollback failure surfaces a non-sensitive recovery error")
    func rollbackFailureIsExplicit() throws {
        let writer = FaultingMetadataWriter()
        let fixture = makeFixture(metadataWriter: writer)
        let firstIdentity = try makeLeafIdentity(host: "one.example.com")
        let secondIdentity = try makeLeafIdentity(host: "two.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "one.example.com",
            displayName: "One",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "two.example.com",
            displayName: "Two",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )
        fixture.store.failDelete(account: secondEntry.keychainAccount)
        writer.failAfterSuccessfulWrites(1)

        #expect(throws: CustomCertificateTransactionError.self) {
            try fixture.manager.deleteAll(kind: .server)
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry, secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)
    }

    @Test("deleting an unknown identifier performs no persistence or secure-store work")
    func deletingUnknownIdentifierIsNoOp() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "known.example.com")
        let entry = try fixture.manager.importServerIdentity(
            hostPattern: "known.example.com",
            displayName: "Known",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
        let operationCounts = fixture.store.operationCounts()

        try fixture.manager.delete(id: UUID())

        #expect(fixture.manager.metadata(kind: .server) == [entry])
        let finalCounts = fixture.store.operationCounts()
        #expect(finalCounts.save == operationCounts.save)
        #expect(finalCounts.load == operationCounts.load)
        #expect(finalCounts.delete == operationCounts.delete)
    }

    @Test("deleting metadata retains a private key account still referenced by another entry")
    func deletionRetainsSharedAccount() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "shared.example.com")
        let imported = try fixture.manager.importServerIdentity(
            hostPattern: "shared.example.com",
            displayName: "Imported",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
        let retained = CustomCertificateMetadata(
            id: UUID(),
            kind: .client,
            displayName: "Shared Account",
            hostPattern: "shared.example.com",
            certificatePEM: imported.certificatePEM,
            keychainAccount: imported.keychainAccount,
            createdAt: imported.createdAt.addingTimeInterval(1),
            notValidBefore: imported.notValidBefore,
            notValidAfter: imported.notValidAfter,
            fingerprintSHA256: imported.fingerprintSHA256
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileCustomCertificateMetadataWriter().write(
            encoder.encode([imported, retained]),
            to: fixture.storageURL
        )
        let manager = CustomCertificateManager(
            storageURL: fixture.storageURL,
            secureStore: fixture.store
        )
        let deleteCount = fixture.store.operationCounts().delete

        try manager.delete(id: imported.id)

        #expect(manager.metadata() == [retained])
        #expect(fixture.store.data(account: retained.keychainAccount) != nil)
        #expect(fixture.store.operationCounts().delete == deleteCount)
    }

    private func makeManager() -> CustomCertificateManager {
        makeFixture().manager
    }

    private func makeFixture(
        metadataWriter: any CustomCertificateMetadataWriter = FileCustomCertificateMetadataWriter()
    ) -> (manager: CustomCertificateManager, store: MemorySecureDataStore, storageURL: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCustomCertificateTests-\(UUID().uuidString)")
            .appendingPathComponent("custom.json")
        let store = MemorySecureDataStore()
        return (
            CustomCertificateManager(
                storageURL: url,
                secureStore: store,
                metadataWriter: metadataWriter
            ),
            store,
            url
        )
    }

    private func makeLeafIdentity(host: String) throws -> (certificatePEM: String, privateKeyPEM: String) {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(host: host, issuer: root.certificate, issuerKey: root.privateKey)
        return (try pem(leaf.certificate), leaf.privateKey.pemRepresentation)
    }

    private func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }

    private func der(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    private static let pkcs12FixtureBase64 = """
    MIIEVAIBAzCCBAIGCSqGSIb3DQEHAaCCA/MEggPvMIID6zCCApoGCSqGSIb3DQEHBqCCAoswggKHAgEAMIICgAYJKoZIhvcNAQcB
    MF8GCSqGSIb3DQEFDTBSMDEGCSqGSIb3DQEFDDAkBBAxNpLso9in7R8sCZHKAQ/xAgIIADAMBggqhkiG9w0CCQUAMB0GCWCGSAFl
    AwQBKgQQtIhtwh53A4jQwcbZNZ/0OYCCAhC8RRu7BAQmpemAYSUHfARZl7twbOUeL6EPletqYeFjUeZWHl5QgNrL37lYG0PJMZ85
    nivPXKtk2vduLcZN3yogsy8U5o7qbXH3dEFbclPBWkf6xGiVhmGWw2M6auOWvMDeoqLZORQBTQpuniDpNqZw0G3Htr8rQwHeHvOH
    SFu/FqKi8VZMPaiRJ1KCrHSpQ4z/Qjver5Vs83lawuTZpXO3QYEJattVmvpy1ekEcGA/TH0+q6qnMWpdZXAAKFW6McmsBvMOiXZ3I
    gcNmnrhsqGBmYRa3tozFmZw4JLrq12KaQMQBL0mwMDaezbIbIRFmYuuCdxtEtPHi6tIZTuOtP3GB26L3693YE1uyOv1cmPEHNTD+
    3+TmgNDhpqf9+gGLLk5SD0D5lDGs9tYPonxGaKvWCL9vjr8ALfFYFN2bjXPmz87gKsxK8JVz1JxYRKqHfPyCn9rc71ClJbpyqfUa
    W7eWT67tkf3EIEl5aTAxm4UC8iNMhJbp2LboZ3zlzDNUEGTLmhMj/lOgSpePYBi2A28sZOzh1Uyu7PwPd51+2mnElQpRMgDmkr54
    rfvHWi/ZAA6/fiTaHl8ap4GFE0dXYoKFg75g54a7KhoENbCygMhBHGHC2SfdNeGyIqCvh//H7UrYN9uV+kDJkdYX6CAtvdmAAYDs
    fzhS6w+X2geQ0a7tCPp1Wey/X6iwTIa/Q2Gxv4wggFJBgkqhkiG9w0BBwGgggE6BIIBNjCCATIwggEuBgsqhkiG9w0BDAoBAqCB
    9zCB9DBfBgkqhkiG9w0BBQ0wUjAxBgkqhkiG9w0BBQwwJAQQBl3K6hD6S8KYv0PTRbAQSgICCAAwDAYIKoZIhvcNAgkFADAdBglg
    hkgBZQMEASoEEBP5A+ukk/fjo0zTeE+6KGQEgZDMc5QbtzBFYUW+GBr7rsmOnFFetxPwgHKrhF4sA1+2yTS5Et7geiUS0bRjmD0K
    918wZ2SnzLV+vvzv6HNJ0S4k8CW1C0lvdt8ZYcoqTkaqX8reOFS43JI/e1uDf+xe2ViAR88gj01iKaZ74pwhUufeYR9vo+SVCHP
    FhO1DNJ8eH+6lFnGEq+F37180LrCYDEoxJTAjBgkqhkiG9w0BCRUxFgQU9+YayiugoLHt103H3Ff2GbmU5/wwSTAxMA0GCWCGSAFl
    AwQCAQUABCCJFNm8nMsKzM5csV9O+pPY5WIF5jdz97gF+KzNWYDYPAQQqJeQHo2mDjCsjalH8p7WxwICCAA=
    """
}
