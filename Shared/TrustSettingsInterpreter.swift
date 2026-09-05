import Foundation
import Security

// MARK: - TrustSettingsInterpreter

/// Interprets the trust-settings array `SecTrustSettingsCopyTrustSettings` returns for one
/// certificate in one domain.
///
/// The rules come from the system `Security/SecTrustSettings.h` header (lines 119–160): an
/// empty array means "always trust this certificate" with an implied result of
/// `kSecTrustSettingsResultTrustRoot`, and a constraints dictionary that omits
/// `kSecTrustSettingsResult` defaults to the same result. Everything else stays negative —
/// absent settings, a failed copy, an unconditional deny, an unspecified result, and any value
/// that cannot be read as a result code.
///
/// This is only a prefilter for the expensive check. A positive answer here means "a real
/// `SecTrust` evaluation is worth running", never "the root is trusted". It lives in `Shared`
/// so the privileged helper's install postcondition and the app's readiness prefilter read the
/// same metadata by the same rules — in particular, so neither reads a deny as success.
nonisolated enum TrustSettingsInterpreter {
    // MARK: Internal

    /// The strict reading of one `SecTrustSettingsCopyTrustSettings` result.
    ///
    /// The distinction that matters is between *knowing* there are no settings and *not being
    /// able to tell*. A locked Keychain, a denied authorization, and a payload that is not an
    /// array of dictionaries all describe the domain, not the certificate, so none of them may
    /// collapse into "no trust settings" — that is what turns a failed read into a second
    /// authorization prompt for a root the user already trusted.
    enum DomainRead {
        /// Settings exist and were readable. An empty array is a real, positive answer:
        /// `SecTrustSettings.h` documents it as "always trust this certificate".
        case entries([[String: Any]])
        /// One of the two documented "there are none" statuses.
        case absent
        /// The copy failed with a status that describes the domain.
        case unreadable(status: OSStatus)
        /// The copy succeeded but returned something that is not an array of entries.
        case malformed
    }

    /// How one trust-settings entry contributes to the prefilter.
    enum EntryVerdict: Equatable {
        /// Explicit `trustRoot`, or a constraints entry that omits the result key.
        case trustsRoot
        /// Explicit `deny` that carries no constraints, so it applies to every evaluation.
        case deniesUnconditionally
        /// Explicit `deny` limited to one policy, policy string, application, or key usage.
        /// Whether it applies to the evaluation the caller cares about is `SecTrust`'s
        /// decision; treating it as a blanket veto turns an otherwise trusted root into a
        /// permanent negative and re-prompts the user forever.
        case deniesForConstrainedUse
        /// Unspecified, `trustAsRoot`, an unknown code, or a malformed value.
        case inconclusive
    }

    /// Classifies one copy result. Only `errSecItemNotFound` and `errSecNoTrustSettings` are
    /// absence; every other status, and every successful-but-unreadable payload, is unavailable.
    static func read(status: OSStatus, settings: CFArray?) -> DomainRead {
        switch status {
        case errSecSuccess:
            guard let entries = settings as? [[String: Any]] else {
                return .malformed
            }
            return .entries(entries)
        case errSecItemNotFound,
             errSecNoTrustSettings:
            return .absent
        default:
            return .unreadable(status: status)
        }
    }

    static func verdict(for entry: [String: Any]) -> EntryVerdict {
        guard let rawResult = entry[kSecTrustSettingsResult as String] else {
            // An omitted result defaults to trustRoot per the SDK header.
            return .trustsRoot
        }
        guard let resultValue = resultCode(from: rawResult) else {
            // A value that is not a result code describes nothing usable, so it must never
            // be read as trust.
            return .inconclusive
        }
        if resultValue == SecTrustSettingsResult.trustRoot.rawValue {
            return .trustsRoot
        }
        if resultValue == SecTrustSettingsResult.deny.rawValue {
            return isConstrained(entry) ? .deniesForConstrainedUse : .deniesUnconditionally
        }
        // `unspecified` defers to the system default (not a user trust decision) and
        // `trustAsRoot` applies to non-root certificates, so neither marks this root trusted.
        return .inconclusive
    }

    /// - Parameter settings: the copied array, or `nil` when no settings exist for this
    ///   certificate and domain or the copy failed. `nil` is never trust.
    static func indicatesTrustedRoot(settings: [[String: Any]]?) -> Bool {
        guard let settings else {
            return false
        }
        if settings.isEmpty {
            return true
        }

        var sawTrustRoot = false
        for entry in settings {
            switch verdict(for: entry) {
            case .deniesUnconditionally:
                // Applies to every evaluation, so no optimistic prefilter result is possible.
                return false
            case .trustsRoot:
                sawTrustRoot = true
            case .deniesForConstrainedUse,
                 .inconclusive:
                continue
            }
        }
        return sawTrustRoot
    }

    // MARK: Private

    /// Keys that scope a trust-settings entry to part of the evaluation space
    /// (`SecTrustSettings.h`). An entry carrying any of them describes a constrained decision.
    private static let constraintKeys: [String] = [
        kSecTrustSettingsPolicy as String,
        kSecTrustSettingsPolicyString as String,
        kSecTrustSettingsApplication as String,
        kSecTrustSettingsKeyUsage as String
    ]

    private static func isConstrained(_ entry: [String: Any]) -> Bool {
        constraintKeys.contains { entry[$0] != nil }
    }

    /// Reads a `SecTrustSettingsResult` code, rejecting Core Foundation booleans.
    ///
    /// A `CFBoolean` bridges to `NSNumber` and casts cleanly to `UInt32`, so `true` would
    /// otherwise be read as `1` — the raw value of `trustRoot` — and turn a malformed entry
    /// into trust.
    private static func resultCode(from rawResult: Any) -> UInt32? {
        guard CFGetTypeID(rawResult as CFTypeRef) != CFBooleanGetTypeID() else {
            return nil
        }
        return rawResult as? UInt32
    }
}
