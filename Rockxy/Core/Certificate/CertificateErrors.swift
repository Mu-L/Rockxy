import Foundation

// The certificate errors live beside `CertificateManager` rather than inside it: every case is
// read by whoever is trying to trust the root CA — the certificate wizard prints them under
// "Installation failed:" and the Welcome window repeats them — so they are translated, and the
// translated prose is long enough to push the manager past its file-length budget.

// MARK: - CertificateGenerationError

nonisolated enum CertificateGenerationError: LocalizedError {
    case invalidDateComputation

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidDateComputation:
            String(
                localized: "Failed to compute certificate validity dates",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - CertificateManagerError

nonisolated enum CertificateManagerError: LocalizedError, Equatable {
    case noRootCA
    case rootCANotTrusted
    case trustValidationFailed
    case trustInstallationInProgress
    case persistedRootIdentityChanged
    case persistedRootIdentityDrift
    case rootRemovalInProgress
    case rootRemovalIncomplete(String)
    case helperInstallUnavailable(String)
    case trustStateUnavailable(String)

    // MARK: Internal

    /// Read in the certificate wizard's "Installation failed:" panel and the Welcome window, and
    /// most cases tell the reader what to do next, so every one is translated.
    var errorDescription: String? {
        switch self {
        case let .helperInstallUnavailable(detail):
            String(
                localized: "The privileged helper was not used for this installation (\(detail)).",
                bundle: RockxyLocalization.bundle
            )
        case .noRootCA:
            String(
                localized: "Root CA certificate has not been generated",
                bundle: RockxyLocalization.bundle
            )
        case .rootCANotTrusted:
            String(
                localized: "Root CA certificate is not trusted — install and trust the certificate before HTTPS interception",
                bundle: RockxyLocalization.bundle
            )
        case .trustValidationFailed:
            String(
                localized: "macOS has not validated the certificate for TLS. Your certificate and key were kept. Recheck the certificate status in Settings.",
                bundle: RockxyLocalization.bundle
            )
        case .trustInstallationInProgress:
            String(
                localized: "A certificate trust installation is already in progress. Wait for it to finish, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case .persistedRootIdentityChanged:
            String(
                localized: """
                Rockxy's persisted root CA changed while trust was being prepared. \
                Quit other running copies of Rockxy, then try again. \
                No second trust prompt was requested.
                """,
                bundle: RockxyLocalization.bundle
            )
        case .persistedRootIdentityDrift:
            // One key, not three concatenated fragments: a translator has to see the whole
            // sentence to order it.
            String(
                localized: """
                Rockxy's active root CA no longer matches its saved certificate and private key. \
                This can happen after another Rockxy copy or a Keychain restore changed certificate storage. \
                Use Install & Trust Certificate to reconcile it before HTTPS interception.
                """,
                bundle: RockxyLocalization.bundle
            )
        case .rootRemovalInProgress:
            String(
                localized: "A certificate removal is already in progress. Wait for it to finish, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case let .trustStateUnavailable(detail):
            String(
                localized: "Rockxy could not read the certificate's Keychain and trust status, so it did not request administrator approval. Check the status again once the keychain is available (\(detail)).",
                bundle: RockxyLocalization.bundle
            )
        case let .rootRemovalIncomplete(detail):
            String(
                localized: "The installed root CA certificate could not be fully removed, so your local certificate and key were kept. Remove it in Keychain Access and try again (\(detail)).",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
