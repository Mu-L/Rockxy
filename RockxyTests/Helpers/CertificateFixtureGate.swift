import Foundation

// MARK: - CertificateFixtureGate

/// Test-only asynchronous exclusive gate that serializes `CertificateStore` override fixtures.
///
/// The previous design locked an `NSLock` in the fixture installer and unlocked it from the
/// cleanup closure. The installer suspends (`await`) while holding it, and the cleanup runs on
/// whatever thread the test happened to resume on, so the lock was routinely unlocked by a
/// different thread than the one that locked it. `NSLock` documents that as undefined behavior.
///
/// This gate never blocks a thread: waiters suspend on continuations and ownership is handed off
/// directly. Its own critical sections are short, synchronous, and never span an `await`, and no
/// continuation is resumed while the lock is held.
///
/// Scope: one gate instance is per process. It serializes fixtures inside a single test process
/// and makes no claim about isolation between separate processes sharing the user's Keychain.
final class CertificateFixtureGate: @unchecked Sendable {
    // MARK: Internal

    /// Proof of ownership for one exclusive turn.
    ///
    /// `release` only acts when the lease matches the turn currently held, so a stale lease can
    /// never end a later owner's turn.
    struct Lease: Sendable, Equatable {
        fileprivate let gateID: UUID
        fileprivate let id: UInt64
    }

    // MARK: Test introspection and seams

    /// Whether some caller currently owns the gate. Test-only observation.
    var isHeldForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHeld
    }

    /// Number of callers currently queued behind the owner. Test-only observation.
    var waiterCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    /// Suspends until this caller owns the gate exclusively.
    ///
    /// Cancellation is honoured while waiting: a caller cancelled before or during registration,
    /// or while queued, exits with `CancellationError` and never consumes the turn. Once a lease
    /// has been granted, cancellation no longer releases it — the owner's explicit `release`
    /// (typically via `defer`) is the only thing that ends the turn.
    func acquire() async throws -> Lease {
        let waiter = Waiter()
        return try await withTaskCancellationHandler {
            // Test seam: lets a regression deterministically cancel a caller in the window
            // between installing the cancellation handler and registering as a waiter.
            if let hook = takeRegistrationHook() {
                await hook()
            }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Lease, any Error>) in
                let outcome: AcquireOutcome
                lock.lock()
                if waiter.isCancelled {
                    waiter.isSettled = true
                    outcome = .cancelled
                } else if isHeld {
                    waiter.continuation = continuation
                    waiters.append(waiter)
                    outcome = .queued
                } else {
                    isHeld = true
                    waiter.isSettled = true
                    outcome = .granted(makeLeaseLocked())
                }
                let observer = waiterEnqueuedObserver
                lock.unlock()

                switch outcome {
                case let .granted(lease):
                    continuation.resume(returning: lease)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .queued:
                    observer?()
                }
            }
        } onCancel: {
            cancelWaiter(waiter)
        }
    }

    /// Ends the turn identified by `lease` and hands ownership to the next live waiter.
    ///
    /// Safe to call from any thread or executor, any number of times: a duplicate or stale lease
    /// is ignored, so re-running a finished fixture's cleanup can never end the current owner's
    /// turn. Everything the caller did before calling `release` happens-before the next owner
    /// observes the gate.
    func release(_ lease: Lease) {
        var handoff: (continuation: CheckedContinuation<Lease, any Error>, lease: Lease)?
        lock.lock()
        if isHeld, lease.gateID == gateID, lease.id == currentLeaseID {
            while !waiters.isEmpty {
                let waiter = waiters.removeFirst()
                guard !waiter.isSettled, !waiter.isCancelled, let continuation = waiter.continuation else {
                    continue
                }
                waiter.continuation = nil
                waiter.isSettled = true
                handoff = (continuation, makeLeaseLocked())
                break
            }
            if handoff == nil {
                isHeld = false
                currentLeaseID = 0
            }
        }
        lock.unlock()

        // Resumed outside the lock: the next owner must never run gate code re-entrantly.
        if let handoff {
            handoff.continuation.resume(returning: handoff.lease)
        }
    }

    /// Installs a one-shot hook awaited by the next `acquire` after its cancellation handler is
    /// installed and before it registers as a waiter. Consumed by the first caller that reaches
    /// that point, so it cannot leak into later acquisitions.
    func installOneShotRegistrationHook(_ hook: @escaping @Sendable () async -> Void) {
        lock.lock()
        oneShotRegistrationHook = hook
        lock.unlock()
    }

    /// Installs a callback invoked (outside the lock) whenever a caller has been queued behind
    /// the current owner. Pass `nil` to remove it.
    func setWaiterEnqueuedObserver(_ observer: (@Sendable () -> Void)?) {
        lock.lock()
        waiterEnqueuedObserver = observer
        lock.unlock()
    }

    // MARK: Private

    /// One acquisition attempt. Every field is read and written under the gate's lock, which is
    /// also what makes it safe to share between the acquiring task and its cancellation handler.
    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<Lease, any Error>?
        var isCancelled = false
        /// Set once the acquisition has been resolved — granted or cancelled. A settled waiter is
        /// never resumed again, which is what keeps a late cancellation from stealing a granted
        /// turn back from its owner.
        var isSettled = false
    }

    private enum AcquireOutcome {
        case granted(Lease)
        case cancelled
        case queued
    }

    private let lock = NSLock()
    private let gateID = UUID()
    private var isHeld = false
    private var currentLeaseID: UInt64 = 0
    private var nextLeaseID: UInt64 = 1
    private var waiters: [Waiter] = []
    private var oneShotRegistrationHook: (@Sendable () async -> Void)?
    private var waiterEnqueuedObserver: (@Sendable () -> Void)?

    /// Requires `lock` to be held.
    private func makeLeaseLocked() -> Lease {
        let lease = Lease(gateID: gateID, id: nextLeaseID)
        nextLeaseID += 1
        currentLeaseID = lease.id
        return lease
    }

    private func cancelWaiter(_ waiter: Waiter) {
        var continuation: CheckedContinuation<Lease, any Error>?
        lock.lock()
        if !waiter.isSettled {
            waiter.isCancelled = true
            if let queued = waiter.continuation {
                // Already registered: unqueue it now so the turn is never handed to a caller
                // that has gone away.
                waiter.continuation = nil
                waiter.isSettled = true
                waiters.removeAll { $0 === waiter }
                continuation = queued
            }
            // Otherwise the caller has not registered yet; `isCancelled` makes it exit on arrival
            // without taking the turn.
        }
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
    }

    private func takeRegistrationHook() -> (@Sendable () async -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let hook = oneShotRegistrationHook
        oneShotRegistrationHook = nil
        return hook
    }
}

// MARK: - Shared instance

/// Process-wide gate every `CertificateStore` override fixture must go through.
let certificateFixtureGate = CertificateFixtureGate()
