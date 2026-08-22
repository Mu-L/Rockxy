import Foundation
@testable import Rockxy
import Testing

// MARK: - ProjectTabSnapshotTests

@MainActor
@Suite("ProjectTabSnapshot")
struct ProjectTabSnapshotTests {
    // MARK: Capture / roundtrip

    @Test("captures durable view intent from a workspace")
    func capturesDurableIntent() {
        let workspace = WorkspaceState(title: "Payments", isClosable: true)
        var filter = FilterCriteria()
        filter.searchText = "checkout"
        filter.methods = ["GET", "POST"]
        filter.statusCodes = [200, 404]
        workspace.filterCriteria = filter
        workspace.isFilterBarVisible = true
        workspace.activeMainTab = .logs
        workspace.inspectorLayout = .bottom
        workspace.isContextDockVisible = true
        workspace.contextDockTab = .aiAssistant
        workspace.focusNavigatorMode = .focus
        workspace.activeTrafficSignal = .errors
        let focusSetID = UUID()
        workspace.activeFocusSetID = focusSetID
        workspace.mutedTrafficSources = [.host("ads.example.com"), .pathPrefix("/telemetry")]

        let snapshot = ProjectTabSnapshot(capturing: workspace)

        #expect(snapshot.id == workspace.id)
        #expect(snapshot.title == "Payments")
        #expect(snapshot.isClosable)
        #expect(snapshot.filter.searchText == "checkout")
        #expect(Set(snapshot.filter.methods) == ["GET", "POST"])
        #expect(Set(snapshot.filter.statusCodes) == [200, 404])
        #expect(snapshot.isFilterBarVisible)
        #expect(snapshot.mainTabRawValue == MainTab.logs.rawValue)
        #expect(snapshot.inspectorLayoutRawValue == InspectorLayoutCoding.bottom)
        #expect(snapshot.isContextDockVisible)
        #expect(snapshot.contextDockTabRawValue == ContextDockTabCoding.aiAssistant)
        #expect(snapshot.focusNavigatorModeRawValue == FocusNavigatorMode.focus.rawValue)
        #expect(snapshot.activeTrafficSignalRawValue == TrafficSignal.errors.rawValue)
        #expect(snapshot.activeFocusSetID == focusSetID)
        #expect(snapshot.mutedTrafficSources.count == 2)
    }

    @Test("roundtrips durable intent through hydrate")
    func roundtripsThroughHydrate() {
        let workspace = WorkspaceState(title: "Payments", isClosable: true)
        workspace.activeMainTab = .timeline
        workspace.inspectorLayout = .bottom
        workspace.contextDockTab = .aiAssistant
        workspace.focusNavigatorMode = .library
        workspace.activeTrafficSignal = .slow
        let focusSetID = UUID()
        workspace.activeFocusSetID = focusSetID
        workspace.mutedTrafficSources = [.host("ads.example.com")]
        workspace.isFilterBarVisible = true

        let snapshot = ProjectTabSnapshot(capturing: workspace)
        let hydrated = snapshot.hydrateWorkspaceState()
        let recaptured = ProjectTabSnapshot(capturing: hydrated)

        #expect(hydrated.id == workspace.id)
        #expect(hydrated.title == "Payments")
        #expect(hydrated.isClosable)
        #expect(hydrated.activeMainTab == .timeline)
        #expect(hydrated.inspectorLayout == .bottom)
        #expect(hydrated.contextDockTab == .aiAssistant)
        #expect(hydrated.focusNavigatorMode == .library)
        #expect(hydrated.activeTrafficSignal == .slow)
        #expect(hydrated.activeFocusSetID == focusSetID)
        #expect(hydrated.mutedTrafficSources == [.host("ads.example.com")])
        #expect(hydrated.isFilterBarVisible)
        #expect(recaptured == snapshot)
    }

    // MARK: Exclusions

    @Test("excludes the transient exact-transaction filter reference")
    func excludesExactTransactionID() {
        let workspace = WorkspaceState()
        var filter = FilterCriteria()
        filter.exactTransactionID = UUID()
        workspace.filterCriteria = filter

        let snapshot = ProjectTabSnapshot(capturing: workspace)
        #expect(snapshot.filter.resolved.exactTransactionID == nil)
    }

    @Test("encoded snapshot omits live/sensitive workspace state")
    func encodedSnapshotOmitsLiveState() throws {
        let workspace = WorkspaceState(title: "Payments", isClosable: false)
        workspace.publishTrafficRevealRequest(for: UUID())
        workspace.isFollowingLiveTraffic = true
        let snapshot = ProjectTabSnapshot(capturing: workspace)
        let hydrated = snapshot.hydrateWorkspaceState()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try #require(String(data: try encoder.encode(snapshot), encoding: .utf8))

        for forbidden in [
            "debugAssistant",
            "selectedTransaction",
            "filteredTransactions",
            "filteredRows",
            "sortDescriptor",
            "domainTree",
            "appNodes",
            "trafficSelectionIndex",
            "trafficRevealRequest",
            "isFollowingLiveTraffic",
        ] {
            #expect(!json.contains(forbidden), "snapshot leaked \(forbidden)")
        }

        #expect(hydrated.trafficRevealRequest == nil)
        #expect(!hydrated.isFollowingLiveTraffic)
    }

    // MARK: Resilience

    @Test("resolves unknown raw enum values to safe defaults")
    func resolvesUnknownRawValues() throws {
        let snapshot = ProjectTabSnapshot(
            title: "Legacy",
            isClosable: true,
            filter: FilterCriteriaSnapshot(searchFieldRawValue: "future_field"),
            mainTabRawValue: "future_tab",
            inspectorLayoutRawValue: "future_layout",
            contextDockTabRawValue: "future_dock",
            focusNavigatorModeRawValue: "future_mode",
            activeTrafficSignalRawValue: "future_signal"
        )

        // Survives a JSON round-trip without throwing.
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProjectTabSnapshot.self, from: data)
        let hydrated = decoded.hydrateWorkspaceState()

        #expect(hydrated.activeMainTab == .traffic)
        #expect(hydrated.inspectorLayout == .hidden)
        #expect(hydrated.contextDockTab == .details)
        #expect(hydrated.focusNavigatorMode == .browse)
        #expect(hydrated.activeTrafficSignal == nil)
        #expect(hydrated.filterCriteria.searchField == .url)
    }

    // MARK: Bounds

    @Test("bounds filter strings and collections on capture")
    func boundsFilterStringsAndCollections() {
        let workspace = WorkspaceState()
        var filter = FilterCriteria()
        filter.searchText = String(repeating: "x", count: 600)
        filter.methods = Set((0 ..< 200).map { "M\($0)" })
        workspace.filterCriteria = filter
        workspace.mutedTrafficSources = Set((0 ..< 200).map { MutedTrafficSource.host("h\($0).example.com") })

        let snapshot = ProjectTabSnapshot(capturing: workspace)
        #expect(snapshot.filter.searchText.count == ProjectStructuralLimits.maxFilterStringGraphemes)
        #expect(snapshot.filter.methods.count <= ProjectStructuralLimits.maxFilterCollectionCount)
        #expect(snapshot.mutedTrafficSources.count <= ProjectStructuralLimits.maxMutedTrafficSources)
    }

    @Test("validate rejects an oversized decoded filter string")
    func validateRejectsOversizedString() {
        let oversized = String(repeating: "y", count: ProjectStructuralLimits.maxFilterStringGraphemes + 1)
        let snapshot = ProjectTabSnapshot(
            title: "Legacy",
            isClosable: false,
            filter: FilterCriteriaSnapshot(searchText: oversized)
        )
        #expect(throws: ProjectSnapshotValidationError.self) {
            try snapshot.validate()
        }
    }
}
