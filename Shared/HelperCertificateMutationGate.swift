import Foundation

// MARK: - HelperCertificateMutationGate

/// Process-wide exclusive gate for the privileged helper's certificate mutations.
///
/// NSXPCConnection delivers messages concurrently, so two clients — or one client retrying after
/// a timeout — can have installs and removals running against the same System keychain at the
/// same time. Every one of those operations is built as read, mutate, verify; interleaving them
/// means a verification can read the other operation's result and a removal can delete the
/// certificate an install just added.
///
/// The gate is deliberately **non-blocking**. A busy request is refused immediately, before it
/// mutates anything, so nothing is queued to run later against state the caller can no longer
/// see: a client that gave up at its own timeout must not have privileged work start afterwards.
/// Reads are never gated — reporting "not installed" because another operation held the gate
/// would be a wrong answer, not a busy one.
final class HelperCertificateMutationGate: @unchecked Sendable {
    // MARK: Internal

    /// Proof of ownership for one mutation.
    ///
    /// `release` acts only when the ticket matches the mutation currently held, so a duplicate or
    /// stale release can never end a later owner's turn.
    struct Ticket: Equatable {
        fileprivate let id: UUID
    }

    /// One gate per helper process. Every mutating entry point shares it, so an install and a
    /// removal exclude each other and not just their own kind.
    static let shared = HelperCertificateMutationGate()

    /// What a refused caller is told. Phrased so it reads as "try again", never as a result.
    static let busyMessage =
        "Another Rockxy certificate operation is already running. Wait for it to finish, then try again."

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heldTicketID != nil
    }

    /// Takes the gate, or returns `nil` when another mutation already owns it. Never waits.
    func tryAcquire() -> Ticket? {
        lock.lock()
        defer { lock.unlock() }

        guard heldTicketID == nil else {
            return nil
        }
        let ticket = Ticket(id: UUID())
        heldTicketID = ticket.id
        return ticket
    }

    func release(_ ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }

        guard heldTicketID == ticket.id else {
            return
        }
        heldTicketID = nil
    }

    /// Runs `body` under the gate, or returns `nil` without running it when the gate is busy.
    ///
    /// The gate is released before the caller replies, so an XPC reply handler that starts the
    /// next operation cannot be refused by the operation that just finished.
    func withExclusiveAccess<T>(_ body: () throws -> T) rethrows -> T? {
        guard let ticket = tryAcquire() else {
            return nil
        }
        defer { release(ticket) }
        return try body()
    }

    // MARK: Private

    private let lock = NSLock()
    private var heldTicketID: UUID?
}
