import Foundation
@testable import Rockxy
import Testing

// MARK: - FixtureTestSignal

/// One-shot latch used to observe gate transitions deterministically instead of guessing with
/// sleeps. Waiting suspends on a continuation; nothing blocks a cooperative thread.
private final class FixtureTestSignal: @unchecked Sendable {
    // MARK: Internal

    func signal() {
        var pending: [CheckedContinuation<Void, any Error>] = []
        lock.lock()
        isSignaled = true
        for waiter in waiters where !waiter.isSettled {
            if let continuation = waiter.continuation {
                waiter.continuation = nil
                waiter.isSettled = true
                pending.append(continuation)
            }
        }
        waiters.removeAll()
        lock.unlock()

        for continuation in pending {
            continuation.resume()
        }
    }

    /// Cancellable wait, used by `expectSignal` so an observation can carry a deadline.
    func wait() async throws {
        let waiter = Waiter()
        try await withTaskCancellationHandler {
            try await register(waiter)
        } onCancel: {
            cancel(waiter)
        }
    }

    /// Wait that survives cancellation, for a task that must keep running after being cancelled.
    func waitIgnoringCancellation() async {
        try? await register(Waiter())
    }

    // MARK: Private

    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<Void, any Error>?
        var isCancelled = false
        var isSettled = false
    }

    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [Waiter] = []

    private func register(_ waiter: Waiter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if isSignaled || waiter.isCancelled {
                let wasCancelled = !isSignaled
                waiter.isSettled = true
                lock.unlock()
                if wasCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume()
                }
                return
            }
            waiter.continuation = continuation
            waiters.append(waiter)
            lock.unlock()
        }
    }

    private func cancel(_ waiter: Waiter) {
        var continuation: CheckedContinuation<Void, any Error>?
        lock.lock()
        if !waiter.isSettled {
            waiter.isCancelled = true
            if let queued = waiter.continuation {
                waiter.continuation = nil
                waiter.isSettled = true
                waiters.removeAll { $0 === waiter }
                continuation = queued
            }
        }
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
    }
}

// MARK: - SignalTimeout

private struct SignalTimeout: Error {
    let label: String
}

// MARK: - FixtureBodyFailure

private struct FixtureBodyFailure: Error {}

/// Waits for `signal` under a bounded deadline so a broken hand-off fails the test instead of
/// hanging the suite.
private func expectSignal(
    _ signal: FixtureTestSignal,
    _ label: String,
    within seconds: Double = 5
)
    async throws
{
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await signal.wait() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SignalTimeout(label: label)
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

// MARK: - OwnershipRecorder

private actor OwnershipRecorder {
    // MARK: Internal

    private(set) var maxConcurrent = 0
    private(set) var completed = 0

    func enter() {
        active += 1
        maxConcurrent = max(maxConcurrent, active)
    }

    func leave() {
        active -= 1
        completed += 1
    }

    // MARK: Private

    private var active = 0
}

// MARK: - CertificateFixtureGateTests

/// Gate-only regressions. They use their own gate instances, touch no Keychain item, and never
/// trust a certificate.
@Suite(.serialized)
struct CertificateFixtureGateTests {
    @Test("a lease cannot release a different gate with the same turn counter")
    func foreignLeaseCannotReleaseAnotherGate() async throws {
        let first = CertificateFixtureGate()
        let second = CertificateFixtureGate()
        let firstLease = try await first.acquire()
        let secondLease = try await second.acquire()
        defer {
            first.release(firstLease)
            second.release(secondLease)
        }

        second.release(firstLease)
        #expect(second.isHeldForTesting)
        #expect(firstLease != secondLease)
    }

    @Test("an already cancelled task cannot acquire a free gate")
    func alreadyCancelledAcquisitionLeavesGateFree() async throws {
        let gate = CertificateFixtureGate()
        let contender = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let lease = try await gate.acquire()
                gate.release(lease)
                return false
            } catch is CancellationError {
                return true
            } catch {
                Issue.record(error)
                return false
            }
        }
        #expect(await contender.value)
        #expect(!gate.isHeldForTesting)
        #expect(gate.waiterCountForTesting == 0)
        let recovery = try await gate.acquire()
        gate.release(recovery)
    }

    @Test("cancellation racing a grant neither loses ownership nor strands a waiter")
    func cancellationRacingGrantRecovers() async throws {
        for _ in 0 ..< 32 {
            let gate = CertificateFixtureGate()
            let owner = try await gate.acquire()
            let enqueued = FixtureTestSignal()
            gate.setWaiterEnqueuedObserver { enqueued.signal() }
            let contender = Task {
                do {
                    let lease = try await gate.acquire()
                    defer { gate.release(lease) }
                    await Task.yield()
                } catch is CancellationError {
                    // Either cancellation wins, or the owner receives and explicitly releases.
                } catch {
                    Issue.record(error)
                }
            }
            defer {
                gate.release(owner)
                contender.cancel()
                gate.setWaiterEnqueuedObserver(nil)
            }
            try await expectSignal(enqueued, "grant-race contender queued")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { gate.release(owner) }
                group.addTask { contender.cancel() }
            }
            await contender.value
            #expect(!gate.isHeldForTesting)
            #expect(gate.waiterCountForTesting == 0)
            let recovery = try await gate.acquire()
            gate.release(recovery)
        }
    }

    @Test("one owner at a time when far more tasks contend than there are cores")
    func exclusiveOwnershipUnderHighContention() async {
        let gate = CertificateFixtureGate()
        let recorder = OwnershipRecorder()
        let contenders = max(16, ProcessInfo.processInfo.activeProcessorCount * 4)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< contenders {
                group.addTask {
                    guard let lease = try? await gate.acquire() else {
                        return
                    }
                    await recorder.enter()
                    // Suspend while owning the turn: overlap would be visible to the recorder.
                    await Task.yield()
                    await recorder.leave()
                    gate.release(lease)
                }
            }
        }

        #expect(await recorder.maxConcurrent == 1)
        #expect(await recorder.completed == contenders)
        #expect(gate.isHeldForTesting == false)
        #expect(gate.waiterCountForTesting == 0)
    }

    @Test("a lease released from another executor frees the gate")
    func leaseReleasedFromAnotherExecutorFreesTheGate() async throws {
        let gate = CertificateFixtureGate()
        let lease = try await gate.acquire()
        defer { gate.release(lease) }
        #expect(gate.isHeldForTesting)

        let released = FixtureTestSignal()
        // This tests cross-thread ownership, not admission to a saturated global work queue.
        // A dedicated thread makes that boundary explicit under a full parallel test run.
        Thread.detachNewThread {
            gate.release(lease)
            released.signal()
        }
        try await expectSignal(released, "cross-executor release")

        #expect(gate.isHeldForTesting == false)

        let successor = try await gate.acquire()
        gate.release(successor)
        #expect(gate.isHeldForTesting == false)
    }

    @Test("a caller cancelled while registering exits without consuming a free turn")
    func cancellationRacingRegistrationLeavesTheGateFree() async throws {
        let gate = CertificateFixtureGate()
        let reachedRegistration = FixtureTestSignal()
        let mayRegister = FixtureTestSignal()

        gate.installOneShotRegistrationHook {
            reachedRegistration.signal()
            await mayRegister.waitIgnoringCancellation()
        }

        let contender = Task { try await gate.acquire() }
        try await expectSignal(reachedRegistration, "acquire reached registration")

        // Cancelled after the cancellation handler is installed but before registration: the
        // gate is free, and the cancelled caller must not take the turn with it.
        contender.cancel()
        mayRegister.signal()

        await #expect(throws: CancellationError.self) {
            _ = try await contender.value
        }
        #expect(gate.isHeldForTesting == false)
        #expect(gate.waiterCountForTesting == 0)

        let recovered = try await gate.acquire()
        gate.release(recovered)
    }

    @Test("a caller cancelled while queued unqueues itself and the gate still recovers")
    func cancellationWhileQueuedRecovers() async throws {
        let gate = CertificateFixtureGate()
        let owner = try await gate.acquire()

        let enqueued = FixtureTestSignal()
        gate.setWaiterEnqueuedObserver { enqueued.signal() }
        let contender = Task { try await gate.acquire() }
        try await expectSignal(enqueued, "contender enqueued")
        gate.setWaiterEnqueuedObserver(nil)
        #expect(gate.waiterCountForTesting == 1)

        contender.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await contender.value
        }

        #expect(gate.waiterCountForTesting == 0)
        #expect(gate.isHeldForTesting)

        gate.release(owner)
        #expect(gate.isHeldForTesting == false)

        let recovered = try await gate.acquire()
        gate.release(recovered)
        #expect(gate.isHeldForTesting == false)
    }

    @Test("cancellation after a grant never releases the turn behind its owner")
    func cancellationAfterGrantKeepsTheTurnWithItsOwner() async throws {
        let gate = CertificateFixtureGate()
        let owner = try await gate.acquire()

        let enqueued = FixtureTestSignal()
        let granted = FixtureTestSignal()
        let mayFinish = FixtureTestSignal()
        gate.setWaiterEnqueuedObserver { enqueued.signal() }

        let successor = Task { () -> Bool in
            let lease = try await gate.acquire()
            granted.signal()
            await mayFinish.waitIgnoringCancellation()
            let sawCancellation = Task.isCancelled
            gate.release(lease)
            return sawCancellation
        }

        try await expectSignal(enqueued, "successor enqueued")
        gate.setWaiterEnqueuedObserver(nil)

        gate.release(owner)
        try await expectSignal(granted, "successor granted")

        successor.cancel()
        // The successor owns the turn; only its own release may end it.
        #expect(gate.isHeldForTesting)

        mayFinish.signal()
        #expect(try await successor.value)
        #expect(gate.isHeldForTesting == false)
    }

    @Test("release is idempotent and a stale lease never ends another owner's turn")
    func staleReleaseNeverEndsAnotherOwnersTurn() async throws {
        let gate = CertificateFixtureGate()
        let first = try await gate.acquire()

        gate.release(first)
        gate.release(first)
        #expect(gate.isHeldForTesting == false)

        let second = try await gate.acquire()
        gate.release(first)
        #expect(gate.isHeldForTesting)

        gate.release(second)
        #expect(gate.isHeldForTesting == false)
    }
}

// MARK: - CertificateFixtureLeaseTests

/// Fixture-level regressions. They only ever address a unique test namespace and never install
/// trust for any certificate.
@Suite(.serialized)
struct CertificateFixtureLeaseTests {
    @Test("fixture cleanup can run on another executor and finish before the next fixture")
    func crossExecutorFixtureCleanup() async throws {
        let first = try await installSharedTestOverrides()
        defer { first.cleanup() }
        try FileManager.default.createDirectory(at: first.storageDir, withIntermediateDirectories: true)
        let marker = first.storageDir.appendingPathComponent("fixture-marker")
        try Data("fixture".utf8).write(to: marker)

        let cleaned = FixtureTestSignal()
        DispatchQueue.global(qos: .userInitiated).async {
            first.cleanup()
            cleaned.signal()
        }
        try await expectSignal(cleaned, "fixture cleanup on another executor")
        let next = try await installSharedTestOverrides()
        defer { next.cleanup() }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(CertificateStore.keychainKeyLabelOverride == next.label)
        #expect(CertificateStore.storageDirectoryOverride == next.storageDir)
    }

    @Test("a finished fixture's cleanup never disturbs the next fixture")
    func staleCleanupDoesNotDisturbTheNextFixture() async throws {
        let first = try await installSharedTestOverrides()
        let firstLabel = first.label
        let firstDirectory = first.storageDir
        first.cleanup()

        let second = try await installSharedTestOverrides()
        defer { second.cleanup() }

        #expect(second.label != firstLabel)
        #expect(second.storageDir != firstDirectory)

        // Re-running the finished cleanup must not clear the live fixture or end its turn.
        first.cleanup()
        first.cleanup()

        #expect(CertificateStore.keychainKeyLabelOverride == second.label)
        #expect(CertificateStore.storageDirectoryOverride == second.storageDir)
        #expect(CertificateStore.activeKeychainCertificateLabel == second.certificateLabel)
        #expect(certificateFixtureGate.isHeldForTesting)
    }

    @Test("a thrown test body still frees the fixture through its defer")
    func thrownBodyStillFreesTheFixture() async throws {
        await #expect(throws: FixtureBodyFailure.self) {
            let overrides = try await installSharedTestOverrides()
            defer { overrides.cleanup() }
            #expect(CertificateStore.keychainKeyLabelOverride == overrides.label)
            throw FixtureBodyFailure()
        }

        let recovered = try await installSharedTestOverrides()
        defer { recovered.cleanup() }
        #expect(CertificateStore.keychainKeyLabelOverride == recovered.label)
    }

    @Test("the default-namespace helper waits behind an override fixture on the same gate")
    func defaultNamespaceHelperSerializesWithOverrideFixture() async throws {
        let overrides = try await installSharedTestOverrides()
        defer {
            certificateFixtureGate.setWaiterEnqueuedObserver(nil)
            overrides.cleanup()
        }

        let enqueued = FixtureTestSignal()
        certificateFixtureGate.setWaiterEnqueuedObserver { enqueued.signal() }
        let defaultNamespace = Task { () -> (String?, URL?) in
            try await withDefaultCertificateNamespace {
                (CertificateStore.keychainKeyLabelOverride, CertificateStore.storageDirectoryOverride)
            }
        }
        try await expectSignal(enqueued, "default-namespace helper enqueued")
        certificateFixtureGate.setWaiterEnqueuedObserver(nil)

        // The waiting helper has not touched the store: the fixture's overrides are intact.
        #expect(CertificateStore.keychainKeyLabelOverride == overrides.label)
        #expect(CertificateStore.storageDirectoryOverride == overrides.storageDir)

        overrides.cleanup()

        let observed = try await defaultNamespace.value
        #expect(observed.0 == nil)
        #expect(observed.1 == nil)
        // The snapshot was taken while the default helper owned the gate. After its return,
        // another suite may already own the next turn, so don't read global overrides unleased.
        let next = try await installSharedTestOverrides()
        defer { next.cleanup() }
        #expect(CertificateStore.keychainKeyLabelOverride == next.label)
        #expect(CertificateStore.storageDirectoryOverride == next.storageDir)
    }
}
