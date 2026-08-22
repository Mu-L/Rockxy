import Foundation
@testable import Rockxy
import Testing

// MARK: - PortableProjectTests

@Suite("PortableProject")
struct PortableProjectTests {
    // MARK: Internal

    // MARK: Round trip

    @Test("export then import preserves name and portable tab view intent")
    func roundTripsPortableIntent() throws {
        let project = Self.makeRichProject()

        let portable = PortableProject(exporting: project)
        let rebuilt = try portable.makeProject(now: Self.fixedDate, maxTabs: 8)

        // Structural invariants hold on the materialized Project.
        try rebuilt.validate()
        #expect(rebuilt.name == project.name)
        #expect(rebuilt.tabs.count == project.tabs.count)

        // The customized second tab's allowlisted intent survives the round trip.
        let source = project.tabs[1]
        let restored = rebuilt.tabs[1]
        #expect(restored.title == source.title)
        #expect(restored.filter == source.filter)
        #expect(restored.mainTabRawValue == source.mainTabRawValue)
        #expect(restored.inspectorLayoutRawValue == source.inspectorLayoutRawValue)
        #expect(restored.activeTrafficSignalRawValue == source.activeTrafficSignalRawValue)
        #expect(restored.mutedTrafficSources == source.mutedTrafficSources)
        #expect(restored.advancedFilterRows.map(\.value) == source.advancedFilterRows.map(\.value))
    }

    @Test("active tab is preserved by index, not by identifier")
    func preservesActiveTabByIndex() throws {
        let project = Self.makeRichProject() // active tab is index 1
        let portable = PortableProject(exporting: project)
        #expect(portable.activeTabIndex == 1)

        let rebuilt = try portable.makeProject(now: Self.fixedDate, maxTabs: 8)
        #expect(rebuilt.activeTabID == rebuilt.tabs[1].id)
    }

    // MARK: Default-deny / fresh identifiers

    @Test("import mints fresh tab UUIDs and drops focus-set references")
    func importRegeneratesIdentifiers() throws {
        let project = Self.makeRichProject()
        let portable = PortableProject(exporting: project)
        let rebuilt = try portable.makeProject(now: Self.fixedDate, maxTabs: 8)

        let originalTabIDs = Set(project.tabs.map(\.id))
        #expect(rebuilt.id != project.id)
        for tab in rebuilt.tabs {
            #expect(!originalTabIDs.contains(tab.id))
            #expect(tab.activeFocusSetID == nil)
        }
    }

    @Test("encoded document contains no project, tab, or focus-set identifiers")
    func encodedFormEncodesNoIdentifiers() throws {
        let focusID = UUID()
        let tabID = UUID()
        let defaultTab = ProjectTabSnapshot.makeDefaultAllTraffic()
        let customTab = ProjectTabSnapshot(
            id: tabID,
            title: "Errors",
            isClosable: true,
            filter: FilterCriteriaSnapshot(searchText: "secret", domains: ["internal.example.com"]),
            activeFocusSetID: focusID
        )
        let project = Project(
            id: UUID(),
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: tabID,
            tabs: [defaultTab, customTab]
        )

        let data = try PortableProjectDocument.encode(project)
        let json = try #require(String(bytes: data, encoding: .utf8))

        // No identifier of any kind should cross the machine boundary...
        #expect(!json.contains(project.id.uuidString))
        #expect(!json.contains(tabID.uuidString))
        #expect(!json.contains(defaultTab.id.uuidString))
        #expect(!json.contains(focusID.uuidString))
        #expect(!json.localizedCaseInsensitiveContains("activeFocusSetID"))
        // ...while genuine, allowlisted view intent is retained.
        #expect(json.contains("formatVersion"))
        #expect(json.contains("internal.example.com"))
    }

    // MARK: Validation / fail-closed

    @Test("rejects an unsupported format version")
    func rejectsUnsupportedFormatVersion() {
        let portable = PortableProject(
            formatVersion: 2,
            name: "Alpha",
            activeTabIndex: 0,
            tabs: [PortableProjectTab(title: "All Traffic", isClosable: false)]
        )
        #expect(throws: PortableProjectError.unsupportedFormatVersion(found: 2)) {
            try portable.validate()
        }
    }

    @Test("rejects an empty tab list")
    func rejectsEmptyTabList() {
        let portable = PortableProject(name: "Alpha", activeTabIndex: 0, tabs: [])
        #expect(throws: PortableProjectError.tabCountOutOfRange(count: 0)) {
            try portable.validate()
        }
    }

    @Test("rejects an out-of-range active tab index")
    func rejectsActiveTabIndexOutOfRange() {
        let portable = PortableProject(
            name: "Alpha",
            activeTabIndex: 5,
            tabs: [PortableProjectTab(title: "All Traffic", isClosable: false)]
        )
        #expect(throws: PortableProjectError.activeTabIndexOutOfRange(index: 5)) {
            try portable.validate()
        }
    }

    @Test("rejects an unnormalizable project name")
    func rejectsInvalidName() {
        let portable = PortableProject(
            name: "   ",
            activeTabIndex: 0,
            tabs: [PortableProjectTab(title: "All Traffic", isClosable: false)]
        )
        #expect(throws: PortableProjectError.nameInvalid(.empty)) {
            try portable.validate()
        }
    }

    @Test("rejects an oversized filter value inside a tab")
    func rejectsOversizedFilterValue() {
        let huge = String(repeating: "a", count: ProjectStructuralLimits.maxFilterStringGraphemes + 1)
        let tab = PortableProjectTab(
            title: "Errors",
            isClosable: true,
            advancedFilterRows: [PortableFilterRule(value: huge)]
        )
        let portable = PortableProject(name: "Alpha", activeTabIndex: 0, tabs: [tab])
        #expect(throws: PortableProjectError.self) {
            try portable.validate()
        }
    }

    @Test("materialization rejects an all-closable tab set that needs one slot for the default")
    func rejectsLossyDefaultInsertionAtCapacity() {
        let tabs = (0 ..< 8).map { index in
            PortableProjectTab(title: "Tab \(index)", isClosable: true)
        }
        let portable = PortableProject(name: "Alpha", activeTabIndex: 7, tabs: tabs)

        #expect(throws: PortableProjectError.tabCapacityExceededAfterDefaultInsertion(
            required: 9,
            limit: 8
        )) {
            _ = try portable.makeProject(now: Self.fixedDate, maxTabs: 8)
        }
    }

    // MARK: Private

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    /// A two-tab Project whose second tab is active and carries a full spread of
    /// allowlisted view intent (filter, layout, signal, mutes, focus reference).
    private static func makeRichProject() -> Project {
        let defaultTab = ProjectTabSnapshot.makeDefaultAllTraffic()
        let customTab = ProjectTabSnapshot(
            id: UUID(),
            title: "Errors",
            isClosable: true,
            filter: FilterCriteriaSnapshot(searchText: "500", methods: ["POST"], statusCodes: [500]),
            advancedFilterRows: [
                FilterRuleSnapshot(value: "example.com"),
                FilterRuleSnapshot(value: "token"),
            ],
            isFilterBarVisible: true,
            mainTabRawValue: MainTab.traffic.rawValue,
            inspectorLayoutRawValue: InspectorLayoutCoding.bottom,
            isContextDockVisible: true,
            contextDockTabRawValue: ContextDockTabCoding.details,
            focusNavigatorModeRawValue: FocusNavigatorMode.focus.rawValue,
            activeTrafficSignalRawValue: TrafficSignal.errors.rawValue,
            activeFocusSetID: UUID(),
            mutedTrafficSources: [
                MutedTrafficSourceSnapshot(kindRawValue: "host", value: "noise.example.com"),
            ]
        )
        return Project(
            id: UUID(),
            name: "Alpha",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            activeTabID: customTab.id,
            tabs: [defaultTab, customTab]
        )
    }
}
