import Foundation
import os
import Security

// The privileged Security.framework side of root CA installation and removal, scoped to one
// keychain named by path and to the `.admin` trust domain.
//
// This used to be a private type inside the helper daemon, which made every rule it encodes —
// how an item is addressed, when a duplicate counts as installed, what a delete has to prove —
// reachable only by mutating the real System keychain as root. It lives here so a test can point
// it at a disposable keychain it created itself and drive the same code.

// MARK: - AdminTrustSettingsSnapshot

/// One certificate's `.admin` trust settings, as the domain reports them.
struct AdminTrustSettingsSnapshot {
    static let absent = AdminTrustSettingsSnapshot(exists: false, entries: nil)

    /// Whether *any* settings exist for this certificate, including an empty array, a defaulted
    /// constraints entry, and a deny.
    let exists: Bool

    /// The entries, when the copied value could be read as an array of dictionaries. `nil` means
    /// "nothing readable", which is never positive trust — including when `exists` is true.
    let entries: [[String: Any]]?
}

// MARK: - AdminTrustSettingsAccess

/// Reads and writes the `.admin` trust settings for one certificate.
///
/// Reads work anywhere. Writes do not: `SecTrustSettingsSetTrustSettings(.admin)` needs
/// interactive Authorization Services, and a non-interactive launchd daemon has no session that
/// can ask a human, so the call is denied with `-60007` even as root. Routing the write through
/// `/usr/bin/security` does not change that — `security add-trusted-cert -d` exits 1 with the same
/// denial from the same context — so this is legacy compatibility for the certificate RPCs, not a
/// way around the approval. The app's own installation performs the trust write in its GUI process
/// and does not dispatch this at all; see `CertificateManager.installAndTrust()`.
///
/// Injecting the whole access — not just the writes — is what lets a fixture exercise the install
/// and removal postconditions without ever touching the real System or login trust domains.
protocol AdminTrustSettingsAccess {
    /// The `.admin` settings for exactly this certificate. Throws for any status that describes
    /// the keychain rather than the settings, so an unavailable domain is never read as absence.
    func adminTrustSettings(derData: Data) throws -> AdminTrustSettingsSnapshot

    /// Records `trustRoot` settings for exactly this certificate, or throws.
    func setAdminTrustRoot(derData: Data) throws

    /// Removes this certificate's `.admin` settings, or throws.
    func removeAdminTrustSettings(derData: Data) throws
}

// MARK: - SystemKeychainCertificateOperations

/// The privileged keychain work both `RootCertificateInstaller` and `RootCertificateRemover`
/// need, bound to a single keychain file.
///
/// Three rules are the point:
///
/// - **One keychain, named explicitly.** Every query carries `kSecMatchSearchList`, so nothing
///   here can discover — or delete — an item in a keychain the caller did not name.
/// - **Persistent identity.** Discovery returns each item's persistent reference paired with the
///   bytes that were actually read back from it, and deletions address exactly those references
///   plus the indexed serial number. A transient `SecCertificate` can stop addressing its item
///   while the item is still installed.
/// - **Statuses are reports, never postconditions.** An add is followed by an exact-DER read, a
///   delete by an absence check, and any status that is neither success nor a documented
///   "nothing there" throws instead of being folded into "nothing is installed".
final class SystemKeychainCertificateOperations: RootCertificateRemovalOperations,
    RootCertificateInstallOperations
{
    // MARK: Lifecycle

    init(keychainPath: String, trust: any AdminTrustSettingsAccess) {
        self.keychainPath = keychainPath
        self.trust = trust
    }

    // MARK: Internal

    static let systemKeychainPath = "/Library/Keychains/System.keychain"

    // MARK: - Discovery

    func systemCertificates(serialNumber: Data) throws -> [SystemKeychainCertificate] {
        try certificates(
            matching: [kSecAttrSerialNumber as String: serialNumber],
            operation: "serial number query"
        )
    }

    func systemCertificates(label: String) throws -> [SystemKeychainCertificate] {
        try certificates(
            matching: [kSecAttrLabel as String: label],
            operation: "label query"
        )
    }

    // MARK: - Installation

    /// Adds exactly these bytes under `label`, removing nothing first.
    ///
    /// The item is created from a `SecCertificate` reference, which is what classic macOS
    /// keychains accept, and the label is then set on the persistent item the add returned —
    /// narrowed by the serial number as well, so even a platform that mishandled the reference
    /// constraint could not relabel an unrelated certificate. `errSecDuplicateItem` returns
    /// `.duplicate` rather than throwing: it says an item collides on the primary key, which the
    /// caller resolves with an exact-DER read, not with a delete-and-retry.
    func addCertificate(derData: Data, label: String) throws -> CertificateAddOutcome {
        let certificate = try secCertificate(from: derData)
        guard let serialNumber = SecCertificateCopySerialNumberData(certificate, nil) as Data? else {
            throw RootCertificateRemovalError.unreadableSerialNumber
        }
        let keychain = try openKeychain()

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecUseKeychain as String: keychain,
            kSecReturnPersistentRef as String: true,
        ]
        var added: CFTypeRef?
        let addStatus = SecItemAdd(addQuery as CFDictionary, &added)
        if addStatus == errSecDuplicateItem {
            return .duplicate
        }
        guard addStatus == errSecSuccess else {
            throw RootCertificateInstallError.keychainFailure(operation: "add certificate", status: addStatus)
        }
        guard let persistentReference = Self.persistentReference(from: added) else {
            // The add succeeded but returned nothing addressable, so the label cannot be set on
            // the item it created. Nothing is deleted to tidy that up.
            throw RootCertificateInstallError.labelReadbackMismatch
        }

        try applyLabel(label, persistentReference: persistentReference, serialNumber: serialNumber, in: keychain)
        return .added
    }

    func hasPositiveAdminTrustSettings(derData: Data) throws -> Bool {
        let snapshot = try trust.adminTrustSettings(derData: derData)
        guard snapshot.exists == (snapshot.entries != nil) else {
            throw RootCertificateRemovalError.malformedKeychainResult(operation: "read positive admin trust")
        }
        return TrustSettingsInterpreter.indicatesTrustedRoot(settings: snapshot.entries)
    }

    func setAdminTrustRoot(derData: Data) throws {
        try trust.setAdminTrustRoot(derData: derData)
    }

    // MARK: - Removal

    func hasAdminTrustSettings(derData: Data) throws -> Bool {
        try trust.adminTrustSettings(derData: derData).exists
    }

    func removeAdminTrustSettings(derData: Data) throws {
        try trust.removeAdminTrustSettings(derData: derData)
    }

    /// Deletes exactly the items that were already inspected, then proves they are gone.
    ///
    /// Each delete is addressed by the persistent reference discovery returned, narrowed by the
    /// keychain and by the serial number carried in the verified bytes. There is no widening
    /// fallback: an item that cannot be addressed this way is reported, never swept up by label
    /// or class.
    func deleteSystemCertificates(_ certificates: [SystemKeychainCertificate]) throws {
        guard !certificates.isEmpty else {
            return
        }
        let keychain = try openKeychain()
        let targets = try certificates.map { try identity(of: $0) }

        for target in targets {
            var query: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecMatchSearchList as String: [keychain],
                // `kSecMatchItemList` is the documented macOS way to address specific items.
                // `kSecValueRef` is the iOS shape, and a class-and-label query would delete every
                // match instead of the copy that was just inspected.
                kSecMatchItemList as String: [target.persistentReference as NSData],
            ]
            query[kSecAttrSerialNumber as String] = target.serialNumber

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw RootCertificateRemovalError.keychainFailure(operation: "delete certificate", status: status)
            }
        }

        // A success or not-found status is a report, not proof. The absence check re-reads the
        // keychain, and a failing read propagates rather than passing for "gone".
        for target in targets {
            let stillInstalled = try systemCertificates(serialNumber: target.serialNumber)
                .contains { $0.derData == target.derData }
            guard !stillInstalled else {
                throw RootCertificateRemovalError.certificateStillInstalled(
                    fingerprint: RootCertificateRemover.fingerprint(of: target.derData)
                )
            }
        }
    }

    // MARK: Private

    /// One inspected item, addressable by its persistent reference and selected by its bytes.
    private struct ItemIdentity {
        let persistentReference: Data
        let derData: Data
        let serialNumber: Data
    }

    private let keychainPath: String
    private let trust: any AdminTrustSettingsAccess

    /// Certificate imports on classic macOS return a one-element array even when a single item
    /// was created. Both documented shapes are accepted; anything ambiguous is refused rather
    /// than guessed at, because the result decides which item gets relabeled.
    private static func persistentReference(from result: CFTypeRef?) -> Data? {
        if let reference = result as? Data {
            return reference.isEmpty ? nil : reference
        }
        guard let references = result as? [Data], references.count == 1,
              let reference = references.first, !reference.isEmpty else
        {
            return nil
        }
        return reference
    }

    private func openKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        let status = SecKeychainOpen(keychainPath, &keychain)
        guard status == errSecSuccess, let keychain else {
            throw RootCertificateRemovalError.keychainFailure(
                operation: "open keychain",
                status: status
            )
        }
        return keychain
    }

    private func secCertificate(from derData: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw RootCertificateRemovalError.unreadableCertificateData
        }
        return certificate
    }

    /// Re-derives the addressable identity of an already-inspected item.
    ///
    /// The reference has to be the persistent one discovery returned, and the bytes have to still
    /// parse as a certificate with a readable serial. A result that fails either check describes
    /// nothing this class may delete.
    private func identity(of certificate: SystemKeychainCertificate) throws -> ItemIdentity {
        guard let persistentReference = certificate.reference as? Data, !persistentReference.isEmpty else {
            throw RootCertificateRemovalError.malformedKeychainResult(operation: "delete certificate")
        }
        let parsed = try secCertificate(from: certificate.derData)
        guard let serialNumber = SecCertificateCopySerialNumberData(parsed, nil) as Data? else {
            throw RootCertificateRemovalError.unreadableSerialNumber
        }
        return ItemIdentity(
            persistentReference: persistentReference,
            derData: certificate.derData,
            serialNumber: serialNumber
        )
    }

    /// Sets the label on exactly one newly created item and reads it back.
    private func applyLabel(
        _ label: String,
        persistentReference: Data,
        serialNumber: Data,
        in keychain: SecKeychain
    )
        throws
    {
        var itemQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchSearchList as String: [keychain],
            kSecMatchItemList as String: [persistentReference as NSData],
        ]
        // Defense in depth: even a platform that mishandled the reference constraint must never
        // broaden an update to every certificate in the keychain.
        itemQuery[kSecAttrSerialNumber as String] = serialNumber

        let updateStatus = SecItemUpdate(
            itemQuery as CFDictionary,
            [kSecAttrLabel as String: label] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw RootCertificateInstallError.keychainFailure(
                operation: "label certificate",
                status: updateStatus
            )
        }

        var readQuery = itemQuery
        readQuery[kSecReturnAttributes as String] = true
        var attributes: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &attributes)
        guard readStatus == errSecSuccess,
              (attributes as? [String: Any])?[kSecAttrLabel as String] as? String == label else
        {
            throw RootCertificateInstallError.labelReadbackMismatch
        }
    }

    /// Runs one keychain-scoped discovery query.
    ///
    /// The persistent reference, the transient reference, and the bytes are all required, the
    /// transient reference has to actually be a certificate, and its bytes have to equal the
    /// returned data. A result that fails any of those describes nothing, so it throws instead of
    /// silently contributing an unremovable or misidentified item.
    private func certificates(
        matching constraints: [String: Any],
        operation: String
    )
        throws -> [SystemKeychainCertificate]
    {
        let keychain = try openKeychain()
        var query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecMatchSearchList as String: [keychain],
            kSecReturnRef as String: true,
            kSecReturnPersistentRef as String: true,
            kSecReturnData as String: true,
        ]
        query.merge(constraints) { _, replacement in replacement }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw RootCertificateRemovalError.keychainFailure(operation: operation, status: status)
        }
        guard let items = result as? [[String: Any]] else {
            throw RootCertificateRemovalError.malformedKeychainResult(operation: operation)
        }

        return try items.map { item in
            guard let derData = item[kSecValueData as String] as? Data,
                  let persistentReference = item[kSecValuePersistentRef as String] as? Data,
                  !persistentReference.isEmpty,
                  let reference = item[kSecValueRef as String],
                  CFGetTypeID(reference as CFTypeRef) == SecCertificateGetTypeID() else
            {
                throw RootCertificateRemovalError.malformedKeychainResult(operation: operation)
            }
            // swiftlint:disable:next force_cast
            let certificate = reference as! SecCertificate
            guard SecCertificateCopyData(certificate) as Data == derData else {
                throw RootCertificateRemovalError.malformedKeychainResult(operation: operation)
            }
            return SystemKeychainCertificate(
                reference: persistentReference as NSData,
                derData: derData
            )
        }
    }
}

// MARK: - SecurityToolAdminTrustSettings

/// Production `.admin` trust settings access: `SecTrustSettingsCopyTrustSettings` for reads and
/// the Apple-signed `/usr/bin/security` tool for writes.
///
/// The reads are the part that is dependable from a daemon. The writes carry the interactive
/// authorization requirement with them: from a non-interactive launchd context the tool exits 1
/// with "authorization denied", exactly as the framework call does, so a failure here means "no
/// one could be asked", not "this helper lacks privilege". Callers must not read that as something
/// a retry, more privilege, or a different tool would fix.
///
/// The binary is signature-validated before every invocation, and each invocation runs through
/// `BoundedHelperCommand`, which owns and reaps its own child, bounds the runtime, and retains
/// only a capped prefix of stderr. Nothing here uses `Process.waitUntilExit()`, which has no
/// upper bound at all.
final class SecurityToolAdminTrustSettings: AdminTrustSettingsAccess {
    // MARK: Lifecycle

    /// - Parameter validateBinary: the signature check applied to `securityToolPath` before each
    ///   run. It is injected because the validator lives in the privileged helper target.
    init(
        keychainPath: String,
        securityToolPath: String = "/usr/bin/security",
        validateBinary: @escaping (String) -> Bool
    ) {
        self.keychainPath = keychainPath
        self.securityToolPath = securityToolPath
        self.validateBinary = validateBinary
    }

    // MARK: Internal

    /// A readable copy is presence — an empty array, a constraints entry that defaults to
    /// trustRoot, and an explicit deny are all settings that exist. Only the two documented
    /// "there are none" statuses mean absence; anything else describes the keychain, not the
    /// settings, and throws so it can never be read as a clean state.
    ///
    /// A successful copy whose payload is not an array of entries throws for the same reason.
    /// Reporting it as `exists: true, entries: nil` made the positive-trust prefilter answer
    /// "not trusted" for a domain nobody could read, which is a request to write trust settings
    /// — and an authorization prompt — on the strength of a failed read.
    func adminTrustSettings(derData: Data) throws -> AdminTrustSettingsSnapshot {
        guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw RootCertificateRemovalError.unreadableCertificateData
        }
        var settings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, .admin, &settings)
        switch TrustSettingsInterpreter.read(status: status, settings: settings) {
        case let .entries(entries):
            return AdminTrustSettingsSnapshot(exists: true, entries: entries)
        case .absent:
            return .absent
        case let .unreadable(status):
            throw RootCertificateRemovalError.keychainFailure(
                operation: "copy admin trust settings",
                status: status
            )
        case .malformed:
            throw RootCertificateRemovalError.malformedKeychainResult(
                operation: "copy admin trust settings"
            )
        }
    }

    func setAdminTrustRoot(derData: Data) throws {
        do {
            try withTemporaryDER(derData, prefix: "rockxy-install-cert") { path in
                try runSecurityTool(arguments: [
                    "add-trusted-cert", "-d",
                    "-r", "trustRoot",
                    "-k", keychainPath,
                    path,
                ])
            }
        } catch let error as TrustToolFailure {
            throw RootCertificateInstallError.trustWriteFailed(detail: error.detail)
        }
    }

    func removeAdminTrustSettings(derData: Data) throws {
        do {
            try withTemporaryDER(derData, prefix: "rockxy-remove-cert") { path in
                try runSecurityTool(arguments: ["remove-trusted-cert", "-d", path])
            }
        } catch let error as TrustToolFailure {
            throw RootCertificateRemovalError.trustRemovalFailed(detail: error.detail)
        }
    }

    // MARK: Private

    /// Operation-neutral failure from the trust tool, mapped to the caller's error domain by the
    /// two entry points above.
    private struct TrustToolFailure: Error {
        let detail: String
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "SecurityToolTrustSettings"
    )

    private let keychainPath: String
    private let securityToolPath: String
    private let validateBinary: (String) -> Bool

    /// Writes the DER to a private temporary file for the duration of one tool invocation.
    private func withTemporaryDER(
        _ derData: Data,
        prefix: String,
        _ body: (String) throws -> Void
    )
        throws
    {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).der")
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: derData,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw TrustToolFailure(detail: "Failed to create temp DER file")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        try body(url.path)
    }

    /// Runs the Apple-signed `security` tool with a bounded lifetime and bounded output.
    private func runSecurityTool(arguments: [String]) throws {
        guard validateBinary(securityToolPath) else {
            throw TrustToolFailure(detail: "security binary failed Apple code signature validation")
        }

        let output: BoundedHelperCommand.Output
        do {
            output = try BoundedHelperCommand.run(
                executable: URL(fileURLWithPath: securityToolPath), arguments: arguments
            )
        } catch BoundedHelperCommand.Failure.timedOut {
            throw TrustToolFailure(detail: "security command timed out")
        } catch {
            throw TrustToolFailure(detail: error.localizedDescription)
        }
        guard output.status == 0 else {
            // Decoded leniently: the diagnostic is a bounded prefix of the tool's stderr, so its
            // last character can be a truncated multi-byte sequence. A strict decode would return
            // nil for that and throw away every readable byte before it.
            // swiftlint:disable:next optional_data_string_conversion
            let stderr = String(decoding: output.diagnostic, as: UTF8.self)
            throw TrustToolFailure(
                detail: "security \(arguments.first ?? "") exit \(output.status): \(stderr)"
            )
        }
        Self.logger.info("SECURITY: security \(arguments.first ?? "", privacy: .public) completed")
    }
}
