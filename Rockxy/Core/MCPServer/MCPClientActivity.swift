import Foundation

// MARK: - MCPClientActivity

/// Non-sensitive operational metadata about the most recent MCP client. Captures only
/// the client's self-reported name/version and the last validated method name; never
/// payloads, arguments, tokens, headers, traffic data, session IDs, or addresses.
struct MCPClientActivity: Equatable, Sendable {
    // MARK: Lifecycle

    init(clientName: String, clientVersion: String, initializedAt: Date) {
        self.clientName = Self.bounded(clientName)
        self.clientVersion = Self.bounded(clientVersion)
        self.initializedAt = initializedAt
        lastMethod = "initialize"
        lastActivityAt = initializedAt
    }

    // MARK: Internal

    /// Upper bound applied to the client-supplied name and version strings.
    static let maxIdentifierLength = 128

    let clientName: String
    let clientVersion: String
    let initializedAt: Date
    private(set) var lastMethod: String
    private(set) var lastActivityAt: Date

    mutating func recordMethod(_ method: String, at date: Date) {
        lastMethod = Self.bounded(method)
        lastActivityAt = date
    }

    // MARK: Private

    private static func bounded(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxIdentifierLength))
    }
}

// MARK: - MCPClientActivityStore

/// Thread-safe holder for the latest MCP client activity of the current server run.
/// Uses `NSLock` because it is written from NIO event loop threads and read from the
/// main actor. Only the latest activity is retained; there is no history.
final class MCPClientActivityStore: @unchecked Sendable {
    // MARK: Internal

    /// Invoked outside the lock after every change, on the calling thread. The
    /// coordinator hops to the main actor and re-reads `latest` from there.
    var onChange: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return changeHandler
        }
        set {
            lock.lock()
            changeHandler = newValue
            lock.unlock()
        }
    }

    var latest: MCPClientActivity? {
        lock.lock()
        defer { lock.unlock() }
        return activity
    }

    func recordInitialize(clientName: String, clientVersion: String, at date: Date = Date()) {
        record(MCPClientActivity(
            clientName: clientName,
            clientVersion: clientVersion,
            initializedAt: date
        ))
    }

    /// Publishes a complete per-connection snapshot. The handler owns the client
    /// identity so activity from an older connection cannot be attributed to whichever
    /// client happened to initialize most recently.
    func record(_ value: MCPClientActivity) {
        lock.lock()
        activity = value
        let handler = changeHandler
        lock.unlock()
        handler?()
    }

    func reset() {
        lock.lock()
        let hadActivity = activity != nil
        activity = nil
        let handler = changeHandler
        lock.unlock()
        if hadActivity {
            handler?()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var activity: MCPClientActivity?
    private var changeHandler: (@Sendable () -> Void)?
}
