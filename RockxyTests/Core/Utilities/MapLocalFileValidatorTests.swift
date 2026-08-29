import Foundation
@testable import Rockxy
import Testing

struct MapLocalFileValidatorTests {
    // MARK: Internal

    @Test("loads regular file data")
    func loadsRegularFile() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("response.json")
        try Data(#"{"status":"ok"}"#.utf8).write(to: file)

        let data = try #require(MapLocalFileValidator.loadFileData(at: file.path))
        #expect(String(data: data, encoding: .utf8) == #"{"status":"ok"}"#)
    }

    @Test("returns nil for nonexistent file")
    func rejectsMissingFile() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-missing-\(UUID().uuidString).json")
            .path

        #expect(MapLocalFileValidator.loadFileData(at: path) == nil)
    }

    @Test("rejects directories")
    func rejectsDirectory() throws {
        let directory = try makeDirectory()
        #expect(MapLocalFileValidator.loadFileData(at: directory.path) == nil)
    }

    @Test("rejects oversized files")
    func rejectsOversizedFile() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("large.bin")
        let data = Data(repeating: 0x41, count: (10 * 1_024 * 1_024) + 1)
        try data.write(to: file)

        #expect(MapLocalFileValidator.loadFileData(at: file.path) == nil)
    }

    @Test("serves an empty file as zero-length data")
    func loadsEmptyFile() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("empty.json")
        try Data().write(to: file)

        let data = try #require(MapLocalFileValidator.loadFileData(at: file.path))
        #expect(data.isEmpty)
    }

    @Test("serves binary file content byte-for-byte")
    func loadsBinaryFile() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("payload.bin")
        let bytes = Data([0x00, 0x01, 0xFF, 0x7F, 0x89, 0x50])
        try bytes.write(to: file)

        let data = try #require(MapLocalFileValidator.loadFileData(at: file.path))
        #expect(data == bytes)
    }

    @Test("expands tilde paths")
    func expandsTildePath() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = home.appendingPathComponent("RockxyTests-MapLocal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("tilde.txt")
        try Data("hello".utf8).write(to: file)
        let tildePath = "~/" + file.path.replacingOccurrences(of: home.path + "/", with: "")

        let data = try #require(MapLocalFileValidator.loadFileData(at: tildePath))
        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    // MARK: Private

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
