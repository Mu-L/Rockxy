import Foundation

// MARK: - TrafficCaptureContext

/// Immutable logical ownership captured when a request begins.
///
/// The proxy listener remains app-wide, but every completed transaction is routed
/// back to the Project and capture session that owned its request start. The
/// generation changes when that session is cleared, so late completions from the
/// cleared generation cannot reappear in the new history.
struct TrafficCaptureContext: Equatable, Hashable, Sendable {
    let projectID: UUID
    let sessionID: UUID
    let generation: UInt64
}

// MARK: - TrafficCaptureContextStore

/// Lock-backed bridge between main-actor Project selection and SwiftNIO event-loop
/// threads. NIO handlers take a synchronous snapshot; they never reach into UI or
/// actor-isolated state while a request is being decoded.
final class TrafficCaptureContextStore: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ context: TrafficCaptureContext? = nil) {
        currentContext = context
    }

    // MARK: Internal

    func snapshot() -> TrafficCaptureContext? {
        lock.lock()
        defer { lock.unlock() }
        return currentContext
    }

    func update(_ context: TrafficCaptureContext?) {
        lock.lock()
        currentContext = context
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var currentContext: TrafficCaptureContext?
}
