import Foundation

// MARK: - CertificateSetupState

enum CertificateSetupState: Equatable {
    case installedAndTrusted
    case installedNotTrusted
    case generatedOnly
    case missing
    /// Rockxy could not read the certificate, Keychain, or trust state. Distinct from `missing`
    /// and `installedNotTrusted`: nothing is known, so the answer is a recheck, never a reinstall.
    case statusUnavailable

    // MARK: Lifecycle

    init(snapshot: RootCAStatusSnapshot) {
        // An unreadable status outranks every boolean below it: those are fail-closed defaults
        // for an answer that was never produced, not findings about the certificate.
        if snapshot.isStatusUnavailable {
            self = .statusUnavailable
        } else if snapshot.isInstalledInKeychain, snapshot.isSystemTrustValidated {
            self = .installedAndTrusted
        } else if snapshot.isInstalledInKeychain {
            self = .installedNotTrusted
        } else if snapshot.hasGeneratedCertificate {
            self = .generatedOnly
        } else {
            self = .missing
        }
    }

    // MARK: Internal

    var title: String {
        switch self {
        case .installedAndTrusted:
            String(localized: "Installed & Trusted", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "Installed, Trust Required", bundle: RockxyLocalization.bundle)
        case .generatedOnly:
            String(localized: "Generated, Not Installed", bundle: RockxyLocalization.bundle)
        case .missing:
            String(localized: "Certificate Missing", bundle: RockxyLocalization.bundle)
        case .statusUnavailable:
            String(localized: "Certificate Status Unavailable", bundle: RockxyLocalization.bundle)
        }
    }

    var message: String {
        switch self {
        case .installedAndTrusted:
            String(localized: "Rockxy Certificate is ready.", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(
                localized: "The root CA is installed, but macOS has not fully trusted it for TLS yet.",
                bundle: RockxyLocalization.bundle
            )
        case .generatedOnly:
            String(
                localized: "The root CA exists locally. Install and trust it in Keychain to decrypt HTTPS traffic.",
                bundle: RockxyLocalization.bundle
            )
        case .missing:
            String(
                localized: "Generate Rockxy's root CA, then install and trust it in Keychain.",
                bundle: RockxyLocalization.bundle
            )
        case .statusUnavailable:
            String(
                localized: "Rockxy cannot read the certificate and trust status right now. Nothing was changed — check the status again once your keychain is available.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var systemImageName: String {
        switch self {
        case .installedAndTrusted:
            "checkmark.circle.fill"
        case .installedNotTrusted:
            "exclamationmark.triangle.fill"
        case .generatedOnly:
            "certificate.fill"
        case .missing:
            "xmark.circle.fill"
        case .statusUnavailable:
            "questionmark.circle.fill"
        }
    }

    var isReady: Bool {
        self == .installedAndTrusted
    }
}
