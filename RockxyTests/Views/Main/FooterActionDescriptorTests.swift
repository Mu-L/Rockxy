import Foundation
@testable import Rockxy
import Testing

struct FooterActionDescriptorTests {
    @Test("Footer tooling action order is stable")
    func toolingActionOrder() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(actions.map(\.id) == [
            .breakpoint,
            .mapLocal,
            .scripting,
            .networkConditions,
        ])
    }

    @Test("Proxy override action appears after Network Conditions only when active")
    func proxyOverrideActionIsConditional() {
        let inactive = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: false
        )
        let active = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )

        #expect(!inactive.contains { $0.id == .proxyOverride })
        #expect(active.map(\.id) == [
            .breakpoint,
            .mapLocal,
            .scripting,
            .networkConditions,
            .proxyOverride,
        ])
    }

    @Test("Proxy override action metadata matches footer contract")
    func proxyOverrideActionMetadata() throws {
        let actions = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )
        let action = try #require(actions.first { $0.id == .proxyOverride })

        #expect(action.title == "Proxy Overridden")
        #expect(action.systemImage == "checkmark.circle.fill")
        #expect(action.help == "Show system proxy override details. Toggle by: ⌥⌘O")
        #expect(action.isActive)
        #expect(action.isEnabled)
    }

    @Test("Footer action IDs stay unique in normal and proxy override states")
    func footerActionIDsStayUnique() {
        for isProxyOverridden in [false, true] {
            let actions = FooterActionDescriptor.toolingActions(
                isAllowListActive: false,
                isProxyOverridden: isProxyOverridden
            )
            #expect(Set(actions.map(\.id)).count == actions.count)
        }
    }

    @Test("Footer actions use SF Symbol names")
    func actionSymbolsArePresent() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(actions.allSatisfy { !$0.systemImage.isEmpty })
        #expect(actions.first { $0.id == .mapLocal }?.systemImage == "folder.badge.gearshape")
        #expect(actions.first { $0.id == .scripting }?.systemImage == "curlybraces")
        #expect(actions.first { $0.id == .breakpoint }?.systemImage == "pause.circle")
        #expect(actions.first { $0.id == .networkConditions }?.systemImage == "speedometer")

        let activeActions = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )
        #expect(activeActions.first { $0.id == .proxyOverride }?.systemImage == "checkmark.circle.fill")
        #expect(activeActions.first { $0.id == .proxyOverride }?.help.contains("⌥⌘O") == true)
    }

    @Test("Allow List active state reflects manager state")
    func activeStates() {
        let tooling = FooterActionDescriptor.toolingActions(
            isAllowListActive: true,
            quickTools: [.allowList, .mapLocal, .scripting, .networkConditions]
        )

        #expect(tooling.first { $0.id == .allowList }?.isActive == true)
    }

    @Test("Footer tool actions render inline without overflow")
    func toolActionsRemainInline() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(FooterActionKind.defaultQuickTools == actions.map(\.id))
    }
}

// MARK: - FooterMutationIndicatorBuilderTests

struct FooterMutationIndicatorBuilderTests {
    // MARK: Internal

    @Test("Indicators are ordered Map Local, Map Remote, then Breakpoint")
    func indicatorOrder() {
        let rules = [
            makeRule(.breakpoint()),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.map(\.id) == [.mapLocal, .mapRemote, .breakpoint])
    }

    @Test("Indicator count reflects only enabled rules per category")
    func enabledRuleCounts() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapLocal(filePath: "/tmp/b.json")),
            makeRule(.mapLocal(filePath: "/tmp/c.json"), isEnabled: false),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint(), isEnabled: false),
            makeRule(.block(statusCode: 403)),
            makeRule(.throttle(delayMs: 50)),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.map(\.id) == [.mapLocal, .mapRemote])
        #expect(indicators.first { $0.id == .mapLocal }?.count == 2)
        #expect(indicators.first { $0.id == .mapRemote }?.count == 1)
    }

    @Test("A category is omitted when its tool-level switch is off")
    func toolSwitchGating() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint()),
        ]

        let withoutMapLocal = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: false,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(withoutMapLocal.map(\.id) == [.mapRemote, .breakpoint])

        let withoutBreakpoint = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: false
        )
        #expect(withoutBreakpoint.map(\.id) == [.mapLocal, .mapRemote])

        let allOff = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: false,
            mapRemoteToolEnabled: false,
            breakpointToolEnabled: false
        )
        #expect(allOff.isEmpty)
    }

    @Test("No indicators are produced when no enabled rules exist")
    func zeroStateOmission() {
        let emptyRules = FooterMutationIndicatorBuilder.indicators(
            rules: [],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(emptyRules.isEmpty)

        let onlyDisabled = FooterMutationIndicatorBuilder.indicators(
            rules: [
                makeRule(.mapLocal(filePath: "/tmp/a.json"), isEnabled: false),
                makeRule(.breakpoint(), isEnabled: false),
            ],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(onlyDisabled.isEmpty)
    }

    @Test("Indicators map to their existing tool-window IDs")
    func targetWindowIDs() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint()),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.first { $0.id == .mapLocal }?.windowID == "mapLocal")
        #expect(indicators.first { $0.id == .mapRemote }?.windowID == "mapRemote")
        #expect(indicators.first { $0.id == .breakpoint }?.windowID == "breakpointRules")
    }

    @Test("Indicators carry SF Symbols and accessible count copy")
    func indicatorMetadata() throws {
        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: [
                makeRule(.mapLocal(filePath: "/tmp/a.json")),
                makeRule(.mapLocal(filePath: "/tmp/b.json")),
            ],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        let mapLocal = try #require(indicators.first { $0.id == .mapLocal })
        #expect(mapLocal.systemImage == "folder.badge.gearshape")
        #expect(mapLocal.title == "Map Local")
        #expect(mapLocal.accessibilityLabel.contains("2"))
        #expect(indicators.allSatisfy { !$0.systemImage.isEmpty })
    }

    // MARK: Private

    private func makeRule(_ action: RuleAction, isEnabled: Bool = true) -> ProxyRule {
        ProxyRule(
            name: "test",
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: action
        )
    }
}

struct ProxyOverrideCommandActionsTests {
    @Test("system proxy override command is enabled only while proxy is running")
    @MainActor
    func toggleSystemProxyOverrideCommandAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        coordinator.isProxyRunning = false
        #expect(actions.canToggleSystemProxyOverride == false)

        coordinator.isProxyRunning = true
        #expect(actions.canToggleSystemProxyOverride)
    }

    @Test("OpenAPI export command requires eligible HTTP traffic")
    @MainActor
    func openAPIExportCommandAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        #expect(actions.canExportOpenAPI == false)

        coordinator.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users")
        ]

        #expect(actions.canExportOpenAPI)
    }

    @Test("main coordinator starts with proxy override indicator hidden")
    @MainActor
    func coordinatorStartsWithProxyOverrideHidden() {
        let coordinator = MainContentCoordinator()

        #expect(coordinator.isProxyOverridden == false)
        #expect(coordinator.isSystemProxyConfigured == false)
    }
}
