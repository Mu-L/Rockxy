import Foundation
import Testing

// MARK: - StringCatalogCoverageTests

/// Guards the Git-tracked Xcode String Catalogs. Mirrors the deterministic checks
/// in `.github/tools/validate_xcstrings.py` so regressions fail the normal test
/// job as well as CI's dedicated localization job.
///
/// Catalogs are read from the source tree via `#filePath` rather than the app
/// bundle, so the test validates the canonical JSON authors edit — not a compiled
/// artifact.
struct StringCatalogCoverageTests {
    // MARK: Internal

    @Test("Localizable.xcstrings is well-formed and fully covered")
    func localizableCatalog() throws {
        try validateCatalog(named: "Localizable.xcstrings")
    }

    @Test("InfoPlist.xcstrings is well-formed and fully covered")
    func infoPlistCatalog() throws {
        try validateCatalog(named: "InfoPlist.xcstrings")
    }

    @Test("Locale discovery ignores empty and source localization keys")
    func localeDiscoveryIgnoresInvalidKeys() {
        let catalog: [String: Any] = [
            "sourceLanguage": "en",
            "strings": [
                "Start Proxy": [
                    "localizations": [
                        "": [String: Any](),
                        "en": [String: Any](),
                        "de": [String: Any](),
                    ],
                ],
            ],
        ]

        #expect(Self.catalogLanguages(in: catalog) == ["de"])
    }

    // MARK: Private

    private static func catalogURL(_ fileName: String) -> URL {
        // <repo>/RockxyTests/Localization/StringCatalogCoverageTests.swift → <repo>/Rockxy/<fileName>
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Localization/
            .deletingLastPathComponent() // RockxyTests/
            .deletingLastPathComponent() // <repo>/
            .appendingPathComponent("Rockxy")
            .appendingPathComponent(fileName)
    }

    private static func requiredLanguages() throws -> [String] {
        var languages: Set = ["zh-Hans"]
        for fileName in ["Localizable.xcstrings", "InfoPlist.xcstrings"] {
            let data = try Data(contentsOf: catalogURL(fileName))
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let catalog = try #require(root, "\(fileName): not a JSON object")
            languages.formUnion(catalogLanguages(in: catalog))
        }
        return languages.sorted()
    }

    private static func catalogLanguages(in catalog: [String: Any]) -> Set<String> {
        guard let strings = catalog["strings"] as? [String: Any] else {
            return []
        }
        let sourceLanguage = catalog["sourceLanguage"] as? String
        var languages: Set<String> = []
        for rawEntry in strings.values {
            guard let entry = rawEntry as? [String: Any],
                  entry["shouldTranslate"] as? Bool != false,
                  let localizations = entry["localizations"] as? [String: Any] else
            {
                continue
            }
            languages.formUnion(localizations.keys.filter { !$0.isEmpty && $0 != sourceLanguage })
        }
        return languages
    }

    private static func sourceUnits(key: String, entry: [String: Any]) -> [String: String] {
        if let localizations = entry["localizations"] as? [String: Any],
           let en = localizations["en"] as? [String: Any]
        {
            let units = collectUnits(en)
            if !units.isEmpty {
                return units
            }
        }
        return ["": key]
    }

    private static func collectUnits(_ node: Any, path: [String] = []) -> [String: String] {
        guard let dictionary = node as? [String: Any] else {
            return [:]
        }

        var units: [String: String] = [:]
        if let stringUnit = dictionary["stringUnit"] as? [String: Any],
           let value = stringUnit["value"] as? String
        {
            units[path.joined(separator: "/")] = value
        }

        for (key, value) in dictionary where key != "stringUnit" {
            for (unitPath, unitValue) in collectUnits(value, path: path + [key]) {
                units[unitPath] = unitValue
            }
        }
        return units
    }

    private static func placeholderTokens(in text: String) -> [String] {
        let pattern = "%(\\d+\\$)?[-+ 0#]*[0-9]*(?:\\.[0-9]+)?(?:hh|h|ll|l|q|L|z|j|t)?[@dDiuUxXoOeEfFgGaAcCsSpn%]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var tokens: [String] = []
        for match in matches {
            let token = ns.substring(with: match.range)
            if token == "%%" {
                continue
            }
            let positional = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : ""
            let conversion = String(token.suffix(1))
            var length = ""
            for candidate in ["hh", "ll", "h", "l", "q", "L", "z", "j", "t"]
                where token.dropLast().contains(candidate)
            {
                length = candidate
                break
            }
            tokens.append("\(positional)\(length)\(conversion)")
        }
        return tokens.sorted()
    }

    private func validateCatalog(named fileName: String) throws {
        let url = Self.catalogURL(fileName)
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let catalog = try #require(root, "\(fileName): not a JSON object")

        #expect(catalog["sourceLanguage"] as? String == "en", "\(fileName): sourceLanguage must be en")

        let strings = try #require(catalog["strings"] as? [String: Any], "\(fileName): missing strings object")
        let requiredLanguages = try Self.requiredLanguages()

        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any] else {
                Issue.record("\(fileName): entry \(key) is not an object")
                continue
            }
            if entry["shouldTranslate"] as? Bool == false {
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let expectedUnits = Self.sourceUnits(key: key, entry: entry)

            for language in requiredLanguages {
                guard let node = localizations[language] as? [String: Any] else {
                    Issue.record("\(fileName): \(key) missing \(language) translation")
                    continue
                }
                let translatedUnits = Self.collectUnits(node)
                if translatedUnits.isEmpty {
                    Issue.record("\(fileName): \(key) has no \(language) value")
                    continue
                }
                guard Set(translatedUnits.keys) == Set(expectedUnits.keys) else {
                    Issue.record("\(fileName): \(key) variation paths differ for \(language)")
                    continue
                }
                for (unitPath, value) in translatedUnits {
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Issue.record("\(fileName): \(key) has an empty \(language) value at \(unitPath)")
                    }
                    let sourceTokens = Self.placeholderTokens(in: expectedUnits[unitPath] ?? "")
                    let translatedTokens = Self.placeholderTokens(in: value)
                    let message = Comment(
                        rawValue: "\(fileName): \(key) placeholder mismatch for \(language) at \(unitPath) "
                            + "(source=\(sourceTokens), \(language)=\(translatedTokens))"
                    )
                    #expect(
                        translatedTokens == sourceTokens,
                        message
                    )
                }
            }
        }
    }
}
