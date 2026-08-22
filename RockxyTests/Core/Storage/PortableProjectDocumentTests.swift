import Foundation
@testable import Rockxy
import Testing

// MARK: - PortableProjectDocumentTests

@Suite("PortableProjectDocument")
struct PortableProjectDocumentTests {
    // MARK: Internal

    // MARK: Round trip

    @Test("write then read roundtrips a portable document")
    func writeReadRoundtrips() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")

        let project = Self.makeProject()
        try PortableProjectDocument.write(project, to: url)

        let loaded = try PortableProjectDocument.read(from: url)
        #expect(loaded == PortableProject(exporting: project))
    }

    @Test("exported file is written with 0600 permissions")
    func writesRestrictivePermissions() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")

        try PortableProjectDocument.write(Self.makeProject(), to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test("export temporary file is private before atomic publication")
    func temporaryFileIsPrivateBeforePublication() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        var observedMode: Int?

        try PortableProjectDocument.write(Self.makeProject(), to: url) { temporaryURL in
            let attrs = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            observedMode = attrs[.posixPermissions] as? Int
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        #expect(observedMode == 0o600)
    }

    @Test("write replaces a destination symlink without modifying its target")
    func writeDoesNotFollowDestinationSymlink() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("sensitive.txt")
        let sentinel = Data("do-not-change".utf8)
        try sentinel.write(to: target)
        let link = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try PortableProjectDocument.write(Self.makeProject(), to: link)

        #expect(try Data(contentsOf: target) == sentinel)
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect((attrs[.type] as? FileAttributeType) == .typeRegular)
        #expect(try PortableProjectDocument.read(from: link).name == "Alpha")
    }

    // MARK: Fail-closed reads

    @Test("read rejects a missing file")
    func rejectsMissingFile() {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Nope.\(PortableProjectDocument.fileExtension)")

        #expect(throws: PortableProjectDocumentError.fileMissing) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read rejects a symlink without following it")
    func rejectsSymlink() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("target.\(PortableProjectDocument.fileExtension)")
        try PortableProjectDocument.write(Self.makeProject(), to: target)
        let link = dir.appendingPathComponent("link.\(PortableProjectDocument.fileExtension)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: PortableProjectDocumentError.symbolicLink) {
            _ = try PortableProjectDocument.read(from: link)
        }
    }

    @Test("read remains bound to the opened inode when the pathname is replaced")
    func readUsesOpenedInodeAcrossPathReplacement() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let selected = dir.appendingPathComponent("selected.\(PortableProjectDocument.fileExtension)")
        let opened = dir.appendingPathComponent("opened.\(PortableProjectDocument.fileExtension)")
        let replacement = dir.appendingPathComponent("replacement.\(PortableProjectDocument.fileExtension)")
        try PortableProjectDocument.write(Self.makeProject(), to: selected)
        let oversized = Data(repeating: 0x20, count: PortableProjectDocument.maxDocumentByteSize + 1)
        try oversized.write(to: replacement)

        let loaded = try PortableProjectDocument.read(from: selected) {
            try FileManager.default.moveItem(at: selected, to: opened)
            try FileManager.default.moveItem(at: replacement, to: selected)
        }

        #expect(loaded.name == "Alpha")
    }

    @Test("read rejects a non-regular node")
    func rejectsNonRegularFile() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(throws: PortableProjectDocumentError.notRegularFile) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read rejects an oversized file before decoding")
    func rejectsOversizedFile() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        let oversized = Data(repeating: 0x20, count: PortableProjectDocument.maxDocumentByteSize + 1)
        try oversized.write(to: url)

        #expect(throws: PortableProjectDocumentError.fileTooLarge(bytes: oversized.count)) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read rejects corrupt JSON")
    func rejectsCorruptJSON() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        try Data("{ not valid json".utf8).write(to: url)

        #expect(throws: PortableProjectDocumentError.corruptData) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read rejects an unsupported format version without materializing")
    func rejectsUnsupportedFormatVersion() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")

        let future = PortableProject(
            formatVersion: 999,
            name: "Alpha",
            activeTabIndex: 0,
            tabs: [PortableProjectTab(title: "All Traffic", isClosable: false)]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(future).write(to: url)

        #expect(throws: PortableProjectDocumentError.unsupportedFormatVersion(found: 999)) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read rejects a structurally invalid document")
    func rejectsInvalidDocument() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")

        let invalid = PortableProject(
            name: "Alpha",
            activeTabIndex: 7,
            tabs: [PortableProjectTab(title: "All Traffic", isClosable: false)]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(invalid).write(to: url)

        #expect(throws: PortableProjectDocumentError.invalid(.activeTabIndexOutOfRange(index: 7))) {
            _ = try PortableProjectDocument.read(from: url)
        }
    }

    @Test("read ignores unknown JSON keys")
    func ignoresUnknownKeys() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Alpha.\(PortableProjectDocument.fileExtension)")
        let json = """
        {
          "formatVersion": 1,
          "name": "Alpha",
          "activeTabIndex": 0,
          "tabs": [
            {"title": "All Traffic", "isClosable": false, "filter": \(Self.emptyFilterJSON),
             "advancedFilterRows": [], "isFilterBarVisible": false, "mainTabRawValue": "traffic",
             "inspectorLayoutRawValue": "hidden", "isContextDockVisible": false,
             "contextDockTabRawValue": "details", "focusNavigatorModeRawValue": "browse",
             "mutedTrafficSources": []}
          ],
          "unexpectedFutureKey": {"nested": true}
        }
        """
        try Data(json.utf8).write(to: url)

        let loaded = try PortableProjectDocument.read(from: url)
        #expect(loaded.name == "Alpha")
        #expect(loaded.tabs.count == 1)
    }

    // MARK: Private

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static let emptyFilterJSON: String = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(FilterCriteriaSnapshot.empty)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }()

    private static func makeProject() -> Project {
        Project.makeDefault(name: "Alpha", createdAt: fixedDate, updatedAt: fixedDate)
    }

    private static func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy.PortableProjectDocumentTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
