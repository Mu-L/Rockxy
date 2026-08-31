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

    @Test("The ambiguous standalone Code key is retired from Localizable.xcstrings")
    func codeKeyIsRemoved() throws {
        let data = try Data(contentsOf: Self.catalogURL("Localizable.xcstrings"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let catalog = try #require(root)
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(strings["Code"] == nil, "The context-free \"Code\" key must not return; use a contextual key")
        #expect(strings["Status code"] != nil, "The HTTP status-code label key must remain")
        #expect(strings["Compact HTTP status code"] != nil, "Compact status labels need a contextual key")
    }

    @Test("Localizable.xcstrings honors the Simplified-Chinese terminology glossary")
    func zhHansGlossary() throws {
        let data = try Data(contentsOf: Self.catalogURL("Localizable.xcstrings"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let catalog = try #require(root)
        let strings = try #require(catalog["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  entry["shouldTranslate"] as? Bool != false,
                  let localizations = entry["localizations"] as? [String: Any],
                  let node = localizations["zh-Hans"] as? [String: Any] else
            {
                continue
            }
            let expectedUnits = Self.sourceUnits(key: key, entry: entry)
            for (unitPath, value) in Self.collectUnits(node) {
                let source = expectedUnits[unitPath] ?? key
                for issue in Self.zhHansGlossaryIssues(key: key, source: source, value: value) {
                    Issue.record(Comment(rawValue: "Localizable.xcstrings: \(key) zh-Hans glossary — \(issue)"))
                }
            }
        }
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

    /// Exact English keys whose "token" is an AI model token (never an auth/pairing
    /// token), mirroring `ZH_HANS_AI_TOKEN_KEYS` in `validate_xcstrings.py`.
    private static let zhHansAITokenKeys: Set<String> = [
        "%@ tokens",
        "%lld input · %lld output tokens",
        "Context window tokens",
        "Maximum output tokens",
        "tokens",
        "tokens per response",
        "Compare model, tokens, finish reason, and latency against adjacent retries.",
        "Check event count, final event, interruption signs, and first-token/overall duration.",
        "Rockxy can identify this AI app session, but model, tokens, and tools need decrypted API evidence.",
        "SSE cadence is shown from captured events. Token boundaries stay unavailable unless the provider exposes them.",
        "Rockxy uses 8,192 tokens by default and limits local inference to 32,768 tokens to avoid excessive memory pressure.",
    ]

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

    /// Deterministic Simplified-Chinese forbid-rules, gated on the English source.
    /// Mirrors `zh_hans_glossary_errors` in `.github/tools/validate_xcstrings.py`.
    private static func zhHansGlossaryIssues(key: String, source: String, value: String) -> [String] {
        let lowered = source.lowercased()
        let semanticContext = "\(key) \(source)".lowercased()
        let isCertificatePinning = lowered.contains("certificate pinning")
            || lowered.contains("pins certificate")
        var issues: [String] = []

        func forbid(_ applies: Bool, _ banned: [String], _ label: String) {
            guard applies else {
                return
            }
            for term in banned where value.contains(term) {
                issues.append("\(label) (found \(term))")
            }
        }

        forbid(lowered.contains("redact"), ["遮盖", "隐去"], "redaction must use 脱敏/已脱敏")
        forbid(isCertificatePinning, ["锁定"], "certificate pinning must use 固定")
        forbid(source.contains("Compose"), ["编写"], "named Compose feature must stay Compose")
        forbid(
            lowered.contains("wire format") || lowered.contains("wire-format"),
            ["线路格式"],
            "Protobuf wire format must use 线格式"
        )
        forbid(zhHansAITokenKeys.contains(key), ["令牌"], "AI model token must use token, not 令牌")

        func require(_ applies: Bool, _ term: String, _ label: String) {
            guard applies, !value.contains(term) else {
                return
            }
            issues.append("\(label) (missing \(term))")
        }

        require(semanticContext.contains("status code"), "状态码", "HTTP status code must use 状态码")
        require(lowered.contains("redact"), "脱敏", "redaction must use 脱敏/已脱敏")
        require(isCertificatePinning, "固定", "certificate pinning must use 固定")
        require(source.contains("Compose"), "Compose", "named Compose feature must stay Compose")
        require(
            lowered.contains("wire format") || lowered.contains("wire-format"),
            "线格式",
            "Protobuf wire format must use 线格式"
        )
        require(zhHansAITokenKeys.contains(key), "token", "AI model token must use token")
        return issues
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
