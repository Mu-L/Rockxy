@testable import Rockxy
import Testing

// MARK: - MCPServerCoordinatorTests

@MainActor
@Suite("MCP Server Coordinator", .serialized)
struct MCPServerCoordinatorTests {
    @Test("Initial state is not running")
    func initialState() {
        let coordinator = MCPServerCoordinator()
        #expect(!coordinator.isRunning)
        #expect(coordinator.activePort == nil)
        #expect(coordinator.lastError == nil)
    }

    @Test("Start when disabled does nothing")
    func startWhenDisabled() async {
        let originalSettings = AppSettingsManager.shared.settings
        defer { AppSettingsManager.shared.settings = originalSettings }

        var settings = originalSettings
        settings.mcpServerEnabled = false
        AppSettingsManager.shared.settings = settings

        let coordinator = MCPServerCoordinator()
        await coordinator.startIfEnabled()
        #expect(!coordinator.isRunning)
        #expect(coordinator.activePort == nil)
    }

    @Test("Stop when not running is safe")
    func stopWhenNotRunning() async {
        let coordinator = MCPServerCoordinator()
        await coordinator.stop()
        #expect(!coordinator.isRunning)
        #expect(coordinator.activePort == nil)
        #expect(coordinator.lastError == nil)
    }

    @Test("Restart when disabled stays stopped")
    func restartWhenDisabled() async {
        let originalSettings = AppSettingsManager.shared.settings
        defer { AppSettingsManager.shared.settings = originalSettings }

        var settings = originalSettings
        settings.mcpServerEnabled = false
        AppSettingsManager.shared.settings = settings

        let coordinator = MCPServerCoordinator()
        await coordinator.restart()
        #expect(!coordinator.isRunning)
    }

    @Test("Detach providers when none attached is safe")
    func detachWithoutAttach() {
        let coordinator = MCPServerCoordinator()
        coordinator.detachProviders()
        #expect(!coordinator.isRunning)
    }
}

// MARK: - MCPSettingsServerStateTests

@Suite("MCP Settings Server State")
struct MCPSettingsServerStateTests {
    @Test("Disabled state wins over stale runtime details")
    func disabledStateWins() {
        #expect(MCPSettingsServerState.resolve(
            isEnabled: false,
            isStarting: true,
            isRunning: true,
            activePort: 9_710,
            lastError: "stale"
        ) == .disabled)
    }

    @Test("Starting state replaces a previous failure while retrying")
    func startingStateWinsOverError() {
        #expect(MCPSettingsServerState.resolve(
            isEnabled: true,
            isStarting: true,
            isRunning: false,
            activePort: nil,
            lastError: "previous failure"
        ) == .starting)
    }

    @Test("Enabled server distinguishes ready, failed, and stopped states")
    func enabledStatesRemainTruthful() {
        #expect(MCPSettingsServerState.resolve(
            isEnabled: true,
            isStarting: false,
            isRunning: true,
            activePort: 9_710,
            lastError: nil
        ) == .running(port: 9_710))
        #expect(MCPSettingsServerState.resolve(
            isEnabled: true,
            isStarting: false,
            isRunning: false,
            activePort: nil,
            lastError: "Port unavailable"
        ) == .failed("Port unavailable"))
        #expect(MCPSettingsServerState.resolve(
            isEnabled: true,
            isStarting: false,
            isRunning: false,
            activePort: nil,
            lastError: nil
        ) == .stopped)
    }
}
