import Dispatch
import Foundation
@testable import Rockxy
import Testing

// Regression tests for the cancellation half of the #319 authorization routing defect.
//
// The authorization queue is serial, so a second operation waits behind whatever dialog is already
// on screen. A caller that gave up while it was queued must never reach the Security API: running
// it then raises a fresh macOS dialog for work nobody is waiting for, and mutates trust state
// after the operation was reported as cancelled. Work that has already started is the opposite
// case — an approval macOS is showing cannot be withdrawn, so the caller stays suspended, and the
// mutation guards it holds stay closed, until the native call actually returns.
//
// Nothing here reaches Authorization Services: the "dialog" is a queue this test holds and
// releases itself.

// MARK: - AuthorizationWorkQueueCancellationTests

@Suite(.serialized)
struct AuthorizationWorkQueueCancellationTests {
    @Test("work cancelled while queued behind an open dialog never runs")
    func queuedWorkCancelledBeforeAdmissionNeverRuns() async {
        let queue = DispatchQueue(label: "tests.certificate-authorization.queued")
        let enqueued = AuthorizationTestFlag()
        var configured = AuthorizationWorkQueue(queue: queue)
        configured.enqueueObserverForTests = { enqueued.set() }
        let authorizationQueue = configured

        // A first item owns the queue exactly the way an authorization dialog owns it: it holds
        // the thread until this test lets go.
        let occupied = AuthorizationTestFlag()
        let release = DispatchSemaphore(value: 0)
        queue.async {
            occupied.set()
            release.wait()
        }
        #expect(await authorizationFlagIsSet(occupied))

        let ran = AuthorizationTestFlag()
        let task = Task {
            try await authorizationQueue.run { _ in ran.set() }
        }
        // Queued, not started: the cancellation below lands in exactly the window the defect was
        // about.
        #expect(await authorizationFlagIsSet(enqueued))

        task.cancel()
        release.signal()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        // Zero invocations, so no second dialog could have been raised and nothing was mutated.
        #expect(!ran.isSet)
    }

    @Test("a native call already in flight is awaited to completion and its outcome is kept")
    func inFlightWorkIsNotAbandoned() async throws {
        let queue = DispatchQueue(label: "tests.certificate-authorization.in-flight")
        let authorizationQueue = AuthorizationWorkQueue(queue: queue)

        let started = AuthorizationTestFlag()
        let finished = AuthorizationTestFlag()
        let resumed = AuthorizationTestFlag()
        let release = DispatchSemaphore(value: 0)

        let task = Task {
            try await authorizationQueue.run { _ in
                started.set()
                // Stands in for a dialog that is already on screen and cannot be withdrawn.
                release.wait()
                finished.set()
            }
            resumed.set()
        }
        #expect(await authorizationFlagIsSet(started))

        task.cancel()
        // Bounded: the await must still be suspended, because the native call has not returned.
        for _ in 0 ..< 200 {
            await Task.yield()
        }
        #expect(!resumed.isSet)
        #expect(!finished.isSet)

        release.signal()
        try await task.value
        #expect(finished.isSet)
        #expect(resumed.isSet)
    }

    @Test("a cancellation between steps stops the next authorization operation")
    func cancellationBetweenStepsStopsLaterWork() async {
        let queue = DispatchQueue(label: "tests.certificate-authorization.steps")
        let authorizationQueue = AuthorizationWorkQueue(queue: queue)

        let firstStepDone = AuthorizationTestFlag()
        let secondStepRan = AuthorizationTestFlag()
        let observedTaskCancellationOnQueue = AuthorizationTestFlag()
        let release = DispatchSemaphore(value: 0)

        let task = Task {
            try await authorizationQueue.run { signal in
                try signal.checkCancellation()
                firstStepDone.set()
                release.wait()
                // The queue's thread carries no task context, so `Task.isCancelled` there answers
                // for a task that does not exist. The signal is what carries the real answer.
                if !Task.isCancelled, signal.isCancelled {
                    observedTaskCancellationOnQueue.set()
                }
                try signal.checkCancellation()
                secondStepRan.set()
            }
        }
        #expect(await authorizationFlagIsSet(firstStepDone))

        task.cancel()
        release.signal()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!secondStepRan.isSet)
        #expect(observedTaskCancellationOnQueue.isSet)
    }
}

// MARK: - RootCATrustInstallInFlightCancellationTests

/// The manager's side of the same rule: the guard that rejects competing mutations is held for as
/// long as the app-side installation can still complete, and the cancellation is reported only
/// once it has.
@Suite(.serialized)
struct RootCATrustInstallInFlightCancellationTests {
    @Test("cancelling a running install holds the guard until it finishes, then reports cancellation")
    func cancellationDuringAppSideInstallHoldsTheGuard() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())

        let started = AuthorizationTestFlag()
        let finished = AuthorizationTestFlag()
        let dialog = AuthorizationTestGate()
        await manager.setHelperInstallOverrideForTests { _ in
            Issue.record("A GUI-session install must not dispatch a helper installation RPC")
        }
        await manager.setAppInstallOverrideForTests { _ in
            started.set()
            // Suspended the way the real call is while macOS shows the dialog.
            await dialog.wait()
            finished.set()
        }

        let task = Task { try await manager.installAndTrust() }
        #expect(await authorizationFlagIsSet(started))

        task.cancel()

        // The installation is still inside the native call, so the material it is installing may
        // not be replaced and the guard must still reject a competing mutation.
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.generateRootCA()
        }
        #expect(!finished.isSet)

        dialog.open()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        // The install completed before the cancellation was reported, and nothing adopted a new
        // identity on the way out.
        #expect(finished.isSet)
        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)

        // The guard is released on the cancelled exit path too.
        try await manager.generateRootCA()
        #expect(await manager.getActiveRootFingerprint() != nil)
    }
}

// MARK: - AuthorizationTestFlag

/// A one-way flag shared between a Dispatch thread and the test's task.
private final class AuthorizationTestFlag: @unchecked Sendable {
    // MARK: Internal

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = false
}

// MARK: - AuthorizationTestGate

/// An async gate the test opens explicitly, so an injected installer can suspend the way the real
/// authorization call does — including inside a task that has already been cancelled.
private final class AuthorizationTestGate: @unchecked Sendable {
    // MARK: Internal

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyOpen: Bool = lock.withLock {
                if isOpen {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if alreadyOpen {
                continuation.resume()
            }
        }
    }

    func open() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            let queued = waiters
            waiters = []
            return queued
        }
        for continuation in pending {
            continuation.resume()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

/// Yields until `flag` is set, bounded so a failure ends the test instead of hanging it.
private func authorizationFlagIsSet(_ flag: AuthorizationTestFlag) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while clock.now < deadline {
        if flag.isSet {
            return true
        }
        await Task.yield()
    }
    return flag.isSet
}
