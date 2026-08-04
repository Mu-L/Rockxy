import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProtocolFilterSelection` — the pure menu selection/presentation helper.

// MARK: - ProtocolFilterSelectionTests

struct ProtocolFilterSelectionTests {
    // MARK: - Menu Group Partition & Order

    @Test("Menu groups partition every non-status filter exactly once")
    func groupsPartitionNonStatusFilters() {
        let grouped = ProtocolFilterSelection.transportFilters
            + ProtocolFilterSelection.protocolFilters
            + ProtocolFilterSelection.contentTypeFilters

        let expected = ProtocolFilter.allCases.filter { !$0.isStatusFilter }

        #expect(Set(grouped) == Set(expected))
        #expect(grouped.count == expected.count)
        #expect(Set(grouped).count == grouped.count)
    }

    @Test("Status group is exactly the five status ranges in ascending order")
    func statusGroupOrder() {
        #expect(ProtocolFilterSelection.statusFilters == [.status1xx, .status2xx, .status3xx, .status4xx, .status5xx])
    }

    @Test("Transport / protocol / content groups keep their required order")
    func groupOrdering() {
        #expect(ProtocolFilterSelection.transportFilters == [.all, .http, .https, .websocket])
        #expect(ProtocolFilterSelection.protocolFilters == [.ai, .aiSession, .web3RPC, .rpcError, .graphql, .grpc])
        #expect(ProtocolFilterSelection.contentTypeFilters == [
            .json, .xml, .js, .css, .document, .media, .form, .font, .other,
        ])
    }

    // MARK: - Inline Tiers

    @Test("Tier counts descend to a single fallback pill")
    func tierCountsShape() {
        let counts = ProtocolFilterSelection.inlinePillTiers.map(\.count)
        #expect(counts.last == 1)
        #expect(counts == counts.sorted(by: >))
        #expect(counts.allSatisfy { $0 >= 1 })
    }

    @Test("Each tier has stable unique pills, leads with .all, and practical tiers show status")
    func tierContents() {
        for tier in ProtocolFilterSelection.inlinePillTiers.indices {
            let visible = ProtocolFilterSelection.inlinePills(forTier: tier)
            #expect(visible.first == .all)
            #expect(Set(visible).count == visible.count)
            #expect(visible.allSatisfy { ProtocolFilter.allCases.contains($0) })
            if tier < ProtocolFilterSelection.inlinePillTiers.count - 1 {
                #expect(visible.contains { $0.isStatusFilter })
                #expect(visible.contains { $0 != .all && !$0.isStatusFilter })
            }
        }
        #expect(ProtocolFilterSelection.inlinePills(forTier: ProtocolFilterSelection.inlinePillTiers.count - 1)
            == [.all])
    }

    @Test("Tier index is clamped to the valid range")
    func tierClamping() {
        let last = ProtocolFilterSelection.inlinePillTiers.count - 1
        #expect(ProtocolFilterSelection.inlinePills(forTier: -5) == ProtocolFilterSelection.inlinePills(forTier: 0))
        #expect(ProtocolFilterSelection.inlinePills(forTier: 99) == ProtocolFilterSelection.inlinePills(forTier: last))
    }

    // MARK: - Overflow Partitioning

    @Test("Visible pills and overflow partition every non-.all filter with no overlap")
    func overflowPartition() {
        let sections = [
            ProtocolFilterSelection.transportFilters,
            ProtocolFilterSelection.protocolFilters,
            ProtocolFilterSelection.contentTypeFilters,
            ProtocolFilterSelection.statusFilters,
        ]
        let allSelectable = Set(ProtocolFilter.allCases.filter { $0 != .all })

        for tier in ProtocolFilterSelection.inlinePillTiers.indices {
            let visible = ProtocolFilterSelection.inlinePills(forTier: tier)
            let visibleReal = Set(visible.filter { $0 != .all })
            let overflow = sections.flatMap {
                ProtocolFilterSelection.overflowFilters(in: $0, visiblePills: visible)
            }

            #expect(!overflow.contains(.all))
            #expect(Set(overflow).count == overflow.count)
            #expect(visibleReal.isDisjoint(with: Set(overflow)))
            #expect(visibleReal.union(overflow) == allSelectable)
        }
    }

    @Test("Overflow of a section keeps stable order and drops visible members")
    func overflowSectionOrder() {
        let visible: [ProtocolFilter] = [.all, .http, .https]
        let transport = ProtocolFilterSelection.overflowFilters(
            in: ProtocolFilterSelection.transportFilters,
            visiblePills: visible
        )
        #expect(transport == [.websocket])

        let protocols = ProtocolFilterSelection.overflowFilters(
            in: ProtocolFilterSelection.protocolFilters,
            visiblePills: visible
        )
        #expect(protocols == ProtocolFilterSelection.protocolFilters)
    }

    // MARK: - Hidden Active Signal

    @Test("Hidden active signal fires only when an active filter is off-screen")
    func hiddenActiveSignal() {
        let visible: [ProtocolFilter] = [.all, .http, .https, .websocket]
        #expect(!ProtocolFilterSelection.hasHiddenActiveFilter(activeFilters: [], visiblePills: visible))
        #expect(!ProtocolFilterSelection.hasHiddenActiveFilter(activeFilters: [.https], visiblePills: visible))
        #expect(ProtocolFilterSelection.hasHiddenActiveFilter(activeFilters: [.json], visiblePills: visible))
        #expect(ProtocolFilterSelection.hasHiddenActiveFilter(
            activeFilters: [.https, .status4xx],
            visiblePills: visible
        ))
    }

    // MARK: - Selection State

    @Test("All Traffic is selected only when no traffic-type filter is active")
    func allTrafficSelectionState() {
        #expect(ProtocolFilterSelection.isSelected(.all, in: []))
        #expect(ProtocolFilterSelection.isSelected(.all, in: [.status2xx]))
        #expect(!ProtocolFilterSelection.isSelected(.all, in: [.json]))
        #expect(ProtocolFilterSelection.isSelected(.json, in: [.json]))
    }

    // MARK: - Toggling

    @Test("Toggling a type inserts then removes it and never stores .all")
    func toggleTypeMembership() {
        let inserted = ProtocolFilterSelection.toggling(.json, in: [])
        #expect(inserted == [.json])
        #expect(!inserted.contains(.all))

        let removed = ProtocolFilterSelection.toggling(.json, in: inserted)
        #expect(removed.isEmpty)
    }

    @Test("Toggling a status preserves active traffic types")
    func toggleStatusMembership() {
        let inserted = ProtocolFilterSelection.toggling(.status5xx, in: [.https, .json])
        #expect(inserted == [.https, .json, .status5xx])

        let removed = ProtocolFilterSelection.toggling(.status5xx, in: inserted)
        #expect(removed == [.https, .json])
    }

    @Test("Selecting All Traffic clears types but preserves status filters")
    func allTrafficPreservesStatuses() {
        let start: Set<ProtocolFilter> = [.json, .https, .status2xx, .status4xx]
        let result = ProtocolFilterSelection.toggling(.all, in: start)
        #expect(result == [.status2xx, .status4xx])
        #expect(!result.contains(.all))
    }

    @Test("Any Status clears status filters but preserves traffic-type filters")
    func anyStatusPreservesTypes() {
        let start: Set<ProtocolFilter> = [.json, .https, .status2xx, .status4xx]
        let result = ProtocolFilterSelection.clearingStatusFilters(in: start)
        #expect(result == [.json, .https])
        #expect(!result.contains(.all))
    }

    @Test("Clear All removes both traffic-type and status filters")
    func clearAllRemovesEveryFilter() {
        let start: Set<ProtocolFilter> = [.all, .https, .json, .status2xx, .status4xx]
        #expect(ProtocolFilterSelection.clearingAllFilters(in: start).isEmpty)
    }

    // MARK: - Active Group Extraction

    @Test("Active type and status filters exclude the opposite group and .all")
    func activeGroupExtraction() {
        let start: Set<ProtocolFilter> = [.all, .https, .json, .status5xx]
        #expect(ProtocolFilterSelection.activeTypeFilters(in: start) == [.https, .json])
        #expect(ProtocolFilterSelection.activeStatusFilters(in: start) == [.status5xx])
    }

    // MARK: - Summary Ordering

    @Test("Summary chips follow allCases order and exclude .all")
    func summaryOrdering() {
        let start: Set<ProtocolFilter> = [.status4xx, .json, .https, .all, .ai]
        #expect(ProtocolFilterSelection.summaryFilters(in: start) == [.https, .ai, .json, .status4xx])
        #expect(!ProtocolFilterSelection.summaryFilters(in: start).contains(.all))
    }

    // MARK: - Menu Labels

    @Test("Menu label renders All Traffic for .all and display names otherwise")
    func menuLabels() {
        #expect(ProtocolFilterSelection.menuLabel(for: .all) == "All Traffic")
        #expect(ProtocolFilterSelection.menuLabel(for: .https) == "HTTPS")
        #expect(ProtocolFilterSelection.menuLabel(for: .status3xx) == "3xx")
    }
}
