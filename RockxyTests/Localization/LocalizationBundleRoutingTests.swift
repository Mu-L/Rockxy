import Foundation
@testable import Rockxy
import Testing

/// SwiftUI resolves a `Text("…")`, `Section("…")`, `TextField("…", …)` or `.help("…")` literal as a
/// `LocalizedStringKey` against **`Bundle.main`**, which follows macOS's language — not Rockxy's own
/// Language setting. `AppLanguagePreference.apply` deliberately never writes `AppleLanguages` (it
/// only clears a legacy one), so a viewer who picks 简体中文 inside Rockxy while macOS stays in
/// English gets a Chinese app with English cookie columns, header sections, and scripting labels,
/// and no relaunch fixes it. Every translatable string therefore goes through
/// `String(localized:bundle: RockxyLocalization.bundle)`.
struct LocalizationBundleRoutingTests {
    // MARK: Internal

    @Test("The app's language bundle is the one that honours the Language setting")
    func languageSettingResolvesThroughItsOwnBundle() throws {
        // The override picks an `.lproj` bundle; `Bundle.main` cannot see that choice.
        let identifier = try #require(Bundle.main.localizations.first { $0.hasPrefix("zh") })
        let path = try #require(Bundle.main.path(forResource: identifier, ofType: "lproj"))
        let overridden = try #require(Bundle(path: path))

        #expect(overridden.bundlePath != Bundle.main.bundlePath)
        // A translated key reads differently through the two bundles, which is the whole defect.
        let key = "Request Headers"
        let englishBase = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: englishBase))
        #expect(
            overridden.localizedString(forKey: key, value: nil, table: nil)
                != english.localizedString(forKey: key, value: nil, table: nil)
        )
    }

    @Test("No view passes a translatable literal to a SwiftUI initializer")
    func noViewLeavesATranslatableLiteralToBundleMain() throws {
        let catalog = try Self.catalogEntries()
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                for literal in Self.swiftUILiterals(in: text) where Self.isTranslatable(literal, in: catalog) {
                    offenders.append("\(path):\(number + 1): \(literal)")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            These literals resolve against Bundle.main instead of RockxyLocalization.bundle. \
            Wrap them in String(localized:bundle:), or mark the key "shouldTranslate": false \
            when it is a protocol token or an example value: \(offenders.sorted())
            """
        )
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
        case catalogUnreadable
    }

    /// The initializers and modifiers that take a `LocalizedStringKey` when handed a literal.
    private static let localizingCalls = [
        "Text(", "Label(", "Button(", "Toggle(", "Link(", "TextField(", "SecureField(",
        "Picker(", "Section(", "Stepper(", "Menu(",
        ".help(", ".accessibilityLabel(", ".accessibilityValue(", ".accessibilityHint(",
        ".navigationTitle(", ".navigationSubtitle(",
    ]

    /// A literal is only a defect when the catalog says it should be translated. Protocol tokens
    /// (`null`, `CONNECT`, `HttpOnly`), example URLs, and app names carry `"shouldTranslate": false`
    /// and read the same through any bundle.
    private static func isTranslatable(_ literal: String, in catalog: [String: Any]) -> Bool {
        guard let entry = catalog[literal] as? [String: Any] else {
            return false
        }
        return (entry["shouldTranslate"] as? Bool) != false
    }

    /// The string literals passed as the first argument of a localizing call on this line.
    private static func swiftUILiterals(in line: String) -> [String] {
        var literals: [String] = []
        for call in localizingCalls {
            var searchStart = line.startIndex
            while let range = line.range(of: call + "\"", range: searchStart ..< line.endIndex) {
                let contentStart = line.index(range.upperBound, offsetBy: 0)
                var cursor = contentStart
                var escaped = false
                var literal = ""
                while cursor < line.endIndex {
                    let character = line[cursor]
                    if escaped {
                        literal.append("\\")
                        literal.append(character)
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        break
                    } else {
                        literal.append(character)
                    }
                    cursor = line.index(after: cursor)
                }
                if cursor < line.endIndex {
                    literals.append(literal)
                }
                searchStart = range.upperBound
            }
        }
        return literals
    }

    private static func catalogEntries() throws -> [String: Any] {
        var root = try projectRoot()
        root.appendPathComponent("Rockxy/Localizable.xcstrings")
        let data = try Data(contentsOf: root)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = object["strings"] as? [String: Any]
        else {
            throw ResolveError.catalogUnreadable
        }
        return strings
    }

    private static func projectRoot() throws -> URL {
        var root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while root.lastPathComponent != "RockxyTests", root.path != "/" {
            root.deleteLastPathComponent()
        }
        guard root.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        root.deleteLastPathComponent()
        return root
    }

    private static func projectSources() throws -> [(path: String, source: String)] {
        let root = try projectRoot()
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
