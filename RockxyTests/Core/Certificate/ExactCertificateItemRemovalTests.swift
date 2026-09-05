import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// MARK: - ExactCertificateItemRemovalTests

struct ExactCertificateItemRemovalTests {
    @Test("exact DER selection retains persistent rather than transient item identity")
    func selectsPersistentReferencesByExactDER() throws {
        let der = try certificateDER(RootCAGenerator.generate().certificate)
        var otherDER = der
        otherDER[otherDER.endIndex - 1] ^= 1
        let first = try discoveryItem(der: der, persistent: Data([1, 2]))
        let second = try discoveryItem(der: otherDER, persistent: Data([3, 4]))

        #expect(try KeychainHelper.exactCertificateRemovalReferences(from: [first, second], matching: der)
            == [Data([1, 2])])
        #expect(try KeychainHelper.exactCertificateRemovalReferences(from: [second], matching: der).isEmpty)
    }

    @Test("malformed or unaddressable certificate results cannot widen removal")
    func rejectsMalformedDiscovery() throws {
        let der = try certificateDER(RootCAGenerator.generate().certificate)
        let valid = try discoveryItem(der: der, persistent: Data([1]))
        for key in [kSecValueData, kSecValueRef, kSecValuePersistentRef] {
            var missing = valid
            missing.removeValue(forKey: key as String)
            #expect(throws: KeychainError.self) {
                try KeychainHelper.exactCertificateRemovalReferences(from: [missing], matching: der)
            }
            var wrongType = valid
            wrongType[key as String] = "not an item"
            #expect(throws: KeychainError.self) {
                try KeychainHelper.exactCertificateRemovalReferences(from: [wrongType], matching: der)
            }
        }
        var empty = valid
        empty[kSecValuePersistentRef as String] = Data()
        #expect(throws: KeychainError.self) {
            try KeychainHelper.exactCertificateRemovalReferences(from: [empty], matching: der)
        }
        var mismatched = valid
        mismatched[kSecValueData as String] = Data([0])
        #expect(throws: KeychainError.self) {
            try KeychainHelper.exactCertificateRemovalReferences(from: [mismatched], matching: der)
        }
    }

    @Test("direct native removal is repeatable, idempotent, and preserves another root")
    func repeatedNativeRemovalPreservesSentinel() throws {
        let namespace = "\(TestIdentity.keychainProbeLabel).exact.\(UUID().uuidString)"
        let sentinel = try certificateDER(RootCAGenerator.generate().certificate)
        let sentinelLabel = namespace + ".sentinel"
        try KeychainHelper.installCertificate(sentinel, label: sentinelLabel)
        defer { try? KeychainHelper.removeCertificate(label: sentinelLabel) }

        for index in 0 ..< 25 {
            let der = try certificateDER(RootCAGenerator.generate().certificate)
            let label = namespace + ".\(index)"
            try KeychainHelper.installCertificate(der, label: label)
            defer { try? KeychainHelper.removeCertificate(label: label) }
            #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
            try KeychainHelper.removeRootCATrust(certData: der)
            #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
            #expect(try KeychainHelper.isCertificateInstalledStrict(certData: sentinel))
            try KeychainHelper.removeRootCATrust(certData: der)
        }
    }

    @Test("same serial from another issuer is not a removal target")
    func sameSerialOtherIssuerSurvives() throws {
        let root = try RootCAGenerator.generate()
        let otherKey = P256.Signing.PrivateKey()
        let otherName = try DistinguishedName { CommonName("Removal Sentinel \(UUID().uuidString)") }
        let other = try Certificate(
            version: .v3,
            serialNumber: root.certificate.serialNumber,
            publicKey: .init(otherKey.publicKey),
            notValidBefore: root.certificate.notValidBefore,
            notValidAfter: root.certificate.notValidAfter,
            issuer: otherName,
            subject: otherName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: .init(),
            issuerPrivateKey: .init(otherKey)
        )
        let targetDER = try certificateDER(root.certificate)
        let otherDER = try certificateDER(other)
        let namespace = "\(TestIdentity.keychainProbeLabel).serial.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(targetDER, label: namespace + ".target")
        defer { try? KeychainHelper.removeCertificate(label: namespace + ".target") }
        try KeychainHelper.installCertificate(otherDER, label: namespace + ".other")
        defer { try? KeychainHelper.removeCertificate(label: namespace + ".other") }

        try KeychainHelper.removeRootCATrust(certData: targetDER)

        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: targetDER))
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: otherDER))
    }

    private func discoveryItem(der: Data, persistent: Data) throws -> [String: Any] {
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        return [
            kSecValueData as String: der,
            kSecValueRef as String: certificate,
            kSecValuePersistentRef as String: persistent
        ]
    }
}

private func certificateDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}
