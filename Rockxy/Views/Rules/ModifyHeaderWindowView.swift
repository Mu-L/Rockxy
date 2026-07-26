import os
import SwiftUI

// Dedicated window for managing Modify Header rules. Displays a table of all
// modifyHeader rules with enable toggles, URL patterns, operation counts, phase
// summary, and operation shorthand. Supports add/edit/delete with a modal sheet.

// MARK: - ModifyHeaderEditorSession

struct ModifyHeaderEditorSession: Identifiable {
    enum Mode {
        case create
        case edit(rule: ProxyRule)
    }

    let id = UUID()
    let mode: Mode
}

// MARK: - ModifyHeaderWindowViewModel

@MainActor @Observable
final class ModifyHeaderWindowViewModel {
    // MARK: Lifecycle

    init(isToolEnabled: Bool? = nil) {
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
    }

    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
    var selectedRuleID: UUID?
    var editorSession: ModifyHeaderEditorSession?
    var searchText = "" {
        didSet {
            reconcileSelection()
        }
    }
    var isToolEnabled: Bool

    /// Unfiltered Modify Header rules in their global evaluation order.
    var headerRules: [ProxyRule] {
        allRules.filter { rule in
            if case .modifyHeader = rule.action {
                return true
            }
            return false
        }
    }

    var modifyHeaderRules: [ProxyRule] {
        guard !searchText.isEmpty else {
            return headerRules
        }
        return headerRules.filter { rule in
            rule.name.localizedCaseInsensitiveContains(searchText)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(searchText)
                || operationSummary(for: rule).localizedCaseInsensitiveContains(searchText)
        }
    }

    var ruleCount: Int {
        modifyHeaderRules.count
    }

    var activeRuleCount: Int {
        headerRules.filter(\.isEnabled).count
    }

    /// Row reordering is only coherent against the full, unfiltered list, so it is
    /// disabled while a search filter narrows the visible rows.
    var isReorderable: Bool {
        searchText.isEmpty
    }

    /// Reorders the global rule array so the Modify Header rules follow `orderedSubset`,
    /// while every non-Modify-Header rule keeps its exact original index. `orderedSubset`
    /// must be a permutation of the array's existing Modify Header rules.
    static func applyingModifyHeaderOrder(
        _ orderedSubset: [ProxyRule],
        to allRules: [ProxyRule]
    )
        -> [ProxyRule]
    {
        let currentIDs = allRules.compactMap { rule -> UUID? in
            if case .modifyHeader = rule.action {
                return rule.id
            }
            return nil
        }
        guard orderedSubset.count == currentIDs.count,
              Set(orderedSubset.map(\.id)) == Set(currentIDs)
        else {
            return allRules
        }

        var iterator = orderedSubset.makeIterator()
        return allRules.map { rule in
            if case .modifyHeader = rule.action {
                return iterator.next() ?? rule
            }
            return rule
        }
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
        reconcileSelection()
    }

    func setToolEnabled(_ enabled: Bool) {
        isToolEnabled = enabled
        enqueueMutation {
            await RulePolicyGate.shared.setModifyHeaderToolEnabled(enabled)
        }
    }

    func moveRules(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard isReorderable else {
            return
        }
        var subset = headerRules
        subset.move(fromOffsets: source, toOffset: destination)
        let updated = Self.applyingModifyHeaderOrder(subset, to: allRules)
        guard updated.map(\.id) != allRules.map(\.id) else {
            return
        }
        allRules = updated
        let orderedIDs = subset.map(\.id)
        enqueueMutation { [self] in
            await RulePolicyGate.shared.reorderModifyHeaderRules(orderedIDs: orderedIDs)
            self.allRules = await RuleEngine.shared.allRules
            self.reconcileSelection()
        }
    }

    func waitForPendingRuleSync() async {
        await pendingRuleSyncTask?.value
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            reconcileSelection()
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        enqueueMutation { [self] in
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            self.allRules = await RuleEngine.shared.allRules
            self.reconcileSelection()
            return accepted
        }
    }

    func presentNewRuleEditor() {
        editorSession = ModifyHeaderEditorSession(mode: .create)
    }

    func presentEditorForSelection() {
        guard let id = selectedRuleID,
              let rule = allRules.first(where: { $0.id == id }) else
        {
            return
        }
        editorSession = ModifyHeaderEditorSession(mode: .edit(rule: rule))
    }

    func dismissEditor() {
        editorSession = nil
    }

    @discardableResult
    func addRule(_ rule: ProxyRule) async -> Bool {
        let task = enqueueMutation { [self] in
            let accepted = await RulePolicyGate.shared.addRule(rule)
            self.allRules = await RuleEngine.shared.allRules
            if accepted {
                self.selectedRuleID = rule.id
            }
            return accepted
        }
        return await task.value
    }

    @discardableResult
    func updateRule(_ rule: ProxyRule) async -> Bool {
        guard allRules.contains(where: { $0.id == rule.id }) else {
            return false
        }
        let task = enqueueMutation { [self] in
            await RulePolicyGate.shared.updateRule(rule)
            self.allRules = await RuleEngine.shared.allRules
            self.selectedRuleID = rule.id
            return true
        }
        return await task.value
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        enqueueMutation { [self] in
            await RulePolicyGate.shared.removeRule(id: id)
            self.allRules = await RuleEngine.shared.allRules
            self.reconcileSelection()
        }
    }

    @discardableResult
    func saveRule(
        existingRule: ProxyRule?,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool,
        operations: [EditableHeaderOperation]
    )
        async -> Bool
    {
        let rule = ModifyHeaderRuleBuilder.build(
            existingRule: existingRule,
            ruleName: ruleName,
            rawPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            operations: operations.toHeaderOperations()
        )
        if existingRule == nil {
            return await addRule(rule)
        }
        return await updateRule(rule)
    }

    func operations(for rule: ProxyRule) -> [HeaderOperation] {
        if case let .modifyHeader(ops) = rule.action {
            return ops
        }
        return []
    }

    func operationCount(for rule: ProxyRule) -> Int {
        operations(for: rule).count
    }

    func phaseSummary(for rule: ProxyRule) -> String {
        operations(for: rule).phaseSummaryLabel
    }

    func scopeSummary(for rule: ProxyRule) -> String {
        let phases = Set(operations(for: rule).map(\.phase))
        if phases == [.request] {
            return String(localized: "Request")
        }
        if phases == [.response] {
            return String(localized: "Response")
        }
        return String(localized: "Both")
    }

    func operationSummary(for rule: ProxyRule) -> String {
        operations(for: rule).operationSummary
    }

    // MARK: Private

    private static let toolEnabledKey = "modifyHeaderToolEnabled"
    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ModifyHeaderWindowViewModel"
    )

    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private var pendingRuleSyncTask: Task<Void, Never>?

    @discardableResult
    private func enqueueMutation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    )
        -> Task<Result, Never>
    {
        let previousTask = pendingRuleSyncTask
        let task = Task { @MainActor in
            await previousTask?.value
            return await operation()
        }
        pendingRuleSyncTask = Task { @MainActor in
            _ = await task.value
        }
        return task
    }

    private func reconcileSelection() {
        guard let selectedRuleID else {
            return
        }
        if !modifyHeaderRules.contains(where: { $0.id == selectedRuleID }) {
            self.selectedRuleID = nil
        }
    }
}

// MARK: - ModifyHeaderWindowView

struct ModifyHeaderWindowView: View {
    // MARK: Internal

    @State var viewModel = ModifyHeaderWindowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            content
            Divider()
            bottomBar
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .task { await viewModel.refreshFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(item: $viewModel.editorSession) { session in
            ModifyHeaderEditSheet(session: session) { name, pattern, method, matchType, includeSubpaths, operations in
                let existingRule: ProxyRule? = if case let .edit(rule) = session.mode {
                    rule
                } else {
                    nil
                }
                let accepted = await viewModel.saveRule(
                    existingRule: existingRule,
                    ruleName: name,
                    urlPattern: pattern,
                    httpMethod: method,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths,
                    operations: operations
                )
                if accepted {
                    viewModel.dismissEditor()
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: Binding(
                    get: { viewModel.isToolEnabled },
                    set: { viewModel.setToolEnabled($0) }
                )) {
                    Text(String(localized: "Enable Modify Headers"))
                        .font(toolMetrics.font(weight: .medium))
                }
                .toggleStyle(.checkbox)
                .help(
                    String(
                        localized: "When off, Modify Header rules are skipped during evaluation. Other rule types are unaffected."
                    )
                )
                .accessibilityLabel(String(localized: "Enable Modify Headers"))

                Text(String(localized: "Apply ordered header operations to matching requests and responses."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Search Modify Header rules"))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
    }

    @ViewBuilder private var content: some View {
        if viewModel.modifyHeaderRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "list.bullet.header")
                    .font(.system(size: max(20, toolMetrics.bodyFontSize + 7)))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Modify Header Rules"))
                    .font(toolMetrics.font(weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Add rules to modify HTTP request and response headers."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                List(selection: $viewModel.selectedRuleID) {
                    if viewModel.isReorderable {
                        ForEach(viewModel.modifyHeaderRules) { rule in
                            ruleRow(rule)
                        }
                        .onMove { source, destination in
                            viewModel.moveRules(fromOffsets: source, toOffset: destination)
                        }
                    } else {
                        ForEach(viewModel.modifyHeaderRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: UUID.self) { _ in
                    contextMenuItems
                } primaryAction: { _ in
                    viewModel.presentEditorForSelection()
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer().frame(width: 24)
            Text(verbatim: "#")
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(String(localized: "Name"))
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
            Text(String(localized: "Scope"))
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(String(localized: "Match"))
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Ops"))
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .frame(height: toolMetrics.tableRowHeight)
        .background(.background.tertiary)
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "Set, add, or remove HTTP headers on matching requests and responses. Each rule can have multiple header operations."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(.quaternary.opacity(0.5))
    }

    private var bottomBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button {
                viewModel.presentNewRuleEditor()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule"))
            .accessibilityLabel(String(localized: "New Modify Header rule"))

            Button {
                guard let id = viewModel.selectedRuleID else {
                    return
                }
                viewModel.removeRule(id: id)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule"))
            .accessibilityLabel(String(localized: "Delete selected Modify Header rule"))

            presetsMenu

            Divider()
                .frame(height: max(16, toolMetrics.footerControlHeight - 10))

            Text(footerHint)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)

            Spacer()

            Text(
                viewModel.isToolEnabled
                    ? "\(viewModel.activeRuleCount) \(String(localized: "ACTIVE"))"
                    : String(localized: "MODIFY HEADERS OFF")
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .foregroundStyle(viewModel.isToolEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(viewModel.isToolEnabled ? Color.green : Color.secondary.opacity(0.14))
            .clipShape(Capsule())
            .accessibilityLabel(
                viewModel.isToolEnabled
                    ? String(localized: "\(viewModel.activeRuleCount) active Modify Header rules")
                    : String(localized: "Modify Headers is off")
            )
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
    }

    @ViewBuilder private var contextMenuItems: some View {
        Button(String(localized: "Edit…")) {
            viewModel.presentEditorForSelection()
        }
        .keyboardShortcut("e", modifiers: .command)

        Divider()

        Button(String(localized: "Delete"), role: .destructive) {
            if let id = viewModel.selectedRuleID {
                viewModel.removeRule(id: id)
            }
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private var presetsMenu: some View {
        Menu {
            Button(String(localized: "Add CORS Headers")) {
                Task { await viewModel.addRule(HeaderModifyPresets.corsHeaders()) }
            }
            Button(String(localized: "Remove Authorization")) {
                Task { await viewModel.addRule(HeaderModifyPresets.removeAuthorization()) }
            }
            Button(String(localized: "Strip Server Header")) {
                Task { await viewModel.addRule(HeaderModifyPresets.stripServerHeader()) }
            }
        } label: {
            Label {
                Text(String(localized: "Presets"))
            } icon: {
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }

    private var footerHint: String {
        let countText: String
        if viewModel.searchText.isEmpty {
            countText = "\(viewModel.headerRules.count) \(String(localized: "rules"))"
        } else {
            countText = String(
                localized: "\(viewModel.modifyHeaderRules.count) of \(viewModel.headerRules.count) rules"
            )
        }
        let reorderHint = viewModel.isReorderable
            ? String(localized: "Drag rows to reorder")
            : String(localized: "Clear search to reorder")
        return "\(countText) · ⌘N \(String(localized: "New Rule")) · \(reorderHint)"
    }

    @ViewBuilder
    private func ruleRow(_ rule: ProxyRule) -> some View {
        let order = (viewModel.modifyHeaderRules.firstIndex { $0.id == rule.id } ?? 0) + 1
        ModifyHeaderRuleRow(
            order: order,
            rule: rule,
            operationCount: viewModel.operationCount(for: rule),
            scopeSummary: viewModel.scopeSummary(for: rule)
        ) {
            viewModel.toggleRule(id: rule.id)
        }
        .tag(rule.id)
    }
}

// MARK: - ModifyHeaderRuleRow

private struct ModifyHeaderRuleRow: View {
    // MARK: Internal

    let order: Int
    let rule: ProxyRule
    let operationCount: Int
    let scopeSummary: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)
            .help(rule.isEnabled ? String(localized: "Disable this rule") : String(localized: "Enable this rule"))
            .accessibilityLabel(String(localized: "Enable \(rule.name)"))

            Text("\(order)")
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityLabel(String(localized: "Order \(order)"))

            Text(rule.name)
                .font(toolMetrics.font(weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 220, alignment: .leading)

            Text(scopeSummary)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            HStack(spacing: 6) {
                Text(rule.matchCondition.method ?? "ANY")
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .leading)
                Text(rule.matchCondition.urlPattern ?? ".*")
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.matchCondition.urlPattern ?? ".*")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(operationCount) \(operationCount == 1 ? String(localized: "op") : String(localized: "ops"))")
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .frame(minHeight: toolMetrics.tableRowHeight)
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - ModifyHeaderEditSheet

private struct ModifyHeaderEditSheet: View {
    // MARK: Lifecycle

    init(
        session: ModifyHeaderEditorSession,
        onSave: @escaping (String, String, HTTPMethodFilter, RuleMatchType, Bool, [EditableHeaderOperation]) async
            -> Void
    ) {
        self.session = session
        self.onSave = onSave

        switch session.mode {
        case .create:
            _name = State(initialValue: "")
            _urlPattern = State(initialValue: "*")
            _httpMethod = State(initialValue: .any)
            _matchType = State(initialValue: .wildcard)
            _includeSubpaths = State(initialValue: true)
            _operations = State(initialValue: [EditableHeaderOperation()])
        case let .edit(rule):
            _name = State(initialValue: rule.name)
            _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? ".*")
            let normalizedMethod = rule.matchCondition.method?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            _httpMethod = State(
                initialValue: normalizedMethod.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
            )
            _matchType = State(initialValue: .regex)
            _includeSubpaths = State(initialValue: false)
            if case let .modifyHeader(ops) = rule.action {
                _operations = State(initialValue: [EditableHeaderOperation].from(ops))
            } else {
                _operations = State(initialValue: [EditableHeaderOperation()])
            }
        }
    }

    // MARK: Internal

    let session: ModifyHeaderEditorSession
    let onSave: (String, String, HTTPMethodFilter, RuleMatchType, Bool, [EditableHeaderOperation]) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Text(isEditing ? String(localized: "Edit Header Rule") : String(localized: "New Header Rule"))
                    .font(
                        .system(
                            size: max(15, toolMetrics.bodyFontSize + 2),
                            weight: .semibold
                        )
                    )

                identityFields
                methodAndMatchRow

                conditionalFields

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Ordered Operations"))
                        .font(toolMetrics.font(weight: .semibold))
                    ScrollView {
                        ModifyHeaderEditorView(operations: $operations)
                    }
                    .frame(minHeight: max(300, toolMetrics.bodyFontSize * 12 + 144))
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel"))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        isSaving = true
                        await onSave(
                            trimmedName,
                            trimmedPattern,
                            httpMethod,
                            matchType,
                            matchType == .wildcard ? includeSubpaths : false,
                            operations
                        )
                        isSaving = false
                    }
                } label: {
                    footerButtonLabel(
                        isEditing ? String(localized: "Save") : String(localized: "Add")
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(720, toolMetrics.bodyFontSize * 24 + 408))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @State private var name = ""
    @State private var urlPattern = ""
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: RuleMatchType
    @State private var includeSubpaths: Bool
    @State private var operations: [EditableHeaderOperation] = [EditableHeaderOperation()]
    @State private var isSaving = false

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPattern: String {
        urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedPattern.isEmpty
            && !operations.isEmpty
            && operations.allSatisfy(\.isValid)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var identityFields: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            fieldGroup(String(localized: "Name")) {
                TextField(String(localized: "Untitled"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Rule name"))
            }
            .frame(width: max(250, toolMetrics.fieldWidth(250)))

            fieldGroup(String(localized: "URL pattern")) {
                TextField("https://example.com/api/*", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "URL pattern"))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var methodAndMatchRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
            inlineField(String(localized: "Method")) {
                Menu {
                    ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                        Button {
                            httpMethod = method
                        } label: {
                            menuCheckmarkLabel(method.rawValue, isSelected: httpMethod == method)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(httpMethod.rawValue, width: toolMetrics.menuWidth(90))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "HTTP Method"))
                .frame(width: toolMetrics.menuWidth(90))
            }

            inlineField(String(localized: "Match type")) {
                Menu {
                    ForEach(RuleMatchType.allCases, id: \.self) { type in
                        Button {
                            matchType = type
                        } label: {
                            menuCheckmarkLabel(type.rawValue, isSelected: matchType == type)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(matchType.rawValue, width: toolMetrics.menuWidth(175))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Match Type"))
                .frame(width: toolMetrics.menuWidth(175))
            }

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                .toggleStyle(.checkbox)
                .font(toolMetrics.font())
        }
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func fieldGroup(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 6)
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

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }
}
