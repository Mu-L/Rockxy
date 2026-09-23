import SwiftUI

/// Explicit `.system(size:)` roles that mirror the horizontal request/response inspector:
/// UI labels and prose stay proportional; callers opt into monospaced only for technical data
/// (request summaries, model IDs, endpoints). Deliberately does not honor the global
/// `useMonospacedFont` preference, so prose never renders monospaced.
func assistantFont(
    _ size: CGFloat,
    weight: Font.Weight = .regular,
    monospaced: Bool = false
)
    -> Font
{
    monospaced
        ? .system(size: size, weight: weight, design: .monospaced)
        : .system(size: size, weight: weight)
}
