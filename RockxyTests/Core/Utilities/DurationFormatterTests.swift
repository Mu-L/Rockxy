import Foundation
@testable import Rockxy
import Testing

/// `DurationFormatter` is the single implementation behind every duration Rockxy shows, so the
/// same interval must read identically in the request list, the inspectors, the Context Dock,
/// and the assistant's evidence — including at the unit boundaries, and in every locale.
struct DurationFormatterTests {
    @Test("Each unit renders at its own scale")
    func unitsCoverMicrosecondsThroughHours() {
        // Pinned against an explicit locale: the spellings below are `en_US`, and the point of
        // the next test is that they are *not* what every locale prints.
        #expect(Self.formatted(0.000412) == "412 µs")
        #expect(Self.formatted(0.923) == "923 ms")
        #expect(Self.formatted(1.5) == "1.50 s")
        #expect(Self.formatted(90) == "1m 30s")
        #expect(Self.formatted(7_920) == "2h 12m")
    }

    @Test("A value that rounds up is shown in the unit it rounds into")
    func roundingNeverSpillsPastAUnit() {
        // 119.6 s rounded down reads "1m 60s"; it must read "2m 0s".
        #expect(Self.formatted(119.6) == "2m 0s")
        #expect(Self.formatted(3_599.7) == "1h 0m")
        // 0.9996 s rounds to 1000 ms, which belongs in the seconds branch.
        #expect(Self.formatted(0.9996) == "1.00 s")
        #expect(Self.formatted(59.999) == "1m 0s")
        // 0.0009999 s rounds to 1000 µs, which belongs in the milliseconds branch.
        #expect(Self.formatted(0.0009999) == "1 ms")
        #expect(Self.formatted(0.0009994) == "999 µs")
    }

    @Test("The decimal separator follows the locale, not the machine")
    func decimalSeparatorIsLocaleDependent() {
        // `String(format: "%.2f s")` takes no locale and always emits a POSIX period, while
        // `ByteCountFormatter` follows the locale — so on `en_VN`, the maintainer's own locale,
        // the Context Dock read "5.64 s" beside a footer total of "1,5 MB" for one session.
        #expect(Self.formatted(1.5, "en_VN") == "1,50 s")
        #expect(Self.formatted(1.5, "de_DE") == "1,50 s")
        #expect(Self.formatted(1.5, "fr_FR") == "1,50 s")
        #expect(Self.formatted(1.5, "zh_Hans_CN") == "1.50 s")
        // A unit with no fractional part is separator-free, so it reads the same everywhere.
        #expect(Self.formatted(0.923, "de_DE") == Self.formatted(0.923, "en_US"))
    }

    @Test("Negative intervals never render as negative durations")
    func negativeIntervalsClampToZero() {
        #expect(Self.formatted(-1) == "0 µs")
    }

    @Test("Long-lived streams read the same in the dock and the request list")
    func contextDockMatchesRequestList() {
        // The Context Dock and the assistant previously had their own two-branch formatter, so a
        // 90 s stream read "90.00 s" in the dock while the row and WebSocket inspector said "1m 30s".
        let stream: TimeInterval = 90
        #expect(ContextDetailsView.hostBaselineDetail(duration: stream * 4, baseline: stream)
            .contains(DurationFormatter.format(seconds: stream)))
    }

    @Test("An open connection reports its running time; a closed one its final duration")
    @MainActor
    func runningConnectionReportsElapsedTime() {
        // While a socket was open the Context Dock read "Unavailable", the list "—", and the
        // WebSocket inspector a running value. Detail surfaces now share the running value.
        let session = TestFixtures.makeWebSocketTransaction()
        session.state = .active
        session.measuredDuration = nil
        let now = session.timestamp.addingTimeInterval(61)

        #expect(session.isRunning)
        #expect(session.displayDuration == nil)
        #expect(session.displayDuration(at: now) == 61)

        session.state = .completed
        session.measuredDuration = 75
        #expect(!session.isRunning)
        #expect(session.displayDuration(at: now) == 75)

        // A finished row with no measurement stays unknown rather than counting up forever.
        let failed = TestFixtures.makeTransaction()
        failed.state = .failed
        failed.timingInfo = nil
        failed.measuredDuration = nil
        #expect(failed.displayDuration(at: now) == nil)
    }

    // MARK: Private

    private static func formatted(_ seconds: TimeInterval, _ localeID: String = "en_US") -> String {
        DurationFormatter.format(seconds: seconds, locale: Locale(identifier: localeID))
    }
}
