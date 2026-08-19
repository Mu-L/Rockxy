import Foundation
@testable import Rockxy
import Testing

// Regression tests for the original four-step Welcome flow and helper recovery policy.

// MARK: - WelcomeViewModelTests

@MainActor
struct WelcomeViewModelTests {
    // MARK: - Four-step progress

    @Test("completed steps preserve the original four setup milestones")
    func completedStepsPreserveFourStepFlow() {
        let viewModel = WelcomeViewModel()
        #expect(viewModel.completedSteps == 0)

        viewModel.certInstalled = true
        #expect(viewModel.completedSteps == 1)

        viewModel.certTrusted = true
        #expect(viewModel.completedSteps == 2)

        viewModel.helperStatus = .installedCompatible
        #expect(viewModel.completedSteps == 3)

        viewModel.systemProxyEnabled = true
        #expect(viewModel.completedSteps == 4)
        #expect(viewModel.totalSteps == 4)
    }

    @Test("Get Started still requires all four original steps")
    func canGetStartedRequiresAllFourSteps() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.systemProxyEnabled = true

        viewModel.helperStatus = .notInstalled
        #expect(viewModel.canGetStarted == false)

        viewModel.helperStatus = .installedCompatible
        #expect(viewModel.canGetStarted == true)

        viewModel.certTrusted = false
        #expect(viewModel.canGetStarted == false)
    }

    @Test("system proxy progress remains independent from certificate and helper state")
    func systemProxyProgressIsIndependent() {
        let viewModel = WelcomeViewModel()
        viewModel.systemProxyEnabled = true

        #expect(viewModel.completedSteps == 1)
        #expect(viewModel.canGetStarted == false)
    }

    // MARK: - Helper action and recovery

    @Test("helper action labels remain aligned with HelperManager states")
    func helperActionLabelsMatchManager() {
        let cases: [(HelperManager.HelperStatus, HelperManager.SigningIssue?, String?)] = [
            (.notInstalled, nil, String(localized: "Install")),
            (.requiresApproval, nil, String(localized: "Open Settings")),
            (.installedCompatible, nil, nil),
            (.installedOutdated, nil, String(localized: "Update")),
            (.installedIncompatible, nil, String(localized: "Update")),
            (.unreachable, nil, String(localized: "Retry")),
            (.signingMismatch, .applicationMustReopen, String(localized: "Quit Rockxy")),
            (.signingMismatch, .appSignatureInvalid(detail: "x"), nil),
            (.signingMismatch, .identityMismatch(appSigner: "a", helperSigner: "b"), String(localized: "Reinstall")),
            (.signingMismatch, nil, nil),
        ]

        for (status, issue, expected) in cases {
            let viewModel = WelcomeViewModel()
            viewModel.applyHelperState(status: status, signingIssue: issue)
            #expect(viewModel.helperActionLabel == expected)
        }
    }

    @Test("helper remains incomplete for approval, unreachable, and signing failures")
    func helperIncompleteStatesDoNotAdvanceFlow() {
        for status in [
            HelperManager.HelperStatus.requiresApproval,
            .unreachable,
            .signingMismatch,
        ] {
            let viewModel = WelcomeViewModel()
            viewModel.helperStatus = status
            #expect(viewModel.completedSteps == 0)
            #expect(viewModel.canGetStarted == false)
        }
    }

    @Test("unreachable and approval states expose the repair route")
    func recoverableHelperStatesOfferRepair() {
        let viewModel = WelcomeViewModel()

        viewModel.helperStatus = .unreachable
        #expect(viewModel.shouldOfferHelperRepair)

        viewModel.helperStatus = .requiresApproval
        #expect(viewModel.shouldOfferHelperRepair)

        viewModel.helperStatus = .notInstalled
        #expect(viewModel.shouldOfferHelperRepair == false)
    }

    @Test("invalid app signature exposes advanced diagnostics")
    func invalidAppSignatureExposesDiagnostics() {
        let viewModel = WelcomeViewModel()

        viewModel.applyHelperState(
            status: .signingMismatch,
            signingIssue: .appSignatureInvalid(detail: "signature changed")
        )

        #expect(viewModel.shouldShowHelperDiagnostics)
    }

    @Test("incomplete app package routes to rebuild instead of destructive repair")
    func incompletePackageDoesNotOfferDestructiveRepair() {
        let error = HelperManager.HelperInstallPreflightError.missingBundledHelperBinary(
            path: "/Applications/Rockxy.app/Contents/Library/LaunchServices/RockxyHelperTool"
        )

        #expect(WelcomeViewModel.resolveHelperFailureRecovery(for: error) == .rebuildApp)
    }

    @Test("required reopen does not offer destructive helper repair")
    func requiredReopenDoesNotOfferDestructiveRepair() {
        let error = HelperManager.HelperOperationError.applicationMustReopen

        #expect(WelcomeViewModel.resolveHelperFailureRecovery(for: error) == .reopenApp)
    }

    @Test("normal helper registration errors can use repair and reinstall")
    func registrationErrorOffersRepairAndReinstall() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -1)

        #expect(WelcomeViewModel.resolveHelperFailureRecovery(for: error) == .repairAndReinstall)
    }

    // MARK: - Action guard and defaults

    @Test("only one Welcome action may run at a time")
    func actionSerializationPolicy() {
        #expect(WelcomeViewModel.canBeginAction(current: nil))
        #expect(WelcomeViewModel.canBeginAction(current: .certificate) == false)
        #expect(WelcomeViewModel.canBeginAction(current: .helper) == false)
        #expect(WelcomeViewModel.canBeginAction(current: .systemProxy) == false)
        #expect(WelcomeViewModel.canBeginAction(current: nil, isCheckingSystem: true) == false)
    }

    @Test("certificate install skips when trust is already complete")
    func installCertificateSkipsWhenTrusted() async {
        let viewModel = WelcomeViewModel()
        viewModel.certTrusted = true

        await viewModel.installCert()

        #expect(viewModel.isPerformingAction == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("initial state matches the original incomplete onboarding flow")
    func initialState() {
        let viewModel = WelcomeViewModel()

        #expect(viewModel.certInstalled == false)
        #expect(viewModel.certTrusted == false)
        #expect(viewModel.helperStatus == .notInstalled)
        #expect(viewModel.systemProxyEnabled == false)
        #expect(viewModel.isCheckingSystem == false)
        #expect(viewModel.isPerformingAction == false)
        #expect(viewModel.isBusy == false)
        #expect(viewModel.activeAction == nil)
        #expect(viewModel.errorArea == nil)
        #expect(viewModel.helperFailureRecovery == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.completedSteps == 0)
        #expect(viewModel.totalSteps == 4)
        #expect(viewModel.canGetStarted == false)
    }
}
