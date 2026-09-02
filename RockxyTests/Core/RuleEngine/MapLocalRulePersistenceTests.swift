import Foundation
@testable import Rockxy
import Testing

// Regression tests for Map Local rule persistence (issue #307). These exercise the
// REAL production save/load path (`RuleSyncService` + `RuleStore`) through the
// injectable `RuleSyncService.store` seam pointed at a temp directory (not a copied
// testable store) so a genuine relaunch, save failure, and decode failure are covered.

@Suite(.serialized)
struct MapLocalRulePersistenceTests {
    // MARK: Internal

    @Test("Map Local rules survive save → process reset → load with every field intact")
    func roundTripPreservesAllVariants() async throws {
        let saved = [Self.fileRule(), Self.directoryRule(), Self.fullResponseRule()]
        let store = RuleStore(fileURL: Self.tempFileURL)
        try? FileManager.default.removeItem(at: Self.tempFileURL)
        defer { try? FileManager.default.removeItem(at: Self.tempFileURL) }

        try store.saveRules(saved)

        // A fresh engine models the next process without sharing mutable singleton
        // state with the repository's many rule tests that execute in parallel.
        let relaunchedEngine = RuleEngine()
        try await relaunchedEngine.loadRules(from: store)
        let loaded = await relaunchedEngine.allRules

        #expect(loaded.count == 3)
        #expect(loaded.map(\.id) == saved.map(\.id))
        for (actual, expected) in zip(loaded, saved) {
            Self.expectEqualRule(actual, expected)
        }
    }

    @Test("Mixed rule categories keep their global slots and order across a reload")
    @MainActor
    func mixedCategoriesRetainOrder() async {
        await withRuleHarness {
            let block = ProxyRule(
                name: "Block Ads",
                matchCondition: RuleMatchCondition(urlPattern: ".*ads\\.example\\.com.*"),
                action: .block(statusCode: 403)
            )
            let modify = ProxyRule(
                name: "Inject Header",
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
                action: .modifyHeader(operations: [
                    HeaderOperation(type: .add, headerName: "X-Debug", headerValue: "1"),
                ])
            )
            let saved = [Self.fileRule(), block, Self.directoryRule(), modify]

            await RuleSyncService.replaceAllRules(saved)
            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()
            #expect(await RuleSyncService.ensureLoaded() == .loaded)

            let loaded = await RuleEngine.shared.allRules
            #expect(loaded.map(\.id) == saved.map(\.id))
            #expect(loaded.map(\.action.toolCategory) == saved.map(\.action.toolCategory))
        }
    }

    @Test("A successful load publishes rules without rewriting the source file")
    @MainActor
    func successfulLoadDoesNotRewriteFile() async {
        await withRuleHarness {
            // Hand-write a pretty-printed (but valid) rules file; a rewrite would
            // re-encode compactly and change the bytes.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let prettyData = try? encoder.encode([Self.fileRule()]) else {
                Issue.record("Expected to encode rules fixture")
                return
            }
            try? prettyData.write(to: Self.tempFileURL, options: .atomic)

            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()
            #expect(await RuleSyncService.ensureLoaded() == .loaded)

            let afterLoad = try? Data(contentsOf: Self.tempFileURL)
            #expect(afterLoad == prettyData)
            #expect(await RuleEngine.shared.allRules.count == 1)
        }
    }

    @Test("A save failure is reported and never masquerades as a durable save")
    @MainActor
    func saveFailureIsVisible() async {
        await withRuleHarness {
            var failureMessage: String?
            let token = NotificationCenter.default.addObserver(
                forName: .rulePersistenceDidFail, object: nil, queue: nil
            ) { note in
                failureMessage = note.object as? String
            }
            defer { NotificationCenter.default.removeObserver(token) }

            // Point the store at an unwritable location to force a real save failure.
            RuleSyncService.store = RuleStore(
                fileURL: URL(fileURLWithPath: "/dev/null/rockxy-nested/rules.json")
            )
            await RuleEngine.shared.replaceAll([])

            let result = await RuleSyncService.addRuleIfAllowedPersisting(Self.fileRule(), maxPerCategory: 10)

            #expect(!result.isDurablySaved)
            if case let .persisted(.failed(message)) = result {
                #expect(!message.isEmpty)
            } else {
                Issue.record("Expected a persisted(.failed) result, got \(result)")
            }
            #expect(failureMessage != nil)
            // The optimistic engine mutation is still visible (truthful active state)…
            #expect(await RuleEngine.shared.allRules.count == 1)
            // …but nothing was written to disk.
            #expect(!FileManager.default.fileExists(atPath: "/dev/null/rockxy-nested/rules.json"))
        }
    }

    @Test("updateRulePersisting reports a save failure instead of silent success")
    @MainActor
    func updateFailureIsVisible() async {
        await withRuleHarness {
            let rule = Self.fileRule()
            await RuleEngine.shared.replaceAll([rule])
            RuleSyncService.store = RuleStore(
                fileURL: URL(fileURLWithPath: "/dev/null/rockxy-nested/rules.json")
            )

            var updated = rule
            updated.name = "Renamed"
            let outcome = await RuleSyncService.updateRulePersisting(updated)
            #expect(outcome.isSaved == false)
        }
    }

    @Test("A failed new-rule save retried against a writable store yields exactly one rule")
    @MainActor
    func saveFailureRetryIsDuplicateSafe() async {
        await withRuleHarness {
            let rule = Self.fileRule()
            await RuleEngine.shared.replaceAll([])

            // First attempt: the store is unwritable, so the optimistic engine mutation
            // lands but the durable write fails.
            RuleSyncService.store = RuleStore(
                fileURL: URL(fileURLWithPath: "/dev/null/rockxy-nested/rules.json")
            )
            let first = await RuleSyncService.addRuleIfAllowedPersisting(rule, maxPerCategory: 10)
            #expect(!first.isDurablySaved)
            #expect(await RuleEngine.shared.allRules.count == 1)

            // The editor adopts the attempted identity (see
            // MapLocalEditorViewModel.adoptFailedAddIdentity), so the retry updates the
            // same rule instead of adding a second one under a fresh UUID.
            RuleSyncService.store = RuleStore(fileURL: Self.tempFileURL)
            var retried = rule
            retried.name = "Retried"
            let second = await RuleSyncService.updateRulePersisting(retried)
            #expect(second.isSaved)

            let engineRules = await RuleEngine.shared.allRules
            #expect(engineRules.count == 1)
            #expect(engineRules.first?.id == rule.id)
            #expect(engineRules.first?.name == "Retried")

            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(persisted.count == 1)
            #expect(persisted.first?.id == rule.id)
            #expect(persisted.first?.name == "Retried")
        }
    }

    @Test("A new rule waits for persisted rules to load before saving the combined set")
    @MainActor
    func persistingAddLoadsExistingRulesFirst() async {
        await withRuleHarness {
            let existing = Self.directoryRule()
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode([existing]) else {
                Issue.record("Expected to encode rules fixture")
                return
            }
            try? data.write(to: Self.tempFileURL, options: .atomic)
            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()

            let added = Self.fileRule()
            let result = await RuleSyncService.addRuleIfAllowedPersisting(added, maxPerCategory: 10)

            #expect(result.isDurablySaved)
            let engineRules = await RuleEngine.shared.allRules
            #expect(engineRules.map(\.id) == [existing.id, added.id])
            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(persisted.map(\.id) == [existing.id, added.id])
        }
    }

    @Test("A load failure blocks a new mutation instead of overwriting saved data")
    @MainActor
    func loadFailureBlocksPersistingAdd() async {
        await withRuleHarness {
            let corrupt = Data(#"{"existing":"unreadable"}"#.utf8)
            try? corrupt.write(to: Self.tempFileURL, options: .atomic)
            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()

            let result = await RuleSyncService.addRuleIfAllowedPersisting(Self.fileRule(), maxPerCategory: 10)

            if case .loadFailed = result {} else {
                Issue.record("Expected loadFailed, got \(result)")
            }
            #expect(await RuleEngine.shared.allRules.isEmpty)
            #expect((try? Data(contentsOf: Self.tempFileURL)) == corrupt)
        }
    }

    @Test("Editor adopts a failed add's identity, switching from add-new to retry-update")
    @MainActor
    func editorAdoptsFailedAddIdentity() {
        let viewModel = MapLocalEditorViewModel()
        viewModel.load(context: .blank)
        // A brand-new editor has no identity, so the save path uses add-new semantics.
        #expect(viewModel.existingID == nil)

        let attempted = Self.fileRule()
        viewModel.adoptFailedAddIdentity(attempted)

        // After adoption the save path routes through update semantics on the same id.
        #expect(viewModel.existingID == attempted.id)
        #expect(viewModel.originalRule?.id == attempted.id)
    }

    @Test("A corrupt rules file is left untouched, not marked loaded, and remains retryable")
    @MainActor
    func decodeFailurePreservesFileAndRetries() async {
        await withRuleHarness {
            let corrupt = Data(#"{"not":"a rule list"}"#.utf8)
            try? corrupt.write(to: Self.tempFileURL, options: .atomic)
            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()

            let failed = await RuleSyncService.ensureLoaded()
            if case .failed = failed {} else {
                Issue.record("Expected a failed load for corrupt data")
            }
            let onDiskAfterFailure = try? Data(contentsOf: Self.tempFileURL)
            #expect(onDiskAfterFailure == corrupt)
            #expect(await RuleEngine.shared.allRules.isEmpty)

            // Retry after fixing the file succeeds (failure was not cached).
            let encoder = JSONEncoder()
            guard let good = try? encoder.encode([Self.fileRule()]) else {
                Issue.record("Expected to encode rules fixture")
                return
            }
            try? good.write(to: Self.tempFileURL, options: .atomic)
            #expect(await RuleSyncService.ensureLoaded() == .loaded)
            #expect(await RuleEngine.shared.allRules.count == 1)
        }
    }

    @Test("Bulk-disabling Map Local rules mutates only Map Local and keeps concurrent additions")
    @MainActor
    func bulkDisableRetainsConcurrentAdditionsAndOtherCategories() async {
        await withRuleHarness {
            let a = Self.fileRule() // Map Local, enabled
            let b = Self.fullResponseRule() // Map Local, enabled
            await RuleSyncService.replaceAllRules([a, b])

            // A Map Local window captured [a, b]. Meanwhile another window adds an
            // unrelated (enabled) Block rule and a fresh Map Local rule — neither is
            // present in the window's stale snapshot.
            let concurrentBlock = Self.blockRule()
            let concurrentMapLocal = Self.directoryRule() // disabled
            await RuleSyncService.addRule(concurrentBlock)
            await RuleSyncService.addRule(concurrentMapLocal)

            // The stale bulk-disable now runs. It must disable only Map Local rules
            // and never drop the concurrent additions or the Block rule's state.
            await RuleSyncService.setMapLocalRulesEnabled(false, maxPerCategory: 10)

            let engine = await RuleEngine.shared.allRules
            #expect(Set(engine.map(\.id)) == Set([a.id, b.id, concurrentBlock.id, concurrentMapLocal.id]))
            // The Block rule is a different category and must be untouched.
            #expect(engine.first { $0.id == concurrentBlock.id }?.isEnabled == true)
            // Every Map Local rule is now disabled.
            for rule in engine where isMapLocal(rule) {
                #expect(rule.isEnabled == false)
            }
            // The mutation was persisted against current state, not a stale snapshot.
            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(Set(persisted.map(\.id)) == Set([a.id, b.id, concurrentBlock.id, concurrentMapLocal.id]))
        }
    }

    @Test("Bulk-enabling Map Local rules respects the per-category quota")
    @MainActor
    func bulkEnableHonorsQuota() async {
        await withRuleHarness {
            var first = Self.fileRule()
            first.isEnabled = false
            var second = Self.fullResponseRule()
            second.isEnabled = false
            var third = Self.directoryRule() // already disabled
            third.name = "Third Map Local"
            await RuleSyncService.replaceAllRules([first, second, third])

            // Quota of 2 means only two Map Local rules may become active.
            await RuleSyncService.setMapLocalRulesEnabled(true, maxPerCategory: 2)

            let engine = await RuleEngine.shared.allRules
            let enabled = engine.filter { isMapLocal($0) && $0.isEnabled }
            #expect(enabled.count == 2)
        }
    }

    @Test("Removing selected Map Local rules keeps concurrent additions and other categories")
    @MainActor
    func removeSelectedRetainsConcurrentAdditions() async {
        await withRuleHarness {
            let a = Self.fileRule()
            let b = Self.fullResponseRule()
            await RuleSyncService.replaceAllRules([a, b])

            // Snapshot captured [a, b]; another window then adds rules before the
            // stale removal executes.
            let concurrentBlock = Self.blockRule()
            let concurrentMapLocal = Self.directoryRule()
            await RuleSyncService.addRule(concurrentBlock)
            await RuleSyncService.addRule(concurrentMapLocal)

            // Remove only the originally-selected Map Local IDs.
            await RuleSyncService.removeRules(ids: [a.id, b.id])

            let engine = await RuleEngine.shared.allRules
            #expect(Set(engine.map(\.id)) == Set([concurrentBlock.id, concurrentMapLocal.id]))
            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(Set(persisted.map(\.id)) == Set([concurrentBlock.id, concurrentMapLocal.id]))
        }
    }

    @Test("Removing selected Map Remote rules via the view model keeps concurrent additions")
    @MainActor
    func mapRemoteRemoveSelectedRetainsConcurrentAdditions() async {
        await withRuleHarness {
            let remoteA = Self.mapRemoteRule(name: "Remote A")
            let remoteB = Self.mapRemoteRule(name: "Remote B")
            await RuleSyncService.replaceAllRules([remoteA, remoteB])

            let viewModel = MapRemoteWindowViewModel()
            await viewModel.refreshFromEngine()
            viewModel.selectedRuleIDs = [remoteA.id, remoteB.id]

            // Another window adds unrelated rules after this window took its snapshot.
            let concurrentBlock = Self.blockRule()
            let concurrentMapLocal = Self.fileRule()
            await RuleSyncService.addRule(concurrentBlock)
            await RuleSyncService.addRule(concurrentMapLocal)

            // Removing the selected Map Remote rules must not touch the concurrent adds.
            viewModel.removeSelectedRules()
            await viewModel.waitForPendingRuleSync()

            let engine = await RuleEngine.shared.allRules
            #expect(Set(engine.map(\.id)) == Set([concurrentBlock.id, concurrentMapLocal.id]))
            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(Set(persisted.map(\.id)) == Set([concurrentBlock.id, concurrentMapLocal.id]))
        }
    }

    @Test("Importing Block rules replaces only Block rules and keeps concurrent Map Local additions")
    @MainActor
    func blockImportReplacesOnlyBlockCategory() async {
        await withRuleHarness {
            let existingBlock = Self.blockRule()
            let mapLocal = Self.fileRule()
            await RuleSyncService.replaceAllRules([existingBlock, mapLocal])

            // A concurrent Map Local addition lands after the Block window's snapshot.
            let concurrentMapLocal = Self.directoryRule()
            await RuleSyncService.addRule(concurrentMapLocal)

            let importedA = ProxyRule(
                name: "Imported A",
                matchCondition: RuleMatchCondition(urlPattern: ".*a\\.example\\.com.*"),
                action: .block(statusCode: 403)
            )
            let importedB = ProxyRule(
                name: "Imported B",
                matchCondition: RuleMatchCondition(urlPattern: ".*b\\.example\\.com.*"),
                action: .block(statusCode: 0)
            )
            await RuleSyncService.replaceBlockRules([importedA, importedB], maxPerCategory: 10)

            let engine = await RuleEngine.shared.allRules
            // Old Block rule gone; both Map Local rules retained (order preserved);
            // imported Block rules appended after the retained non-Block rules.
            #expect(engine.map(\.id) == [mapLocal.id, concurrentMapLocal.id, importedA.id, importedB.id])
            #expect(!engine.contains { $0.id == existingBlock.id })
            let persisted = (try? RuleStore(fileURL: Self.tempFileURL).loadRules()) ?? []
            #expect(persisted.map(\.id) == [mapLocal.id, concurrentMapLocal.id, importedA.id, importedB.id])
        }
    }

    @Test("Importing Block rules caps enabled imported rules to the per-category quota")
    @MainActor
    func blockImportHonorsQuota() async {
        await withRuleHarness {
            await RuleSyncService.replaceAllRules([])
            let imported = (0 ..< 4).map { index in
                ProxyRule(
                    name: "Imported \(index)",
                    matchCondition: RuleMatchCondition(urlPattern: ".*\(index)\\.example\\.com.*"),
                    action: .block(statusCode: 403)
                )
            }

            await RuleSyncService.replaceBlockRules(imported, maxPerCategory: 2)

            let engine = await RuleEngine.shared.allRules
            #expect(engine.count == 4)
            let enabledBlock = engine.filter { isBlock($0) && $0.isEnabled }
            #expect(enabledBlock.count == 2)
            // The first two imported Block rules stay enabled; the overflow is disabled.
            #expect(engine[0].isEnabled)
            #expect(engine[1].isEnabled)
            #expect(engine.suffix(2).allSatisfy { !$0.isEnabled })
        }
    }

    @Test("Concurrent ensureLoaded calls are idempotent")
    @MainActor
    func concurrentEnsureLoadIsIdempotent() async {
        await withRuleHarness {
            let encoder = JSONEncoder()
            guard let good = try? encoder.encode([Self.fileRule(), Self.directoryRule()]) else {
                Issue.record("Expected to encode rules fixture")
                return
            }
            try? good.write(to: Self.tempFileURL, options: .atomic)
            await RuleEngine.shared.replaceAll([])
            await RuleSyncService.resetLoadStateForTesting()

            async let first = RuleSyncService.ensureLoaded()
            async let second = RuleSyncService.ensureLoaded()
            let outcomes = await [first, second]

            #expect(outcomes.allSatisfy { $0 == .loaded })
            #expect(await RuleEngine.shared.allRules.count == 2)
        }
    }

    @Test("A newer snapshot committed first is never overwritten by an older ticket's stale snapshot")
    func newerTicketWinsRegardlessOfCommitOrder() async {
        let url = Self.queueTempFileURL(suffix: "order")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RuleStore(fileURL: url)
        let queue = RulePersistenceQueue()

        let older = [Self.fileRule()]
        let newer = [Self.fileRule(), Self.directoryRule()]

        // Reserve in mutation-completion order: older ticket first, newer second.
        let oldTicket = await queue.reserveTicket()
        let newTicket = await queue.reserveTicket()

        // Commit out of order: the newer, encompassing snapshot lands first, the
        // stale older snapshot second — reproducing the write-order race.
        let newCommit = await queue.commit(ticket: newTicket, newer, using: store)
        let oldCommit = await queue.commit(ticket: oldTicket, older, using: store)

        #expect(newCommit.superseded == false)
        #expect(newCommit.outcome == .saved)
        // The stale older commit is superseded and never writes.
        #expect(oldCommit.superseded)
        #expect(oldCommit.outcome == .saved)

        let persisted = (try? store.loadRules()) ?? []
        #expect(persisted.map(\.id) == newer.map(\.id))
    }

    @Test("An older commit after a failed newer attempt inherits the failure and never persists")
    func olderCommitInheritsFailedNewerOutcome() async {
        // Newer snapshot targets an unwritable path → a real save failure.
        let failingStore = RuleStore(
            fileURL: URL(fileURLWithPath: "/dev/null/rockxy-queue-nested/rules.json")
        )
        // Older snapshot targets a writable temp store; it must STILL not write.
        let url = Self.queueTempFileURL(suffix: "failure")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let writableStore = RuleStore(fileURL: url)

        let queue = RulePersistenceQueue()
        let oldTicket = await queue.reserveTicket()
        let newTicket = await queue.reserveTicket()

        let newCommit = await queue.commit(
            ticket: newTicket, [Self.fileRule(), Self.directoryRule()], using: failingStore
        )
        #expect(newCommit.superseded == false)
        #expect(newCommit.outcome.isSaved == false)

        let oldCommit = await queue.commit(ticket: oldTicket, [Self.fileRule()], using: writableStore)
        // The older caller inherits the newer, encompassing attempt's failure so it
        // cannot falsely report durability, and its stale snapshot is not written.
        #expect(oldCommit.superseded)
        #expect(oldCommit.outcome.isSaved == false)
        #expect(oldCommit.outcome == newCommit.outcome)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    // MARK: Private

    private static let tempFileURL: URL = FileManager.default.temporaryDirectory
        // Keep a space in the path to mirror production's "Application Support"
        // directory and catch accidental use of URL.path()'s encoded form. Include
        // the process ID because Xcode can execute Swift Testing suites in multiple
        // worker processes that must not delete each other's fixture.
        .appendingPathComponent(
            "rockxy maplocal tests \(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
        .appendingPathComponent("rules.json")

    /// Isolated temp file for the persistence-queue ordering tests. Kept distinct
    /// from `tempFileURL` (and per-suffix + per-PID) so a queue test never shares a
    /// path with the harness-backed tests or a parallel worker process.
    private static func queueTempFileURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "rockxy maplocal queue \(suffix) \(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
            .appendingPathComponent("rules.json")
    }

    private static func fileRule() -> ProxyRule {
        ProxyRule(
            id: UUID(),
            name: "Serve Mock JSON",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://example.com/api/*",
                sourceURLPattern: "https://example.com/api/*",
                method: "GET",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            action: .mapLocal(
                filePath: "/tmp/mock/response.json",
                statusCode: 200,
                isDirectory: false,
                delayMs: 0,
                responseHeaders: [
                    HTTPHeader(name: "Content-Type", value: "application/json"),
                    HTTPHeader(name: "X-Order", value: "1"),
                ]
            ),
            priority: 3
        )
    }

    private static func directoryRule() -> ProxyRule {
        ProxyRule(
            id: UUID(),
            name: "Serve Assets Dir",
            isEnabled: false,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://cdn\\.example\\.com/assets/(.*)",
                sourceURLPattern: "https://cdn\\.example\\.com/assets/(.*)",
                method: "POST",
                matchType: .regex
            ),
            action: .mapLocal(
                filePath: "/tmp/mock/assets",
                statusCode: 404,
                isDirectory: true,
                delayMs: 1_500,
                responseHeaders: [HTTPHeader(name: "Cache-Control", value: "no-store")]
            ),
            priority: 7
        )
    }

    private static func blockRule() -> ProxyRule {
        ProxyRule(
            name: "Block Ads",
            matchCondition: RuleMatchCondition(urlPattern: ".*ads\\.example\\.com.*"),
            action: .block(statusCode: 403)
        )
    }

    private static func mapRemoteRule(name: String) -> ProxyRule {
        ProxyRule(
            id: UUID(),
            name: name,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://example.com/api/*",
                sourceURLPattern: "https://example.com/api/*",
                matchType: .wildcard
            ),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
    }

    private static func fullResponseRule() -> ProxyRule {
        ProxyRule(
            id: UUID(),
            name: "Full HTTP Response",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://example.com/login*",
                sourceURLPattern: "https://example.com/login*",
                matchType: .wildcard,
                includeSubpaths: true
            ),
            action: .mapLocal(
                filePath: "/tmp/mock/full-response.http",
                statusCode: 201,
                isDirectory: false,
                delayMs: 250,
                responseHeaders: [
                    HTTPHeader(name: "Set-Cookie", value: "a=1"),
                    HTTPHeader(name: "Set-Cookie", value: "b=2"),
                    HTTPHeader(name: "X-Order", value: "z"),
                ]
            ),
            priority: 1
        )
    }

    private static func expectEqualRule(_ actual: ProxyRule, _ expected: ProxyRule) {
        #expect(actual.id == expected.id)
        #expect(actual.name == expected.name)
        #expect(actual.isEnabled == expected.isEnabled)
        #expect(actual.priority == expected.priority)
        #expect(actual.matchCondition == expected.matchCondition)

        guard case let .mapLocal(aPath, aStatus, aDir, aDelay, aHeaders) = actual.action,
              case let .mapLocal(ePath, eStatus, eDir, eDelay, eHeaders) = expected.action else
        {
            Issue.record("Expected both actions to be .mapLocal")
            return
        }
        #expect(aPath == ePath)
        #expect(aStatus == eStatus)
        #expect(aDir == eDir)
        #expect(aDelay == eDelay)
        #expect(aHeaders == eHeaders)
    }

    private func isMapLocal(_ rule: ProxyRule) -> Bool {
        if case .mapLocal = rule.action {
            return true
        }
        return false
    }

    private func isBlock(_ rule: ProxyRule) -> Bool {
        if case .block = rule.action {
            return true
        }
        return false
    }

    /// Runs `body` under the shared rule-test lock with `RuleSyncService.store`,
    /// the engine's rules, and the load-cache all backed up and restored.
    @MainActor
    private func withRuleHarness(_ body: () async -> Void) async {
        await RuleTestLock.shared.acquire()
        let storeBackup = RuleSyncService.store
        let engineBackup = await RuleEngine.shared.allRules

        try? FileManager.default.createDirectory(
            at: Self.tempFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: Self.tempFileURL)
        RuleSyncService.store = RuleStore(fileURL: Self.tempFileURL)

        await body()

        RuleSyncService.store = storeBackup
        await RuleEngine.shared.replaceAll(engineBackup)
        await RuleSyncService.resetLoadStateForTesting()
        try? FileManager.default.removeItem(at: Self.tempFileURL)
        await RuleTestLock.shared.release()
    }
}
