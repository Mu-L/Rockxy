import SwiftUI

/// Diff viewer that renders the comparison in either Side by Side or Unified mode.
/// Shows the Left/Right transaction identity above the diff, supports structured
/// sections with headers, and a freeform text paste fallback.
struct DiffViewerView: View {
    // MARK: Internal

    @Bindable var viewModel: DiffViewModel

    var body: some View {
        switch viewModel.workspaceState {
        case .textPaste:
            textPasteMode
        case .textReady:
            comparisonContent(showsIdentity: false)
        case .ready:
            comparisonContent(showsIdentity: true)
        case .missingBoth:
            missingBothState
        case .missingLeft,
             .missingRight:
            partialState
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var partialTitle: String {
        viewModel.workspaceState == .missingLeft
            ? String(localized: "Assign a Left Transaction")
            : String(localized: "Assign a Right Transaction")
    }

    private var partialIcon: String {
        viewModel.workspaceState == .missingLeft ? "arrow.left" : "arrow.right"
    }

    private var partialDescription: String {
        viewModel.workspaceState == .missingLeft
            ? String(localized: "Click the L column on a candidate to finish this basic compare.")
            : String(localized: "Click the R column on a candidate to finish this basic compare.")
    }

    // MARK: - Ready Content

    private func comparisonContent(showsIdentity: Bool) -> some View {
        VStack(spacing: 0) {
            if showsIdentity {
                identityHeader
                Divider()
            }
            if viewModel.isComparing {
                loadingState
            } else {
                diffContent
            }
        }
    }

    @ViewBuilder private var diffContent: some View {
        let result = viewModel.activeDiffResult
        switch viewModel.presentationMode {
        case .sideBySide:
            sideBySideView(result)
        case .unified:
            unifiedView(result)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 0) {
            transactionIdentity(String(localized: "Left"), transaction: viewModel.leftTransaction)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            transactionIdentity(String(localized: "Right"), transaction: viewModel.rightTransaction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.3))
    }

    // MARK: - Text Paste Mode

    private var textPasteMode: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Side A — paste or type text"))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                TextEditor(text: $viewModel.textA)
                    .font(toolMetrics.font(monospaced: true))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(String(localized: "Left text"))
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Side B — paste or type text"))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                TextEditor(text: $viewModel.textB)
                    .font(toolMetrics.font(monospaced: true))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(String(localized: "Right text"))
            }
        }
    }

    // MARK: - Partial State

    private var partialState: some View {
        ContentUnavailableView {
            Label(partialTitle, systemImage: partialIcon)
                .font(toolMetrics.font(weight: .medium))
        } description: {
            Text(partialDescription)
                .font(toolMetrics.secondaryFont())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var missingBothState: some View {
        ContentUnavailableView {
            Label(String(localized: "Choose Two Transactions"), systemImage: "rectangle.split.2x1")
                .font(toolMetrics.font(weight: .medium))
        } description: {
            Text(String(localized: "Compare two selected requests, then assign Left and Right in the comparison set."))
                .font(toolMetrics.secondaryFont())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: toolMetrics.controlSpacing) {
            ProgressView()
            Text(String(localized: "Preparing bounded comparison…"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transactionIdentity(_ label: String, transaction: HTTPTransaction?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(toolMetrics.secondaryFont(weight: .bold))
                .foregroundStyle(.secondary)
            if let transaction {
                DiffMethodBadge(method: transaction.request.method)
                Text(transaction.request.url.absoluteString)
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(transaction.request.url.absoluteString)
            } else {
                Text(String(localized: "Not assigned"))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Side by Side

    private func sideBySideView(_ result: DiffResult) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.sections) { section in
                        sectionHeader(section.title)
                        let rows = DiffResult.sideBySideRows(from: section.lines)
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                sideBySideCell(row.left)
                                    .frame(minWidth: max(320, (geometry.size.width - 1) / 2))
                                Divider()
                                sideBySideCell(row.right)
                                    .frame(minWidth: max(320, (geometry.size.width - 1) / 2))
                            }
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func sideBySideCell(_ line: DiffLine?) -> some View {
        if let line {
            diffLineRow(line)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(18, toolMetrics.bodyFontSize + 5))
        }
    }

    // MARK: - Unified

    private func unifiedView(_ result: DiffResult) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.sections) { section in
                        sectionHeader(section.title)
                        ForEach(section.lines) { line in
                            diffLineRow(line)
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text("— \(title) —")
            .font(toolMetrics.secondaryFont(weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2))
    }

    private func diffLineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text("\(line.lineNumber)")
                .font(toolMetrics.metadataFont(monospaced: true))
                .foregroundStyle(.tertiary)
                .frame(width: toolMetrics.fieldWidth(36), alignment: .trailing)
                .padding(.trailing, 4)

            Text(prefix(for: line.type))
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(emphasisColor(for: line.type))
                .frame(width: toolMetrics.fieldWidth(14))

            Text(line.content)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(contentColor(for: line.type))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(for: line.type))
    }

    private func prefix(for type: DiffLineType) -> String {
        switch type {
        case .unchanged: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    private func emphasisColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .secondary
        case .added: Theme.Highlight.green
        case .removed: Theme.Highlight.red
        }
    }

    private func contentColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .secondary
        case .added,
             .removed: .primary
        }
    }

    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .clear
        case .added: Theme.Highlight.green.opacity(0.16)
        case .removed: Theme.Highlight.red.opacity(0.16)
        }
    }
}
