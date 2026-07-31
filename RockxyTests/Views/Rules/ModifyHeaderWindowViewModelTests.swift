import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct ModifyHeaderWindowViewModelTests {
    // MARK: Internal

    @Test("new editor operation defaults to Set so existing header values are replaced")
    func newOperationDefaultsToSet() {
        let operation = EditableHeaderOperation()

        #expect(operation.type == .replace)
        #expect(operation.type.editorLabel == "Set")
    }

    @Test("saveRule waits for persistence path and reloads saved Modify Header rule")
    func saveRulePersistsBeforeReturning() async {
        await withSharedRuleStateRestored {
            let viewModel = ModifyHeaderWindowViewModel()
            let operation = EditableHeaderOperation(
                type: .replace,
                headerName: "Authorization",
                headerValue: "Bearer demo-access-token"
            )

            let accepted = await viewModel.saveRule(
                existingRule: nil,
                ruleName: "Profile Auth",
                urlPattern: "127.0.0.1:43210/rockxy-demo/profile",
                httpMethod: .any,
                matchType: .wildcard,
                includeSubpaths: false,
                operations: [operation]
            )

            #expect(accepted)
            let loaded = await RuleEngine.shared.allRules.filter { rule in
                if case .modifyHeader = rule.action {
                    return true
                }
                return false
            }
            #expect(loaded.count == 1)
            #expect(viewModel.modifyHeaderRules.map(\.id) == loaded.map(\.id))

            guard let saved = loaded.first else {
                Issue.record("Expected saved Modify Header rule")
                return
            }
            #expect(saved.name == "Profile Auth")
            #expect(saved.matchCondition.method == nil)
            #expect(saved.matchCondition.urlPattern == #"127\.0\.0\.1:43210\/rockxy-demo\/profile($|[?#])"#)

            if case let .modifyHeader(operations) = saved.action {
                #expect(operations.count == 1)
                #expect(operations[0].type == .replace)
                #expect(operations[0].headerName == "Authorization")
                #expect(operations[0].headerValue == "Bearer demo-access-token")
                #expect(operations[0].phase == .request)
            } else {
                Issue.record("Expected Modify Header action")
            }
        }
    }

    @Test("applyingModifyHeaderOrder reorders only Modify Header slots, unrelated rules keep their indices")
    func applyingModifyHeaderOrderPreservesUnrelatedIndices() {
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        let mhA = Self.modifyHeaderRule(named: "A")
        let throttle = ProxyRule(
            name: "Throttle",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .throttle(delayMs: 100)
        )
        let mhB = Self.modifyHeaderRule(named: "B")
        let mapLocal = ProxyRule(
            name: "Map",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .mapLocal(filePath: "/tmp/x.json")
        )
        let mhC = Self.modifyHeaderRule(named: "C")
        let all = [block, mhA, throttle, mhB, mapLocal, mhC]

        let reordered = ModifyHeaderWindowViewModel.applyingModifyHeaderOrder([mhC, mhA, mhB], to: all)

        #expect(reordered.map(\.id) == [block.id, mhC.id, throttle.id, mhA.id, mapLocal.id, mhB.id])
        // Unrelated rules keep their exact global slots.
        #expect(reordered[0].id == block.id)
        #expect(reordered[2].id == throttle.id)
        #expect(reordered[4].id == mapLocal.id)
    }

    @Test("moveRules reorders Modify Header rules globally and persists, unrelated rules unchanged")
    func moveRulesPersistsInterleavedReorder() async {
        await withSharedRuleStateRestored {
            let block = ProxyRule(
                name: "Block",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .block(statusCode: 403)
            )
            let mhA = Self.modifyHeaderRule(named: "A")
            let throttle = ProxyRule(
                name: "Throttle",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .throttle(delayMs: 100)
            )
            let mhB = Self.modifyHeaderRule(named: "B")
            let mapLocal = ProxyRule(
                name: "Map",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .mapLocal(filePath: "/tmp/x.json")
            )
            let mhC = Self.modifyHeaderRule(named: "C")
            await RuleSyncService.replaceAllRules([block, mhA, throttle, mhB, mapLocal, mhC])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()
            #expect(viewModel.headerRules.map(\.id) == [mhA.id, mhB.id, mhC.id])

            viewModel.moveRules(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            await viewModel.waitForPendingRuleSync()

            let persisted = await RuleEngine.shared.allRules
            #expect(persisted.map(\.id) == [block.id, mhC.id, throttle.id, mhA.id, mapLocal.id, mhB.id])
        }
    }

    @Test("rapid reorder actions persist the latest visible order")
    func rapidReorderPersistsLatestOrder() async {
        await withSharedRuleStateRestored {
            let mhA = Self.modifyHeaderRule(named: "A")
            let mhB = Self.modifyHeaderRule(named: "B")
            let mhC = Self.modifyHeaderRule(named: "C")
            await RuleSyncService.replaceAllRules([mhA, mhB, mhC])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()
            viewModel.moveRules(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            viewModel.moveRules(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            await viewModel.waitForPendingRuleSync()

            let persisted = await RuleEngine.shared.allRules
            #expect(persisted.map(\.id) == [mhB.id, mhC.id, mhA.id])
        }
    }

    @Test("reorder followed by delete cannot restore the deleted rule")
    func reorderThenDeleteKeepsRuleDeleted() async {
        await withSharedRuleStateRestored {
            let block = ProxyRule(
                name: "Block",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .block(statusCode: 403)
            )
            let mhA = Self.modifyHeaderRule(named: "A")
            let throttle = ProxyRule(
                name: "Throttle",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .throttle(delayMs: 100)
            )
            let mhB = Self.modifyHeaderRule(named: "B")
            let mhC = Self.modifyHeaderRule(named: "C")
            await RuleSyncService.replaceAllRules([block, mhA, throttle, mhB, mhC])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()
            viewModel.moveRules(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            viewModel.removeRule(id: mhB.id)
            await viewModel.waitForPendingRuleSync()

            let persisted = await RuleEngine.shared.allRules
            #expect(persisted.map(\.id) == [block.id, mhC.id, throttle.id, mhA.id])
            #expect(!persisted.contains(where: { $0.id == mhB.id }))
        }
    }

    @Test("moveRules is a no-op while a search filter is active")
    func moveRulesNoOpWhileFiltering() async {
        await withSharedRuleStateRestored {
            let mhA = Self.modifyHeaderRule(named: "A")
            let mhB = Self.modifyHeaderRule(named: "B")
            await RuleSyncService.replaceAllRules([mhA, mhB])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()
            viewModel.searchText = "A"
            #expect(!viewModel.isReorderable)

            viewModel.moveRules(fromOffsets: IndexSet(integer: 1), toOffset: 0)
            await viewModel.waitForPendingRuleSync()

            let persisted = await RuleEngine.shared.allRules
            #expect(persisted.map(\.id) == [mhA.id, mhB.id])
        }
    }

    @Test("activeRuleCount and search filter reflect current rules")
    func activeCountAndFilter() async {
        await withSharedRuleStateRestored {
            var mhA = Self.modifyHeaderRule(named: "Alpha")
            mhA.isEnabled = true
            var mhB = Self.modifyHeaderRule(named: "Beta")
            mhB.isEnabled = false
            await RuleSyncService.replaceAllRules([mhA, mhB])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()

            #expect(viewModel.ruleCount == 2)
            #expect(viewModel.activeRuleCount == 1)

            viewModel.searchText = "Alpha"
            #expect(viewModel.modifyHeaderRules.map(\.id) == [mhA.id])
        }
    }

    @Test("search clears a selection that is no longer visible")
    func searchClearsHiddenSelection() async {
        await withSharedRuleStateRestored {
            let mhA = Self.modifyHeaderRule(named: "Alpha")
            let mhB = Self.modifyHeaderRule(named: "Beta")
            await RuleSyncService.replaceAllRules([mhA, mhB])

            let viewModel = ModifyHeaderWindowViewModel()
            await viewModel.refreshFromEngine()
            viewModel.selectedRuleID = mhB.id
            viewModel.searchText = "Alpha"

            #expect(viewModel.modifyHeaderRules.map(\.id) == [mhA.id])
            #expect(viewModel.selectedRuleID == nil)
        }
    }

    @Test("rapid tool gate changes persist the latest checkbox state")
    func rapidToolGateChangesPersistLatestState() async {
        await withSharedRuleStateRestored {
            let key = "modifyHeaderToolEnabled"
            let storedValue = UserDefaults.standard.object(forKey: key) as? Bool
            let viewModel = ModifyHeaderWindowViewModel(isToolEnabled: true)

            viewModel.setToolEnabled(false)
            viewModel.setToolEnabled(true)
            await viewModel.waitForPendingRuleSync()

            #expect(viewModel.isToolEnabled)
            #expect(UserDefaults.standard.object(forKey: key) as? Bool == true)

            if let storedValue {
                UserDefaults.standard.set(storedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            await RuleEngine.shared.setModifyHeaderToolEnabled(storedValue ?? true)
        }
    }

    // MARK: Private

    private static func modifyHeaderRule(named name: String) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .modifyHeader(operations: [
                HeaderOperation(type: .add, headerName: "X-\(name)", headerValue: "1"),
            ])
        )
    }

    private func withSharedRuleStateRestored(_ body: () async -> Void) async {
        await RuleTestLock.shared.acquire()
        let rulesSnapshot = await RuleEngine.shared.allRules
        let gateSnapshot = RulePolicyGate.shared

        RulePolicyGate.shared = RulePolicyGate(policy: DefaultAppPolicy())
        await RuleSyncService.replaceAllRules([])
        await body()

        await RuleSyncService.replaceAllRules(rulesSnapshot)
        RulePolicyGate.shared = gateSnapshot
        await RuleTestLock.shared.release()
    }
}
