import Foundation

/// Formats a user-visible count for display.
///
/// This is the single implementation behind every bare count Rockxy shows, so the same quantity
/// never reads differently in a table value and in the sentence next to it. A count interpolated
/// into a `String(localized:)` key is extracted as `%lld` and rendered with the locale's digit
/// grouping, while `"\(count)"` and `String(count)` are locale-blind: on `en_VN` the Review Data
/// sheet printed a context window of "128.000 tokens" where the AI inspector's Total read
/// "128000", and on `fr_FR` the same pair reads "128 000" against "128000".
///
/// Ports, wire header values such as `Content-Length`, and compact capacity ratios (`3/5`) are
/// deliberately *not* formatted here — a grouped port is wrong and a bounded ratio never reaches
/// a grouping boundary.
enum CountFormatter {
    /// A count rendered on its own, in the app's effective locale.
    static func format(_ value: Int) -> String {
        value.formatted(.number.locale(RockxyLocalization.locale))
    }
}
