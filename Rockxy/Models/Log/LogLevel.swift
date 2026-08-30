import Foundation

/// Severity levels for captured log entries, mirroring Apple's OSLog levels.
/// Raw values are ordered by severity to support `Comparable` filtering (e.g. "warning and above").
enum LogLevel: Int, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5

    // MARK: Internal

    var displayName: String {
        switch self {
        case .debug: String(localized: "Debug", bundle: RockxyLocalization.bundle)
        case .info: String(localized: "Info", bundle: RockxyLocalization.bundle)
        case .notice: String(localized: "Notice", bundle: RockxyLocalization.bundle)
        case .warning: String(localized: "Warning", bundle: RockxyLocalization.bundle)
        case .error: String(localized: "Error", bundle: RockxyLocalization.bundle)
        case .fault: String(localized: "Fault", bundle: RockxyLocalization.bundle)
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
