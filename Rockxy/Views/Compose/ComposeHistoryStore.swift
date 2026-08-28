import Foundation
import os

// Persists Compose history snapshots outside the active window lifecycle.

// MARK: - ComposeHistoryStore

/// Disk-backed storage for Compose history.
///
/// Request history can contain sensitive payloads. The live in-memory history keeps
/// exact request headers so same-session restore is lossless, but persisted entries
/// redact Authorization/Cookie-style headers before the JSON file is written.
final class ComposeHistoryStore: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        fileURL: URL? = nil,
        maxEntries: Int = ComposeHistoryStore.defaultMaxEntries,
        bodySizeLimit: Int = ComposeHistoryStore.defaultBodySizeLimit,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maxEntries = maxEntries
        self.bodySizeLimit = bodySizeLimit
        self.fileManager = fileManager
    }

    // MARK: Internal

    static let defaultMaxEntries = 200
    static let defaultBodySizeLimit = 256 * 1_024

    static var live: ComposeHistoryStore {
        ComposeHistoryStore()
    }

    let maxEntries: Int
    let bodySizeLimit: Int

    func load() -> [ComposeHistoryEntry] {
        if let cachedEntries = persistenceCoordinator.cachedEntries(for: fileURL) {
            return cachedEntries
        }
        let loadedEntries: [ComposeHistoryEntry]
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return persistenceCoordinator.cacheLoadedEntriesIfAbsent([], for: fileURL)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            loadedEntries = try decoder.decode([ComposeHistoryEntry].self, from: data)
        } catch {
            Self.logger.error("Failed to load compose history: \(error.localizedDescription)")
            loadedEntries = []
        }
        return persistenceCoordinator.cacheLoadedEntriesIfAbsent(loadedEntries, for: fileURL)
    }

    func save(_ entries: [ComposeHistoryEntry]) async throws {
        let revision = persistenceCoordinator.prepareSave(entries, for: fileURL)
        let maxEntries = maxEntries
        let bodySizeLimit = bodySizeLimit
        let data = try await Task.detached(priority: .utility) {
            let cappedEntries = Array(entries.prefix(maxEntries)).map {
                Self.entryForPersistence($0, bodySizeLimit: bodySizeLimit)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(cappedEntries)
        }.value
        try await persistenceCoordinator.write(data, to: fileURL, revision: revision)
    }

    func boundedEntry(_ entry: ComposeHistoryEntry) async -> ComposeHistoryEntry {
        let bodySizeLimit = bodySizeLimit
        return await Task.detached(priority: .utility) {
            Self.boundedEntry(entry, bodySizeLimit: bodySizeLimit)
        }.value
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ComposeHistoryStore")

    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let persistenceCoordinator = ComposeHistoryPersistenceCoordinator.shared

    private static func defaultFileURL() -> URL {
        if RockxyIdentity.isRunningTests {
            return RockxyIdentity.current.appSupportPath("compose-history-\(UUID().uuidString).json")
        }
        return RockxyIdentity.current.appSupportPath("compose-history.json")
    }

    private static func boundedEntry(
        _ entry: ComposeHistoryEntry,
        bodySizeLimit: Int
    )
        -> ComposeHistoryEntry
    {
        let bodySnapshot = capped(entry.body, maximumBytes: bodySizeLimit)
        let responseSnapshot = entry.responseBody.map {
            capped($0, maximumBytes: bodySizeLimit)
        }
        return ComposeHistoryEntry(
            id: entry.id,
            method: entry.method,
            url: entry.url,
            headers: entry.headers,
            queryItems: entry.queryItems,
            body: bodySnapshot.value,
            bodyContentType: entry.bodyContentType,
            statusCode: entry.statusCode,
            responseHeaders: entry.responseHeaders,
            responseBody: responseSnapshot?.value,
            bodyTruncated: entry.bodyTruncated || bodySnapshot.truncated,
            responseBodyTruncated: entry.responseBodyTruncated || (responseSnapshot?.truncated ?? false),
            timestamp: entry.timestamp
        )
    }

    private static func entryForPersistence(
        _ entry: ComposeHistoryEntry,
        bodySizeLimit: Int
    )
        -> ComposeHistoryEntry
    {
        let boundedEntry = boundedEntry(entry, bodySizeLimit: bodySizeLimit)
        return ComposeHistoryEntry(
            id: boundedEntry.id,
            method: boundedEntry.method,
            url: boundedEntry.url,
            headers: redacted(boundedEntry.headers),
            queryItems: boundedEntry.queryItems,
            body: boundedEntry.body,
            bodyContentType: boundedEntry.bodyContentType,
            statusCode: boundedEntry.statusCode,
            responseHeaders: boundedEntry.responseHeaders.map(redacted),
            responseBody: boundedEntry.responseBody,
            bodyTruncated: boundedEntry.bodyTruncated,
            responseBodyTruncated: boundedEntry.responseBodyTruncated,
            timestamp: boundedEntry.timestamp
        )
    }

    private static func redacted(_ headers: [EditableReplayHeader]) -> [EditableReplayHeader] {
        headers.map { header in
            guard SensitiveDataRedactor.sensitiveHeaders.contains(header.name.lowercased()) else {
                return header
            }
            return EditableReplayHeader(
                id: header.id,
                name: header.name,
                value: String(localized: "<redacted before saving>", bundle: RockxyLocalization.bundle),
                isEnabled: false
            )
        }
    }

    private static func capped(
        _ text: String,
        maximumBytes: Int
    )
        -> (value: String, truncated: Bool)
    {
        guard text.utf8.count > maximumBytes else {
            return (text, false)
        }
        var result = ""
        var byteCount = 0
        for character in text {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumBytes else {
                break
            }
            result.append(character)
            byteCount += characterByteCount
        }
        return (result, true)
    }
}

// MARK: - ComposeHistoryPersistenceCoordinator

private final class ComposeHistoryPersistenceCoordinator: @unchecked Sendable {
    // MARK: Internal

    static let shared = ComposeHistoryPersistenceCoordinator()

    func cachedEntries(for fileURL: URL) -> [ComposeHistoryEntry]? {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntriesByURL[fileURL]
    }

    func cacheLoadedEntriesIfAbsent(
        _ entries: [ComposeHistoryEntry],
        for fileURL: URL
    )
        -> [ComposeHistoryEntry]
    {
        lock.lock()
        defer { lock.unlock() }
        if let cachedEntries = cachedEntriesByURL[fileURL] {
            return cachedEntries
        }
        cachedEntriesByURL[fileURL] = entries
        return entries
    }

    func prepareSave(_ entries: [ComposeHistoryEntry], for fileURL: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let revision = (revisionByURL[fileURL] ?? 0) + 1
        revisionByURL[fileURL] = revision
        cachedEntriesByURL[fileURL] = entries
        return revision
    }

    func write(_ data: Data, to fileURL: URL, revision: Int) async throws {
        try await writer.write(data, to: fileURL, revision: revision)
    }

    // MARK: Private

    private let lock = NSLock()
    private let writer = ComposeHistoryWriter()
    private var cachedEntriesByURL: [URL: [ComposeHistoryEntry]] = [:]
    private var revisionByURL: [URL: Int] = [:]
}

// MARK: - ComposeHistoryWriter

private actor ComposeHistoryWriter {
    // MARK: Internal

    func write(_ data: Data, to fileURL: URL, revision: Int) throws {
        guard revision > (latestRevisionByURL[fileURL] ?? 0) else {
            return
        }
        latestRevisionByURL[fileURL] = revision
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Private

    private var latestRevisionByURL: [URL: Int] = [:]
}
