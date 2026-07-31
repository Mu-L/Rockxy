import Foundation
@testable import Rockxy
import Testing

// MARK: - AdvancedProxySettingsDraftTests

@Suite("AdvancedProxySettingsDraft")
struct AdvancedProxySettingsDraftTests {
    @Test("Default draft mirrors Rockxy's shipped listener configuration")
    func defaultDraftMatchesShippedDefaults() {
        let draft = AdvancedProxySettingsDraft.default

        #expect(draft.portText == "9090")
        #expect(draft.parsedPort == 9_090)
        #expect(draft.autoSelectPort)
        #expect(draft.onlyListenOnLocalhost)
        #expect(draft.isPortValid)
        #expect(draft.canApply)
    }

    @Test("Draft round-trips through AppSettings listener fields")
    func draftRoundTripsThroughSettings() {
        var settings = AppSettings()
        settings.proxyPort = 8_888
        settings.autoSelectPort = false
        settings.onlyListenOnLocalhost = false

        let draft = AdvancedProxySettingsDraft(settings: settings)

        #expect(draft.portText == "8888")
        #expect(!draft.autoSelectPort)
        #expect(!draft.onlyListenOnLocalhost)
    }

    @Test("Invalid ports fail validation and block apply")
    func invalidPortsFailValidation() {
        let invalidInputs = ["", "0", "-1", "70000", "80a", "  ", "65536"]
        for input in invalidInputs {
            let draft = AdvancedProxySettingsDraft(portText: input)
            #expect(draft.parsedPort == nil, "\(input) should not parse")
            #expect(!draft.isPortValid, "\(input) should be invalid")
            #expect(!draft.canApply, "\(input) should block apply")
            #expect(
                draft.applied(to: AppSettings(), changedFrom: .default) == nil,
                "\(input) must not persist"
            )
        }
    }

    @Test("Boundary ports are accepted and whitespace is trimmed")
    func boundaryPortsAreValid() {
        #expect(AdvancedProxySettingsDraft(portText: "1").parsedPort == 1)
        #expect(AdvancedProxySettingsDraft(portText: "65535").parsedPort == 65_535)
        #expect(AdvancedProxySettingsDraft(portText: "  9091 ").parsedPort == 9_091)
    }

    @Test("Applying merges only fields the user changed and preserves unrelated settings")
    func applyMergesChangedFieldsOnly() throws {
        var base = AppSettings()
        base.proxyPort = 9_090
        base.autoSelectPort = true
        base.onlyListenOnLocalhost = true
        base.listenIPv6 = true
        base.recordOnLaunch = true
        base.mcpServerEnabled = true

        let baseline = AdvancedProxySettingsDraft(settings: base)
        var edited = baseline
        edited.portText = "9099"

        let updated = try #require(edited.applied(to: base, changedFrom: baseline))

        #expect(updated.proxyPort == 9_099)
        // Fields the user did not change stay as they were in `base`.
        #expect(updated.autoSelectPort)
        #expect(updated.onlyListenOnLocalhost)
        // IPv6 storage compatibility is never touched by the draft.
        #expect(updated.listenIPv6)
        // Unrelated settings are preserved verbatim.
        #expect(updated.recordOnLaunch)
        #expect(updated.mcpServerEnabled)
    }

    @Test("Apply does not overwrite a listener field changed elsewhere while the window was open")
    func applyDoesNotClobberExternalListenerChange() throws {
        // Baseline reflects what the window loaded.
        let baseline = AdvancedProxySettingsDraft(
            portText: "9090",
            autoSelectPort: true,
            onlyListenOnLocalhost: true
        )

        // The user only edits the port here.
        var edited = baseline
        edited.portText = "9099"

        // Meanwhile another surface changed localhost-only in persisted settings.
        var external = AppSettings()
        external.proxyPort = 9_090
        external.autoSelectPort = true
        external.onlyListenOnLocalhost = false

        let updated = try #require(edited.applied(to: external, changedFrom: baseline))

        // The user's port change applies...
        #expect(updated.proxyPort == 9_099)
        // ...but the externally-changed localhost setting is preserved, not reverted.
        #expect(!updated.onlyListenOnLocalhost)
    }

    @Test("Effective address follows the localhost toggle")
    func effectiveAddressFollowsLocalhostToggle() {
        let localhost = AdvancedProxySettingsDraft(onlyListenOnLocalhost: true)
        #expect(localhost.effectiveListenAddress == "127.0.0.1")

        let allInterfaces = AdvancedProxySettingsDraft(onlyListenOnLocalhost: false)
        #expect(allInterfaces.effectiveListenAddress == "0.0.0.0")
    }

    @Test("Equatable identity supports dirty/cancel comparisons")
    func equatableSupportsDirtyComparisons() {
        let saved = AdvancedProxySettingsDraft(settings: AppSettings())
        var edited = saved
        #expect(edited == saved)

        edited.portText = "9095"
        #expect(edited != saved)

        edited = saved
        #expect(edited == saved)
    }
}

// MARK: - ProxyListenerSnapshotTests

@Suite("ProxyListenerSnapshot")
struct ProxyListenerSnapshotTests {
    @Test("A fallback resolved port alone does not imply the saved settings changed")
    func fallbackPortDoesNotImplyRestart() {
        // Requested 9090 but bound 9091 because 9090 was occupied at launch.
        let snapshot = ProxyListenerSnapshot(
            requestedPort: 9_090,
            resolvedPort: 9_091,
            listenAddress: "127.0.0.1",
            autoSelectPort: true
        )

        #expect(snapshot.isUsingFallbackPort)
        // Saved preferred settings still match the requested startup parameters.
        #expect(snapshot.matchesRequestedListener(
            preferredPort: 9_090,
            autoSelectPort: true,
            listenAddress: "127.0.0.1"
        ))
    }

    @Test("A changed preferred port, address, or auto-select flags a restart")
    func changedRequestedParametersImplyRestart() {
        let snapshot = ProxyListenerSnapshot(
            requestedPort: 9_090,
            resolvedPort: 9_090,
            listenAddress: "127.0.0.1",
            autoSelectPort: true
        )

        #expect(!snapshot.isUsingFallbackPort)
        #expect(!snapshot.matchesRequestedListener(
            preferredPort: 9_099,
            autoSelectPort: true,
            listenAddress: "127.0.0.1"
        ))
        #expect(!snapshot.matchesRequestedListener(
            preferredPort: 9_090,
            autoSelectPort: false,
            listenAddress: "127.0.0.1"
        ))
        #expect(!snapshot.matchesRequestedListener(
            preferredPort: 9_090,
            autoSelectPort: true,
            listenAddress: "0.0.0.0"
        ))
    }
}
