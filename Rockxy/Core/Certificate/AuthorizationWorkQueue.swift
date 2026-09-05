import Dispatch
import Foundation

// Runs the blocking, authorization-backed Security calls off the Swift concurrency pool, and
// carries the scheduling task's cancellation to the thread they run on.

// MARK: - AuthorizationCancellationSignal

/// The scheduling task's cancellation, readable from the authorization thread.
///
/// Authorization work runs on a plain Dispatch queue, outside any task, so `Task.isCancelled`
/// there answers for a context the work never had and is always false. This carries the real
/// answer across, so a queued operation can be refused before it starts and a multi-step one can
/// stop between two interactive calls instead of raising the second dialog.
///
/// Cancellation never interrupts a native call that is already running: an authorization dialog
/// on screen cannot be withdrawn, and reporting a cancellation for work macOS may still apply is
/// exactly the lie this type exists to avoid.
nonisolated final class AuthorizationCancellationSignal: @unchecked Sendable {
    // MARK: Internal

    /// Whether the task that scheduled this work has been cancelled.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Throws when the scheduling task has been cancelled.
    ///
    /// Call it before each step that can raise its own authorization dialog — never in the middle
    /// of one, where the write may already have been applied.
    func checkCancellation() throws {
        guard !isCancelled else {
            throw CancellationError()
        }
    }

    // MARK: Fileprivate

    fileprivate func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Claims the turn for the queued work, unless the scheduling task is already gone.
    ///
    /// The admission decision and the cancellation flag are read under the same lock, so work that
    /// is refused can never start, and the refusal is decided exactly once.
    fileprivate func admitWork() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancelled
    }

    // MARK: Private

    private let lock = NSLock()
    private var cancelled = false
}

// MARK: - AuthorizationWorkQueue

/// A serial queue for the authorization-backed Security calls, with cancellation honoured at
/// admission.
///
/// `SecTrustSettingsSetTrustSettings(.admin)` and `SecTrustSettingsRemoveTrustSettings(.admin)`
/// hold their thread for as long as the macOS dialog is on screen. On the main actor that would
/// freeze the UI behind the very dialog it is waiting for, and on a cooperative-pool thread it
/// would hold a Swift concurrency thread hostage for the whole interaction — so the call gets a
/// thread of its own and the caller suspends on a continuation instead.
///
/// The queue is serial, so a second operation waits behind whatever dialog is already up. An
/// abandoned request must not surface later as a dialog of its own, so cancellation is registered
/// before the work is enqueued and checked on the queue before anything runs.
nonisolated struct AuthorizationWorkQueue: Sendable {
    // MARK: Lifecycle

    init(label: String) {
        self.init(queue: DispatchQueue(label: label, qos: .userInitiated))
    }

    /// Runs on a caller-supplied queue. Production uses `init(label:)`; a test supplies its own
    /// queue so it can hold it the way an open dialog does.
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: Internal

    #if DEBUG
    /// Invoked on the scheduling task once `work` has been handed to the queue, so a test can
    /// cancel exactly in the window where the operation is queued and has not started.
    var enqueueObserverForTests: (@Sendable () -> Void)?
    #endif

    /// Runs one blocking, authorization-backed operation on the queue.
    ///
    /// The outcome of work that started is delivered verbatim — success or the error it threw —
    /// and the caller stays suspended until it finishes, so a mutation guard held across this
    /// await is never released while native work can still complete. Work that was cancelled
    /// before it started never runs and reports `CancellationError`. The continuation is resumed
    /// exactly once, from the queue; the cancellation handler only records the cancellation.
    func run(_ work: @escaping @Sendable (AuthorizationCancellationSignal) throws -> Void) async throws {
        let signal = AuthorizationCancellationSignal()
        #if DEBUG
        let enqueueObserver = enqueueObserverForTests
        #endif

        // Registered before the work is enqueued: a task cancelled at any point from here on sets
        // the flag the queue reads at admission.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async {
                    guard signal.admitWork() else {
                        // Queued behind an open dialog and abandoned in the meantime. Running now
                        // would raise a second dialog for work nobody is waiting for.
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try work(signal)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                #if DEBUG
                enqueueObserver?()
                #endif
            }
        } onCancel: {
            signal.cancel()
        }
    }

    // MARK: Private

    private let queue: DispatchQueue
}
