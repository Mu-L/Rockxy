@testable import Rockxy
import Testing

// MARK: - ProjectNormalizationTests

@Suite("ProjectNormalization")
struct ProjectNormalizationTests {
    @Test("trims surrounding whitespace and newlines")
    func trimsSurroundingWhitespace() throws {
        #expect(try ProjectNormalization.normalizedDisplayName("  Staging  ") == "Staging")
        #expect(try ProjectNormalization.normalizedDisplayName("\n\tStaging\n") == "Staging")
    }

    @Test("applies canonical Unicode composition")
    func canonicalComposition() throws {
        // "e" + combining acute accent normalizes to precomposed "é".
        let decomposed = "Cafe\u{0301}"
        let normalized = try ProjectNormalization.normalizedDisplayName(decomposed)
        #expect(normalized == "Café")
        #expect(normalized.unicodeScalars.count == 4)
    }

    @Test("rejects an empty or whitespace-only name")
    func rejectsEmpty() {
        #expect(throws: ProjectNameNormalizationError.empty) {
            _ = try ProjectNormalization.normalizedDisplayName("   \n\t ")
        }
    }

    @Test("rejects interior control characters")
    func rejectsControlCharacters() {
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\ning")
        }
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{0007}ing")
        }
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{2028}ing")
        }
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{2029}ing")
        }
    }

    @Test("rejects unsafe invisible and directional formatting characters")
    func rejectsUnsafeFormatCharacters() {
        // U+202E RIGHT-TO-LEFT OVERRIDE — directional spoofing.
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{202E}ing")
        }
        // U+200B ZERO WIDTH SPACE — invisible.
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{200B}ing")
        }
        // U+00AD SOFT HYPHEN — invisible.
        #expect(throws: ProjectNameNormalizationError.containsControlCharacters) {
            _ = try ProjectNormalization.normalizedDisplayName("Stag\u{00AD}ing")
        }
    }

    @Test("preserves legitimate joining controls (ZWNJ/ZWJ)")
    func preservesJoiningControls() throws {
        // U+200D ZERO WIDTH JOINER binds the family emoji into one grapheme cluster.
        let family = "👨‍👩‍👧‍👦"
        #expect(try ProjectNormalization.normalizedDisplayName(family) == family)

        // U+200C ZERO WIDTH NON-JOINER is legitimate in joining scripts.
        let zwnj = "a\u{200C}b"
        #expect(try ProjectNormalization.normalizedDisplayName(zwnj) == zwnj)
    }

    @Test("enforces the 1...80 grapheme bound")
    func enforcesGraphemeBound() throws {
        let maxName = String(repeating: "a", count: 80)
        #expect(try ProjectNormalization.normalizedDisplayName(maxName).count == 80)

        let tooLong = String(repeating: "a", count: 81)
        #expect(throws: ProjectNameNormalizationError.tooLong(graphemeCount: 81)) {
            _ = try ProjectNormalization.normalizedDisplayName(tooLong)
        }
    }

    @Test("counts grapheme clusters, not scalars, for emoji")
    func countsGraphemeClusters() throws {
        // A single family emoji is one grapheme cluster but many scalars.
        let emoji = "👨‍👩‍👧‍👦"
        #expect(emoji.unicodeScalars.count > 1)
        let name = String(repeating: emoji, count: 80)
        #expect(try ProjectNormalization.normalizedDisplayName(name).count == 80)
    }

    @Test("folds case and diacritics deterministically for uniqueness")
    func foldsCaseAndDiacritics() throws {
        let a = try ProjectNormalization.foldedKey(forRawName: "Café")
        let b = try ProjectNormalization.foldedKey(forRawName: "cafe")
        let c = try ProjectNormalization.foldedKey(forRawName: "  CAFE ")
        #expect(a == b)
        #expect(b == c)
    }

    @Test("distinct names fold to distinct keys")
    func distinctNamesDistinctKeys() throws {
        let a = try ProjectNormalization.foldedKey(forRawName: "Staging")
        let b = try ProjectNormalization.foldedKey(forRawName: "Production")
        #expect(a != b)
    }

    @Test("requireCanonical accepts an already-canonical value")
    func requireCanonicalAcceptsCanonical() throws {
        try ProjectNormalization.requireCanonical("Staging")
        try ProjectNormalization.requireCanonical("Café")
    }

    @Test("requireCanonical rejects a value that is not its own normalized form")
    func requireCanonicalRejectsNoncanonical() {
        // Untrimmed: normalizes to "Staging", so it is not canonical as stored.
        #expect(throws: ProjectNameNormalizationError.notCanonical) {
            try ProjectNormalization.requireCanonical("  Staging  ")
        }
        // Decomposed accent: canonical form is precomposed, so the stored value differs.
        #expect(throws: ProjectNameNormalizationError.notCanonical) {
            try ProjectNormalization.requireCanonical("Cafe\u{0301}")
        }
    }

    @Test("requireCanonical surfaces the underlying invalidity for a corrupt value")
    func requireCanonicalSurfacesInvalidity() {
        #expect(throws: ProjectNameNormalizationError.empty) {
            try ProjectNormalization.requireCanonical("   ")
        }
    }
}
