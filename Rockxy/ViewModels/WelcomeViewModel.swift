import Foundation
import os
import SwiftUI

// Owns the original four-step onboarding flow and helper recovery state.

// MARK: - WelcomeViewModel

@MainActor @Observable
final class WelcomeViewModel {
    // MARK: Internal

    enum ActiveAction: Equatable {
        case certificate
        case helper
        case systemProxy
    }

    enum ErrorArea: Equatable {
        case certificate
        case helper
        case systemProxy
    }

    /// An incomplete app bundle cannot be repaired by deleting the currently installed helper.
    /// Other helper failures can offer the confirmed hard-remove-and-reinstall path.
    enum HelperFailureRecovery: Equatable {
        case repairAndReinstall
        case rebuildApp
    }

    var certInstalled = false
    var certTrusted = false
    var helperStatus: HelperManager.HelperStatus = .notInstalled
    var helperSigningIssue: HelperManager.SigningIssue?
    var systemProxyEnabled = false

    private(set) var activeAction: ActiveAction?
    private(set) var errorArea: ErrorArea?
    private(set) var helperFailureRecovery: HelperFailureRecovery?
    private(set) var isCheckingSystem = false
    var errorMessage: String?

    var isPerformingAction: Bool {
        activeAction != nil
    }

    var isBusy: Bool {
        isCheckingSystem || isPerformingAction
    }

    var completedSteps: Int {
        var count = 0
        if certInstalled {
            count += 1
        }
        if certTrusted {
            count += 1
        }
        if helperStatus == .installedCompatible {
            count += 1
        }
        if systemProxyEnabled {
            count += 1
        }
        return count
    }

    var totalSteps: Int {
        4
    }

    var canGetStarted: Bool {
        certInstalled && certTrusted && helperStatus == .installedCompatible && systemProxyEnabled
    }

    var helperActionLabel: String? {
        HelperManager.helperActionLabel(
            status: helperStatus,
            signingIssue: helperSigningIssue
        )
    }

    var shouldOfferHelperRepair: Bool {
        helperStatus == .unreachable
            || helperStatus == .requiresApproval
            || helperFailureRecovery == .repairAndReinstall
    }

    var helperStatusDetail: String? {
        switch helperStatus {
        case .notInstalled:
            nil
        case .requiresApproval:
            String(
                localized: "Approve Rockxy in System Settings → General → Login Items, then return here."
            )
        case .installedCompatible:
            String(localized: "Installed, compatible, and reachable.")
        case .installedOutdated:
            String(localized: "An older helper is installed. Update it from this Rockxy build.")
        case .installedIncompatible:
            String(localized: "The installed helper is incompatible with this Rockxy build.")
        case .unreachable:
            String(localized: "The helper is registered, but Rockxy cannot reach it.")
        case .signingMismatch:
            switch helperSigningIssue {
            case .identityMismatch:
                String(localized: "The installed helper belongs to a differently signed Rockxy build.")
            case .appSignatureInvalid,
                 nil:
                String(localized: "This Rockxy build has a signing problem. Open diagnostics before continuing.")
            }
        }
    }

    static func canBeginAction(current: ActiveAction?, isCheckingSystem: Bool = false) -> Bool {
        current == nil && !isCheckingSystem
    }

    static func resolveHelperFailureRecovery(for error: Error) -> HelperFailureRecovery {
        if error is HelperManager.HelperInstallPreflightError {
            return .rebuildApp
        }
        return .repairAndReinstall
    }

    func loadInitialStatus() async {
        guard !isCheckingSystem, activeAction == nil else {
            return
        }
        isCheckingSystem = true
        defer { isCheckingSystem = false }

        let readiness = ReadinessCoordinator.shared
        await readiness.deepRefresh()
        apply(readiness: readiness)
    }

    func refreshStatus() async {
        await ReadinessCoordinator.shared.refresh()
        apply(readiness: ReadinessCoordinator.shared)
    }

    func syncFromCoordinator() {
        apply(readiness: ReadinessCoordinator.shared)
    }

    func installCert() async {
        guard !certTrusted else {
            return
        }
        await perform(.certificate, errorArea: .certificate) {
            try await CertificateManager.shared.installAndTrust()
        }
    }

    func installHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.install()
        }
    }

    func applyHelperState(
        status: HelperManager.HelperStatus,
        signingIssue: HelperManager.SigningIssue?
    ) {
        helperStatus = status
        helperSigningIssue = signingIssue
    }

    func retryHelperConnection() async {
        guard begin(.helper, errorArea: .helper) else {
            return
        }
        defer { activeAction = nil }

        await HelperManager.shared.retryConnection()
        await refreshStatus()

        guard helperStatus == .unreachable else {
            errorArea = nil
            return
        }
        errorMessage = HelperManager.shared.lastErrorMessage
            ?? String(localized: "Rockxy still cannot reach the installed helper.")
        helperFailureRecovery = .repairAndReinstall
    }

    func repairAndReinstallHelper() async {
        guard begin(.helper, errorArea: .helper) else {
            return
        }
        defer { activeAction = nil }

        let captureWasActive = ReadinessCoordinator.shared.isCaptureActive
        if captureWasActive {
            NotificationCenter.default.post(name: .stopProxyRequested, object: nil)
            try? await Task.sleep(for: .milliseconds(750))
        }

        do {
            _ = try await HelperManager.shared.forceResetAndReinstall(resetBackgroundItems: false)
            await refreshStatus()
            if helperStatus == .unreachable {
                errorMessage = HelperManager.shared.lastErrorMessage
                    ?? String(localized: "Rockxy reinstalled the helper but still cannot reach it.")
                helperFailureRecovery = .repairAndReinstall
            } else {
                errorArea = nil
            }
        } catch {
            Self.logger.error("Failed to repair helper: \(error.localizedDescription)")
            await refreshStatus()
            recordFailure(error, area: .helper)
        }
    }

    func reinstallHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.reinstall()
        }
    }

    func updateHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.update()
        }
    }

    func enableProxy() async {
        await perform(.systemProxy, errorArea: .systemProxy) {
            let settings = AppSettingsStorage.load()
            try await SystemProxyManager.shared.enableSystemProxy(port: settings.proxyPort)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WelcomeViewModel")

    private func begin(_ action: ActiveAction, errorArea: ErrorArea) -> Bool {
        guard Self.canBeginAction(current: activeAction, isCheckingSystem: isCheckingSystem) else {
            return false
        }
        activeAction = action
        self.errorArea = errorArea
        errorMessage = nil
        if action == .helper {
            helperFailureRecovery = nil
        }
        return true
    }

    private func perform(
        _ action: ActiveAction,
        errorArea: ErrorArea,
        operation: () async throws -> Void
    )
        async
    {
        guard begin(action, errorArea: errorArea) else {
            return
        }
        defer { activeAction = nil }

        do {
            try await operation()
            await refreshStatus()
            if action == .helper, helperStatus == .unreachable {
                errorMessage = HelperManager.shared.lastErrorMessage
                    ?? String(localized: "Rockxy still cannot reach the installed helper.")
                helperFailureRecovery = .repairAndReinstall
            } else {
                self.errorArea = nil
            }
        } catch {
            Self.logger.error("Welcome \(String(describing: action)) action failed: \(error.localizedDescription)")
            await refreshStatus()
            recordFailure(error, area: errorArea)
        }
    }

    private func recordFailure(_ error: Error, area: ErrorArea) {
        errorMessage = error.localizedDescription
        errorArea = area
        if area == .helper {
            helperFailureRecovery = Self.resolveHelperFailureRecovery(for: error)
        }
    }

    private func apply(readiness: ReadinessCoordinator) {
        certInstalled = readiness.certReadiness != .notGenerated
        certTrusted = readiness.canInterceptHTTPS
        applyHelperState(status: readiness.helperReadiness, signingIssue: readiness.helperSigningIssue)
        systemProxyEnabled = readiness.proxyMode != .unavailable
    }
}
