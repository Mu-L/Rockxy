import AppKit
import Combine
import Foundation
import os

// MARK: - CAShareController

@MainActor
final class CAShareController: ObservableObject {
    // MARK: Internal

    @Published var currentSession: RootCADownloadSession?
    @Published var currentFingerprint: String?

    static func userFacingMessage(for error: Error) -> String {
        switch error {
        case let error as RootCADownloadError:
            switch error {
            case .tokenGenerationFailed:
                String(
                    localized: "Could not create a secure certificate sharing token. Try again.",
                    bundle: RockxyLocalization.bundle
                )
            case .invalidSessionURL:
                String(
                    localized: "Could not build the certificate sharing URL. Try again.",
                    bundle: RockxyLocalization.bundle
                )
            case .noReachableLANAddress:
                String(
                    localized: "No reachable Wi-Fi or Ethernet IPv4 address was found. Connect this Mac to the same network as the device, then try again.",
                    bundle: RockxyLocalization.bundle
                )
            case .noRootCA:
                String(
                    localized: "No Root CA certificate is available. Generate a Root CA first.",
                    bundle: RockxyLocalization.bundle
                )
            case .portUnavailable:
                String(
                    localized: "Could not start the temporary certificate sharing server. Try again.",
                    bundle: RockxyLocalization.bundle
                )
            }
        case let error as RootCAShareValidationError:
            error.localizedDescription
        default:
            String(
                localized: "Certificate sharing could not be started. Check your network and try again.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    func startSharing() async throws -> RootCADownloadSession {
        operationGeneration += 1
        let generation = operationGeneration
        await shareServer.stop()
        guard operationGeneration == generation else {
            throw CancellationError()
        }

        currentSession = nil
        currentFingerprint = nil

        try await CertificateManager.shared.ensureRootCA()
        guard operationGeneration == generation else {
            throw CancellationError()
        }
        guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
            throw RootCADownloadError.noRootCA
        }
        guard operationGeneration == generation else {
            throw CancellationError()
        }

        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
        guard operationGeneration == generation else {
            throw CancellationError()
        }
        let fingerprint = try RootCAFingerprintVerifier.verifiedFingerprint(
            certificatePEM: pem,
            expectedFingerprint: snapshot.fingerprintSHA256
        )
        let session = try await shareServer.start(certificatePEM: pem)
        guard operationGeneration == generation else {
            throw CancellationError()
        }

        currentFingerprint = fingerprint
        currentSession = session
        return session
    }

    func copyShareURL(sessionURL: URL) throws {
        guard currentFingerprint != nil else {
            Self.logger.error("Refused to copy Root CA share URL because the fingerprint is unavailable.")
            throw RootCAShareValidationError.missingFingerprint
        }
        guard currentSession?.publicURL == sessionURL else {
            Self.logger
                .error(
                    "Refused to copy Root CA share URL because the session URL no longer matches the active share session."
                )
            throw RootCADownloadError.invalidSessionURL
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionURL.absoluteString, forType: .string)
        Self.logger.info("Copied Root CA share URL to the pasteboard.")
    }

    func stopSharing(
        clearSession: Bool,
        expectedSessionID: RootCADownloadSession.ID? = nil
    )
        async
    {
        if let expectedSessionID, currentSession?.id != expectedSessionID {
            return
        }
        operationGeneration += 1
        if clearSession {
            currentSession = nil
            currentFingerprint = nil
        }
        await shareServer.stop()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "CAShareController"
    )

    private let shareServer = RootCADownloadServer()
    private var operationGeneration = 0
}
