import Foundation

/// Formats byte counts into human-readable strings (e.g. "1.2 MB") using binary (1024-based) units.
///
/// This is the single implementation behind every captured byte count Rockxy shows, so the same
/// number never reads differently in the request list, the inspectors, the Context Dock, the
/// status bar, and the assistant's evidence. `ByteCountFormatter`'s `.file` style is decimal, so
/// a formatter that reached for it rendered 999,999 bytes as "1 MB" while the shared one said
/// "977 KB"; download and on-disk sizes keep `.file` on purpose, captured traffic does not.
enum SizeFormatter {
    static func format(bytes: Int) -> String {
        format(bytes: Int64(bytes))
    }

    static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        // Left on, `ByteCountFormatter` spells an empty body "Zero KB" next to its own
        // "1 byte" and "512 bytes"; a bodiless request reads "0 bytes" instead.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
