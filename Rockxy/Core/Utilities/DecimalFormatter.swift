import Foundation

/// Formats a fractional number, or a percentage, in the app's effective locale.
///
/// This is the single implementation behind every number Rockxy shows with a decimal part, so a
/// window never mixes separators. `String(format: "%.2f")` takes no locale and always emits a
/// POSIX period, while `ByteCountFormatter` follows the locale — so on `en_VN`, where the decimal
/// separator is a comma, the Context Dock read a duration of "5.64 s" beside a footer total of
/// "1,5 MB" for the same session.
///
/// A percent sign is positioned by the locale too: `de_DE` and `fr_FR` write "45 %" with a
/// non-breaking space, so a hand-appended "%" is wrong in the same way a hand-appended separator is.
enum DecimalFormatter {
    /// A fractional value rendered with a fixed number of decimal places.
    static func format(
        _ value: Double,
        fractionDigits: Int,
        locale: Locale = RockxyLocalization.locale
    ) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// A percentage rendered from a 0–100 value, with the locale's own sign placement.
    static func percent(
        _ value: Double,
        fractionDigits: Int = 0,
        locale: Locale = RockxyLocalization.locale
    ) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(fractionDigits)).locale(locale))
    }
}
