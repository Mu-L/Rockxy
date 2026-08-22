import Foundation
@testable import Rockxy
import Testing

// MARK: - ProjectCatalogRepositoryTests

@Suite("ProjectCatalogRepository")
struct ProjectCatalogRepositoryTests {
    // MARK: Load: missing & roundtrip

    @Test("missing file yields a valid default catalog")
    func missingFileYieldsDefault() async throws {
        let repo = makeRepo()
        let catalog = try await repo.load()
        #expect(catalog.projects.count == 1)
        try catalog.validate()
    }

    @Test("save then load roundtrips the catalog")
    func roundtrips() async throws {
        let repo = makeRepo()
        let original = ProjectCatalog.makeDefault(now: Self.fixedDate)
        try await repo.save(original)
        let loaded = try await repo.load()
        #expect(loaded == original)
    }

    @Test("a missing catalog is created, persisted, and stable across loads")
    func missingCatalogPersistsStableIdentity() async throws {
        let repo = makeRepo()
        let first = try await repo.load()
        #expect(FileManager.default.fileExists(atPath: repo.fileURL.path))
        // Reloading reads the persisted file, so identifiers survive relaunches.
        let second = try await repo.load()
        #expect(second == first)
        #expect(second.projects[0].id == first.projects[0].id)
        #expect(second.activeProjectID == first.activeProjectID)
    }

    // MARK: Load: fail-closed inputs

    @Test("rejects a newer schema version without overwriting")
    func rejectsNewerSchema() async throws {
        let repo = makeRepo()
        var catalog = ProjectCatalog.makeDefault(now: Self.fixedDate)
        catalog.schemaVersion = 2
        try writeCatalog(catalog, to: repo)

        await #expect(throws: ProjectCatalogRepositoryError.unsupportedSchemaVersion(found: 2)) {
            _ = try await repo.load()
        }
    }

    @Test("rejects corrupt JSON")
    func rejectsCorruptJSON() async throws {
        let repo = makeRepo()
        try writeRaw(Data("{ not valid json".utf8), to: repo)
        await #expect(throws: ProjectCatalogRepositoryError.corruptData) {
            _ = try await repo.load()
        }
    }

    @Test("rejects an oversized file before decoding")
    func rejectsOversizedFile() async throws {
        let repo = makeRepo()
        let oversized = Data(repeating: 0x20, count: ProjectCatalogRepository.maxCatalogByteSize + 1)
        try writeRaw(oversized, to: repo)
        await #expect(throws: ProjectCatalogRepositoryError.self) {
            _ = try await repo.load()
        }
    }

    @Test("rejects a symlink target")
    func rejectsSymlink() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(at: repo.directoryURL, withIntermediateDirectories: true)
        let target = repo.directoryURL.appendingPathComponent("target.json")
        let encoder = JSONEncoder()
        try encoder.encode(ProjectCatalog.makeDefault(now: Self.fixedDate)).write(to: target)
        try FileManager.default.createSymbolicLink(at: repo.fileURL, withDestinationURL: target)

        await #expect(throws: ProjectCatalogRepositoryError.symbolicLink) {
            _ = try await repo.load()
        }
    }

    @Test("rejects a non-regular target")
    func rejectsNonRegularFile() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(at: repo.fileURL, withIntermediateDirectories: true)
        await #expect(throws: ProjectCatalogRepositoryError.notRegularFile) {
            _ = try await repo.load()
        }
    }

    @Test("rejects a symlinked projects directory without following it")
    func rejectsDirectorySymlink() async throws {
        let repo = makeRepo()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy.dirTarget.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repo.directoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: repo.directoryURL, withDestinationURL: target)

        await #expect(throws: ProjectCatalogRepositoryError.directorySymbolicLink) {
            _ = try await repo.load()
        }
    }

    @Test("rejects a non-directory projects container")
    func rejectsNonDirectoryContainer() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(
            at: repo.directoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(to: repo.directoryURL)

        await #expect(throws: ProjectCatalogRepositoryError.notDirectory) {
            _ = try await repo.load()
        }
    }

    @Test("rejects duplicate project IDs")
    func rejectsDuplicateProjectIDs() async throws {
        let repo = makeRepo()
        let shared = UUID()
        let catalog = ProjectCatalog(
            activeProjectID: shared,
            projects: [
                Project.makeDefault(id: shared, name: "Alpha", createdAt: Self.fixedDate, updatedAt: Self.fixedDate),
                Project.makeDefault(id: shared, name: "Beta", createdAt: Self.fixedDate, updatedAt: Self.fixedDate),
            ]
        )
        try writeCatalog(catalog, to: repo)

        await #expect(throws: ProjectCatalogRepositoryError.validation(.duplicateProjectID(shared))) {
            _ = try await repo.load()
        }
    }

    @Test("rejects an unresolved active project ID")
    func rejectsInvalidActiveID() async throws {
        let repo = makeRepo()
        let catalog = ProjectCatalog(
            activeProjectID: UUID(),
            projects: [Project.makeDefault(name: "Alpha", createdAt: Self.fixedDate, updatedAt: Self.fixedDate)]
        )
        try writeCatalog(catalog, to: repo)

        await #expect(throws: ProjectCatalogRepositoryError.validation(.unresolvedActiveProjectID)) {
            _ = try await repo.load()
        }
    }

    @Test("an invalid file is preserved, never silently overwritten by load")
    func invalidFilePreserved() async throws {
        let repo = makeRepo()
        let corrupt = Data("{ corrupt".utf8)
        try writeRaw(corrupt, to: repo)
        await #expect(throws: ProjectCatalogRepositoryError.corruptData) {
            _ = try await repo.load()
        }
        let after = try Data(contentsOf: repo.fileURL)
        #expect(after == corrupt)
    }

    // MARK: Write: permissions, atomicity, cleanup

    @Test("writes with 0600 file and 0700 directory permissions")
    func writesRestrictivePermissions() async throws {
        let repo = makeRepo()
        try await repo.save(ProjectCatalog.makeDefault(now: Self.fixedDate))

        let fileAttrs = try FileManager.default.attributesOfItem(atPath: repo.fileURL.path)
        #expect((fileAttrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: repo.directoryURL.path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
    }

    @Test("leaves no temporary files after a successful write")
    func cleansUpTemporaryFiles() async throws {
        let repo = makeRepo()
        try await repo.save(ProjectCatalog.makeDefault(now: Self.fixedDate))
        let contents = try FileManager.default.contentsOfDirectory(atPath: repo.directoryURL.path)
        #expect(!contents.contains { $0.hasSuffix(".tmp") })
        #expect(contents.contains(ProjectCatalogRepository.catalogFileName))
    }

    // MARK: Write: stale revision guard

    @Test("rejects a stale revision but accepts a newer one")
    func rejectsStaleRevision() async throws {
        let repo = makeRepo()
        let base = ProjectCatalog.makeDefault(now: Self.fixedDate)

        try await repo.save(withRevision(base, 5))
        await #expect(throws: ProjectCatalogRepositoryError.staleRevision(attempted: 3, current: 5)) {
            try await repo.save(withRevision(base, 3))
        }
        try await repo.save(withRevision(base, 6))
        let loaded = try await repo.load()
        #expect(loaded.revision == 6)
    }

    @Test("a save that never followed a load will not clobber a newer on-disk catalog")
    func saveBeforeLoadRejectsStale() async throws {
        let repo = makeRepo()
        let existing = withRevision(ProjectCatalog.makeDefault(now: Self.fixedDate), 10)
        try writeCatalog(existing, to: repo)

        await #expect(throws: ProjectCatalogRepositoryError.staleRevision(attempted: 5, current: 10)) {
            try await repo.save(withRevision(ProjectCatalog.makeDefault(now: Self.fixedDate), 5))
        }
        let onDisk = try await repo.load()
        #expect(onDisk.revision == 10)
        #expect(onDisk == existing)
    }

    @Test("a save that never followed a load refuses to overwrite a corrupt catalog")
    func saveBeforeLoadRefusesCorrupt() async throws {
        let repo = makeRepo()
        let corrupt = Data("{ corrupt".utf8)
        try writeRaw(corrupt, to: repo)

        await #expect(throws: ProjectCatalogRepositoryError.corruptData) {
            try await repo.save(ProjectCatalog.makeDefault(now: Self.fixedDate))
        }
        #expect(try Data(contentsOf: repo.fileURL) == corrupt)
    }

    @Test("save refuses a catalog corrupted after this repository loaded it")
    func saveAfterLoadRefusesExternalCorruption() async throws {
        let repo = makeRepo()
        let loaded = try await repo.load()
        let corrupt = Data("{ externally corrupt".utf8)
        try corrupt.write(to: repo.fileURL)

        await #expect(throws: ProjectCatalogRepositoryError.corruptData) {
            try await repo.save(withRevision(loaded, loaded.revision + 1))
        }

        #expect(try Data(contentsOf: repo.fileURL) == corrupt)
    }

    // MARK: Reset / recovery

    @Test("reset preserves the prior regular file as a bounded recovery backup")
    func resetPreservesRecoveryBackup() async throws {
        let repo = makeRepo()
        let corrupt = Data("{ corrupt".utf8)
        try writeRaw(corrupt, to: repo)

        let fresh = try await repo.reset()
        try fresh.validate()

        let backupURL = repo.directoryURL.appendingPathComponent(ProjectCatalogRepository.recoveryBackupFileName)
        #expect(try Data(contentsOf: backupURL) == corrupt)
        let backupAttrs = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        #expect((backupAttrs[.posixPermissions] as? Int) == 0o600)

        let reloaded = try await repo.load()
        #expect(reloaded == fresh)
    }

    @Test("reset discards a symlinked catalog without following it")
    func resetDiscardsSymlinkWithoutFollowing() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(at: repo.directoryURL, withIntermediateDirectories: true)
        let secret = repo.directoryURL.appendingPathComponent("secret.json")
        let secretData = Data("secret".utf8)
        try secretData.write(to: secret)
        try FileManager.default.createSymbolicLink(at: repo.fileURL, withDestinationURL: secret)

        _ = try await repo.reset()

        // The symlink target is untouched, and no backup was made for a symlink.
        #expect(try Data(contentsOf: secret) == secretData)
        let backupURL = repo.directoryURL.appendingPathComponent(ProjectCatalogRepository.recoveryBackupFileName)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        // The live file is now a valid regular default.
        let reloaded = try await repo.load()
        try reloaded.validate()
    }

    @Test("reset refuses to recursively remove a non-regular catalog node")
    func resetPreservesNonRegularCatalogNode() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(at: repo.fileURL, withIntermediateDirectories: true)
        let sentinel = repo.fileURL.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)

        await #expect(throws: ProjectCatalogRepositoryError.notRegularFile) {
            try await repo.reset()
        }

        #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
    }

    @Test("reset preserves an existing recovery backup when the live catalog is non-regular")
    func resetKeepsRecoveryBackupWhenLiveCatalogIsInvalid() async throws {
        let repo = makeRepo()
        try FileManager.default.createDirectory(at: repo.directoryURL, withIntermediateDirectories: true)
        let backupURL = repo.directoryURL.appendingPathComponent(ProjectCatalogRepository.recoveryBackupFileName)
        let recoveryData = Data("previous recovery".utf8)
        try recoveryData.write(to: backupURL)
        try FileManager.default.createDirectory(at: repo.fileURL, withIntermediateDirectories: true)

        await #expect(throws: ProjectCatalogRepositoryError.notRegularFile) {
            try await repo.reset()
        }

        #expect(try Data(contentsOf: backupURL) == recoveryData)
        #expect(FileManager.default.fileExists(atPath: repo.fileURL.path))
    }

    @Test("reset refuses to recursively remove a non-regular recovery node")
    func resetPreservesNonRegularRecoveryNode() async throws {
        let repo = makeRepo()
        try writeRaw(Data("{ corrupt".utf8), to: repo)
        let backupURL = repo.directoryURL.appendingPathComponent(ProjectCatalogRepository.recoveryBackupFileName)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let sentinel = backupURL.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)

        await #expect(throws: ProjectCatalogRepositoryError.notRegularFile) {
            try await repo.reset()
        }

        #expect(try Data(contentsOf: repo.fileURL) == Data("{ corrupt".utf8))
        #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
    }

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private func makeRepo() -> ProjectCatalogRepository {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy.ProjectCatalogRepositoryTests.\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        return ProjectCatalogRepository(directoryURL: dir, now: { Self.fixedDate })
    }

    private func writeRaw(_ data: Data, to repo: ProjectCatalogRepository) throws {
        try FileManager.default.createDirectory(at: repo.directoryURL, withIntermediateDirectories: true)
        try data.write(to: repo.fileURL)
    }

    private func writeCatalog(_ catalog: ProjectCatalog, to repo: ProjectCatalogRepository) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writeRaw(try encoder.encode(catalog), to: repo)
    }

    private func withRevision(_ catalog: ProjectCatalog, _ revision: UInt64) -> ProjectCatalog {
        var copy = catalog
        copy.revision = revision
        return copy
    }
}
