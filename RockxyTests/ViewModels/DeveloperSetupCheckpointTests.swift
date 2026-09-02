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

// MARK: - CapturingProcessRunner

private final class CapturingProcessRunner: DeveloperSetupProcessRunning, @unchecked Sendable {
    // MARK: Internal

    var wasInvoked: Bool {
        lock.withLock { invocationCount > 0 }
    }

    func run(executableURL _: URL, arguments _: [String]) throws {
        lock.withLock { invocationCount += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var invocationCount = 0
}

// MARK: - CapturingPasteboard

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

    @Test("Java VMs is an eligible Automatic Setup route target")
    func automaticRouteAcceptsJavaVMs() {
        let store = DeveloperSetupRouteStore()

        #expect(SetupTarget.javaVMs.isRuntimeTerminalTarget)
        #expect(store.requestAutomatic(targetID: .javaVMs) == true)
        #expect(store.consumeAutomaticRoute()?.targetID == .javaVMs)
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
    // MARK: Internal

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

    @Test("Routing a Java session regenerates the script with JVM proxy properties")
    func javaSessionGeneratesJVMProxyProperties() {
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python
        )

        viewModel.applyRoute(
            DeveloperSetupRoute(targetID: .javaVMs, tab: .setup, destination: .automatic, generation: 1),
            destination: .automatic
        )

        #expect(viewModel.targetID == .javaVMs)
        #expect(viewModel.isRuntimeTerminalTarget)
        #expect(viewModel.context.targetID == .javaVMs)

        let script = RockxySetupScriptBuilder.script(context: viewModel.context)
        #expect(script.contains("-Dhttps.proxyHost="))
        #expect(script.contains("export JAVA_TOOL_OPTIONS="))
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
    func customTerminalCopiesCommand() async {
        let scriptURL = temporaryScriptURL()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let pasteboard = CapturingPasteboard()
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .python,
            pasteboard: pasteboard,
            scriptURL: scriptURL
        )
        viewModel.selectedTerminalApp = .custom

        await viewModel.openPreparedTerminal()

        #expect(viewModel.statusMessage?.localizedCaseInsensitiveContains("copied") == true)
        #expect(pasteboard.string == viewModel.manualSourceCommand)
    }

    @Test("Automatic terminal launch is blocked while the proxy is stopped")
    func stoppedProxyBlocksAutomaticTerminalLaunch() async {
        let scriptURL = temporaryScriptURL()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let pasteboard = CapturingPasteboard()
        let processRunner = CapturingProcessRunner()
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = false
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .javaVMs,
            processRunner: processRunner,
            pasteboard: pasteboard,
            scriptURL: scriptURL
        )

        await viewModel.openPreparedTerminal()

        #expect(viewModel.statusMessage == String(
            localized: "Start the Rockxy proxy before opening a prepared terminal.",
            bundle: RockxyLocalization.bundle
        ))
        #expect(FileManager.default.fileExists(atPath: scriptURL.path) == false)
        #expect(processRunner.wasInvoked == false)
        #expect(pasteboard.string == nil)
    }

    @Test("View model surfaces launcher failure instead of a success message")
    func viewModelReportsLauncherFailure() async {
        let scriptURL = temporaryScriptURL()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
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

    // MARK: Private

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
