import Crypto
import Foundation
import NIOSSL
import SwiftASN1
import UniformTypeIdentifiers
import X509

// MARK: - CertificateExportFormat

enum CertificateExportFormat: CaseIterable, Equatable, Hashable {
    case privateKey
    case rootCertificateP12
    case rootCertificatePEM
    case rootCertificateDER

    // MARK: Internal

    var menuTitle: String {
        switch self {
        case .privateKey:
            String(localized: "Private Key…", bundle: RockxyLocalization.bundle)
        case .rootCertificateP12:
            String(localized: "Root Certificate as P12…", bundle: RockxyLocalization.bundle)
        case .rootCertificatePEM:
            String(localized: "Root Certificate as PEM…", bundle: RockxyLocalization.bundle)
        case .rootCertificateDER:
            String(localized: "Root Certificate as DER…", bundle: RockxyLocalization.bundle)
        }
    }

    var defaultFileName: String {
        switch self {
        case .privateKey:
            "RockxyCA-PrivateKey.pem"
        case .rootCertificateP12:
            "RockxyCA.p12"
        case .rootCertificatePEM:
            "RockxyCA.pem"
        case .rootCertificateDER:
            "RockxyCA.der"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .privateKey,
             .rootCertificatePEM:
            [UTType(filenameExtension: "pem") ?? .data]
        case .rootCertificateP12:
            [UTType(filenameExtension: "p12") ?? .data]
        case .rootCertificateDER:
            [UTType(filenameExtension: "der") ?? .data]
        }
    }

    var containsPrivateMaterial: Bool {
        switch self {
        case .privateKey,
             .rootCertificateP12:
            true
        case .rootCertificatePEM,
             .rootCertificateDER:
            false
        }
    }
}

// MARK: - CertificateExportPayload

struct CertificateExportPayload: Equatable {
    let format: CertificateExportFormat
    let defaultFileName: String
    let data: Data
    let containsPrivateMaterial: Bool
}

// MARK: - CertificateExportMaterial

struct CertificateExportMaterial {
    let certificate: Certificate?
    let privateKey: P256.Signing.PrivateKey?
}

// MARK: - CertificateExportService

struct CertificateExportService {
    // MARK: Lifecycle

    init(
        materialProvider: @escaping MaterialProvider,
        writeHandler: @escaping WriteHandler = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.materialProvider = materialProvider
        self.writeHandler = writeHandler
    }

    // MARK: Internal

    typealias MaterialProvider = @Sendable () async throws -> CertificateExportMaterial
    typealias WriteHandler = @Sendable (Data, URL) throws -> Void

    func payload(for format: CertificateExportFormat) async throws -> CertificateExportPayload {
        let material = try await materialProvider()
        guard let certificate = material.certificate else {
            throw CertificateExportError.missingCertificate
        }

        let data: Data
        switch format {
        case .rootCertificatePEM:
            data = try Data(certificatePEM(certificate).utf8)
        case .rootCertificateDER:
            data = try certificateDER(certificate)
        case .privateKey:
            guard let privateKey = material.privateKey else {
                throw CertificateExportError.missingPrivateKey
            }
            data = Data(privateKey.pemRepresentation.utf8)
        case .rootCertificateP12:
            guard let privateKey = material.privateKey else {
                throw CertificateExportError.missingPrivateKey
            }
            data = try p12Data(certificate: certificate, privateKey: privateKey)
        }

        return CertificateExportPayload(
            format: format,
            defaultFileName: format.defaultFileName,
            data: data,
            containsPrivateMaterial: format.containsPrivateMaterial
        )
    }

    func export(_ payload: CertificateExportPayload, to url: URL) throws {
        try writeHandler(payload.data, url)
    }

    // MARK: Private

    private let materialProvider: MaterialProvider
    private let writeHandler: WriteHandler

    private func certificatePEM(_ certificate: Certificate) throws -> String {
        let der = try certificateDER(certificate)
        return PEMDocument(type: "CERTIFICATE", derBytes: Array(der)).pemString
    }

    private func certificateDER(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    private func p12Data(certificate: Certificate, privateKey: P256.Signing.PrivateKey) throws -> Data {
        let cert = try NIOSSLCertificate(bytes: Array(certificateDER(certificate)), format: .der)
        let key = try NIOSSLPrivateKey(bytes: Array(privateKey.pemRepresentation.utf8), format: .pem)
        let bundle = NIOSSLPKCS12Bundle(certificateChain: [cert], privateKey: key)
        return try Data(bundle.serialize(passphrase: [UInt8]()))
    }
}

// MARK: - CertificateExportError

enum CertificateExportError: LocalizedError, Equatable {
    case missingCertificate
    case missingPrivateKey

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .missingCertificate:
            String(localized: "Rockxy has not generated a root certificate yet.", bundle: RockxyLocalization.bundle)
        case .missingPrivateKey:
            String(localized: "Rockxy could not find the root CA private key.", bundle: RockxyLocalization.bundle)
        }
    }
}
