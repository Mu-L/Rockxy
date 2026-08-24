import SwiftUI

// MARK: - BreakpointRulesViewModel

@MainActor @Observable
final class BreakpointRulesViewModel {
    init(syncsChanges: Bool = !RockxyIdentity.isRunningTests) {
        self.syncsChanges = syncsChanges
    }

    var selectedRuleID: UUID?
    var searchText = "" {
        didSet {
            reconcileSelection(requireVisible: true)
        }
    }

    var mutationError: String?
    private(set) var allRules: [ProxyRule] = []

    var isBreakpointToolEnabled: Bool = UserDefaults.standard.object(
        forKey: "breakpointToolEnabled"
    ) as? Bool ?? true

    var breakpointRules: [ProxyRule] {
        allRules.filter {
            if case .breakpoint = $0.action {
                return true
            }
            return false
        }
    }

    var filteredBreakpointRules: [ProxyRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return breakpointRules
        }
        return breakpointRules.filter { rule in
            let decoded = BreakpointRuleForm.decode(rule: rule)
            return rule.name.localizedCaseInsensitiveContains(query)
                || decoded.displayPattern.localizedCaseInsensitiveContains(query)
                || methodLabel(for: rule).localizedCaseInsensitiveContains(query)
                || phaseLabel(for: rule).localizedCaseInsensitiveContains(query)
        }
    }

    var ruleCount: Int {
        breakpointRules.count
    }

    var activeRuleCount: Int {
        breakpointRules.count(where: \.isEnabled)
    }

    var selectedRule: ProxyRule? {
        guard let selectedRuleID else {
            return nil
        }
        return breakpointRules.first { $0.id == selectedRuleID }
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
        reconcileSelection()
    }

    func handleRulesDidChange(_ notification: Notification) {
        guard let rules = notification.object as? [ProxyRule] else {
            return
        }
        allRules = rules
        reconcileSelection()
    }

    func addBreakpointRule(
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool
    ) {
        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: ruleName,
            rawPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            phaseRequest: phaseRequest,
            phaseResponse: phaseResponse,
            includeSubpaths: includeSubpaths
        )
        allRules.append(rule)
        selectedRuleID = rule.id
        guard syncsChanges else {
            return
        }
        enqueueMutation { [self] in
            let accepted = await RulePolicyGate.shared.addRule(rule)
            await refreshAfterMutation(selecting: accepted ? rule.id : nil)
            if !accepted {
                mutationError = quotaError
            }
        }
    }

    func updateRule(
        id: UUID,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool
    ) {
        guard let original = allRules.first(where: { $0.id == id }) else {
            return
        }
        let rule = BreakpointRuleForm.makeRule(
            original: original,
            ruleName: ruleName,
            rawPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            phaseRequest: phaseRequest,
            phaseResponse: phaseResponse,
            includeSubpaths: includeSubpaths
        )
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index] = rule
        selectedRuleID = rule.id
        guard syncsChanges else {
            return
        }
        enqueueMutation { [self] in
            await RulePolicyGate.shared.updateRule(rule)
            await refreshAfterMutation(selecting: rule.id)
        }
    }

    @discardableResult
    func saveRule(
        original: ProxyRule?,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool,
        using gate: RulePolicyGate = .shared
    ) async -> Bool {
        let rule = BreakpointRuleForm.makeRule(
            original: original,
            ruleName: ruleName,
            rawPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            phaseRequest: phaseRequest,
            phaseResponse: phaseResponse,
            includeSubpaths: includeSubpaths
        )

        guard syncsChanges else {
            if let index = allRules.firstIndex(where: { $0.id == rule.id }) {
                allRules[index] = rule
            } else {
                allRules.append(rule)
            }
            selectedRuleID = rule.id
            return true
        }

        let task = enqueueMutation { [self] in
            if original == nil {
                let accepted = await gate.addRule(rule)
                guard accepted else {
                    await refreshAfterMutation(selecting: nil)
                    mutationError = quotaError
                    return false
                }
            } else {
                await gate.updateRule(rule)
            }
            await refreshAfterMutation(selecting: rule.id)
            return true
        }
        return await task.value
    }

    func removeSelected() {
        guard let selectedRuleID else {
            return
        }
        removeRule(id: selectedRuleID)
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        guard syncsChanges else {
            return
        }
        enqueueMutation { [self] in
            await RulePolicyGate.shared.removeRule(id: id)
            await refreshAfterMutation(selecting: nil)
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        guard syncsChanges else {
            return
        }
        enqueueMutation { [self] in
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            await refreshAfterMutation(selecting: id)
            if !accepted {
                mutationError = quotaError
            }
        }
    }

    func duplicateRule(id: UUID) {
        guard let original = breakpointRules.first(where: { $0.id == id }) else {
            return
        }
        let copy = ProxyRule(
            name: String(localized: "Copy of \(original.name)"),
            isEnabled: original.isEnabled,
            matchCondition: original.matchCondition,
            action: original.action,
            priority: original.priority
        )
        allRules.append(copy)
        selectedRuleID = copy.id
        guard syncsChanges else {
            return
        }
        enqueueMutation { [self] in
            let accepted = await RulePolicyGate.shared.addRule(copy)
            await refreshAfterMutation(selecting: accepted ? copy.id : nil)
            if !accepted {
                mutationError = quotaError
            }
        }
    }

    func toggleBreakpointTool() {
        setBreakpointToolEnabled(!isBreakpointToolEnabled)
    }

    func setBreakpointToolEnabled(_ enabled: Bool) {
        isBreakpointToolEnabled = enabled
        guard syncsChanges else {
            return
        }
        enqueueMutation {
            await RulePolicyGate.shared.setBreakpointToolEnabled(enabled)
        }
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        BreakpointRuleForm.decode(rule: rule).displayPattern
    }

    func matchTypeLabel(for rule: ProxyRule) -> String {
        switch BreakpointRuleForm.decode(rule: rule).matchType {
        case .wildcard:
            String(localized: "Wildcard")
        case .regex:
            String(localized: "Regex")
        }
    }

    func phaseLabel(for rule: ProxyRule) -> String {
        guard case let .breakpoint(phase) = rule.action else {
            return String(localized: "Both")
        }
        switch phase {
        case .request:
            return String(localized: "Request")
        case .response:
            return String(localized: "Response")
        case .both:
            return String(localized: "Request + Response")
        }
    }

    func breaksOnRequest(_ rule: ProxyRule) -> Bool {
        guard case let .breakpoint(phase) = rule.action else {
            return false
        }
        return phase == .request || phase == .both
    }

    func breaksOnResponse(_ rule: ProxyRule) -> Bool {
        guard case let .breakpoint(phase) = rule.action else {
            return false
        }
        return phase == .response || phase == .both
    }

    private let syncsChanges: Bool
    private var pendingRuleSyncTask: Task<Void, Never>?

    private var quotaError: String {
        String(localized: "The active Breakpoint rule limit was reached. Disable another rule and try again.")
    }

    @discardableResult
    private func enqueueMutation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    ) -> Task<Result, Never> {
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

    private func refreshAfterMutation(selecting ruleID: UUID?) async {
        allRules = await RuleEngine.shared.allRules
        selectedRuleID = ruleID
        reconcileSelection()
    }

    private func reconcileSelection(requireVisible: Bool = false) {
        guard let selectedRuleID else {
            return
        }
        let candidates = requireVisible ? filteredBreakpointRules : breakpointRules
        if !candidates.contains(where: { $0.id == selectedRuleID }) {
            self.selectedRuleID = nil
        }
    }
}

// MARK: - BreakpointRulesWindowView

struct BreakpointRulesWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            Divider()
            tableContent
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBreakpointRulesWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Breakpoint Rules"),
            isPresented: Binding(
                get: { viewModel.mutationError != nil },
                set: { if !$0 { viewModel.mutationError = nil } }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.mutationError = nil }
        } message: {
            if let mutationError = viewModel.mutationError {
                Text(mutationError)
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = BreakpointRulesViewModel()

    private var header: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { viewModel.isBreakpointToolEnabled },
                    set: { viewModel.setBreakpointToolEnabled($0) }
                )) {
                    Text(String(localized: "Enable Breakpoint Tool"))
                        .font(toolMetrics.font(weight: .medium))
                }
                .toggleStyle(.checkbox)

                Text(String(localized: "Pause matching traffic before it continues through the proxy."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Search Breakpoint rules"))
                .keyboardShortcut("f", modifiers: .command)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerTopPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(
                String(
                    localized:
                    """
                    The first enabled rule that matches pauses the request, response, or both. \
                    Disabling a rule affects future matches; traffic already waiting remains in the Breakpoint Queue.
                    """
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color.accentColor.opacity(0.055))
    }

    private var tableContent: some View {
        Table(viewModel.filteredBreakpointRules, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Enabled")) { rule in
                HStack {
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(
                        rule.isEnabled
                            ? String(localized: "Disable \(rule.name)")
                            : String(localized: "Enable \(rule.name)")
                    )
                    Spacer()
                }
            }
            .width(72)

            TableColumn(String(localized: "Name")) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(rule.isEnabled ? 1 : 0.5)
                    .help(rule.name)
            }
            .width(min: 170, ideal: 220)

            TableColumn(String(localized: "Method")) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1 : 0.5)
            }
            .width(82)

            TableColumn(String(localized: "Match Type")) { rule in
                Text(viewModel.matchTypeLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1 : 0.5)
            }
            .width(92)

            TableColumn(String(localized: "Matching Rule")) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(rule.isEnabled ? 1 : 0.5)
                    .help(viewModel.matchingRuleLabel(for: rule))
            }
            .width(min: 280, ideal: 420)

            TableColumn(String(localized: "Pause Phase")) { rule in
                Text(viewModel.phaseLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1 : 0.5)
            }
            .width(min: 116, ideal: 138)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first,
                  let rule = viewModel.breakpointRules.first(where: { $0.id == id }) else {
                return
            }
            openEditor(for: rule)
        }
        .overlay {
            if viewModel.filteredBreakpointRules.isEmpty {
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No Matching Breakpoint Rules")
                        : String(localized: "No Breakpoint Rules"),
                    systemImage: isSearching ? "magnifyingglass" : "pause.circle",
                    description: Text(
                        isSearching
                            ? String(localized: "Try a different name, method, phase, or URL pattern.")
                            : String(localized: "Click + or create a rule from captured traffic.")
                    )
                )
            }
        }
        .font(toolMetrics.font())
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            compactAddRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(String(localized: "Open Queue")) {
                openWindow(id: "breakpoints")
            }

            Button(String(localized: "Templates…")) {
                openWindow(id: "breakpointTemplates")
            }
            .keyboardShortcut("t", modifiers: .command)

            moreMenu
            statusCapsule
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var compactAddRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                openNewEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel(String(localized: "New Breakpoint rule"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            Button {
                viewModel.removeSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
            .accessibilityLabel(String(localized: "Delete selected Breakpoint rule"))
        }
        .foregroundStyle(.primary)
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule")) {
                openNewEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.selectedRule {
                    openEditor(for: rule)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRule == nil)

            Button(String(localized: "Duplicate")) {
                if let id = viewModel.selectedRuleID {
                    viewModel.duplicateRule(id: id)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Delete Rule"), role: .destructive) {
                viewModel.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    private var statusCapsule: some View {
        Text(statusText)
            .font(toolMetrics.secondaryFont(weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: toolMetrics.footerControlHeight)
            .rockxyChipStyle(isActive: viewModel.isBreakpointToolEnabled)
    }

    private var enableDisableLabel: String {
        guard let selectedRule = viewModel.selectedRule else {
            return String(localized: "Enable Rule")
        }
        return selectedRule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    private var footerHint: String {
        let count = isSearching
            ? "\(viewModel.filteredBreakpointRules.count) of \(viewModel.ruleCount)"
            : "\(viewModel.ruleCount)"
        return String(localized: "\(count) rules  •  ⌘N New  •  ⌘↩ Edit  •  ⌘D Duplicate  •  ⌘⌫ Delete")
    }

    private var statusText: String {
        guard viewModel.isBreakpointToolEnabled else {
            return String(localized: "BREAKPOINTS OFF")
        }
        return String(localized: "\(viewModel.activeRuleCount) ACTIVE")
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.breakpointRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate")) {
                viewModel.selectedRuleID = id
                viewModel.duplicateRule(id: id)
            }
            Button(
                viewModel.breakpointRules.first(where: { $0.id == id })?.isEnabled == true
                    ? String(localized: "Disable Rule")
                    : String(localized: "Enable Rule")
            ) {
                viewModel.toggleRule(id: id)
            }
            Divider()
            Button(String(localized: "Delete Rule"), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func openNewEditor(context: BreakpointEditorContext? = nil) {
        BreakpointRuleEditorStore.shared.openNew(context: context) {
            await viewModel.saveRule(
                original: nil,
                ruleName: $0,
                urlPattern: $1,
                httpMethod: $2,
                matchType: $3,
                phaseRequest: $4,
                phaseResponse: $5,
                includeSubpaths: $6
            )
        }
        openWindow(id: "breakpointRuleEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        BreakpointRuleEditorStore.shared.openExisting(rule) {
            await viewModel.saveRule(
                original: rule,
                ruleName: $0,
                urlPattern: $1,
                httpMethod: $2,
                matchType: $3,
                phaseRequest: $4,
                phaseResponse: $5,
                includeSubpaths: $6
            )
        }
        openWindow(id: "breakpointRuleEditor")
    }

    private func consumePendingContext() {
        guard let context = BreakpointEditorContextStore.shared.consumePending() else {
            return
        }
        openNewEditor(context: context)
    }
}
