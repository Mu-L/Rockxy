import Foundation
@testable import Rockxy
import Testing

/// Every wall-clock time Rockxy shows comes from `TimestampFormatter`, so one transaction reads
/// the same way in the request list, the Diff candidate picker, the WebSocket frame list, and the
/// script console. Two of those built a `DateFormatter` with a hardcoded `"HH:mm:ss"`, which is
/// locale-blind and ignores the user's 24-Hour Time preference: on `en_US` the request list said
/// "21:19:10" for the row the Diff picker called "9:19:10 PM".
struct TimestampFormatterTests {
    // MARK: Internal

    @Test("A time of day follows the viewer's locale and clock preference")
    func timeOfDayFollowsTheLocale() {
        // A 12-hour locale must not get a 24-hour clock, which is exactly what the fixed pattern
        // forced on every user whose region spells this time "9:19:10 PM".
        let twelveHour = Self.reference(locale: "en_US", template: "jms")
        let twentyFourHour = Self.reference(locale: "en_GB", template: "jms")

        #expect(twelveHour != twentyFourHour)
        #expect(twelveHour.contains("9"))
        #expect(twentyFourHour.contains("21"))
        // The shipped formatter follows whatever locale the test host runs under.
        #expect(TimestampFormatter.timeOfDay(Self.sample) == Self.reference(
            locale: Locale.current.identifier,
            template: "jms"
        ))
    }

    @Test("Frame timestamps keep their milliseconds")
    func frameTimestampsKeepMilliseconds() {
        // WebSocket frames arrive milliseconds apart; dropping the sub-second digits would make
        // the frame list unorderable by eye.
        let formatted = TimestampFormatter.timeOfDayWithMilliseconds(Self.sample)

        #expect(formatted == Self.reference(locale: Locale.current.identifier, template: "jmsSSS"))
        #expect(formatted.contains("123"))
        #expect(formatted != TimestampFormatter.timeOfDay(Self.sample))
    }

    @Test("No view formats a wall-clock time with a fixed pattern")
    func noViewPinsAClockFormat() throws {
        // `en_US_POSIX` with a fixed pattern is correct for machine-readable output — the MCP
        // version string parses that way on purpose — and is the only place it belongs.
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.fixedPatternOwners.contains(path) {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines where line.contains("dateFormat =") {
                offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines pin a date pattern instead of using TimestampFormatter: \(offenders.sorted())"
        )
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// 2026-09-22 21:19:10.123 local time, the row that exposed the divergence.
    private static let sample = Date(timeIntervalSince1970: 1_790_086_750.123)

    /// `MCPProtocolMessages` parses a `yyyy-MM-dd` version string with a pinned `en_US_POSIX`
    /// calendar and locale. That is machine-readable output, not a time anyone reads.
    private static let fixedPatternOwners: Set<String> = [
        "Rockxy/Core/MCPServer/MCPProtocolMessages.swift",
    ]

    private static func reference(locale identifier: String, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: identifier)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: sample)
    }

    private static func projectSources() throws -> [(path: String, source: String)] {
        var root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while root.lastPathComponent != "RockxyTests", root.path != "/" {
            root.deleteLastPathComponent()
        }
        guard root.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        root.deleteLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Rockxy")
        let prefix = root.path + "/"
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        var sources: [(path: String, source: String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else {
                continue
            }
            let resolved = url.resolvingSymlinksInPath().path
            let path = resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : resolved
            try sources.append((path, String(contentsOf: url, encoding: .utf8)))
        }
        return sources
    }
}
