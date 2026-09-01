import Foundation
@testable import Rockxy
import Testing

// MARK: - MockProxyStateProvider

@MainActor
final class MockProxyStateProvider: MCPProxyStateProvider {
    var isProxyRunning = true
    var activeProxyPort = 9_090
    var isRecording = true
    var isSystemProxyConfigured = false
    var transactionCount = 42
}

// MARK: - MCPStatusServiceTests

@MainActor
@Suite("MCP Status Service")
struct MCPStatusServiceTests {
    // MARK: Internal

    // MARK: - get_version

    @Test("Get version returns app info")
    func getVersion() {
        let service = makeService()
        let result = service.getVersion()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("app_version"))
        #expect(text.contains("build_number"))
        #expect(text.contains("mcp_protocol_version"))
        #expect(text.contains("app_name"))
        #expect(text.contains(MCPProtocolVersion.current))
    }

    @Test("Get version result is valid JSON")
    func getVersionValidJSON() throws {
        let service = makeService()
        let result = service.getVersion()

        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["mcp_protocol_version"] as? String == MCPProtocolVersion.current)
    }

    // MARK: - get_proxy_status

    @Test("Get proxy status with no provider attached")
    func proxyStatusNilProvider() async {
        let service = makeService()
        let result = await service.getProxyStatus()

        expectNoError(result)
        let json = try? decodeJSONObject(from: result)
        #expect(json?["is_running"] as? Bool == false)
        #expect(json?["has_provider"] as? Bool == false)
        #expect(json?["status_reason"] as? String == "Proxy window not active")
    }

    @Test("Get proxy status with active provider")
    func proxyStatusActive() async {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = true
        provider.activeProxyPort = 8_888
        provider.isRecording = true
        provider.isSystemProxyConfigured = true
        provider.transactionCount = 100

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"is_running\":true") || text.contains("\"is_running\": true"))
        #expect(text.contains("8888"))
        #expect(text.contains("\"is_recording\":true") || text.contains("\"is_recording\": true"))
        #expect(text.contains("\"is_system_proxy\":true") || text.contains("\"is_system_proxy\": true"))
        #expect(text.contains("100"))
    }

    @Test("Get proxy status reads MainContentCoordinator runtime state")
    func proxyStatusReadsMainContentCoordinator() async throws {
        let mainCoordinator = MainContentCoordinator()
        mainCoordinator.isProxyRunning = true
        mainCoordinator.activeProxyPort = 7_777
        mainCoordinator.isRecording = false
        mainCoordinator.isSystemProxyConfigured = true
        mainCoordinator.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/live/1"),
            TestFixtures.makeTransaction(url: "https://api.example.com/live/2"),
            TestFixtures.makeTransaction(url: "https://api.example.com/live/3"),
        ]

        let coordinator = MCPServerCoordinator()
        coordinator.attachProviders(flow: mainCoordinator, state: mainCoordinator)
        let service = MCPStatusService(serverCoordinator: coordinator)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["is_running"] as? Bool == true)
        #expect(json["port"] as? Int == 7_777)
        #expect(json["is_recording"] as? Bool == false)
        #expect(json["is_system_proxy"] as? Bool == true)
        #expect(json["transaction_count"] as? Int == 3)
    }

    @Test("Get proxy status with stopped proxy")
    func proxyStatusStopped() async {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = false
        provider.activeProxyPort = 0
        provider.isRecording = false
        provider.isSystemProxyConfigured = false
        provider.transactionCount = 0

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"is_running\":false") || text.contains("\"is_running\": false"))
        #expect(!text.contains("\"port\""))
    }

    @Test("Get proxy status result is valid JSON")
    func proxyStatusValidJSON() async throws {
        let provider = MockProxyStateProvider()
        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["is_running"] as? Bool == true)
        #expect(json?["transaction_count"] as? Int == 42)
    }

    @Test("Get proxy status port only included when running")
    func proxyStatusPortWhenRunning() async throws {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = true
        provider.activeProxyPort = 9_090

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["port"] as? Int == 9_090)
    }

    // MARK: - get_ssl_proxying_list

    @Test("Get SSL proxying list exposes legacy fields and application rule arrays")
    func sslProxyingListApplicationRules() async throws {
        let manager = SSLProxyingManager.shared
        // Snapshot and restore so persistent user rule state is unchanged by this test.
        let originalRules = manager.applicationRules
        defer { manager.replaceAllApplicationRules(originalRules) }

        let bundleIdentity = ClientApplicationIdentity.bundle(
            identifier: "com.example.MCPTestApp",
            displayName: "MCP Test App"
        )
        let executableIdentity = ClientApplicationIdentity.executable(
            normalizedPath: "/Applications/MCPTestTool.app/Contents/MacOS/MCPTestTool",
            displayName: "MCP Test Tool"
        )
        manager.replaceAllApplicationRules([
            ApplicationSSLProxyingRule(identity: bundleIdentity, listType: .include),
            ApplicationSSLProxyingRule(identity: executableIdentity, listType: .exclude),
        ])

        let service = makeService()
        let result = await service.getSSLProxyingList()

        expectNoError(result)
        let json = try decodeJSONObject(from: result)

        // Legacy fields remain present and unchanged in shape.
        #expect(json["is_enabled"] is Bool)
        #expect(json["include_rules"] is [Any])
        #expect(json["exclude_rules"] is [Any])
        #expect(json["bypass_domains"] is String)

        // New application-scoped arrays.
        let includeRules = try #require(json["application_include_rules"] as? [[String: Any]])
        let excludeRules = try #require(json["application_exclude_rules"] as? [[String: Any]])

        let bundleRule = try #require(includeRules
            .first { $0["application_identifier"] as? String == bundleIdentity.identifier })
        #expect(bundleRule["id"] is String)
        #expect(bundleRule["display_name"] as? String == "MCP Test App")
        #expect(bundleRule["is_enabled"] as? Bool == true)
        #expect(bundleRule["bundle_identifier"] as? String == "com.example.MCPTestApp")

        let executableRule = try #require(excludeRules
            .first { $0["application_identifier"] as? String == executableIdentity.identifier })
        // Executable-backed identities key on a sha256 digest, never a raw filesystem path.
        #expect((executableRule["application_identifier"] as? String)?.hasPrefix("exec:") == true)
        #expect(executableRule["is_enabled"] as? Bool == true)
        #expect(executableRule["bundle_identifier"] == nil)

        // No raw executable/machine path leaks anywhere in the serialized payload.
        let text = try #require(result.content.first?.text)
        #expect(!text.contains("/Applications/MCPTestTool.app"))
        #expect(!text.contains("/Contents/MacOS/"))
    }

    // MARK: Private

    private func makeService(stateProvider: MockProxyStateProvider? = nil) -> MCPStatusService {
        let coordinator = MCPServerCoordinator()
        if let stateProvider {
            coordinator.attachProviders(
                flow: MockFlowProvider(),
                state: stateProvider
            )
        }
        return MCPStatusService(serverCoordinator: coordinator)
    }

    private func expectNoError(_ result: MCPToolCallResult) {
        #expect(result.isError != true)
    }

    private func decodeJSONObject(from result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
