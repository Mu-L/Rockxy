import SwiftUI

// MARK: - ScriptConsolePanel

/// Right-side console panel in the Script Editor window. Shows user `console.log`
/// output filtered by the eye-icon menu. Empty state shows an "Empty Console"
/// header with a hint to call `console.log()` to log events.
struct ScriptConsolePanel: View {
    // MARK: Internal

    @Bindable var viewModel: ScriptEditorViewModel

    var body: some View {
        content
            .font(toolMetrics.font())
            .frame(maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var content: some View {
        let visible = viewModel.visibleConsoleEntries
        switch viewModel.consoleEmptyState {
        case .empty:
            emptyState(
                title: String(localized: "Empty Console", bundle: RockxyLocalization.bundle),
                message: String(localized: "Use console.log() to log events", bundle: RockxyLocalization.bundle)
            )
        case .filtered:
            emptyState(
                title: String(localized: "No Matching Output", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Console entries exist, but the active level filter hides them all.",
                    bundle: RockxyLocalization.bundle
                )
            )
        case .populated:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visible) { entry in
                            ScriptConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: visible.count) { _, _ in
                    if let last = visible.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: max(16, toolMetrics.bodyFontSize + 3), weight: .medium))
                .foregroundStyle(.primary)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ScriptConsoleEntryRow

private struct ScriptConsoleEntryRow: View {
    // MARK: Internal

    let entry: ScriptConsoleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(toolMetrics.metadataFont(monospaced: true))
                .foregroundStyle(.tertiary)
            Text(entry.message)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(colorFor(level: entry.level))
                .textSelection(.enabled)
        }
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func colorFor(level: ScriptConsoleLogLevel) -> Color {
        switch level {
        case .errors: .red
        case .warnings: .orange
        case .userLogs: .primary
        case .system: .secondary
        }
    }
}
