import Foundation

/// Formats time durations into the most readable unit: microseconds, milliseconds, seconds,
/// minutes, or hours.
///
/// This is the single implementation behind every duration Rockxy shows, so the same interval
/// never reads differently in the request list, the inspectors, the Context Dock, and the
/// assistant's evidence. Each branch is chosen from the *rounded* value, so a duration that
/// rounds up into the next unit is shown in that unit ("1.00 s", never "1000 ms"; "1 ms", never
/// "1000 µs"; "2m 0s", never "1m 60s").
///
/// The fractional part goes through `DecimalFormatter`: `String(format: "%.2f s")` takes no locale
/// and always emits a POSIX period, so on `en_VN` the dock printed "5.64 s" next to its own
/// footer's "1,5 MB".
enum DurationFormatter {
    static func format(seconds: TimeInterval, locale: Locale = RockxyLocalization.locale) -> String {
        let seconds = max(0, seconds)
        let microseconds = (seconds * 1_000_000).rounded()
        if microseconds < 1_000 {
            return "\(DecimalFormatter.format(microseconds, fractionDigits: 0, locale: locale)) µs"
        }
        let milliseconds = (seconds * 1_000).rounded()
        if milliseconds < 1_000 {
            return "\(DecimalFormatter.format(milliseconds, fractionDigits: 0, locale: locale)) ms"
        }
        let hundredths = (seconds * 100).rounded()
        if hundredths < 6_000 {
            return "\(DecimalFormatter.format(hundredths / 100, fractionDigits: 2, locale: locale)) s"
        }
        let whole = Int(seconds.rounded())
        if whole < 3_600 {
            return "\(whole / 60)m \(whole % 60)s"
        }
        return "\(whole / 3_600)h \((whole % 3_600) / 60)m"
    }
}
