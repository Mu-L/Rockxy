import SwiftUI

// MARK: - DiffCandidateTableView

/// Pool table showing candidate transactions for comparison, wrapped in a
/// native card. Users assign Left/Right by clicking the L/R columns.
struct DiffCandidateTableView: View {
    // MARK: Internal

    @Bindable var viewModel: DiffViewModel

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            Divider()
            Group {
                if viewModel.candidates.isEmpty {
                    emptyState
                } else {
                    candidateTable
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var methodColumnWidth: CGFloat {
        max(60, toolMetrics.metadataFontSize * 4 + 18)
    }

    private var clientColumnWidth: CGFloat {
        max(90, toolMetrics.secondaryFontSize * 5 + 24)
    }

    private var statusColumnWidth: CGFloat {
        max(56, toolMetrics.metadataFontSize * 2.4 + 16)
    }

    private var timeColumnWidth: CGFloat {
        max(100, toolMetrics.secondaryFontSize * 7 + 34)
    }

    private var durationColumnWidth: CGFloat {
        max(82, toolMetrics.secondaryFontSize * 4.5 + 20)
    }

    private var candidateTable: some View {
        Table(viewModel.candidates) {
            TableColumn("L") { transaction in
                assignmentControl(
                    isAssigned: viewModel.isLeft(transaction),
                    label: String(localized: "Assign as Left transaction", bundle: RockxyLocalization.bundle),
                    action: { viewModel.assignLeft(transaction) }
                )
            }
            .width(max(32, toolMetrics.compactButtonSize + 4))

            TableColumn("R") { transaction in
                assignmentControl(
                    isAssigned: viewModel.isRight(transaction),
                    label: String(localized: "Assign as Right transaction", bundle: RockxyLocalization.bundle),
                    action: { viewModel.assignRight(transaction) }
                )
            }
            .width(max(32, toolMetrics.compactButtonSize + 4))

            TableColumn(String(localized: "Method", bundle: RockxyLocalization.bundle)) { transaction in
                DiffMethodBadge(method: transaction.request.method)
            }
            .width(methodColumnWidth)

            TableColumn(String(localized: "URL", bundle: RockxyLocalization.bundle)) { transaction in
                Text(transaction.request.url.absoluteString)
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(transaction.request.url.absoluteString)
            }

            TableColumn(String(localized: "Client", bundle: RockxyLocalization.bundle)) { transaction in
                Text(transaction.clientApp ?? "—")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(transaction.clientApp ?? String(
                        localized: "Unknown client",
                        bundle: RockxyLocalization.bundle
                    ))
            }
            .width(clientColumnWidth)

            TableColumn(String(localized: "Compact HTTP status code", bundle: RockxyLocalization.bundle)) { transaction in
                if let statusCode = transaction.response?.statusCode {
                    DiffStatusCodeBadge(statusCode: statusCode)
                } else {
                    Text("—")
                        .font(toolMetrics.secondaryFont(monospaced: true))
                        .foregroundStyle(.secondary)
                }
            }
            .width(statusColumnWidth)

            TableColumn(String(localized: "Time", bundle: RockxyLocalization.bundle)) { transaction in
                let formattedTime = formatTime(transaction.timestamp)
                Text(formattedTime)
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(formattedTime)
            }
            .width(timeColumnWidth)

            TableColumn(String(localized: "Duration", bundle: RockxyLocalization.bundle)) { transaction in
                Text(formatDuration(transaction.timingInfo?.totalDuration ?? transaction.measuredDuration))
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.secondary)
            }
            .width(durationColumnWidth)
        }
        .scrollContentBackground(.hidden)
    }

    private var cardHeader: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Comparison Set", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont(weight: .semibold))
            Text(String(localized: "\(viewModel.candidates.count) captured", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Clear", bundle: RockxyLocalization.bundle)) {
                viewModel.clearCandidates()
            }
            .buttonStyle(.plain)
            .font(toolMetrics.secondaryFont())
            .disabled(viewModel.candidates.isEmpty)
            .help(String(localized: "Clear local comparison candidates", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .frame(minHeight: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No compare candidates yet", bundle: RockxyLocalization.bundle),
                systemImage: "rectangle.split.2x1"
            )
            .font(toolMetrics.font(weight: .medium))
        } description: {
            Text(
                String(
                    localized: "Select two requests and choose \"Compare Selected\" to start a basic local compare.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func assignmentControl(isAssigned: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isAssigned ? "circle.fill" : "circle")
                .font(.system(size: toolMetrics.compactIconFontSize))
                .foregroundStyle(isAssigned ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isAssigned ? [.isSelected] : [])
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "—"
        }
        return String(format: "%.0fms", seconds * 1_000)
    }
}

// MARK: - DiffMethodBadge

struct DiffMethodBadge: View {
    // MARK: Internal

    let method: String

    var body: some View {
        Text(method)
            .font(toolMetrics.metadataFont(weight: .semibold, monospaced: true))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(foregroundColor)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var color: Color {
        switch method.uppercased() {
        case "GET": Theme.Highlight.blue
        case "POST": Theme.Highlight.green
        case "PUT": Theme.Highlight.orange
        case "PATCH": Theme.Highlight.yellow
        case "DELETE": Theme.Highlight.red
        case "HEAD": Theme.Highlight.purple
        default: .secondary
        }
    }

    private var foregroundColor: Color {
        method.uppercased() == "PATCH" ? .primary : color
    }
}

// MARK: - DiffStatusCodeBadge

private struct DiffStatusCodeBadge: View {
    // MARK: Internal

    let statusCode: Int

    var body: some View {
        Text("\(statusCode)")
            .font(toolMetrics.metadataFont(weight: .medium, monospaced: true))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var color: Color {
        switch statusCode {
        case 200 ..< 300: Theme.Highlight.green
        case 300 ..< 400: Theme.Highlight.blue
        case 400 ..< 500: Theme.Highlight.orange
        case 500 ..< 600: Theme.Highlight.red
        default: .secondary
        }
    }
}
