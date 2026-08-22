import Foundation
import os

// MARK: - ProjectCatalogPersisting

/// Injection seam for Project catalog persistence. ``ProjectStore`` depends on
/// this protocol so tests can substitute an in-memory or faulting double and do
/// no real Application Support I/O.
protocol ProjectCatalogPersisting: Sendable {
    /// Loads the persisted catalog. A genuinely missing catalog is created and
    /// persisted immediately so its identifiers are stable across launches. Throws
    /// (without writing) for any invalid existing file.
    func load() async throws -> ProjectCatalog
    /// Atomically persists the catalog. Throws ``ProjectCatalogRepositoryError``
    /// for oversized encodings, a stale revision, or an invalid on-disk file that
    /// must not be overwritten.
    func save(_ catalog: ProjectCatalog) async throws
    /// Deliberate recovery entry point: replaces the on-disk catalog with a fresh
    /// default, preserving the prior regular file as a bounded recovery backup
    /// where safely possible. Only ever called after the user chooses to reset.
    func reset() async throws -> ProjectCatalog
}

// MARK: - ProjectCatalogRepositoryError

enum ProjectCatalogRepositoryError: Error, Equatable {
    case fileTooLarge(bytes: Int)
    case encodedCatalogTooLarge(bytes: Int)
    case notRegularFile
    case symbolicLink
    case directorySymbolicLink
    case notDirectory
    case unsupportedSchemaVersion(found: Int)
    case corruptData
    case validation(ProjectCatalogValidationError)
    case staleRevision(attempted: UInt64, current: UInt64)
}

// MARK: - ProjectCatalogRepository

/// Actor-backed versioned JSON storage for the Project catalog.
///
/// The path is constant (`projects/catalog.json`); user input never becomes a
/// path component. Reads are bounded and fail closed on a symlinked or
/// non-directory container, or a symlink, non-regular, oversized, corrupt,
/// newer-schema, or structurally invalid catalog file, and never overwrite such a
/// file. A genuinely missing catalog is created and persisted so its UUIDs are
/// stable. Writes go through a sibling temporary file with an atomic replacement,
/// `0600` file / `0700` directory permissions, and a monotonic revision guard —
/// seeded from disk before the first write — so a stale or out-of-order write
/// cannot clobber a newer or invalid catalog.
actor ProjectCatalogRepository: ProjectCatalogPersisting {
    // MARK: Lifecycle

    init(
        directoryURL: URL = RockxyIdentity.current.appSupportPath("projects"),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.now = now
        fileURL = directoryURL.appendingPathComponent(Self.catalogFileName, isDirectory: false)
        recoveryBackupURL = directoryURL.appendingPathComponent(Self.recoveryBackupFileName, isDirectory: false)
    }

    // MARK: Internal

    /// Maximum encoded/pre-read catalog size (2 MiB).
    static let maxCatalogByteSize = 2_097_152

    static let catalogFileName = "catalog.json"

    /// Fixed-name copy of the previous regular file kept by ``reset()`` so a manual
    /// recovery can inspect what was replaced. Bounded and never a symlink target.
    static let recoveryBackupFileName = "catalog.recovery.json"

    nonisolated let directoryURL: URL
    nonisolated let fileURL: URL

    func load() throws -> ProjectCatalog {
        if let existing = try readValidatedCatalog() {
            seedRevisionBaseline(with: existing.revision)
            return existing
        }
        // Genuinely missing: create and persist immediately so the identifiers are
        // stable across launches rather than regenerated until the first mutation.
        try prepareDirectory()
        let fresh = ProjectCatalog.makeDefault(now: now())
        lastPersistedRevision = 0
        try writeCatalogAtomically(fresh)
        return fresh
    }

    func save(_ catalog: ProjectCatalog) throws {
        // Revalidate the current regular file before every write. This protects not
        // only save-before-load, but also a catalog replaced or corrupted by another
        // process after this repository instance loaded it.
        try refreshRevisionBaselineFromDisk()

        guard catalog.revision > lastPersistedRevision else {
            throw ProjectCatalogRepositoryError.staleRevision(
                attempted: catalog.revision,
                current: lastPersistedRevision
            )
        }
        do {
            try catalog.validate()
        } catch let error as ProjectCatalogValidationError {
            throw ProjectCatalogRepositoryError.validation(error)
        }

        try writeCatalogAtomically(catalog)
        Self.logger.info("Persisted project catalog revision \(catalog.revision)")
    }

    func reset() throws -> ProjectCatalog {
        try prepareDirectory()
        try backUpExistingFileForRecovery()
        let fresh = ProjectCatalog.makeDefault(now: now())
        lastPersistedRevision = 0
        try writeCatalogAtomically(fresh)
        Self.logger.info("Reset project catalog to a fresh default")
        return fresh
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ProjectCatalogRepository"
    )

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let recoveryBackupURL: URL

    /// Highest revision known to be on disk; guards against stale async writes.
    private var lastPersistedRevision: UInt64 = 0

    private let encoder: JSONEncoder = {
        let configured = JSONEncoder()
        configured.outputFormatting = [.sortedKeys]
        return configured
    }()

    private let decoder = JSONDecoder()

    /// Returns the validated on-disk catalog, or `nil` when the file is genuinely
    /// missing. Throws (without mutating) for any invalid existing node, so callers
    /// never overwrite a file they could not fully validate.
    private func readValidatedCatalog() throws -> ProjectCatalog? {
        try validateDirectoryIfPresent()

        guard let type = fileType(at: fileURL) else {
            return nil
        }
        guard type != .typeSymbolicLink else {
            throw ProjectCatalogRepositoryError.symbolicLink
        }
        guard type == .typeRegular else {
            throw ProjectCatalogRepositoryError.notRegularFile
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? Int, size > Self.maxCatalogByteSize {
            throw ProjectCatalogRepositoryError.fileTooLarge(bytes: size)
        }

        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maxCatalogByteSize else {
            throw ProjectCatalogRepositoryError.fileTooLarge(bytes: data.count)
        }

        let catalog: ProjectCatalog
        do {
            catalog = try decoder.decode(ProjectCatalog.self, from: data)
        } catch {
            throw ProjectCatalogRepositoryError.corruptData
        }

        guard catalog.schemaVersion == ProjectCatalog.currentSchemaVersion else {
            throw ProjectCatalogRepositoryError.unsupportedSchemaVersion(found: catalog.schemaVersion)
        }
        do {
            try catalog.validate()
        } catch let error as ProjectCatalogValidationError {
            throw ProjectCatalogRepositoryError.validation(error)
        }
        return catalog
    }

    private func seedRevisionBaseline(with revision: UInt64) {
        lastPersistedRevision = max(lastPersistedRevision, revision)
    }

    private func refreshRevisionBaselineFromDisk() throws {
        if let existing = try readValidatedCatalog() {
            lastPersistedRevision = max(lastPersistedRevision, existing.revision)
        }
    }

    /// Encodes, bounds, and atomically replaces the catalog file, enforcing final
    /// `0700` directory and `0600` file permissions. Permission failures surface
    /// rather than being ignored. Advances ``lastPersistedRevision`` on success.
    private func writeCatalogAtomically(_ catalog: ProjectCatalog) throws {
        let data = try encoder.encode(catalog)
        guard data.count <= Self.maxCatalogByteSize else {
            throw ProjectCatalogRepositoryError.encodedCatalogTooLarge(bytes: data.count)
        }

        try prepareDirectory()
        try assertExistingFileSafeToReplace()

        let tempURL = directoryURL.appendingPathComponent(
            ".\(UUID().uuidString).catalog.tmp",
            isDirectory: false
        )
        do {
            try data.write(to: tempURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

            if fileType(at: fileURL) != nil {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: fileURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        lastPersistedRevision = catalog.revision
    }

    /// Rejects a symlinked or non-directory container before use.
    private func validateDirectoryIfPresent() throws {
        guard let type = fileType(at: directoryURL) else {
            return
        }
        guard type != .typeSymbolicLink else {
            throw ProjectCatalogRepositoryError.directorySymbolicLink
        }
        guard type == .typeDirectory else {
            throw ProjectCatalogRepositoryError.notDirectory
        }
    }

    /// Validates the container, creating it with `0700` when absent, and always
    /// enforces final `0700` permissions on the leaf directory.
    private func prepareDirectory() throws {
        try validateDirectoryIfPresent()
        if fileType(at: directoryURL) == nil {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func assertExistingFileSafeToReplace() throws {
        guard let type = fileType(at: fileURL) else {
            return
        }
        guard type != .typeSymbolicLink else {
            throw ProjectCatalogRepositoryError.symbolicLink
        }
        guard type == .typeRegular else {
            throw ProjectCatalogRepositoryError.notRegularFile
        }
    }

    /// Preserves the previous regular catalog file as a fixed-name recovery backup
    /// when it is safe and bounded; never follows a symlink and discards any
    /// non-regular or oversized node instead of preserving it.
    private func backUpExistingFileForRecovery() throws {
        guard let type = fileType(at: fileURL) else {
            return
        }
        if let recoveryType = fileType(at: recoveryBackupURL) {
            guard recoveryType == .typeRegular || recoveryType == .typeSymbolicLink else {
                throw ProjectCatalogRepositoryError.notRegularFile
            }
            try fileManager.removeItem(at: recoveryBackupURL)
        }
        if type == .typeSymbolicLink {
            // Explicit reset may remove the link itself, but never follows it.
            try fileManager.removeItem(at: fileURL)
            return
        }
        guard type == .typeRegular else {
            throw ProjectCatalogRepositoryError.notRegularFile
        }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? Int, size > Self.maxCatalogByteSize {
            throw ProjectCatalogRepositoryError.fileTooLarge(bytes: size)
        }
        try fileManager.moveItem(at: fileURL, to: recoveryBackupURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryBackupURL.path)
    }

    /// The node type at `url` using `lstat` semantics (a symlink reports itself),
    /// or `nil` when nothing exists there.
    private func fileType(at url: URL) -> FileAttributeType? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.type] as? FileAttributeType
    }
}
