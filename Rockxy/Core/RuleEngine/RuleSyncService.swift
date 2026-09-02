import Foundation
import os

// MARK: - RulePersistenceOutcome

/// Result of attempting to durably write the current rule set to disk.
enum RulePersistenceOutcome: Sendable, Equatable {
    case saved
    /// Save failed; `message` is a user-facing localized description.
    case failed(message: String)

    // MARK: Internal

    var isSaved: Bool {
        if case .saved = self {
            return true
        }
        return false
    }
}

// MARK: - RuleLoadOutcome

/// Result of attempting to load persisted rules from disk.
enum RuleLoadOutcome: Sendable, Equatable {
    case loaded
    /// Load/decode failed; the on-disk file was left untouched. `message` is user-facing.
    case failed(message: String)

    // MARK: Internal

    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

// MARK: - RuleMutationResult

/// Combined quota + persistence result for rule-creating surfaces that must not
/// report success unless the change was durably written.
enum RuleMutationResult: Sendable, Equatable {
    case quotaExceeded
    /// Existing rules could not be loaded, so no mutation was attempted.
    case loadFailed(message: String)
    case persisted(RulePersistenceOutcome)

    // MARK: Internal

    /// True only when the mutation was both accepted by the quota gate and saved.
    var isDurablySaved: Bool {
        if case .persisted(.saved) = self {
            return true
        }
        return false
    }
}

// MARK: - RuleSyncService

/// Coordinates rule mutations between the shared `RuleEngine` actor, disk persistence
/// via `RuleStore`, and UI notification via `NotificationCenter`.
/// All rule changes should flow through this service.
enum RuleSyncService {
    // MARK: Internal

    /// Injectable persistence seam. Production uses the identity-scoped rules file;
    /// serialized tests rebind this to a `RuleStore(fileURL:)` under a temp directory
    /// to exercise the real save/load path (including failures) safely.
    ///
    /// **Mutability contract:** reassigned only from controlled, serialized contexts.
    /// Do not rebind from parallel tests or arbitrary runtime paths.
    static var store = RuleStore()

    static func addRule(_ rule: ProxyRule) async {
        await RuleEngine.shared.addRule(rule)
        await syncAll()
    }

    static func removeRule(id: UUID) async {
        await RuleEngine.shared.removeRule(id: id)
        await syncAll()
    }

    static func toggleRule(id: UUID) async {
        await RuleEngine.shared.toggleRule(id: id)
        await syncAll()
    }

    static func updateRule(_ rule: ProxyRule) async {
        await RuleEngine.shared.updateRule(rule)
        await syncAll()
    }

    static func replaceAllRules(_ rules: [ProxyRule]) async {
        await RuleEngine.shared.replaceAll(rules)
        await syncAll()
    }

    /// Removes only the given IDs against current engine state (never a stale
    /// caller snapshot), then persists once. Concurrent additions and other
    /// categories are retained.
    static func removeRules(ids: Set<UUID>) async {
        await RuleEngine.shared.removeRules(ids: ids)
        await syncAll()
    }

    /// Bulk enables/disables every Map Local rule against current engine state
    /// under the per-category quota, then persists once. Other categories and
    /// concurrent additions are retained.
    static func setMapLocalRulesEnabled(_ enabled: Bool, maxPerCategory: Int) async {
        await RuleEngine.shared.setMapLocalRulesEnabled(enabled, maxPerCategory: maxPerCategory)
        await syncAll()
    }

    /// Replaces only Block rules with `importedBlockRules` against current engine
    /// state under the per-category quota, then persists once. Non-Block rules
    /// (including concurrent additions from other windows) are retained.
    static func replaceBlockRules(_ importedBlockRules: [ProxyRule], maxPerCategory: Int) async {
        await RuleEngine.shared.replaceBlockRules(importedBlockRules, maxPerCategory: maxPerCategory)
        await syncAll()
    }

    static func reorderModifyHeaderRules(orderedIDs: [UUID]) async {
        await RuleEngine.shared.reorderModifyHeaderRules(orderedIDs: orderedIDs)
        await syncAll()
    }

    static func reorderMapLocalRules(orderedIDs: [UUID]) async {
        await RuleEngine.shared.reorderMapLocalRules(orderedIDs: orderedIDs)
        await syncAll()
    }

    static func setRuleEnabled(id: UUID, enabled: Bool) async {
        await RuleEngine.shared.setEnabled(id: id, enabled: enabled)
        await syncAll()
    }

    static func addNetworkConditionExclusive(_ rule: ProxyRule) async {
        await RuleEngine.shared.addNetworkConditionExclusive(rule)
        await syncAll()
    }

    static func enableExclusiveNetworkCondition(id: UUID) async {
        await RuleEngine.shared.enableExclusiveNetworkCondition(id: id)
        await syncAll()
    }

    static func disableAllNetworkConditions() async {
        await RuleEngine.shared.disableAllNetworkConditions()
        await syncAll()
    }

    static func enableExclusiveNetworkConditionIfAllowed(
        id: UUID,
        maxPerCategory: Int
    )
        async -> Bool
    {
        let accepted = await RuleEngine.shared.enableExclusiveNetworkConditionIfAllowed(
            id: id,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    // MARK: - Persistence-Aware Operations

    /// Adds a rule under the quota gate and reports whether it was durably saved.
    /// Unlike ``addRuleIfAllowed(_:maxPerCategory:)``, the caller learns if the
    /// engine mutation was accepted but the disk write failed, so a UI surface can
    /// avoid reporting success or dismissing prematurely.
    static func addRuleIfAllowedPersisting(_ rule: ProxyRule, maxPerCategory: Int) async -> RuleMutationResult {
        // Never overwrite an existing on-disk rule set with a mutation based on
        // an as-yet-unloaded engine snapshot. This matters when macOS restores an
        // editor window before the main workspace finishes launching.
        if case let .failed(message) = await ensureLoaded() {
            return .loadFailed(message: message)
        }
        let accepted = await RuleEngine.shared.addRuleIfAllowed(rule, maxPerCategory: maxPerCategory)
        guard accepted else {
            return .quotaExceeded
        }
        return await .persisted(syncAll())
    }

    /// Updates a rule and reports whether the change was durably saved.
    static func updateRulePersisting(_ rule: ProxyRule) async -> RulePersistenceOutcome {
        if case let .failed(message) = await ensureLoaded() {
            return .failed(message: message)
        }
        await RuleEngine.shared.updateRule(rule)
        return await syncAll()
    }

    // MARK: - Atomic Quota-Checked Operations

    static func addRuleIfAllowed(_ rule: ProxyRule, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.addRuleIfAllowed(rule, maxPerCategory: maxPerCategory)
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func toggleRuleIfAllowed(id: UUID, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.toggleRuleIfAllowed(id: id, maxPerCategory: maxPerCategory)
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func setEnabledIfAllowed(id: UUID, enabled: Bool, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.setEnabledIfAllowed(
            id: id,
            enabled: enabled,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func addNetworkConditionExclusiveIfAllowed(
        _ rule: ProxyRule,
        maxPerCategory: Int
    )
        async -> Bool
    {
        let accepted = await RuleEngine.shared.addNetworkConditionExclusiveIfAllowed(
            rule,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func setBreakpointToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "breakpointToolEnabled")
        await RuleEngine.shared.setBreakpointToolEnabled(enabled)
    }

    static func setBlockListToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "blockListToolEnabled")
        await RuleEngine.shared.setBlockListToolEnabled(enabled)
    }

    static func setMapLocalToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "mapLocalToolEnabled")
        await RuleEngine.shared.setMapLocalToolEnabled(enabled)
    }

    static func setMapRemoteToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "mapRemoteToolEnabled")
        await RuleEngine.shared.setMapRemoteToolEnabled(enabled)
    }

    static func setNetworkConditionsToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "networkConditionsToolEnabled")
        await RuleEngine.shared.setNetworkConditionsToolEnabled(enabled)
    }

    static func setModifyHeaderToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "modifyHeaderToolEnabled")
        await RuleEngine.shared.setModifyHeaderToolEnabled(enabled)
    }

    /// Idempotent, app-scoped rule load. The first caller performs the disk load;
    /// concurrent callers await the same in-flight load, and callers after a
    /// successful load return immediately. A failed load is NOT cached, so a later
    /// caller transparently retries. Safe to call from any window's `.task` without
    /// depending on main-window project hydration.
    @discardableResult
    static func ensureLoaded() async -> RuleLoadOutcome {
        await loadCoordinator.ensureLoaded()
    }

    @discardableResult
    static func loadFromDisk() async -> RuleLoadOutcome {
        // Read and apply the breakpoint-tool flag BEFORE loading rules so the
        // rule engine has the correct evaluation gate in place when rules are
        // first compiled and become live.
        let blockListEnabled = UserDefaults.standard.object(forKey: "blockListToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setBlockListToolEnabled(blockListEnabled)
        let bpEnabled = UserDefaults.standard.object(forKey: "breakpointToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setBreakpointToolEnabled(bpEnabled)
        let mapLocalEnabled = UserDefaults.standard.object(forKey: "mapLocalToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setMapLocalToolEnabled(mapLocalEnabled)
        let mapRemoteEnabled = UserDefaults.standard.object(forKey: "mapRemoteToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setMapRemoteToolEnabled(mapRemoteEnabled)
        let networkConditionsEnabled = UserDefaults.standard.object(
            forKey: "networkConditionsToolEnabled"
        ) as? Bool ?? true
        await RuleEngine.shared.setNetworkConditionsToolEnabled(networkConditionsEnabled)
        let modifyHeaderEnabled = UserDefaults.standard.object(forKey: "modifyHeaderToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setModifyHeaderToolEnabled(modifyHeaderEnabled)
        do {
            // A successful load publishes the loaded rules WITHOUT rewriting the
            // source file — the on-disk copy is already authoritative and the
            // engine now mirrors it, so re-saving would be redundant churn.
            try await RuleEngine.shared.loadRules(from: store)
            await publishAll()
            return .loaded
        } catch {
            // Leave the on-disk file untouched: a corrupt/unreadable file must not
            // be overwritten with an empty/default snapshot, and the load must not
            // be treated as successful. Publish current engine state so the UI has
            // a coherent snapshot, surface the failure, and allow a later retry.
            logger.error("Failed to load rules from disk: \(error.localizedDescription)")
            await publishAll()
            let message = String(
                localized:
                "Rockxy could not load your saved rules: \(error.localizedDescription). Your saved rules file was left untouched — try reopening this window to load again.",
                bundle: RockxyLocalization.bundle
            )
            await postFailure(named: .rulesDidFailToLoad, message: message)
            return .failed(message: message)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleSyncService")
    private static let persistenceQueue = RulePersistenceQueue()
    private static let loadCoordinator = RuleLoadCoordinator()

    @discardableResult
    private static func syncAll() async -> RulePersistenceOutcome {
        // Reserve a persistence ticket BEFORE reading engine state. Each triggering
        // mutation has completed before its own reservation, so a snapshot taken
        // under a newer ticket necessarily includes the mutations associated with
        // every earlier ticket. The queue uses that to make
        // the highest attempted ticket win, so a stale snapshot read under an older
        // ticket can never overwrite (or falsely claim the durability of) a newer,
        // encompassing one.
        let ticket = await persistenceQueue.reserveTicket()
        let allRules = await RuleEngine.shared.allRules
        let commit = await persistenceQueue.commit(ticket: ticket, allRules, using: store)

        if commit.superseded {
            // A newer, encompassing snapshot already attempted its write. Do not
            // publish this stale snapshot or re-emit a failure the newer attempt
            // already owns. Re-reading and publishing here would introduce another
            // read/post race and could move observers backwards again.
            return commit.outcome
        }

        // This is the newest snapshot attempted so far. Publish the in-engine rules
        // so observers see a coherent snapshot that matches live evaluation, even
        // when the durable write failed.
        await publish(allRules)
        switch commit.outcome {
        case .saved:
            logger.debug("Rules synced: \(allRules.count) rules")
        case let .failed(message):
            logger.error("Failed to persist rules: \(message)")
            await postFailure(named: .rulePersistenceDidFail, message: message)
        }
        return commit.outcome
    }

    private static func publishAll() async {
        let allRules = await RuleEngine.shared.allRules
        await publish(allRules)
        logger.debug("Rules published without persistence: \(allRules.count) rules")
    }

    private static func publish(_ allRules: [ProxyRule]) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .rulesDidChange, object: allRules)
        }
    }

    private static func postFailure(named name: Notification.Name, message: String) async {
        await MainActor.run {
            NotificationCenter.default.post(name: name, object: message)
        }
    }
}

extension RuleSyncService {
    /// Test seam: clears the idempotent-load cache so a subsequent `ensureLoaded()`
    /// performs a fresh disk read (used to simulate a process relaunch).
    static func resetLoadStateForTesting() async {
        await loadCoordinator.reset()
    }
}

// MARK: - RuleLoadCoordinator

/// Serializes and deduplicates rule loading so any window can trigger it safely.
private actor RuleLoadCoordinator {
    // MARK: Internal

    func ensureLoaded() async -> RuleLoadOutcome {
        if loaded {
            return .loaded
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await RuleSyncService.loadFromDisk() }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        // Only cache a successful load; a failure stays uncached so the next
        // caller retries rather than being stuck with an empty/failed state.
        if outcome.isLoaded {
            loaded = true
        }
        return outcome
    }

    func reset() async {
        // Testing can reset while another app surface still has a load in
        // flight. Let that read finish before clearing the cache so it cannot
        // replace the engine after the simulated relaunch has begun.
        if let inFlight {
            _ = await inFlight.value
        }
        loaded = false
        inFlight = nil
    }

    // MARK: Private

    private var loaded = false
    private var inFlight: Task<RuleLoadOutcome, Never>?
}

// MARK: - RulePersistenceCommit

/// Result of a ``RulePersistenceQueue/commit(ticket:_:using:)`` attempt.
struct RulePersistenceCommit: Sendable, Equatable {
    let outcome: RulePersistenceOutcome
    /// True when a newer (higher-ticket) snapshot had already been attempted, so
    /// this stale snapshot was NOT written and `outcome` mirrors that newer attempt.
    let superseded: Bool
}

// MARK: - RulePersistenceQueue

/// Serializes durable rule writes and defends against the stale-snapshot
/// write-order race. A ticket is reserved BEFORE the caller reads engine state;
/// the highest attempted ticket wins, so an older snapshot can never overwrite —
/// or falsely report the durability of — a newer, encompassing one.
///
/// `internal` (not `private`) purely so serialized tests can drive a fresh queue
/// instance through `@testable import`; production always uses the private static
/// `RuleSyncService.persistenceQueue`.
actor RulePersistenceQueue {
    // MARK: Internal

    /// Reserves a monotonically increasing ticket. Callers MUST reserve before
    /// reading the engine snapshot they intend to persist. Because each caller's
    /// mutation completes before reservation, a higher-ticket snapshot includes
    /// every mutation associated with a lower ticket.
    func reserveTicket() -> UInt64 {
        nextTicket += 1
        return nextTicket
    }

    /// Durably writes `rules` unless a newer snapshot has already been attempted.
    /// A superseded (older-ticket) commit never writes and returns the newer
    /// attempt's outcome, so an older caller cannot report a durability the newer,
    /// encompassing snapshot did not achieve. Ticket gaps (reserved-but-never-
    /// committed) are harmless: only magnitude is compared, never contiguity.
    func commit(ticket: UInt64, _ rules: [ProxyRule], using store: RuleStore) -> RulePersistenceCommit {
        if ticket < highestAttemptedTicket {
            return RulePersistenceCommit(outcome: lastOutcome, superseded: true)
        }
        highestAttemptedTicket = ticket
        let outcome = write(rules, using: store)
        lastOutcome = outcome
        return RulePersistenceCommit(outcome: outcome, superseded: false)
    }

    // MARK: Private

    private var nextTicket: UInt64 = 0
    private var highestAttemptedTicket: UInt64 = 0
    private var lastOutcome: RulePersistenceOutcome = .saved

    private func write(_ rules: [ProxyRule], using store: RuleStore) -> RulePersistenceOutcome {
        do {
            try store.saveRules(rules)
            return .saved
        } catch {
            let message = String(
                localized:
                "Rockxy could not save your rules to disk: \(error.localizedDescription). Your latest change is active now but will be lost when Rockxy quits.",
                bundle: RockxyLocalization.bundle
            )
            return .failed(message: message)
        }
    }
}
