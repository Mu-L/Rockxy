import SwiftUI

// Table rendering for the Block List window. Extracted from `BlockListWindowView.swift`
// to keep that file within the length limit; behavior and type names are unchanged.

// MARK: - BlockListTableView

struct BlockListTableView<ContextMenuContent: View>: View {
    // MARK: Internal

    let rules: [ProxyRule]
    @Binding var selectedRuleID: UUID?

    let onToggle: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @ViewBuilder let contextMenuItems: (UUID) -> ContextMenuContent

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            ZStack {
                zebraRows

                if rules.isEmpty {
                    Text(String(localized: "Click \"+\" or ⌘N to add new entry", bundle: RockxyLocalization.bundle))
                        .font(.system(size: toolMetrics.emptyStateFontSize))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                                BlockRuleTableRow(
                                    rule: rule,
                                    isSelected: selectedRuleID == rule.id,
                                    rowIndex: index,
                                    onSelect: { selectedRuleID = rule.id },
                                    onToggle: { onToggle(rule.id) }
                                )
                                .contextMenu {
                                    contextMenuItems(rule.id)
                                }
                                .onTapGesture(count: 2) {
                                    onEdit(rule.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(String(localized: "Enabled", bundle: RockxyLocalization.bundle))
                .frame(width: 66, alignment: .leading)
            tableDivider
            Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                .frame(width: 300, alignment: .leading)
            tableDivider
            Text(String(localized: "Block Action", bundle: RockxyLocalization.bundle))
                .frame(width: 150, alignment: .leading)
            tableDivider
            Text(String(localized: "Method", bundle: RockxyLocalization.bundle))
                .frame(width: 90, alignment: .leading)
            tableDivider
            Text(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.tableHeaderFont())
        .lineLimit(1)
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .frame(height: toolMetrics.tableRowHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var tableDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(width: 1, height: max(16, toolMetrics.tableRowHeight - 10))
            .padding(.trailing, 10)
    }

    private var zebraRows: some View {
        GeometryReader { proxy in
            let rowCount = max(1, Int(ceil(proxy.size.height / toolMetrics.tableRowHeight)))
            VStack(spacing: 0) {
                ForEach(0 ..< rowCount, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
                            .opacity(0.08))
                        .frame(height: toolMetrics.tableRowHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - BlockRuleTableRow

private struct BlockRuleTableRow: View {
    // MARK: Internal

    let rule: ProxyRule
    let isSelected: Bool
    let rowIndex: Int
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 66)

            Text(rule.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 300, alignment: .leading)

            actionLabel
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)

            Text(rule.matchCondition.method ?? "ANY")
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(rule.matchCondition.sourceURLPattern ?? rule.matchCondition.urlPattern ?? "")
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.font())
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
        .frame(height: toolMetrics.tableRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        return AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
            .opacity(0.08))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var actionLabel: some View {
        if case let .block(statusCode) = rule.action {
            Text(
                statusCode == 0
                    ? String(localized: "Drop Connection", bundle: RockxyLocalization.bundle)
                    : String(localized: "Return 403 Forbidden", bundle: RockxyLocalization.bundle)
            )
        }
    }
}
