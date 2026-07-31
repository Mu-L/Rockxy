import SwiftUI

// Renders the modify header editor interface for rule editing and management.

// MARK: - EditableHeaderOperation

/// Mutable model for editing a single header operation in the editor view.
@Observable
final class EditableHeaderOperation: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        phase: HeaderModifyPhase = .request,
        type: HeaderOperationType = .replace,
        headerName: String = "",
        headerValue: String = ""
    ) {
        self.id = id
        self.phase = phase
        self.type = type
        self.headerName = headerName
        self.headerValue = headerValue
    }

    convenience init(from operation: HeaderOperation) {
        self.init(
            phase: operation.phase,
            type: operation.type,
            headerName: operation.headerName,
            headerValue: operation.headerValue ?? ""
        )
    }

    // MARK: Internal

    let id: UUID
    var phase: HeaderModifyPhase
    var type: HeaderOperationType
    var headerName: String
    var headerValue: String

    var isValid: Bool {
        validationMessage == nil
    }

    var validationMessage: String? {
        guard !headerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Header Name is required")
        }
        if type != .remove, headerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Header Value is required for \(type.editorLabel)")
        }
        return nil
    }

    func toHeaderOperation() -> HeaderOperation {
        HeaderOperation(
            type: type,
            headerName: headerName.trimmingCharacters(in: .whitespacesAndNewlines),
            headerValue: type == .remove ? nil : headerValue.trimmingCharacters(in: .whitespacesAndNewlines),
            phase: phase
        )
    }
}

// MARK: - ModifyHeaderEditorView

/// Shared editor component for managing a list of header operations.
/// Used by both `RuleEditSheet` (inline quick-add) and `ModifyHeaderEditSheet`
/// (dedicated window editor). Supports add/remove rows, inline validation,
/// and phase selection per operation.
struct ModifyHeaderEditorView: View {
    // MARK: Internal

    @Binding var operations: [EditableHeaderOperation]

    var allValid: Bool {
        !operations.isEmpty && operations.allSatisfy { $0.validationMessage == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
            helperText

            if operations.isEmpty {
                emptyState
            } else {
                operationsTable
            }

            addButton

            validationMessages
        }
        .font(toolMetrics.font())
    }

    // MARK: Private

    private static let minFieldWidth: CGFloat = 150

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var phaseWidth: CGFloat {
        operationMenuWidth
    }

    private var operationWidth: CGFloat {
        operationMenuWidth
    }

    private var operationMenuWidth: CGFloat {
        toolMetrics.menuWidth(112)
    }

    private var fieldMinWidth: CGFloat {
        toolMetrics.fieldWidth(Self.minFieldWidth)
    }

    private var removeWidth: CGFloat {
        max(24, toolMetrics.compactButtonSize)
    }

    private var orderWidth: CGFloat {
        24
    }

    private var reorderWidth: CGFloat {
        toolMetrics.compactButtonSize
    }

    private var rowSpacing: CGFloat {
        toolMetrics.controlSpacing
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var helperText: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Operations are applied in order. Later rows can overwrite earlier rows."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.72))
            Spacer()
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text(String(localized: "No operations. Add at least one header operation."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var operationsTable: some View {
        VStack(spacing: 0) {
            headerRow

            VStack(spacing: 6) {
                ForEach(Array(operations.enumerated()), id: \.element.id) { index, operation in
                    operationRow(operation, index: index)
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var headerRow: some View {
        HStack(spacing: rowSpacing) {
            Text(verbatim: "#")
                .frame(width: orderWidth, alignment: .trailing)
            Text(String(localized: "Phase"))
                .frame(width: phaseWidth, alignment: .leading)
            Text(String(localized: "Operation"))
                .frame(width: operationWidth, alignment: .leading)
            Text(String(localized: "Header Name"))
                .frame(minWidth: fieldMinWidth, maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Header Value"))
                .frame(minWidth: fieldMinWidth, maxWidth: .infinity, alignment: .leading)
            Spacer()
                .frame(width: reorderWidth)
            Spacer()
                .frame(width: removeWidth)
        }
        .font(toolMetrics.font(weight: .semibold))
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var addButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                operations.append(EditableHeaderOperation())
            }
        } label: {
            Label(String(localized: "Add Operation"), systemImage: "plus")
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(toolMetrics.font())
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 2)
    }

    @ViewBuilder private var validationMessages: some View {
        let invalidOps = operations.enumerated().compactMap { index, op -> (Int, String)? in
            guard let message = op.validationMessage else {
                return nil
            }
            return (index, message)
        }
        if !invalidOps.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(invalidOps, id: \.0) { index, message in
                    Text(String(localized: "Row \(index + 1): \(message)"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func operationRow(_ operation: EditableHeaderOperation, index: Int) -> some View {
        HStack(spacing: rowSpacing) {
            Text("\(index + 1)")
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
                .frame(width: orderWidth, alignment: .trailing)
                .accessibilityLabel(String(localized: "Operation \(index + 1)"))

            Menu {
                ForEach(HeaderModifyPhase.allCases, id: \.self) { phase in
                    Button {
                        operation.phase = phase
                    } label: {
                        menuCheckmarkLabel(phaseLabel(phase), isSelected: operation.phase == phase)
                    }
                }
            } label: {
                dataEntryMenuLabel(phaseLabel(operation.phase), width: phaseWidth)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .font(toolMetrics.font())
            .controlSize(.regular)
            .frame(width: phaseWidth, height: toolMetrics.formControlHeight)

            Menu {
                ForEach(HeaderOperationType.allCases, id: \.self) { type in
                    Button {
                        operation.type = type
                    } label: {
                        menuCheckmarkLabel(type.editorLabel, isSelected: operation.type == type)
                    }
                }
            } label: {
                dataEntryMenuLabel(operation.type.editorLabel, width: operationWidth)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .font(toolMetrics.font())
            .controlSize(.regular)
            .frame(width: operationWidth, height: toolMetrics.formControlHeight)

            TextField(
                String(localized: "e.g. X-Debug-Mode"),
                text: Binding(
                    get: { operation.headerName },
                    set: { operation.headerName = $0 }
                )
            )
            .font(toolMetrics.font())
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .frame(minWidth: fieldMinWidth)
            .frame(height: toolMetrics.formControlHeight)

            headerValueField(for: operation)

            Button {
                move(operation, by: reorderDelta(for: index))
            } label: {
                Image(systemName: reorderIconName(for: index))
                    .font(toolMetrics.secondaryFont())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(operations.count < 2)
            .help(reorderHelp(for: index))
            .accessibilityLabel(reorderAccessibilityLabel(for: index))
            .frame(width: reorderWidth, height: toolMetrics.formControlHeight)

            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    operations.removeAll { $0.id == operation.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(toolMetrics.secondaryFont())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Remove operation"))
            .accessibilityLabel(String(localized: "Remove operation \(index + 1)"))
            .frame(width: removeWidth, height: toolMetrics.formControlHeight)
        }
        .frame(minHeight: toolMetrics.formControlHeight)
    }

    @ViewBuilder
    private func headerValueField(for operation: EditableHeaderOperation) -> some View {
        if operation.type == .remove {
            Text(String(localized: "Not used"))
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .frame(minWidth: fieldMinWidth, alignment: .leading)
                .frame(height: toolMetrics.formControlHeight, alignment: .leading)
                .padding(.horizontal, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            TextField(
                String(localized: "e.g. enabled"),
                text: Binding(
                    get: { operation.headerValue },
                    set: { operation.headerValue = $0 }
                )
            )
            .font(toolMetrics.font())
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .frame(minWidth: fieldMinWidth)
            .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func move(_ operation: EditableHeaderOperation, by delta: Int) {
        guard let index = operations.firstIndex(where: { $0.id == operation.id }) else {
            return
        }
        let target = index + delta
        guard operations.indices.contains(target) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            operations.swapAt(index, target)
        }
    }

    private func reorderDelta(for index: Int) -> Int {
        index == operations.count - 1 ? -1 : 1
    }

    private func reorderIconName(for index: Int) -> String {
        index == operations.count - 1 ? "chevron.up" : "chevron.down"
    }

    private func reorderHelp(for index: Int) -> String {
        index == operations.count - 1
            ? String(localized: "Move operation up")
            : String(localized: "Move operation down")
    }

    private func reorderAccessibilityLabel(for index: Int) -> String {
        index == operations.count - 1
            ? String(localized: "Move operation \(index + 1) up")
            : String(localized: "Move operation \(index + 1) down")
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: toolMetrics.formControlHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func phaseLabel(_ phase: HeaderModifyPhase) -> String {
        switch phase {
        case .request:
            String(localized: "Request")
        case .response:
            String(localized: "Response")
        case .both:
            String(localized: "Both")
        }
    }
}

// MARK: - Helper: Build Operations from Editable Models

extension [EditableHeaderOperation] {
    func toHeaderOperations() -> [HeaderOperation] {
        map { $0.toHeaderOperation() }
    }

    static func from(_ operations: [HeaderOperation]) -> [EditableHeaderOperation] {
        if operations.isEmpty {
            return [EditableHeaderOperation()]
        }
        return operations.map { EditableHeaderOperation(from: $0) }
    }
}

// MARK: - Helper: Phase Summary

extension [HeaderOperation] {
    /// Computes the phase summary label for display in rule lists.
    var phaseSummaryLabel: String {
        guard !isEmpty else {
            return ""
        }
        let phases = Set(map(\.phase))
        if phases == [.request] {
            return "Req"
        }
        if phases == [.response] {
            return "Resp"
        }
        if phases == [.both] {
            return "Both"
        }
        return "Mixed"
    }

    /// Generates shorthand summary: +HeaderA, -HeaderB, ~HeaderC
    var operationSummary: String {
        map { op in
            let prefix = switch op.type {
            case .add: "+"
            case .remove: "-"
            case .replace: "~"
            }
            return "\(prefix)\(op.headerName)"
        }
        .joined(separator: ", ")
    }
}

// MARK: - HeaderOperationType + Editor Labels

extension HeaderOperationType {
    var editorLabel: String {
        switch self {
        case .add:
            String(localized: "Add")
        case .remove:
            String(localized: "Remove")
        case .replace:
            String(localized: "Set")
        }
    }
}
