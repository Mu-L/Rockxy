import CoreGraphics
@testable import Rockxy
import Testing

/// Tests for the pure tab-distribution logic that keeps inspector tabs reachable in narrow panes.
/// Widths are synthetic point values so the assertions stay independent of font metrics.
struct InspectorTabOverflowPlannerTests {
    // MARK: Internal

    // MARK: - Tests

    @Test("All tabs fit: every tab is visible and no overflow menu is needed")
    func allFit() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: items([("a", 40), ("b", 40), ("c", 40)]),
            activeID: "a",
            availableWidth: 200,
            overflowAffordanceWidth: 30
        )

        #expect(plan.visibleIDs == ["a", "b", "c"])
        #expect(plan.overflowIDs.isEmpty)
        #expect(!plan.hasOverflow)
    }

    @Test("Overflow: leading tabs stay visible and the tail collapses into the menu")
    func overflowPushesTail() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: items([("a", 40), ("b", 40), ("c", 40), ("d", 40)]),
            activeID: "a",
            availableWidth: 120,
            overflowAffordanceWidth: 30
        )

        #expect(plan.hasOverflow)
        #expect(plan.visibleIDs == ["a", "b"])
        #expect(plan.overflowIDs == ["c", "d"])
    }

    @Test("Active tab is forced visible even when it sits at the end of the list")
    func activeForcedVisible() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: items([("a", 40), ("b", 40), ("c", 40), ("d", 40)]),
            activeID: "d",
            availableWidth: 110,
            overflowAffordanceWidth: 30
        )

        #expect(plan.visibleIDs.contains("d"))
        #expect(plan.visibleIDs == ["a", "d"])
        #expect(plan.overflowIDs == ["b", "c"])
    }

    @Test("Stable order: visible and overflow lists preserve source order without dropping tabs")
    func stableOrder() {
        let source = ["one", "two", "three", "four", "five"]
        let plan = InspectorTabOverflowPlanner.plan(
            items: items(source.map { ($0, 50) }),
            activeID: "three",
            availableWidth: 160,
            overflowAffordanceWidth: 40
        )

        let combined = plan.visibleIDs + plan.overflowIDs
        #expect(Set(combined) == Set(source))
        #expect(combined.count == source.count)
        #expect(plan.visibleIDs == source.filter { plan.visibleIDs.contains($0) })
        #expect(plan.overflowIDs == source.filter { plan.overflowIDs.contains($0) })
        #expect(plan.visibleIDs.contains("three"))
    }

    @Test("Extremely narrow width still keeps only the active tab visible")
    func extremelyNarrow() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: items([("a", 60), ("b", 60), ("c", 60)]),
            activeID: "b",
            availableWidth: 1,
            overflowAffordanceWidth: 30
        )

        #expect(plan.visibleIDs == ["b"])
        #expect(plan.overflowIDs == ["a", "c"])
        #expect(plan.hasOverflow)
    }

    @Test("Mixed-category identifiers distribute by width, not by id prefix")
    func mixedCategoryIDs() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: items([
                ("native.headers", 70),
                ("native.body", 60),
                ("preview.9F1C", 80),
                ("protocol.ai", 50),
                ("protocol.web3", 55),
            ]),
            activeID: "protocol.ai",
            availableWidth: 200,
            overflowAffordanceWidth: 36
        )

        #expect(plan.hasOverflow)
        #expect(plan.visibleIDs.contains("protocol.ai"))
        #expect(plan.visibleIDs == ["native.headers", "protocol.ai"])
        #expect(plan.overflowIDs == ["native.body", "preview.9F1C", "protocol.web3"])
    }

    @Test("Empty input yields an empty plan with no overflow")
    func emptyInput() {
        let plan = InspectorTabOverflowPlanner.plan(
            items: [],
            activeID: nil,
            availableWidth: 100,
            overflowAffordanceWidth: 30
        )

        #expect(plan.visibleIDs.isEmpty)
        #expect(plan.overflowIDs.isEmpty)
        #expect(!plan.hasOverflow)
    }

    // MARK: Private

    // MARK: - Helpers

    private func items(_ pairs: [(String, CGFloat)]) -> [InspectorTabLayoutItem] {
        pairs.map { InspectorTabLayoutItem(id: $0.0, width: $0.1) }
    }
}
