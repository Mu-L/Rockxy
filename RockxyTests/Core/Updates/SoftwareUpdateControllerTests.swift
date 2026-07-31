import AppKit
import CoreGraphics
import Foundation
@testable import Rockxy
import Sparkle
import Testing

// MARK: - SoftwareUpdateControllerTests

@MainActor
struct SoftwareUpdateControllerTests {
    @Test("no-update context renders published release notes for the running build")
    func noUpdateContextUsesMatchingAppcastNotes() throws {
        let controller = SoftwareUpdateController(configuration: makeConfiguration(
            appVersion: "0.12.0",
            buildNumber: "15"
        ))
        let item = try makeAppcastItem(
            displayVersion: "0.12.0",
            buildNumber: "15",
            description: "<h1>Rockxy 0.12.0</h1><p>Notes</p>"
        )
        let error = NSError(
            domain: "RockxyTests.SoftwareUpdateController",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: "Rockxy 0.12.0 is already installed.",
                SPULatestAppcastItemFoundKey: item,
            ]
        )

        let context = controller.makeNoUpdateContext(from: error)

        #expect(context.currentVersion == "0.12.0 (15)")
        #expect(context.latestVersion == "0.12.0")
        #expect(
            context.releaseNotes
                == .html("<h1>Rockxy 0.12.0</h1><p>Notes</p>", baseURL: nil)
        )
        #expect(context.detailURL?.absoluteString == "https://example.com/releases/full")
    }

    @Test("no-update context avoids showing mismatched published notes for newer local builds")
    func noUpdateContextFallsBackForUnpublishedLocalBuild() throws {
        let controller = SoftwareUpdateController(configuration: makeConfiguration(
            appVersion: "0.12.1",
            buildNumber: "16"
        ))
        let item = try makeAppcastItem(
            displayVersion: "0.12.0",
            buildNumber: "15",
            description: "<h1>Rockxy 0.12.0</h1><p>Notes</p>"
        )
        let error = NSError(
            domain: "RockxyTests.SoftwareUpdateController",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: "Rockxy 0.12.1 is already installed.",
                SPULatestAppcastItemFoundKey: item,
            ]
        )

        let context = controller.makeNoUpdateContext(from: error)

        #expect(context.currentVersion == "0.12.1 (16)")
        #expect(context.latestVersion == "0.12.0")
        #expect(
            context.releaseNotes
                == .unavailable(
                    "Release notes for this local build are unavailable because this version is not published to the update feed yet."
                )
        )
        #expect(context.detailURL == AppUpdater.fullChangelogURL)
    }

    @Test("release note updates persist into later update phases")
    func releaseNotesPersistAcrossPhaseTransitions() {
        let controller = SoftwareUpdateController(configuration: makeConfiguration(
            appVersion: "0.12.0",
            buildNumber: "15"
        ))

        controller.showAvailable(context: makeAvailableContext(releaseNotes: .loading)) { _ in }
        defer { controller.dismiss() }

        controller.updateReleaseNotes(.plainText("Resolved release notes"))
        controller.showDownloading(cancel: {})

        guard case let .downloading(context, _, _) = controller.phase else {
            Issue.record("Expected downloading phase after starting the download")
            return
        }

        #expect(context.releaseNotes == .plainText("Resolved release notes"))
    }

    @Test("update stage descriptions refresh when the update phase advances")
    func updateStageDescriptionsRefreshAcrossTransitions() {
        let controller = SoftwareUpdateController(configuration: makeConfiguration(
            appVersion: "0.12.0",
            buildNumber: "15"
        ))

        controller.showAvailable(context: makeAvailableContext()) { _ in }
        defer { controller.dismiss() }

        controller.showReadyToInstall(reply: { _ in })

        guard case let .readyToInstall(readyContext) = controller.phase else {
            Issue.record("Expected ready-to-install phase")
            return
        }
        #expect(readyContext.updateStageDescription == "Downloaded")

        controller.showInstalling(applicationTerminated: false, retryTerminatingApplication: {})

        guard case let .installing(installingContext, applicationTerminated) = controller.phase else {
            Issue.record("Expected installing phase")
            return
        }
        #expect(applicationTerminated == false)
        #expect(installingContext.updateStageDescription == "Installing")
    }

    @Test("software update window centers on the active app window")
    func updateWindowFrameCentersOnAnchorWindow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let anchorFrame = NSRect(x: 100, y: 100, width: 1_200, height: 800)

        let frame = SoftwareUpdateWindowPositioning.positionedFrame(
            windowSize: SoftwareUpdateWindowPositioning.contentSize,
            anchorFrame: anchorFrame,
            visibleFrame: visibleFrame
        )

        #expect(frame.midX == anchorFrame.midX)
        #expect(frame.midY == anchorFrame.midY)
        #expect(frame.minX >= visibleFrame.minX)
        #expect(frame.maxX <= visibleFrame.maxX)
        #expect(frame.minY >= visibleFrame.minY)
        #expect(frame.maxY <= visibleFrame.maxY)
    }

    @Test("software update window falls back to screen centering")
    func updateWindowFrameCentersOnScreenWithoutAnchorWindow() {
        let visibleFrame = NSRect(x: 1_440, y: 0, width: 1_920, height: 1_080)

        let frame = SoftwareUpdateWindowPositioning.positionedFrame(
            windowSize: SoftwareUpdateWindowPositioning.contentSize,
            anchorFrame: nil,
            visibleFrame: visibleFrame
        )

        #expect(frame.midX == visibleFrame.midX)
        #expect(frame.midY == visibleFrame.midY)
    }

    @Test("software update window stays inside the display visible frame")
    func updateWindowFrameClampsToVisibleScreenArea() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let anchorFrame = NSRect(x: 1_300, y: 750, width: 400, height: 300)

        let frame = SoftwareUpdateWindowPositioning.positionedFrame(
            windowSize: SoftwareUpdateWindowPositioning.contentSize,
            anchorFrame: anchorFrame,
            visibleFrame: visibleFrame
        )

        #expect(frame.maxX == visibleFrame.maxX)
        #expect(frame.maxY == visibleFrame.maxY)
        #expect(frame.minX >= visibleFrame.minX)
        #expect(frame.minY >= visibleFrame.minY)
    }

    @Test("interactive close policy is phase-aware and refuses unsafe phases")
    func interactiveCloseOutcomeMatchesEachPhase() {
        let context = makeAvailableContext()
        let noUpdate = SoftwareUpdateController.NoUpdateContext(
            title: "Up to date",
            summary: "No update",
            currentVersion: "0.12.0 (15)",
            latestVersion: "0.12.0",
            releaseNotes: .unavailable("None"),
            detailURL: nil
        )
        let errorContext = SoftwareUpdateController.ErrorContext(
            title: "Failed",
            summary: "Something went wrong",
            recoverySuggestion: nil
        )

        #expect(SoftwareUpdateController.Phase.hidden.interactiveCloseOutcome == .deny)
        #expect(SoftwareUpdateController.Phase.checking.interactiveCloseOutcome == .dismiss)
        #expect(SoftwareUpdateController.Phase.available(context).interactiveCloseOutcome == .dismiss)
        #expect(
            SoftwareUpdateController.Phase
                .downloading(context, bytesReceived: 0, expectedBytes: nil)
                .interactiveCloseOutcome == .dismiss
        )
        #expect(SoftwareUpdateController.Phase.extracting(context, progress: nil).interactiveCloseOutcome == .deny)
        #expect(SoftwareUpdateController.Phase.readyToInstall(context).interactiveCloseOutcome == .dismiss)
        #expect(
            SoftwareUpdateController.Phase
                .installing(context, applicationTerminated: false)
                .interactiveCloseOutcome == .deny
        )
        #expect(SoftwareUpdateController.Phase.noUpdate(noUpdate).interactiveCloseOutcome == .acknowledge)
        #expect(SoftwareUpdateController.Phase.error(errorContext).interactiveCloseOutcome == .acknowledge)
    }

    @Test("checking interactive close cancels exactly once")
    func checkingInteractiveCloseCancelsOnce() {
        let controller = makeController()
        var cancelCount = 0
        controller.showChecking(cancel: { cancelCount += 1 })

        controller.requestInteractiveClose()
        #expect(cancelCount == 1)
        #expect(controller.phase == .hidden)

        controller.requestInteractiveClose()
        #expect(cancelCount == 1)
    }

    @Test("available interactive close invokes the dismiss choice exactly once")
    func availableInteractiveCloseDismissesOnce() {
        let controller = makeController()
        var choices: [SPUUserUpdateChoice] = []
        controller.showAvailable(context: makeAvailableContext()) { choices.append($0) }

        controller.requestInteractiveClose()
        #expect(choices == [.dismiss])
        #expect(controller.phase == .hidden)

        controller.requestInteractiveClose()
        #expect(choices == [.dismiss])
    }

    @Test("downloading interactive close cancels the download exactly once")
    func downloadingInteractiveCloseCancelsOnce() {
        let controller = makeController()
        controller.showAvailable(context: makeAvailableContext()) { _ in }
        var cancelCount = 0
        controller.showDownloading(cancel: { cancelCount += 1 })

        guard case .downloading = controller.phase else {
            Issue.record("Expected downloading phase")
            return
        }

        controller.requestInteractiveClose()
        #expect(cancelCount == 1)
        #expect(controller.phase == .hidden)

        controller.requestInteractiveClose()
        #expect(cancelCount == 1)
    }

    @Test("ready-to-install interactive close invokes the dismiss choice exactly once")
    func readyToInstallInteractiveCloseDismissesOnce() {
        let controller = makeController()
        controller.showAvailable(context: makeAvailableContext()) { _ in }
        var choices: [SPUUserUpdateChoice] = []
        controller.showReadyToInstall(reply: { choices.append($0) })

        controller.requestInteractiveClose()
        #expect(choices == [.dismiss])
        #expect(controller.phase == .hidden)
    }

    @Test("no-update and error interactive close acknowledges exactly once")
    func acknowledgementPhasesAcknowledgeOnce() {
        let noUpdateController = makeController()
        var noUpdateAcks = 0
        noUpdateController.showNoUpdate(error: makeError(), acknowledgement: { noUpdateAcks += 1 })
        noUpdateController.requestInteractiveClose()
        #expect(noUpdateAcks == 1)
        #expect(noUpdateController.phase == .hidden)
        noUpdateController.requestInteractiveClose()
        #expect(noUpdateAcks == 1)

        let errorController = makeController()
        var errorAcks = 0
        errorController.showError(makeError(), acknowledgement: { errorAcks += 1 })
        errorController.requestInteractiveClose()
        #expect(errorAcks == 1)
        #expect(errorController.phase == .hidden)
    }

    @Test("extracting and installing refuse interactive close and preserve the session")
    func unsafePhasesRefuseInteractiveClose() {
        let extractingController = makeController()
        defer { extractingController.dismiss() }
        extractingController.showAvailable(context: makeAvailableContext()) { _ in }
        extractingController.showExtracting()
        guard case .extracting = extractingController.phase else {
            Issue.record("Expected extracting phase")
            return
        }
        #expect(extractingController.windowShouldClose(NSWindow()) == false)
        extractingController.requestInteractiveClose()
        guard case .extracting = extractingController.phase else {
            Issue.record("Extracting phase must be preserved after a refused close")
            return
        }

        let installingController = makeController()
        defer { installingController.dismiss() }
        installingController.showAvailable(context: makeAvailableContext()) { _ in }
        installingController.showInstalling(applicationTerminated: false, retryTerminatingApplication: {})
        guard case .installing = installingController.phase else {
            Issue.record("Expected installing phase")
            return
        }
        #expect(installingController.windowShouldClose(NSWindow()) == false)
        installingController.requestInteractiveClose()
        guard case .installing = installingController.phase else {
            Issue.record("Installing phase must be preserved after a refused close")
            return
        }
    }

    @Test("visible action followed by programmatic dismiss never double-fires the callback")
    func visibleActionThenDismissDoesNotDoubleCallback() {
        let installController = makeController()
        var installChoices: [SPUUserUpdateChoice] = []
        installController.showAvailable(context: makeAvailableContext()) { installChoices.append($0) }
        installController.chooseInstall()
        installController.dismiss()
        #expect(installChoices == [.install])

        let laterController = makeController()
        var laterChoices: [SPUUserUpdateChoice] = []
        laterController.showAvailable(context: makeAvailableContext()) { laterChoices.append($0) }
        laterController.chooseLater()
        #expect(laterChoices == [.dismiss])
        #expect(laterController.phase == .hidden)
    }

    @Test("synchronous callback transitions are not cleared by the previous action")
    func synchronousCallbackTransitionIsPreserved() {
        let installController = makeController()
        defer { installController.dismiss() }
        installController.showAvailable(context: makeAvailableContext()) { choice in
            guard choice == .install else {
                return
            }
            installController.showDownloading(cancel: {})
        }

        installController.chooseInstall()

        guard case .downloading = installController.phase else {
            Issue.record("A synchronous download transition must survive the install reply")
            return
        }

        let laterController = makeController()
        defer { laterController.dismiss() }
        laterController.showAvailable(context: makeAvailableContext()) { choice in
            guard choice == .dismiss else {
                return
            }
            laterController.showError(makeError(), acknowledgement: {})
        }

        laterController.chooseLater()

        guard case .error = laterController.phase else {
            Issue.record("A synchronous error transition must survive the dismiss reply")
            return
        }
    }

    @Test("interactive close preserves a synchronous callback transition")
    func interactiveClosePreservesSynchronousTransition() {
        let controller = makeController()
        defer { controller.dismiss() }
        controller.showAvailable(context: makeAvailableContext()) { choice in
            guard choice == .dismiss else {
                return
            }
            controller.showError(makeError(), acknowledgement: {})
        }

        controller.requestInteractiveClose()

        guard case .error = controller.phase else {
            Issue.record("A synchronous transition must survive interactive-close cleanup")
            return
        }
    }
}

@MainActor
private func makeController() -> SoftwareUpdateController {
    SoftwareUpdateController(configuration: makeConfiguration(appVersion: "0.12.0", buildNumber: "15"))
}

private func makeError() -> NSError {
    NSError(
        domain: "RockxyTests.SoftwareUpdateController",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Rockxy 0.12.0 is already installed."]
    )
}

private func makeConfiguration(appVersion: String, buildNumber: String) -> RockxyUpdateConfiguration {
    RockxyUpdateConfiguration(infoDictionary: [
        "RockxyUpdatesEnabled": "NO",
        "SUFeedURL": "https://example.com/appcast.xml",
        "SUPublicEDKey": "public-key",
        "CFBundleShortVersionString": appVersion,
        "CFBundleVersion": buildNumber,
        "RockxyBuildReleaseDate": "2026-04-28T00:00:00Z",
    ])
}

private func makeAppcastItem(
    displayVersion: String,
    buildNumber: String,
    description: String
)
    throws -> SUAppcastItem
{
    let itemDictionary: [String: Any] = [
        "title": "Rockxy \(displayVersion)",
        "link": "https://example.com/releases/\(displayVersion)",
        "description": [
            "content": description,
            "format": "html",
        ],
        "sparkle:fullReleaseNotesLink": "https://example.com/releases/full",
        "enclosure": [
            "url": "https://example.com/downloads/Rockxy-\(displayVersion).zip",
            "length": "123",
            "sparkle:version": buildNumber,
            "sparkle:shortVersionString": displayVersion,
        ],
    ]
    var failureReason: NSString?
    guard let item = SUAppcastItem(
        dictionary: itemDictionary,
        relativeTo: URL(string: "https://example.com/appcast.xml"),
        failureReason: &failureReason
    ) else {
        throw NSError(
            domain: "RockxyTests.SoftwareUpdateController",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: failureReason as String? ?? "Unable to create SUAppcastItem fixture.",
            ]
        )
    }
    return item
}

private func makeAvailableContext(
    releaseNotes: SoftwareUpdateReleaseNotesContent = .loading,
    stageDescription: String = "Not downloaded"
)
    -> SoftwareUpdateController.UpdateContext
{
    SoftwareUpdateController.UpdateContext(
        title: "Rockxy 0.12.0",
        summary: "Rockxy 0.12.0 is now available.",
        currentVersion: "0.11.0",
        latestVersion: "0.12.0",
        buildNumber: "15",
        updateStageDescription: stageDescription,
        publishedDate: nil,
        releaseNotes: releaseNotes,
        detailURL: URL(string: "https://example.com/releases/0.12.0"),
        isInformationOnly: false,
        downloadSize: 123
    )
}
