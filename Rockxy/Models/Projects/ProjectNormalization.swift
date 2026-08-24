import Foundation

// MARK: - ProjectNameNormalizationError

/// Deterministic rejection reasons for a Project name or tab title.
enum ProjectNameNormalizationError: Error, Equatable {
    /// The value was empty after trimming and normalization.
    case empty
    /// The value contained a control, or unsafe invisible/directional formatting,
    /// character after normalization (e.g. U+202E RLO, U+200B ZWSP, U+00AD soft
    /// hyphen). Legitimate joining controls (U+200C ZWNJ, U+200D ZWJ) are allowed.
    case containsControlCharacters
    /// The value exceeded ``ProjectStructuralLimits/nameGraphemeRange``.
    case tooLong(graphemeCount: Int)
    /// The stored value was not already in canonical form: it differs from its own
    /// ``ProjectNormalization/normalizedDisplayName(_:)``. Persisted names/titles
    /// must be stored canonically so folded uniqueness is well defined.
    case notCanonical
}

// MARK: - ProjectNormalization

/// Deterministic normalization and folding for Project names and tab titles.
///
/// The same rules apply to both so persisted display text is stable across
/// launches and platforms: trim surrounding whitespace/newlines, apply canonical
/// Unicode composition, reject control and unsafe formatting characters, and
/// bound the grapheme count.
/// Uniqueness compares the *folded* key so visually identical names that differ
/// only by case or diacritics collide deterministically.
enum ProjectNormalization {
    // MARK: Internal

    /// Returns the canonical display form of a name/title, or throws a
    /// deterministic reason it is invalid. Canonical means: canonical Unicode
    /// composition, surrounding whitespace trimmed, no control or unsafe
    /// invisible/directional formatting characters (joining controls U+200C/U+200D
    /// are preserved), and a bounded grapheme count. Applying this twice is
    /// idempotent — that fixed point is exactly what ``requireCanonical(_:)``
    /// enforces on stored values.
    static func normalizedDisplayName(_ raw: String) throws -> String {
        // Canonical composition first, then trim, so composed/decomposed forms of
        // a surrounding-whitespace character are handled identically.
        let normalized = raw
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            throw ProjectNameNormalizationError.empty
        }

        if normalized.unicodeScalars.contains(where: isDisallowedScalar) {
            throw ProjectNameNormalizationError.containsControlCharacters
        }

        let graphemeCount = normalized.count
        guard ProjectStructuralLimits.nameGraphemeRange.contains(graphemeCount) else {
            throw ProjectNameNormalizationError.tooLong(graphemeCount: graphemeCount)
        }

        return normalized
    }

    /// Throws unless `value` is already in canonical form (equal to its own
    /// ``normalizedDisplayName(_:)``). Used by structural validation to reject a
    /// stored name/title that was never canonicalized, so folded uniqueness always
    /// compares canonical values.
    static func requireCanonical(_ value: String) throws {
        let canonical = try normalizedDisplayName(value)
        guard canonical.unicodeScalars.elementsEqual(value.unicodeScalars) else {
            throw ProjectNameNormalizationError.notCanonical
        }
    }

    /// Returns the deterministic uniqueness key for an already-normalized name.
    /// Folding is case- and diacritic-insensitive under a fixed POSIX locale so
    /// the result does not vary with the host's current locale.
    static func foldedKey(for normalizedName: String) -> String {
        normalizedName.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// Convenience: normalize then fold, used when comparing raw user input to
    /// existing normalized names.
    static func foldedKey(forRawName raw: String) throws -> String {
        try foldedKey(for: normalizedDisplayName(raw))
    }

    // MARK: Private

    /// Zero-width joiners that are legitimate in emoji sequences (e.g. the family
    /// emoji) and joining scripts, so they must survive normalization even though
    /// they share the `.format` general category with spoofing scalars.
    private static let allowedFormatScalars: Set<Unicode.Scalar> = [
        "\u{200C}", // ZERO WIDTH NON-JOINER
        "\u{200D}", // ZERO WIDTH JOINER
    ]

    /// Rejects control characters and unsafe invisible/directional formatting used
    /// for spoofing (e.g. U+202E RLO, U+200B ZWSP, U+00AD soft hyphen) while
    /// preserving the joining controls in ``allowedFormatScalars``.
    private static func isDisallowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            true
        case .format:
            !allowedFormatScalars.contains(scalar)
        default:
            false
        }
    }
}
