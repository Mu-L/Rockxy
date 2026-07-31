import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingListViewModelTests

@MainActor
struct SSLProxyingListViewModelTests {
    // MARK: Internal

    // MARK: - Initial State

    @Test("initial state has empty search and no selection")
    func initialState() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        #expect(vm.selectedRuleID == nil)
        #expect(vm.searchText.isEmpty)
        #expect(vm.showAddDomainSheet == false)
        #expect(vm.showAddAppSheet == false)
        #expect(vm.showBypassSheet == false)
        #expect(vm.editingRule == nil)
        #expect(vm.filteredRules.isEmpty)
    }

    // MARK: - Behavior Labels

    @Test("behaviorLabel maps list type to reader-facing text")
    func behaviorLabelMapping() {
        #expect(SSLProxyingListViewModel.behaviorLabel(for: .include) == String(localized: "Decrypt HTTPS"))
        #expect(
            SSLProxyingListViewModel.behaviorLabel(for: .exclude)
                == String(localized: "Tunnel Without Decryption")
        )
    }

    // MARK: - Unified Filtering

    @Test("filteredRules returns every rule regardless of behavior")
    func filteredRulesUnified() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "decrypt.com", listType: .include)
        vm.addRule(domain: "tunnel.com", listType: .exclude)

        #expect(vm.filteredRules.count == 2)
        let domains = Set(vm.filteredRules.map(\.domain))
        #expect(domains == ["decrypt.com", "tunnel.com"])
    }

    @Test("filteredRules filters by host pattern search")
    func filteredRulesSearchHost() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "api.example.com", listType: .include)
        vm.addRule(domain: "cdn.other.com", listType: .include)

        vm.searchText = "example"
        #expect(vm.filteredRules.count == 1)
        #expect(vm.filteredRules[0].domain == "api.example.com")
    }

    @Test("filteredRules filters by behavior label search")
    func filteredRulesSearchBehavior() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "a.com", listType: .include)
        vm.addRule(domain: "b.com", listType: .exclude)

        vm.searchText = "tunnel"
        #expect(vm.filteredRules.count == 1)
        #expect(vm.filteredRules[0].domain == "b.com")
    }

    // MARK: - Counts

    @Test("ruleCount, decryptCount, and tunnelCount reflect all rules")
    func counts() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "inc1.com", listType: .include)
        vm.addRule(domain: "inc2.com", listType: .include)
        vm.addRule(domain: "exc1.com", listType: .exclude)

        #expect(vm.ruleCount == 3)
        #expect(vm.decryptCount == 2)
        #expect(vm.tunnelCount == 1)
        #expect(vm.enabledDecryptCount == 2)
        #expect(vm.enabledTunnelCount == 1)

        vm.toggleRule(id: vm.manager.rules[0].id)
        #expect(vm.enabledDecryptCount == 1)
    }

    // MARK: - CRUD With Explicit Behavior

    @Test("addRule stores the requested behavior")
    func addRuleExplicitBehavior() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "decrypt.com", listType: .include)
        vm.addRule(domain: "tunnel.com", listType: .exclude)

        #expect(vm.manager.rules[0].listType == .include)
        #expect(vm.manager.rules[1].listType == .exclude)
        #expect(vm.selectedRuleID == vm.manager.rules[1].id)
    }

    @Test("addRule trims whitespace and rejects empty")
    func addRuleTrims() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "  ", listType: .include)
        #expect(vm.manager.rules.isEmpty)

        vm.addRule(domain: "  test.com  ", listType: .include)
        #expect(vm.manager.rules[0].domain == "test.com")
    }

    @Test("addRule skips duplicate domain within the same behavior case-insensitively")
    func addRuleSkipsDuplicate() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "example.com", listType: .include)
        vm.addRule(domain: "EXAMPLE.com", listType: .include)
        #expect(vm.manager.rules.count == 1)
    }

    @Test("addRule allows the same domain across behaviors")
    func addRuleAllowsCrossBehaviorDuplicate() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "example.com", listType: .include)
        vm.addRule(domain: "example.com", listType: .exclude)
        #expect(vm.manager.rules.count == 2)
    }

    @Test("updateRule changes host pattern and behavior while preserving id and enabled state")
    func updateRuleChangesHostAndBehavior() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "old.com", listType: .include)
        let original = vm.manager.rules[0]
        vm.toggleRule(id: original.id)
        #expect(vm.manager.rules[0].isEnabled == false)

        vm.updateRule(id: original.id, domain: "new.com", listType: .exclude)
        let updated = vm.manager.rules[0]
        #expect(updated.id == original.id)
        #expect(updated.domain == "new.com")
        #expect(updated.listType == .exclude)
        #expect(updated.isEnabled == false)
    }

    @Test("updateRule rejects whitespace-only input and preserves original")
    func updateRuleRejectsWhitespace() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "old.com", listType: .include)
        let id = vm.manager.rules[0].id
        vm.updateRule(id: id, domain: "  ", listType: .include)
        #expect(vm.manager.rules[0].domain == "old.com")
    }

    @Test("updateRule rejects same-behavior duplicate and preserves both originals")
    func updateRuleRejectsDuplicate() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["one.com", "two.com"], listType: .include)
        let firstID = vm.manager.rules[0].id

        let didUpdate = vm.updateRule(id: firstID, domain: "TWO.com", listType: .include)

        #expect(!didUpdate)
        #expect(vm.manager.rules.map(\.domain) == ["one.com", "two.com"])
    }

    @Test("updateRule allows the same host across opposite behaviors")
    func updateRuleAllowsOppositeBehaviorOverlap() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "one.com", listType: .include)
        vm.addRule(domain: "two.com", listType: .exclude)
        let excludeID = vm.manager.rules[1].id

        let didUpdate = vm.updateRule(id: excludeID, domain: "one.com", listType: .exclude)

        #expect(didUpdate)
        #expect(vm.manager.rules.count == 2)
        #expect(vm.manager.rules[1].domain == "one.com")
    }

    // MARK: - Batch Add

    @Test("addRules adds multiple domains, preserves order, and selects last")
    func addRulesBatch() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["a.com", "b.com", "c.com"], listType: .include)
        #expect(vm.manager.rules.count == 3)
        #expect(vm.manager.rules.map(\.domain) == ["a.com", "b.com", "c.com"])
        #expect(vm.selectedRuleID == vm.manager.rules.last?.id)
    }

    @Test("addRules trims and skips empty entries")
    func addRulesTrims() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["  a.com  ", "", "  ", "b.com"], listType: .include)
        #expect(vm.manager.rules.count == 2)
        #expect(vm.manager.rules[0].domain == "a.com")
        #expect(vm.manager.rules[1].domain == "b.com")
    }

    @Test("addRules skips duplicates within the batch and against existing rules")
    func addRulesSkipsDuplicates() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "a.com", listType: .include)
        vm.addRules(["A.com", "b.com", "b.com"], listType: .include)
        #expect(vm.manager.rules.count == 2)
        #expect(vm.manager.rules.map(\.domain) == ["a.com", "b.com"])
    }

    @Test("addRules uses the requested behavior")
    func addRulesBehavior() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["x.com"], listType: .exclude)
        #expect(vm.manager.rules[0].listType == .exclude)
    }

    // MARK: - Selection & Removal Fallback

    @Test("selectRule updates current selection")
    func selectRule() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["one.com", "two.com"], listType: .include)
        let firstID = vm.manager.rules[0].id
        vm.selectRule(id: firstID)
        #expect(vm.selectedRuleID == firstID)
    }

    @Test("removeSelected falls back to the adjacent rule at the same index")
    func removeSelectedFallbackAdjacent() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["a.com", "b.com", "c.com"], listType: .include)
        let middleID = vm.manager.rules[1].id
        let lastID = vm.manager.rules[2].id
        vm.selectedRuleID = middleID

        vm.removeSelected()
        // Index 1 was removed; the rule that now occupies index 1 (formerly "c.com").
        #expect(vm.selectedRuleID == lastID)
    }

    @Test("removeSelected falls back to previous when removing the last rule")
    func removeSelectedFallbackPrevious() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["a.com", "b.com"], listType: .include)
        let lastID = vm.manager.rules[1].id
        let firstID = vm.manager.rules[0].id
        vm.selectedRuleID = lastID

        vm.removeSelected()
        #expect(vm.selectedRuleID == firstID)
    }

    @Test("removeSelected clears selection when the only rule is removed")
    func removeSelectedClearsWhenEmpty() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "only.com", listType: .include)
        vm.selectedRuleID = vm.manager.rules[0].id
        vm.removeSelected()
        #expect(vm.manager.rules.isEmpty)
        #expect(vm.selectedRuleID == nil)
    }

    @Test("removeSelected does nothing without selection")
    func removeSelectedNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        vm.selectedRuleID = nil
        vm.removeSelected()
        #expect(vm.manager.rules.count == 1)
    }

    // MARK: - Toggle

    @Test("toggleRule toggles enabled state")
    func toggleRule() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        let id = vm.manager.rules[0].id
        #expect(vm.manager.rules[0].isEnabled == true)
        vm.toggleRule(id: id)
        #expect(vm.manager.rules[0].isEnabled == false)
    }

    // MARK: - Labels

    @Test("toggleLabel returns row-specific enable/disable text")
    func toggleLabelRowSpecific() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        let id = vm.manager.rules[0].id
        #expect(vm.toggleLabel(for: id) == String(localized: "Disable Rule"))
        vm.toggleRule(id: id)
        #expect(vm.toggleLabel(for: id) == String(localized: "Enable Rule"))
    }

    @Test("toggleLabel defaults for unknown id")
    func toggleLabelUnknown() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        #expect(vm.toggleLabel(for: UUID()) == String(localized: "Enable Rule"))
    }

    @Test("enableDisableLabel reflects the selection")
    func enableDisableLabelSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id
        #expect(vm.enableDisableLabel == String(localized: "Disable Rule"))
        vm.toggleRule(id: id)
        #expect(vm.enableDisableLabel == String(localized: "Enable Rule"))
    }

    @Test("enableDisableLabel defaults when no selection")
    func enableDisableLabelNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        #expect(vm.enableDisableLabel == String(localized: "Enable Rule"))
    }

    // MARK: - Selection Reconciliation

    @Test("reconcileSelectionAfterRulesChange clears removed selection")
    func reconcileClearsRemoved() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id
        vm.manager.removeRule(id: id)
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    @Test("reconcileSelectionAfterRulesChange keeps valid selection")
    func reconcileKeepsValid() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .include)
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == id)
    }

    @Test("reconcileSelectionAfterRulesChange clears selection hidden by search")
    func reconcileClearsSelectionHiddenBySearch() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "api.example.com", listType: .include)
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id

        vm.searchText = "nomatch"
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    // MARK: - Host Pattern Validation

    @Test("host pattern validation accepts matcher-compatible patterns")
    func hostPatternValidationAcceptsSupportedValues() {
        let validPatterns = [
            "*",
            "api.example.com",
            "*.example.com",
            "*.local",
            "localhost",
            "service_name.internal",
            "api.example.com.",
            "127.0.0.1",
            "::1",
            "2001:db8::1",
        ]

        for pattern in validPatterns {
            #expect(SSLHostPatternValidation.message(for: pattern) == nil, "Expected valid: \(pattern)")
        }
    }

    @Test("host pattern validation rejects values that cannot match a bare host")
    func hostPatternValidationRejectsUnsupportedValues() {
        let invalidPatterns = [
            ".",
            "foo..bar",
            "api@example.com",
            "https://example.com",
            "example.com/path",
            "example.com?query=1",
            "example.com:443",
            "[::1]",
            "foo*bar.com",
            "*.",
            String(repeating: "a", count: 256),
        ]

        for pattern in invalidPatterns {
            #expect(SSLHostPatternValidation.message(for: pattern) != nil, "Expected invalid: \(pattern)")
        }
    }

    // MARK: - Editor

    @Test("presentEditorForSelection loads the selected rule")
    func presentEditor() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com", listType: .exclude)
        vm.selectedRuleID = vm.manager.rules[0].id
        vm.presentEditorForSelection()
        #expect(vm.editingRule != nil)
        #expect(vm.editingRule?.domain == "test.com")
        #expect(vm.editingRule?.listType == .exclude)
        #expect(vm.showAddDomainSheet == true)
    }

    @Test("presentEditorForSelection does nothing without selection")
    func presentEditorNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.presentEditorForSelection()
        #expect(vm.editingRule == nil)
        #expect(vm.showAddDomainSheet == false)
    }

    // MARK: Private

    private func makeViewModel() -> (SSLProxyingListViewModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-vm-test-\(UUID().uuidString).json")
        let manager = SSLProxyingManager(storageURL: url)
        return (SSLProxyingListViewModel(manager: manager), url)
    }
}
