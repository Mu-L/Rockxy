import Foundation
@testable import Rockxy
import Testing

// MARK: - WebSocketInspectorLayoutTests

/// Source-level contract for the WebSocket inspector layout in a short bottom inspector: the
/// connection header must never be pushed out of view, and a selected frame keeps a readable
/// payload area while the frame list keeps a couple of rows.
struct WebSocketInspectorLayoutTests {
    @Test("WebSocket inspector top-aligns overflow and bounds list/detail heights")
    func layoutKeepsHeaderAndDetailReadable() throws {
        let source = try Self.projectFile("Rockxy/Views/Inspector/WebSocketInspectorView.swift")

        #expect(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
        #expect(source.contains("frameDetail\n                            .layoutPriority(1)"))
        #expect(source.contains(".frame(minHeight: Self.minimumFrameListHeight)"))
        #expect(Self.occurrences(of: "minHeight: Self.minimumPayloadHeight", in: source) == 3)
        #expect(!source.contains("            .frame(maxHeight: 200)\n"))
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func projectFile(_ path: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
