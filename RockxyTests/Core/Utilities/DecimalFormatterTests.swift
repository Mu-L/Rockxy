import Foundation
@testable import Rockxy
import Testing

/// Every number Rockxy shows with a decimal part comes from `DecimalFormatter`, so one window
/// never mixes separators. `String(format: "%.2f")` takes no locale and always emits a POSIX
/// period, while `ByteCountFormatter` follows the locale — on `en_VN`, the maintainer's own
/// locale, the Context Dock read a duration of "5.64 s" beside a footer total of "1,5 MB".
struct DecimalFormatterTests {
    // MARK: Internal

    @Test("The decimal separator follows the locale")
    func separatorIsLocaleDependent() {
        #expect(DecimalFormatter.format(1.5, fractionDigits: 2, locale: Locale(identifier: "en_US")) == "1.50")
        #expect(DecimalFormatter.format(1.5, fractionDigits: 2, locale: Locale(identifier: "en_VN")) == "1,50")
        #expect(DecimalFormatter.format(1.5, fractionDigits: 2, locale: Locale(identifier: "de_DE")) == "1,50")
        // The bug is exactly this inequality: a hand-rolled "%.2f" prints the first spelling for
        // every one of these locales.
        #expect(
            DecimalFormatter.format(1.5, fractionDigits: 2, locale: Locale(identifier: "en_US"))
                != DecimalFormatter.format(1.5, fractionDigits: 2, locale: Locale(identifier: "de_DE"))
        )
    }

    @Test("A duration and a byte count agree on their separator")
    func durationsAndSizesUseOneSeparator() {
        // The live divergence: both of these come from the same Context Dock.
        let duration = DurationFormatter.format(seconds: 5.64, locale: Locale(identifier: "en_VN"))
        let separator = Locale(identifier: "en_VN").decimalSeparator ?? "."

        #expect(duration.contains(separator))
        #expect(!duration.contains("."))
    }

    @Test("The percent sign is placed by the locale")
    func percentSignFollowsTheLocale() {
        // `de_DE` and `fr_FR` write "45 %" with a non-breaking space, so a hand-appended "%" is
        // wrong in the same way a hand-appended separator is.
        let german = DecimalFormatter.percent(45, locale: Locale(identifier: "de_DE"))
        let american = DecimalFormatter.percent(45, locale: Locale(identifier: "en_US"))

        #expect(american == "45%")
        #expect(german != american)
        #expect(german.contains("45"))
        #expect(DecimalFormatter.percent(2.5, fractionDigits: 1, locale: Locale(identifier: "en_US")) == "2.5%")
    }

    @Test("No surface formats a fractional number by hand")
    func noSurfaceFormatsAFractionByHand() throws {
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.fractionFormatOwners.contains(path) {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                guard Self.formatsAFractionByHand(text) else {
                    continue
                }
                offenders.append("\(path):\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines render a fractional number without DecimalFormatter: \(offenders.sorted())"
        )
    }

    @Test("No surface appends a percent sign by hand")
    func noSurfaceAppendsAPercentSign() throws {
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.percentSignOwners.contains(path) {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                guard Self.appendsAPercentSign(text) else {
                    continue
                }
                offenders.append("\(path):\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines append a percent sign by hand: \(offenders.sorted())"
        )
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// `DecimalFormatter` itself, plus `MCPProtocolMessages`, whose output is machine-readable
    /// JSON pinned to a fixed spelling on purpose — the same exemption `TimestampFormatter` grants.
    private static let fractionFormatOwners: Set<String> = [
        "Rockxy/Core/Utilities/DecimalFormatter.swift",
    ]

    /// A `String(localized:)` key may carry a literal `%%`: that is the catalog's own escape and
    /// the translator decides the placement. Only an interpolation with a bare `%` glued to it is
    /// a hand-built percentage.
    private static let percentSignOwners: Set<String> = [
        "Rockxy/Core/Utilities/DecimalFormatter.swift",
    ]

    /// A `String(format:)` conversion with a fractional part — "%.1f", "%.2f", "%g" — is a number
    /// being spelled out without a locale.
    private static let fractionFormatPattern = try? NSRegularExpression(
        pattern: #"String\(format: "[^"]*%[-0-9]*\.[0-9]+[fFeEgG]"#
    )

    /// An interpolation immediately followed by a percent sign inside a string literal.
    private static let percentSignPattern = try? NSRegularExpression(
        pattern: #"\\\([^)]*\)%(?!%)"#
    )

    private static func formatsAFractionByHand(_ line: String) -> Bool {
        guard let fractionFormatPattern, !isAComment(line) else {
            return false
        }
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return fractionFormatPattern.firstMatch(in: line, range: range) != nil
    }

    private static func appendsAPercentSign(_ line: String) -> Bool {
        guard let percentSignPattern, !isAComment(line) else {
            return false
        }
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return percentSignPattern.firstMatch(in: line, range: range) != nil
    }

    /// A doc comment explaining the bug quotes the very spelling the guard rejects.
    private static func isAComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    private static func projectSources() throws -> [(path: String, source: String)] {
        let root = try resolveProjectRoot().appendingPathComponent("Rockxy")
        let prefix = root.deletingLastPathComponent().path + "/"
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
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

    private static func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
