import Foundation
@testable import Rockxy
import Testing

// MARK: - FailingProcessRunner

private struct FailingProcessRunner: DeveloperSetupProcessRunning {
    func run(executableURL: URL, arguments _: [String]) throws {
        throw DeveloperSetupLaunchError.processFailed(
            command: executableURL.lastPathComponent,
            status: 2,
            message: "simulated failure"
        )
    }
}

@MainActor
private final class CapturingPasteboard: DeveloperSetupPasteboardWriting {
    private(set) var string: String?

    func write(_ string: String) {
        self.string = string
    }
}

// MARK: - DeveloperSetupRouteStoreTests

@MainActor
struct DeveloperSetupRouteStoreTests {
    @Test("Manual route carries the target identity and manual destination")
    func manualRouteCarriesTarget() {
        let store = DeveloperSetupRouteStore()

        store.requestManual(targetID: .postman)
        let route = store.consumeManualRoute()

        #expect(route?.targetID == .postman)
        #expect(route?.destination == .manual)
        #expect(store.consumeManualRoute() == nil)
    }

    @Test("Automatic routes are rejected for non runtime-terminal targets")
    func automaticRouteRejectsUnsupportedTargets() {
        let store = DeveloperSetupRouteStore()

        #expect(store.requestAutomatic(targetID: .postman) == false)
        #expect(store.consumeAutomaticRoute() == nil)

        #expect(store.requestAutomatic(targetID: .iosDevice) == false)
        #expect(store.consumeAutomaticRoute() == nil)

        #expect(store.requestAutomatic(targetID: .python) == true)
        #expect(store.consumeAutomaticRoute()?.targetID == .python)
    }

    @Test("A newer route wins over an older one by generation")
    func newerRouteWinsByGeneration() {
        let store = DeveloperSetupRouteStore()

        store.request(targetID: .python, tab: .snippets)
        let first = store.hubRoute
        store.request(targetID: .ruby, tab: .setup)
        let second = store.hubRoute

        #expect((second?.generation ?? 0) > (first?.generation ?? 0))
        #expect(store.consumeHubRoute()?.targetID == .ruby)
    }

    @Test("Default runtime target is a shipped terminal runtime")
    func defaultRuntimeTargetIsTerminalRuntime() {
        let target = SetupTarget.target(for: DeveloperSetupRouteStore.defaultRuntimeTargetID)
        #expect(target?.isRuntimeTerminalTarget == true)
    }
}

// MARK: - DeveloperSetupSessionTargetTests

@MainActor
struct DeveloperSetupSessionTargetTests {
    @Test("Session setup reflects the routed target instead of a generic default")
    func sessionReflectsRoutedTarget() {
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python
        )

        viewModel.applyRoute(
            DeveloperSetupRoute(targetID: .postman, tab: .setup, destination: .manual, generation: 1),
            destination: .manual
        )

        #expect(viewModel.targetID == .postman)
        #expect(viewModel.target.id == .postman)
        #expect(viewModel.isRuntimeTerminalTarget == false)
        #expect(viewModel.targetSnippetText != nil)
    }

    @Test("Session route rejects stale generations and the wrong destination")
    func sessionRouteRejectsStaleOrWrongDestination() {
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python
        )

        viewModel.applyRoute(
            DeveloperSetupRoute(targetID: .ruby, tab: .setup, destination: .manual, generation: 2),
            destination: .manual
        )
        viewModel.applyRoute(
            DeveloperSetupRoute(targetID: .postman, tab: .setup, destination: .manual, generation: 1),
            destination: .manual
        )
        viewModel.applyRoute(
            DeveloperSetupRoute(targetID: .nodeJS, tab: .setup, destination: .automatic, generation: 3),
            destination: .manual
        )

        #expect(viewModel.targetID == .ruby)
    }

    @Test("Runtime-terminal targets remain terminal-eligible")
    func runtimeTargetIsTerminalEligible() {
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python
        )
        #expect(viewModel.isRuntimeTerminalTarget == true)
    }

    @Test("Brave was removed from the browser picker")
    func braveRemovedFromBrowserPicker() {
        #expect(SetupBrowserApp.allCases.count == 3)
        for browser in SetupBrowserApp.allCases {
            #expect(browser.isEnabled)
            #expect(browser.title.localizedCaseInsensitiveContains("brave") == false)
            #expect(browser.title.localizedCaseInsensitiveContains("coming soon") == false)
        }
    }

    @Test("Terminal launcher reports a nonzero exit as an error")
    func terminalLauncherReportsNonzeroExit() {
        #expect(throws: DeveloperSetupLaunchError.self) {
            try RockxySetupSessionLauncher.openTerminal(
                .appleTerminal,
                sourceCommand: "echo hi",
                runner: FailingProcessRunner()
            )
        }
    }

    @Test("Browser launcher never silently succeeds on a failed process")
    func browserLauncherReportsFailure() {
        #expect(throws: (any Error).self) {
            try RockxySetupSessionLauncher.openBrowser(
                .chromeCurrentProfile,
                proxyHost: "127.0.0.1",
                proxyPort: 9_090,
                runner: FailingProcessRunner()
            )
        }
    }

    @Test("Custom terminal copies the setup command and reports it")
    func customTerminalCopiesCommand() async throws {
        let scriptURL = temporaryScriptURL()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let pasteboard = CapturingPasteboard()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python,
            pasteboard: pasteboard,
            scriptURL: scriptURL
        )
        viewModel.selectedTerminalApp = .custom

        await viewModel.openPreparedTerminal()

        #expect(viewModel.statusMessage?.localizedCaseInsensitiveContains("copied") == true)
        #expect(pasteboard.string == viewModel.manualSourceCommand)
    }

    @Test("View model surfaces launcher failure instead of a success message")
    func viewModelReportsLauncherFailure() async throws {
        let scriptURL = temporaryScriptURL()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python,
            processRunner: FailingProcessRunner(),
            scriptURL: scriptURL
        )
        viewModel.selectedTerminalApp = .appleTerminal

        await viewModel.openPreparedTerminal()

        let status = viewModel.statusMessage ?? ""
        #expect(status.localizedCaseInsensitiveContains("could not"))
        #expect(status.localizedCaseInsensitiveContains("opened") == false)
    }

    private func temporaryScriptURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-developer-setup-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("rockxy_env_setup.sh")
    }
}

// MARK: - DeveloperSetupViewModelRoutingTests

@MainActor
struct DeveloperSetupViewModelRoutingTests {
    @Test("Hub route selects the routed target and applies the routed tab")
    func hubRouteAppliesTargetAndTab() async {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        await viewModel.applyHubRoute(
            DeveloperSetupRoute(targetID: .postman, tab: .snippets, destination: .hub, generation: 1)
        )

        #expect(viewModel.selectedTarget.id == .postman)
        #expect(viewModel.selectedTab == .snippets)
    }

    @Test("A newer hub route wins over an older async route")
    func newerHubRouteWins() async {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        async let older: Void = viewModel.applyHubRoute(
            DeveloperSetupRoute(targetID: .postman, tab: .snippets, destination: .hub, generation: 1)
        )
        async let newer: Void = viewModel.applyHubRoute(
            DeveloperSetupRoute(targetID: .ruby, tab: .setup, destination: .hub, generation: 2)
        )
        _ = await (older, newer)

        #expect(viewModel.selectedTarget.id == .ruby)
        #expect(viewModel.selectedTab == .setup)
    }

    @Test("An older hub route is rejected after a newer generation")
    func olderHubRouteIsRejected() async {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        await viewModel.applyHubRoute(
            DeveloperSetupRoute(targetID: .ruby, tab: .setup, destination: .hub, generation: 2)
        )
        await viewModel.applyHubRoute(
            DeveloperSetupRoute(targetID: .postman, tab: .snippets, destination: .hub, generation: 1)
        )

        #expect(viewModel.selectedTarget.id == .ruby)
        #expect(viewModel.selectedTab == .setup)
    }

    @Test("Serialized target switches land on the final target")
    func serializedTargetSwitchLandsOnFinalTarget() async {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        let firstSwitch = Task { @MainActor in
            await viewModel.selectTarget(.nodeJS)
        }
        await Task.yield()
        await viewModel.selectTarget(.docker)
        await firstSwitch.value

        #expect(viewModel.selectedTarget.id == .docker)
        #expect(viewModel.supportsAutomation == false)
    }
}
