import Foundation
import Darwin
import Testing

/// Serializes all tests that mutate shared rule or HTTPS-decryption policy state.
///
/// Swift Testing's `@Suite(.serialized)` only serializes within a single suite.
/// When xcodebuild assigns tests from multiple suites to the same process,
/// they run concurrently and contend for the shared `RuleEngine` actor.
/// This actor-based lock forces cross-suite serialization.
actor RuleTestLock {
    // MARK: Internal

    static let shared = RuleTestLock()

    func acquire() async {
        if !isLocked {
            acquireProcessLock()
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            releaseProcessLock()
            isLocked = false
        }
    }

    // MARK: Private

    private var isLocked = false
    private var processLockFileDescriptor: Int32?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquireProcessLock() {
        let path = NSTemporaryDirectory() + "rockxy-rule-tests.lock"
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        precondition(fd >= 0, "Unable to open rule test lock file")

        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR {
                continue
            }
            close(fd)
            preconditionFailure("Unable to acquire rule test lock")
        }
        processLockFileDescriptor = fd
    }

    private func releaseProcessLock() {
        guard let fd = processLockFileDescriptor else {
            return
        }
        flock(fd, LOCK_UN)
        close(fd)
        processLockFileDescriptor = nil
    }
}

/// Holds `RuleTestLock` around an entire serialized suite so singleton-backed tests in
/// different suites cannot overwrite one another while an async assertion is suspended.
struct SharedPolicyStateTrait: SuiteTrait, TestScoping {
    let isRecursive = false

#if compiler(>=6.2)
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        try await withSharedPolicyState(performing: function)
    }
#else
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await withSharedPolicyState(performing: function)
    }
#endif

    private func withSharedPolicyState(
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await RuleTestLock.shared.acquire()
        do {
            try await function()
        } catch {
            await RuleTestLock.shared.release()
            throw error
        }
        await RuleTestLock.shared.release()
    }
}

extension SuiteTrait where Self == SharedPolicyStateTrait {
    static var sharedPolicyState: Self { Self() }
}
