import AppKit
import ServiceManagement

@MainActor
enum HelperRecoveryPresenter {
    // MARK: Internal

    static func requestRequiredReopen() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.requestQuitForRequiredReopen()
        } else {
            NSApp.terminate(nil)
        }
    }

    static func presentForceReset(stopCapture: (() -> Void)? = nil) {
        let confirmation = NSAlert()
        confirmation.alertStyle = .critical
        confirmation.messageText = String(
            localized: "Force reset the Rockxy Helper?",
            bundle: RockxyLocalization.bundle
        )
        confirmation.informativeText = String(
            localized: """
            Rockxy will stop capture, request administrator approval, remove stale launchd and privileged helper files, \
            then reinstall the helper from the current app bundle. System proxy settings may be restored during the reset.

            Use this only when install, uninstall, and recheck are stuck.
            """, bundle: RockxyLocalization.bundle
        )
        confirmation.addButton(withTitle: String(localized: "Force Reset", bundle: RockxyLocalization.bundle))
        confirmation.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))

        guard confirmation.runModal() == .alertFirstButtonReturn else {
            return
        }

        runForceReset(stopCapture: stopCapture, resetBackgroundItems: false)
    }

    // MARK: Private

    private static func runForceReset(
        stopCapture: (() -> Void)?,
        resetBackgroundItems: Bool
    ) {
        NotificationCenter.default.post(name: .stopProxyRequested, object: nil)
        stopCapture?()

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
                let result = try await HelperManager.shared.forceResetAndReinstall(
                    resetBackgroundItems: resetBackgroundItems
                )
                await ReadinessCoordinator.shared.deepRefresh()
                presentSuccess(result: result)
            } catch {
                presentFailure(
                    error: error,
                    stopCapture: stopCapture,
                    canTryBackgroundItemsReset: !resetBackgroundItems
                )
            }
        }
    }

    private static func presentSuccess(result: HelperManager.ForceResetRepairResult) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Helper reset complete", bundle: RockxyLocalization.bundle)
        alert.informativeText = result.localizedSummary
        if result.requiresApproval {
            alert.addButton(withTitle: String(localized: "Open Login Items", bundle: RockxyLocalization.bundle))
        }
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))

        switch alert.runModal() {
        case .alertFirstButtonReturn where result.requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            break
        }
    }

    private static func presentFailure(
        error: Error,
        stopCapture: (() -> Void)?,
        canTryBackgroundItemsReset: Bool
    ) {
        if error as? HelperManager.HelperOperationError == .applicationMustReopen {
            presentRequiredReopen()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Helper reset failed", bundle: RockxyLocalization.bundle)
        alert.informativeText = error.localizedDescription

        if canTryBackgroundItemsReset {
            alert.addButton(withTitle: String(
                localized: "Try Background Items Reset",
                bundle: RockxyLocalization.bundle
            ))
        }
        alert.addButton(withTitle: String(localized: "Copy Details", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))

        let response = alert.runModal()
        if canTryBackgroundItemsReset, response == .alertFirstButtonReturn {
            presentBackgroundItemsResetConfirmation(stopCapture: stopCapture)
            return
        }

        let copyDetailsResponse: NSApplication.ModalResponse = canTryBackgroundItemsReset
            ? .alertSecondButtonReturn
            : .alertFirstButtonReturn
        if response == copyDetailsResponse {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(error.localizedDescription, forType: .string)
        }
    }

    private static func presentRequiredReopen() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Reopen Rockxy to continue", bundle: RockxyLocalization.bundle)
        alert.informativeText = HelperManager.applicationMustReopenMessage
        alert.addButton(withTitle: String(localized: "Quit Rockxy", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Not Now", bundle: RockxyLocalization.bundle))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        requestRequiredReopen()
    }

    private static func presentBackgroundItemsResetConfirmation(stopCapture: (() -> Void)?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(
            localized: "Reset macOS Login and Background Items data?",
            bundle: RockxyLocalization.bundle
        )
        alert.informativeText = String(
            localized: """
            This runs sfltool resetbtm after removing Rockxy helper files. It can reset Background Items state \
            for other apps, so use it only when the normal force reset cannot recover Rockxy.
            """, bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "Reset Background Items", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        runForceReset(stopCapture: stopCapture, resetBackgroundItems: true)
    }
}
