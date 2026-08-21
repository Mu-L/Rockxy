import Foundation
@testable import Rockxy
import Testing

struct TrafficCommandDescriptorTests {
    @Test("Clear Session descriptor exposes ⌘K and never toggles")
    func clearSessionContract() {
        let descriptor = TrafficCommandDescriptor.clearSession(isEnabled: false)

        #expect(descriptor.id == .clearSession)
        #expect(descriptor.title == "Clear Session")
        #expect(descriptor.systemImage == "trash")
        #expect(descriptor.help.contains("⌘K"))
        #expect(descriptor.help.localizedCaseInsensitiveContains("all tabs"))
        #expect(descriptor.isActive == false)
        #expect(!descriptor.isEnabled)
    }

    @Test("Clear availability follows global session content, never active filters")
    func clearSessionAvailability() {
        #expect(!TrafficCommandAvailability.canClearSession(
            transactionCount: 0,
            logCount: 0,
            hasSessionProvenance: false,
            isClearingSession: false
        ))
        #expect(TrafficCommandAvailability.canClearSession(
            transactionCount: 1,
            logCount: 0,
            hasSessionProvenance: false,
            isClearingSession: false
        ))
        #expect(TrafficCommandAvailability.canClearSession(
            transactionCount: 0,
            logCount: 1,
            hasSessionProvenance: false,
            isClearingSession: false
        ))
        #expect(TrafficCommandAvailability.canClearSession(
            transactionCount: 0,
            logCount: 0,
            hasSessionProvenance: true,
            isClearingSession: false
        ))
        #expect(!TrafficCommandAvailability.canClearSession(
            transactionCount: 1,
            logCount: 1,
            hasSessionProvenance: true,
            isClearingSession: true
        ))
    }

    @Test("Follow Live descriptor reflects the per-workspace live-tail state")
    func followLiveActiveState() {
        let off = TrafficCommandDescriptor.followLive(isActive: false)
        let on = TrafficCommandDescriptor.followLive(isActive: true)

        #expect(off.id == .followLive)
        #expect(off.systemImage == "dot.radiowaves.right")
        #expect(off.isActive == false)

        #expect(on.isActive)
        #expect(on.isEnabled)
        #expect(on.help != off.help)
    }

    @Test("Both Follow Live states surface the ⇧⌘L shortcut")
    func followLiveShortcutHint() {
        for isActive in [false, true] {
            #expect(TrafficCommandDescriptor.followLive(isActive: isActive).help.contains("⇧⌘L"))
        }
    }

    @Test("Jump to Last Request reuses the View command without owning a second shortcut")
    func jumpToLastRequestContract() {
        let descriptor = TrafficCommandDescriptor.jumpToLastRequest(isEnabled: false)

        #expect(descriptor.id == .jumpToLastRequest)
        #expect(descriptor.title == "Jump to Last Request")
        #expect(descriptor.systemImage == "arrow.down.to.line")
        #expect(descriptor.help.contains("⌘↓"))
        #expect(descriptor.help.localizedCaseInsensitiveContains("without changing Follow Live"))
        #expect(!descriptor.isEnabled)
    }

    @Test("Recording stays an overflow action with explicit stopped, recording, and paused states")
    func recordingOverflowContract() {
        let stopped = TrafficRecordingCommandPresentation.make(isProxyRunning: false, isRecording: true)
        let recording = TrafficRecordingCommandPresentation.make(isProxyRunning: true, isRecording: true)
        let paused = TrafficRecordingCommandPresentation.make(isProxyRunning: true, isRecording: false)

        #expect(!stopped.isEnabled)
        #expect(recording.title == "Pause Recording")
        #expect(recording.systemImage == "pause.fill")
        #expect(paused.title == "Resume Recording")
        #expect(paused.systemImage == "record.circle")
        #expect([stopped, recording, paused].allSatisfy { $0.help.contains("⌘P") })
    }

    @Test("Request actions expose distinct local state without inventing shortcuts")
    func requestActionContracts() {
        let copy = TrafficCommandDescriptor.copyAsCURL(isEnabled: true)
        let pin = TrafficCommandDescriptor.togglePin(isPinned: true, isEnabled: true)
        let save = TrafficCommandDescriptor.toggleSave(isSaved: true, isEnabled: true)

        #expect(copy.systemImage == "terminal")
        #expect(copy.help.contains("⇧⌘C"))
        #expect(pin.title == "Unpin Request")
        #expect(pin.systemImage == "pin.fill")
        #expect(pin.isActive)
        #expect(save.title == "Unsave Request")
        #expect(save.systemImage == "tray.full.fill")
        #expect(save.isActive)
    }

    @Test("Command strip action families complement filtering and footer tool launchers")
    func ownershipMatrix() {
        let descriptors = [
            TrafficCommandDescriptor.clearSession(),
            TrafficCommandDescriptor.jumpToFirstRequest(isEnabled: true),
            TrafficCommandDescriptor.followLive(isActive: false),
            TrafficCommandDescriptor.jumpToLastRequest(isEnabled: true),
            TrafficCommandDescriptor.copyAsCURL(isEnabled: true),
            TrafficCommandDescriptor.togglePin(isPinned: false, isEnabled: true),
            TrafficCommandDescriptor.toggleSave(isSaved: false, isEnabled: true),
        ]

        #expect(descriptors.map(\.id) == TrafficCommandKind.allCases)
        #expect(descriptors.allSatisfy { !$0.systemImage.isEmpty })
        // Search and protocol filtering keep their own rows; the command strip never masquerades
        // as a second filter surface.
        #expect(descriptors.allSatisfy { !$0.help.localizedCaseInsensitiveContains("filter") })
    }

    @Test("Single-request actions fail closed for no selection and multi-selection")
    func singleRequestAvailability() {
        #expect(!TrafficCommandAvailability.canActOnSingleRequest(
            hasPrimarySelection: false,
            selectionCount: 0
        ))
        #expect(TrafficCommandAvailability.canActOnSingleRequest(
            hasPrimarySelection: true,
            selectionCount: 1
        ))
        #expect(!TrafficCommandAvailability.canActOnSingleRequest(
            hasPrimarySelection: true,
            selectionCount: 2
        ))
    }

    @Test("Protocol-sensitive request bridges reject WebSocket and CONNECT source rows")
    func ruleAndReplayAvailability() {
        #expect(TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: 1,
            isWebSocket: false,
            method: "GET"
        ))
        #expect(!TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: 1,
            isWebSocket: true,
            method: "GET"
        ))
        #expect(!TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: 1,
            isWebSocket: false,
            method: "connect"
        ))
        #expect(!TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: 2,
            isWebSocket: false,
            method: "GET"
        ))
    }

    @Test("Footer cannot regain Clear Session or Follow Live ownership")
    func footerOwnershipIsolation() {
        let footerActionIDs = Set(FooterActionKind.allCases.map(\.rawValue))

        #expect(footerActionIDs.isDisjoint(with: ["clearSession", "followLive"]))
    }

    @Test("Command-bar quick tools default to Block List, Allow List, Map Remote")
    func commandBarQuickToolDefaults() {
        #expect(QuickToolsLayout.default.commandBar == [.blockList, .allowList, .mapRemote])
    }

    @Test("Shared quick-tools layout never claims Clear Session or Follow Live ownership")
    func quickToolsIsolationFromSessionAndLive() {
        let layout = QuickToolsLayout.default
        let toolIDs = Set((layout.commandBar + layout.footer).map(\.rawValue))

        #expect(toolIDs.isDisjoint(with: ["clearSession", "followLive"]))
        // Recording stays in the overflow menu — it is not a quick tool.
        #expect(!toolIDs.contains("proxyOverride"))
    }

    @Test("One-shot jump selects the newest visible request without changing Follow Live")
    @MainActor
    func jumpDoesNotChangeFollowLive() {
        let coordinator = MainContentCoordinator()
        let hidden = TestFixtures.makeTransaction(url: "https://hidden.example.com/first")
        let visible = TestFixtures.makeTransaction(url: "https://visible.example.com/latest")
        coordinator.transactions = [hidden, visible]
        coordinator.filterCriteria.sidebarDomain = "visible.example.com"
        coordinator.recomputeFilteredTransactions()

        coordinator.selectLastFilteredTransaction()

        #expect(coordinator.selectedTransaction?.id == visible.id)
        #expect(!coordinator.isFollowingLiveTraffic)

        coordinator.setFollowingLiveTraffic(true)
        coordinator.selectLastFilteredTransaction()

        #expect(coordinator.selectedTransaction?.id == visible.id)
        #expect(coordinator.isFollowingLiveTraffic)
    }
}
