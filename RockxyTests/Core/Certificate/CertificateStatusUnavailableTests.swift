import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Regression tests for the lane of issue #319 where a *failed read* was reported as a finding:
// unreadable trust settings answered "not trusted", an unreadable Keychain answered "not
// installed", and a failed persisted load answered "no certificate". Each of those turns into an
// offer to install and trust — which is a second administrator prompt for a root the user already
// approved. Nothing here locks the real Keychain or trust store; the unreadable state is injected
// at the one seam every status answer already goes through.

// MARK: - TrustSettingsStrictReadTests

/// `SecTrustSettings.h` defines what a copy result means. Only two statuses are absence.
struct TrustSettingsStrictReadTests {
    // MARK: Internal

    @Test("a successful copy of an empty array is a real positive, not an empty answer")
    func emptyArrayIsPositive() throws {
        let read = TrustSettingsInterpreter.read(status: errSecSuccess, settings: [] as CFArray)

        let copiedEntries = try #require(entries(of: read))
        #expect(copiedEntries.isEmpty)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: copiedEntries))
    }

    @Test("readable entries keep the existing default, constrained-deny, and deny interpretation")
    func readableEntriesKeepExistingInterpretation() throws {
        let defaulted: [[String: Any]] = [[kSecTrustSettingsPolicy as String: "ssl"]]
        let constrainedDeny: [[String: Any]] = [[
            kSecTrustSettingsResult as String: SecTrustSettingsResult.deny.rawValue,
            kSecTrustSettingsPolicy as String: "smime",
        ]]
        let unconditionalDeny: [[String: Any]] = [
            [kSecTrustSettingsResult as String: SecTrustSettingsResult.deny.rawValue],
        ]

        let defaultedEntries = try #require(
            entries(of: TrustSettingsInterpreter.read(status: errSecSuccess, settings: defaulted as CFArray))
        )
        let constrainedEntries = try #require(
            entries(of: TrustSettingsInterpreter.read(status: errSecSuccess, settings: constrainedDeny as CFArray))
        )
        let unconditionalEntries = try #require(
            entries(of: TrustSettingsInterpreter.read(status: errSecSuccess, settings: unconditionalDeny as CFArray))
        )

        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: defaultedEntries))
        // A deny scoped to another policy is not a blanket veto, and a deny alone is not trust.
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: constrainedEntries) == false)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: unconditionalEntries) == false)
    }

    @Test("only the two documented statuses mean there are no trust settings")
    func onlyDocumentedStatusesAreAbsence() {
        #expect(isAbsent(TrustSettingsInterpreter.read(status: errSecItemNotFound, settings: nil)))
        #expect(isAbsent(TrustSettingsInterpreter.read(status: errSecNoTrustSettings, settings: nil)))
    }

    @Test("an authorization, lock, or availability failure is unavailable and never absence")
    func failedStatusesAreUnavailable() {
        // -25293 is what a locked or authorization-refused Keychain answers; reading it as
        // absence is the defect this pins.
        #expect(errSecAuthFailed == -25_293)

        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable, errSecIO] {
            let read = TrustSettingsInterpreter.read(status: status, settings: nil)
            #expect(isAbsent(read) == false)
            #expect(entries(of: read) == nil)
            if case let .unreadable(reported) = read {
                #expect(reported == status)
            } else {
                Issue.record("status \(status) must classify as unreadable")
            }
        }
    }

    @Test("a successful copy with an unreadable payload is unavailable, not absence")
    func malformedPayloadIsUnavailable() {
        // Both malformed shapes: no array at all, and an array that is not entries.
        let missingPayload = TrustSettingsInterpreter.read(status: errSecSuccess, settings: nil)
        let wrongPayload = TrustSettingsInterpreter.read(
            status: errSecSuccess,
            settings: ["not-an-entry"] as CFArray
        )

        for read in [missingPayload, wrongPayload] {
            #expect(isAbsent(read) == false)
            #expect(entries(of: read) == nil)
            #expect(isMalformed(read))
        }
    }

    // MARK: Private

    private func entries(of read: TrustSettingsInterpreter.DomainRead) -> [[String: Any]]? {
        if case let .entries(entries) = read {
            return entries
        }
        return nil
    }

    private func isAbsent(_ read: TrustSettingsInterpreter.DomainRead) -> Bool {
        if case .absent = read {
            return true
        }
        return false
    }

    private func isMalformed(_ read: TrustSettingsInterpreter.DomainRead) -> Bool {
        if case .malformed = read {
            return true
        }
        return false
    }
}

// MARK: - KeychainStrictStatusReadTests

/// The Keychain-facing wrappers. Read-only: nothing here locks or mutates a real keychain.
@Suite(.serialized)
struct KeychainStrictStatusReadTests {
    @Test("a label that addresses nothing is a readable negative, not a failure")
    func absentLabelIsReadableNegative() throws {
        let label = "\(TestIdentity.keychainProbeLabel).absent.\(UUID().uuidString)"

        #expect(try KeychainHelper.isCertificateInstalledStrict(label: label) == false)
        #expect(try KeychainHelper.adminTrustsRootStrict(label: label) == false)
    }

    @Test("an installed but untrusted certificate reads as a known negative in the admin domain")
    func installedUntrustedCertificateIsKnownNegative() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let root = try RootCAGenerator.generate()
        let der = try statusUnavailableDER(root.certificate)
        try KeychainHelper.installCertificate(der, label: overrides.certificateLabel)

        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: der))
        // No admin trust settings were written for this fixture, so absence is the real answer.
        #expect(try KeychainHelper.adminTrustsRootStrict(certData: der) == false)
        #expect(try KeychainHelper.adminTrustsRootStrict(label: overrides.certificateLabel) == false)
    }

    @Test("unreadable certificate bytes throw instead of answering not-trusted")
    func unreadableCertificateDataThrows() {
        #expect(throws: KeychainError.self) {
            try KeychainHelper.adminTrustsRootStrict(certData: Data())
        }
        #expect(throws: KeychainError.self) {
            try KeychainHelper.isCertificateInstalledStrict(certData: Data())
        }
    }

    @Test("the unreadable-trust error carries a safe reason with no path or key material")
    func unreadableTrustErrorIsSafe() throws {
        let withStatus = try #require(KeychainError.trustSettingsUnreadable(errSecAuthFailed).errorDescription)
        let withoutStatus = try #require(KeychainError.trustSettingsUnreadable(nil).errorDescription)

        #expect(withStatus.contains("\(errSecAuthFailed)"))
        #expect(withStatus.contains("/") == false)
        #expect(withoutStatus.isEmpty == false)
        #expect(withoutStatus.contains("/") == false)
    }
}

// MARK: - RootCAStatusUnavailableTests

/// The manager's status answer, driven through the injected strict read.
@Suite(.serialized)
struct RootCAStatusUnavailableTests {
    @Test("each status answer reads one snapshot and a later read failure blocks installation")
    func laterReadFailureIsNotErasedByABooleanCheck() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let reader = StatusReadSequence()
        let recorder = StatusUnavailableCallRecorder()
        await manager.setStatusReadOverrideForTests { try reader.read() }
        await manager.setHelperInstallOverrideForTests { _ in recorder.recordHelper() }
        await manager.setAppInstallOverrideForTests { _ in recorder.recordApp() }

        let first = await manager.rootCAStatusSnapshot()
        #expect(first.isStatusUnavailable == false)
        #expect(reader.count == 1)
        let failure = await #expect(throws: CertificateManagerError.self) {
            try await manager.installAndTrust()
        }
        guard case .trustStateUnavailable? = failure else {
            Issue.record("A later failed read must remain unavailable, not become an install attempt")
            return
        }
        #expect(reader.count == 2)
        #expect(recorder.helperCalls == 0)
        #expect(recorder.appCalls == 0)
        #expect(await manager.lastTrustValidationResult == nil)
    }

    @Test("installation consumes one checked status instead of rereading through a lossy boolean")
    func installUsesOneCheckedStatus() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let reader = StatusReadSequence()
        await manager.setStatusReadOverrideForTests { try reader.read() }
        await manager.setHelperInstallOverrideForTests { _ in
            Issue.record("The trust installation must not dispatch a helper installation RPC")
        }
        await manager.setAppInstallOverrideForTests { _ in
            throw KeychainError.trustNotApplied
        }
        // One read decides whether the install may proceed; a failed install does not go looking
        // for a second opinion about the state it just tried to change.
        await #expect(throws: KeychainError.self) { try await manager.installAndTrust() }
        #expect(reader.count == 1)
    }

    @Test("an unreadable trust domain reports unavailable and preserves the root CA")
    func unreadableTrustStateReportsUnavailable() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let fingerprint = try #require(await manager.getActiveRootFingerprint())
        let key = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        let certificateBytes = try Data(contentsOf: CertificateStore.rootCACertificateURL)

        await manager.setStatusReadOverrideForTests { throw KeychainError.trustSettingsUnreadable(errSecAuthFailed) }
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.isStatusUnavailable)
        #expect(snapshot.statusReadFailure?.scope == .installedTrustState)
        #expect(snapshot.statusReadErrorMessage?.isEmpty == false)
        // The certificate itself was readable, so that field is still a real answer.
        #expect(snapshot.isGeneratedStateKnown)
        #expect(snapshot.hasGeneratedCertificate)
        #expect(snapshot.isInstalledAndTrustStateKnown == false)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(snapshot.fingerprintSHA256 == fingerprint)

        // Unknown outranks the fail-closed booleans everywhere the UI reads them.
        #expect(CertificateSetupState(snapshot: snapshot) == .statusUnavailable)
        #expect(CertificateSetupState(snapshot: snapshot).isReady == false)

        // Nothing was rotated, replaced, or deleted while answering.
        #expect(await manager.getActiveRootFingerprint() == fingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == key)
        #expect(try Data(contentsOf: CertificateStore.rootCACertificateURL) == certificateBytes)

        await manager.setStatusReadOverrideForTests(nil)
    }

    @Test("install and trust stops before every mutator when the status cannot be read")
    func installNeverReachesMutatorsWhenStatusIsUnreadable() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let fingerprint = try #require(await manager.getActiveRootFingerprint())
        let key = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        let recorder = StatusUnavailableCallRecorder()
        await manager.setHelperInstallOverrideForTests { _ in recorder.recordHelper() }
        await manager.setAppInstallOverrideForTests { _ in recorder.recordApp() }
        await manager.setStatusReadOverrideForTests { throw KeychainError.trustSettingsUnreadable(errSecAuthFailed) }

        let failure = await #expect(throws: CertificateManagerError.self) {
            try await manager.installAndTrust()
        }

        // A typed unavailable failure, not `trustValidationFailed` and not a helper error: the
        // call never got far enough to have an opinion about trust.
        #expect(failure != .trustValidationFailed)
        #expect(failure?.errorDescription?.contains("did not request administrator approval") == true)
        // Neither privileged path ran, so no authorization dialog was raised for a status this
        // call could not read.
        #expect(recorder.helperCalls == 0)
        #expect(recorder.appCalls == 0)
        #expect(await manager.getActiveRootFingerprint() == fingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == key)

        await manager.setStatusReadOverrideForTests(nil)
    }

    @Test("a readable negative stays a finding and never reports as unavailable")
    func readableNegativeIsNotUnavailable() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()

        await manager.setStatusReadOverrideForTests {
            StatusReadResultForTests(isInstalledInKeychain: false, hasAdminTrustSettings: false)
        }
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.isStatusUnavailable == false)
        #expect(snapshot.statusReadFailure == nil)
        #expect(snapshot.isInstalledInKeychain == false)
        #expect(snapshot.hasTrustSettings == false)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(CertificateSetupState(snapshot: snapshot) == .generatedOnly)

        await manager.setStatusReadOverrideForTests(nil)
    }

    @Test("a readable answer after a failed one clears the unavailable diagnostic")
    func recoveryClearsUnavailableDiagnostic() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let fingerprint = try #require(await manager.getActiveRootFingerprint())

        await manager.setStatusReadOverrideForTests { throw KeychainError.trustSettingsUnreadable(errSecAuthFailed) }
        #expect(await manager.rootCAStatusSnapshot().isStatusUnavailable)

        // The keychain became readable again: the same certificate is now reported as installed
        // and untrusted, with no diagnostic left over from the failed read.
        await manager.setStatusReadOverrideForTests {
            StatusReadResultForTests(isInstalledInKeychain: true, hasAdminTrustSettings: false)
        }
        let recovered = await manager.rootCAStatusSnapshot(performValidation: true)

        #expect(recovered.isStatusUnavailable == false)
        #expect(recovered.statusReadErrorMessage == nil)
        // The reason the failed read recorded describes nothing now, so it is gone too.
        #expect(recovered.lastValidationErrorMessage == nil)
        #expect(recovered.isInstalledInKeychain)
        #expect(recovered.fingerprintSHA256 == fingerprint)
        #expect(CertificateSetupState(snapshot: recovered) == .installedNotTrusted)

        await manager.setStatusReadOverrideForTests(nil)
    }

    @Test("an unreadable persisted certificate reports unavailable, not a missing root CA")
    func persistedLoadFailureReportsUnavailable() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        // The fixture's own file, inside the fixture's own temporary directory.
        let certificateURL = CertificateStore.rootCACertificateURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: certificateURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)
        }

        let manager = CertificateManager.makeForTesting()
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.isStatusUnavailable)
        #expect(snapshot.statusReadFailure?.scope == .persistedMaterial)
        // "Not Generated" would be a guess about material that is still on disk.
        #expect(snapshot.isGeneratedStateKnown == false)
        #expect(CertificateSetupState(snapshot: snapshot) == .statusUnavailable)

        // No rotation, and the key that belongs to the persisted certificate is untouched.
        #expect(await manager.getActiveRootFingerprint() == nil)
        #expect(try KeychainHelper
            .loadPrivateKey(label: overrides.label) == Data(persisted.privateKey.x963Representation))
    }
}

// MARK: - CertificateUnavailableUXTests

/// What the four-step Welcome flow and the shared status panel are allowed to say and offer.
struct CertificateUnavailableUXTests {
    // MARK: Internal

    @Test("a readable certificate stays generated when only its trust state is unavailable")
    @MainActor
    func knownMaterialSurvivesUnavailableTrust() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true, isInstalledInKeychain: false, hasTrustSettings: false,
            isSystemTrustValidated: false, notValidBefore: nil, notValidAfter: nil,
            fingerprintSHA256: "fixture", commonName: "Rockxy", lastValidationErrorMessage: "read failed",
            statusReadFailure: RootCAStatusReadFailure(scope: .installedTrustState, message: "read failed")
        )
        let state = WelcomeViewModel.certificateStepState(certReadiness: .unknown, snapshot: snapshot)
        #expect(state.isGenerated)
        #expect(state.isTrusted == false)
        #expect(state.isUnavailable)
        let model = WelcomeViewModel()
        model.applyCertificateState(state)
        model.recordFailure(CertificateManagerError.trustStateUnavailable("read failed"), area: .certificate)
        model.applyCertificateState(.init(isGenerated: true, isTrusted: false, unavailableMessage: nil))
        #expect(model.errorMessage == nil)
        #expect(model.errorArea == nil)
        model.recordFailure(HelperConnectionError.certInstallFailed("helper failed"), area: .helper)
        model.applyCertificateState(.init(isGenerated: true, isTrusted: true, unavailableMessage: nil))
        #expect(model.errorMessage?.contains("helper failed") == true)
    }

    @Test("an unknown readiness marks neither certificate step complete and carries the reason")
    func unknownReadinessDoesNotMarkStepsComplete() {
        let snapshot = unavailableSnapshot(message: "Keychain is locked (status: -25293)")

        let state = WelcomeViewModel.certificateStepState(certReadiness: .unknown, snapshot: snapshot)

        // `!= .notGenerated` used to be enough to tick step 1; an unreadable status is not a
        // generated certificate.
        #expect(state.isGenerated == false)
        #expect(state.isTrusted == false)
        #expect(state.isUnavailable)
        #expect(state.unavailableMessage == "Keychain is locked (status: -25293)")
    }

    @Test("an unknown readiness with no reason still shows recovery copy")
    func unknownReadinessAlwaysHasAMessage() {
        let state = WelcomeViewModel.certificateStepState(certReadiness: .unknown, snapshot: nil)

        #expect(state.isUnavailable)
        #expect(state.unavailableMessage?.isEmpty == false)
    }

    @Test("known readiness values keep their existing step mapping")
    func knownReadinessKeepsExistingMapping() {
        let installed = WelcomeViewModel.certificateStepState(certReadiness: .installedNotTrusted, snapshot: nil)
        #expect(installed.isGenerated)
        #expect(installed.isTrusted == false)
        #expect(installed.isUnavailable == false)

        let trusted = WelcomeViewModel.certificateStepState(certReadiness: .trusted, snapshot: nil)
        #expect(trusted.isGenerated)
        #expect(trusted.isTrusted)

        let missing = WelcomeViewModel.certificateStepState(certReadiness: .notGenerated, snapshot: nil)
        #expect(missing.isGenerated == false)
        #expect(missing.isUnavailable == false)
    }

    @Test("Welcome keeps four steps and blocks completion while the status is unreadable")
    @MainActor
    func welcomeKeepsFourStepsWhileUnavailable() {
        let viewModel = WelcomeViewModel()
        viewModel.applyHelperState(status: .installedCompatible, signingIssue: nil)
        viewModel.systemProxyEnabled = true
        viewModel.errorMessage = "helper diagnostics"

        viewModel.applyCertificateState(WelcomeViewModel.certificateStepState(
            certReadiness: .unknown,
            snapshot: unavailableSnapshot(message: "Keychain is locked")
        ))

        #expect(viewModel.totalSteps == 4)
        #expect(viewModel.isCertStatusUnavailable)
        #expect(viewModel.certStatusUnavailableMessage == "Keychain is locked")
        #expect(viewModel.completedSteps == 2)
        #expect(viewModel.canGetStarted == false)
        // The certificate diagnostic lives in its own field, so an unrelated failure is intact.
        #expect(viewModel.errorMessage == "helper diagnostics")

        // Recovery restores the normal actions and clears the diagnostic.
        viewModel.applyCertificateState(WelcomeViewModel.certificateStepState(
            certReadiness: .trusted,
            snapshot: nil
        ))
        #expect(viewModel.isCertStatusUnavailable == false)
        #expect(viewModel.canGetStarted)
    }

    @Test("Welcome offers a status recheck, not an install, while the status is unreadable")
    func welcomeOffersRecheckNotInstall() throws {
        let view = try readProjectFile("Rockxy/Views/Welcome/WelcomeView.swift")

        #expect(view.contains("await viewModel.recheckCertificateStatus()"))
        #expect(view.contains("String(localized: \"Recheck Status\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("certificateSupplement"))
        // The four steps, the close action, and the busy guards are untouched.
        #expect(view.contains(".disabled(!viewModel.canGetStarted || viewModel.isBusy)"))
        #expect(view.contains("String(localized: \"Close\", bundle: RockxyLocalization.bundle)"))

        let model = try readProjectFile("Rockxy/ViewModels/WelcomeViewModel.swift")
        // The recheck is a read: a deep refresh and nothing else.
        let recheck = try #require(declaration(named: "func recheckCertificateStatus() async", in: model))
        #expect(recheck.contains("ReadinessCoordinator.shared.deepRefresh()"))
        #expect(recheck.contains("installAndTrust") == false)
        #expect(recheck.contains("generateRootCA") == false)
        // And the install refuses to run at all while the status is unknown.
        let install = try #require(declaration(named: "func installCert() async", in: model))
        #expect(install.contains("!isCertStatusUnavailable"))
    }

    @Test("the status panel shows Unavailable fields, the reason, and only a recheck action")
    func statusPanelShowsUnavailableWithoutDestructiveActions() throws {
        let panel = try readProjectFile("Rockxy/Views/Certificate/CertificateStatusPanel.swift")

        #expect(panel.contains("case .statusUnavailable:"))
        #expect(panel.contains("String(localized: \"Unavailable\", bundle: RockxyLocalization.bundle)"))
        #expect(panel
            .contains("String(localized: \"Certificate Status Unavailable\", bundle: RockxyLocalization.bundle)"))

        // The reason is shown from the status failure, not gated behind `hasTrustSettings`.
        let callout = try #require(declaration(named: "private var calloutMessage: String?", in: panel))
        #expect(callout.contains("snapshot.isStatusUnavailable"))
        #expect(callout.contains("statusReadErrorMessage"))

        // The icon, text, and background share the same semantic color: unavailable is orange,
        // while a known trust-validation failure is red.
        let errorCallout = try #require(declaration(named: "@ViewBuilder private var errorCallout: some View", in: panel))
        #expect(errorCallout.contains("let tint: Color = isStatusUnavailable ? .orange : .red"))
        #expect(errorCallout.contains(".foregroundStyle(tint)"))
        #expect(errorCallout.contains(".foregroundStyle(.orange)") == false)

        // The unavailable branch offers a recheck and no generate, reset, or install.
        let actions = try #require(declaration(named: "@ViewBuilder private var actionButtons: some View", in: panel))
        let branchStart = try #require(actions.range(of: "case .statusUnavailable:"))
        let branchEnd = try #require(actions.range(of: "case .notAvailable:"))
        let unavailableBranch = String(actions[branchStart.upperBound ..< branchEnd.lowerBound])

        #expect(unavailableBranch.contains("onAction(.recheck)"))
        #expect(unavailableBranch.contains("onAction(.generate)") == false)
        #expect(unavailableBranch.contains("onAction(.reset)") == false)
        #expect(unavailableBranch.contains("onAction(.installAndTrust)") == false)
    }

    @Test("the Mac guide rechecks instead of repairing trust and keeps its window contract")
    func macGuideRechecksInsteadOfRepairing() throws {
        let guide = try readProjectFile("Rockxy/Views/Certificate/MacCertificateSetupGuideView.swift")
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(guide.contains("case .statusUnavailable:"))
        #expect(guide.contains("String(localized: \"Recheck Status\", bundle: RockxyLocalization.bundle)"))
        #expect(guide.contains("statusUnavailableMessage"))
        // Generation is not offered for material whose absence was never established.
        #expect(guide.contains("snapshot?.hasGeneratedCertificate != true, !isStatusUnavailable"))
        // Window identity, settings routing, and the manual guidance are unchanged.
        #expect(app.contains("id: \"certificateSetup\""))
        #expect(guide.contains("RockxySettingsTab.select(.general)"))
    }

    @Test("every new user-facing string is in the catalog with a translation")
    func newCopyIsLocalized() throws {
        let catalog = try catalogStrings()

        for key in [
            "Certificate Status Unavailable",
            "Rockxy cannot read the certificate and trust status right now.",
            "Rockxy cannot read the certificate and trust status right now. Nothing was changed — check the status again once your keychain is available.",
            "Rockxy cannot verify the Root CA trust status, so HTTPS interception is paused. HTTP traffic and logs are still captured.",
            "Rockxy could not read the Keychain or trust state. Nothing was changed.",
            "Rockxy could not read the certificate status, so nothing was changed. Recheck the status once your keychain is available.",
            "Root CA status unavailable",
            "status unavailable",
            "Recheck Status",
            "Unavailable",
        ] {
            let entry = try #require(catalog[key] as? [String: Any], "missing catalog entry: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "no localizations: \(key)")
            // English is the source language and stays implicit; the supported translation is
            // zh-Hans. No other language is claimed for copy nobody translated.
            let chinese = try #require(localizations["zh-Hans"] as? [String: Any], "no zh-Hans: \(key)")
            let unit = try #require(chinese["stringUnit"] as? [String: Any])
            #expect(unit["state"] as? String == "translated")
            #expect((unit["value"] as? String)?.isEmpty == false)
        }
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
        case malformedCatalog
    }

    private func unavailableSnapshot(message: String) -> RootCAStatusSnapshot {
        RootCAStatusSnapshot(
            hasGeneratedCertificate: false,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: message,
            statusReadFailure: RootCAStatusReadFailure(scope: .installedTrustState, message: message)
        )
    }

    private func catalogStrings() throws -> [String: Any] {
        let url = try projectRoot().appendingPathComponent("Rockxy/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let catalog = object as? [String: Any],
              let strings = catalog["strings"] as? [String: Any] else
        {
            throw ResolveError.malformedCatalog
        }
        return strings
    }

    private func declaration(named signature: String, in source: String) -> String? {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else
        {
            return nil
        }
        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[signatureRange.lowerBound ... cursor])
                }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func projectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}

// MARK: - StatusUnavailableCallRecorder

/// Counts how often either privileged installation path was entered.
private final class StatusUnavailableCallRecorder: @unchecked Sendable {
    // MARK: Internal

    var helperCalls: Int {
        lock.withLock { helper }
    }

    var appCalls: Int {
        lock.withLock { app }
    }

    func recordHelper() {
        lock.withLock { helper += 1 }
    }

    func recordApp() {
        lock.withLock { app += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var helper = 0
    private var app = 0
}

// MARK: - StatusReadSequence

private final class StatusReadSequence: @unchecked Sendable {
    // MARK: Internal

    var count: Int {
        lock.withLock { calls }
    }

    func read() throws -> StatusReadResultForTests {
        try lock.withLock {
            calls += 1
            guard calls == 1 else {
                throw KeychainError.trustSettingsUnreadable(errSecAuthFailed)
            }
            return StatusReadResultForTests(isInstalledInKeychain: false, hasAdminTrustSettings: false)
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var calls = 0
}

// MARK: - Shared Helpers

private func statusUnavailableDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}
