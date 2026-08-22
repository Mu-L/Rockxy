@testable import Rockxy
import Testing

// MARK: - AppPolicyTests

struct AppPolicyTests {
    @Test("DefaultAppPolicy has expected baseline values")
    func defaultValues() {
        let policy = DefaultAppPolicy()
        #expect(policy.maxWorkspaceTabs == 8)
        #expect(policy.maxProjects == 3)
        #expect(policy.maxDomainFavorites == 5)
        #expect(policy.maxActiveRulesPerTool == 10)
        #expect(policy.maxEnabledScripts == 10)
        #expect(policy.maxLiveHistoryEntries == 1_000)
        #expect(policy.upstreamProxyAllowsSOCKS5 == false)
        #expect(policy.upstreamProxyAllowsAuthentication == false)
        #expect(policy.maxUpstreamProxyBypassEntries == 3)
        #expect(policy.protobufDecodingAllowsSchemaUpload == false)
        #expect(policy.maxProtobufSchemas == 0)
    }

    @Test("MainContentCoordinator uses DefaultAppPolicy by default")
    @MainActor
    func coordinatorDefaultPolicy() {
        let coordinator = MainContentCoordinator()
        #expect(coordinator.policy.maxWorkspaceTabs == 8)
        #expect(coordinator.policy.maxDomainFavorites == 5)
    }

    @Test("MainContentCoordinator accepts custom policy")
    @MainActor
    func coordinatorCustomPolicy() {
        let custom = TestPolicy(maxWorkspaceTabs: 3, maxDomainFavorites: 2)
        let coordinator = MainContentCoordinator(policy: custom)
        #expect(coordinator.policy.maxWorkspaceTabs == 3)
        #expect(coordinator.policy.maxDomainFavorites == 2)
    }

    @Test("maxProjects falls back to the public default via the protocol extension")
    func maxProjectsExtensionDefault() {
        // TestPolicy does not set maxProjects, so it resolves through the default.
        #expect(TestPolicy().maxProjects == ProjectStructuralLimits.defaultProjectCapacity)
        #expect(TestPolicy().maxProjects == 3)
    }
}

// MARK: - TestPolicy

private struct TestPolicy: AppPolicy {
    var maxWorkspaceTabs = 8
    var maxDomainFavorites = 5
    var maxActiveRulesPerTool = 10
    var maxEnabledScripts = 10
    var maxLiveHistoryEntries = 1_000
}
