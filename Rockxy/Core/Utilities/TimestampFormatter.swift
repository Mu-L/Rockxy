import Foundation

/// Formats a capture timestamp as a time of day.
///
/// This is the single implementation behind every wall-clock time Rockxy shows, so the same
/// transaction never reads differently in the request list, the Diff candidate picker, the
/// WebSocket frame list, and the script console. A hardcoded `dateFormat` of `"HH:mm:ss"` is
/// locale-blind and ignores the user's 24-Hour Time preference: on `en_US` the request list
/// printed "21:19:10" for the row the Diff picker called "9:19:10 PM", and on `ko_KR` for the one
/// it called "오후 9:19:10". A fixed pattern belongs only in machine-readable output, where
/// `en_US_POSIX` pins it on purpose.
///
/// The formatters are cached: `DateFormatter` is expensive to build, and a WebSocket frame list
/// asks for one per visible row on every redraw.
enum TimestampFormatter {
    // MARK: Internal

    /// Hour, minute, and second in the user's locale and clock preference.
    static func timeOfDay(_ date: Date) -> String {
        timeOfDayFormatter.string(from: date)
    }

    /// As `timeOfDay(_:)`, plus milliseconds. WebSocket frames arrive milliseconds apart, so the
    /// frame list needs the sub-second digits to order them by eye.
    static func timeOfDayWithMilliseconds(_ date: Date) -> String {
        millisecondFormatter.string(from: date)
    }

    // MARK: Private

    /// A localized template, not a fixed pattern: `setLocalizedDateFormatFromTemplate` resolves
    /// the field order and the 12-/24-hour choice from the current locale.
    private static let timeOfDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jms")
        return formatter
    }()

    private static let millisecondFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmsSSS")
        return formatter
    }()
}
