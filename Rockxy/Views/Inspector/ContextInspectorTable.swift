import SwiftUI

// MARK: - ContextTableField

/// A single leading-label / trailing-value pair for a Context Dock diagnostics table.
/// Values are monospaced by default because most carry technical data (status, host,
/// byte counts, timing); pass `monospaced: false` for prose such as an application name.
struct ContextTableField {
    let label: String
    let value: String
    var monospaced = true
    var color: Color = .primary
}

// MARK: - ContextInspectorTable

/// Reusable table shell for the Context Dock Details inspector. Mirrors `HeaderKeyValueTable`'s
/// visual language — a control-background title header, text-background rows, a 0.5pt separator
/// stroke, 6pt corner radius, and clipped rounded container — so every diagnostics group reads
/// like the horizontal inspector's native key/value grid rather than a flat heading plus rows.
/// Callers compose rows and interleave `Divider()` between them.
struct ContextInspectorTable<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ContextInspectorTableHeader(title: title)
            Divider()
            content()
        }
        .contextInspectorTableChrome()
    }
}

// MARK: - ContextInspectorFieldTable

/// Convenience table for the common all-Field/Value groups (Selection summary, Details).
/// Renders a header plus a divided list of `ContextInspectorFieldRow`s.
struct ContextInspectorFieldTable: View {
    let title: String
    let fields: [ContextTableField]

    var body: some View {
        ContextInspectorTable(title: title) {
            ForEach(Array(fields.enumerated()), id: \.element.label) { index, field in
                if index > 0 {
                    Divider()
                }
                ContextInspectorFieldRow(field: field)
            }
        }
    }
}

// MARK: - ContextInspectorDisclosureTable

/// A table whose title header doubles as a progressive-disclosure toggle. Collapsed, it reads as a
/// single rounded bar; expanded, the same bordered container reveals divided rows. Used by the
/// Timing and Related Requests groups.
struct ContextInspectorDisclosureTable<Content: View>: View {
    // MARK: Internal

    let title: String
    @Binding var isExpanded: Bool

    var summary: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: metrics.fontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 6)
                    if let summary {
                        Text(summary)
                            .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                content()
            }
        }
        .contextInspectorTableChrome()
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - ContextInspectorFieldRow

/// Dense two-column table row: a proportional secondary label beside a value column, separated by a
/// vertical divider. The value is monospaced for technical data and stays leading-aligned and
/// selectable so long host / path / pattern text truncates predictably in a narrow dock.
struct ContextInspectorFieldRow: View {
    // MARK: Internal

    let field: ContextTableField

    var body: some View {
        HStack(spacing: 0) {
            Text(field.label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .frame(width: ContextInspectorTableMetrics.labelColumnWidth(metrics), alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            Text(field.value)
                .font(field.monospaced
                    ? .system(size: metrics.secondaryFontSize, design: .monospaced)
                    : .system(size: metrics.secondaryFontSize))
                .foregroundStyle(field.color)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - ContextInspectorInsightRow

/// A two-column insight row: a compact semantic icon + title on the field side, the detail on the
/// value side, split by the same vertical divider so insights read as a table mapping.
struct ContextInspectorInsightRow: View {
    // MARK: Internal

    let systemImage: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: ContextInspectorTableMetrics.insightLabelColumnWidth(metrics), alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            Text(detail)
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - ContextInspectorFullRow

/// A full-width table row for content that spans both columns: truncation warnings, truthful empty
/// states, action rows, selectable request rows, and the Notes editor.
struct ContextInspectorFullRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

// MARK: - ContextInspectorTableMetrics

/// Shared column sizing so field, insight, and value columns align across every table. Scales with
/// the Appearance font size, mirroring the horizontal inspector's key column.
enum ContextInspectorTableMetrics {
    static func labelColumnWidth(_ metrics: AppUIDisplayMetrics) -> CGFloat {
        min(max(90, metrics.fontSize * 5 + 8), 150)
    }

    static func insightLabelColumnWidth(_ metrics: AppUIDisplayMetrics) -> CGFloat {
        min(max(110, metrics.fontSize * 5.5 + 8), 160)
    }
}

// MARK: - ContextInspectorTableHeader

private struct ContextInspectorTableHeader: View {
    // MARK: Internal

    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: metrics.fontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - ContextInspectorTableChrome

private struct ContextInspectorTableChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension View {
    func contextInspectorTableChrome() -> some View {
        modifier(ContextInspectorTableChrome())
    }
}
