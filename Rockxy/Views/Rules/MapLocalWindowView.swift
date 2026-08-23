import AppKit
import os
import SwiftUI

// Presents the native Map Local management and editor windows.

// MARK: - MapLocalViewModel

@MainActor @Observable
final class MapLocalViewModel {
    // MARK: Lifecycle

    init(isToolEnabled: Bool? = nil) {
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
    }

    // MARK: Internal

    var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleIDs: Set<UUID> = []
    var isToolEnabled: Bool
    var errorMessage: String?

    var mapLocalRules: [ProxyRule] {
        allRules.filter {
            if case .mapLocal = $0.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return mapLocalRules
        }
        return mapLocalRules.filter { rule in
            rule.name.lowercased().contains(query)
                || (rule.matchCondition.sourceURLPattern?.lowercased().contains(query) ?? false)
                || (rule.matchCondition.urlPattern?.lowercased().contains(query) ?? false)
                || methodLabel(for: rule).lowercased().contains(query)
                || filePath(for: rule).lowercased().contains(query)
        }
    }

    var ruleCount: Int {
        mapLocalRules.count
    }

    var activeRuleCount: Int {
        mapLocalRules.filter(\.isEnabled).count
    }

    var selectedRule: ProxyRule? {
        guard let id = selectedRuleIDs.first else {
            return nil
        }
        return allRules.first { $0.id == id }
    }

    var areAllEnabled: Bool {
        get {
            let locals = mapLocalRules
            return !locals.isEmpty && locals.allSatisfy(\.isEnabled)
        }
        set {
            var updated = allRules
            for index in updated.indices {
                if case .mapLocal = updated[index].action {
                    updated[index].isEnabled = newValue
                }
            }
            allRules = updated
            Task {
                await RulePolicyGate.shared.replaceAllRules(updated)
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            selectedRuleIDs = selectedRuleIDs.filter { id in
                rules.contains { $0.id == id }
            }
        }
    }

    func setToolEnabled(_ enabled: Bool) {
        isToolEnabled = enabled
        Task { await RulePolicyGate.shared.setMapLocalToolEnabled(enabled) }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func addRule(_ rule: ProxyRule) {
        allRules.append(rule)
        selectedRuleIDs = [rule.id]
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        Task { await RulePolicyGate.shared.updateRule(rule) }
    }

    func removeSelectedRules() {
        let idsToRemove = selectedRuleIDs
        guard !idsToRemove.isEmpty else {
            return
        }
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        let updated = allRules
        Task { await RulePolicyGate.shared.replaceAllRules(updated) }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        selectedRuleIDs.remove(id)
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func duplicateSelectedRule() {
        guard var rule = selectedRule else {
            return
        }
        rule = ProxyRule(
            name: "\(rule.name) Copy",
            isEnabled: rule.isEnabled,
            matchCondition: rule.matchCondition,
            action: rule.action,
            priority: rule.priority
        )
        addRule(rule)
    }

    func filePath(for rule: ProxyRule) -> String {
        if case let .mapLocal(path, _, _, _) = rule.action {
            return path
        }
        return ""
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        if let sourcePattern = rule.matchCondition.sourceURLPattern,
           !sourcePattern.isEmpty
        {
            let prefix = rule.matchCondition.matchType == .regex ? "Regex: " : "Wildcard: "
            return prefix + sourcePattern
        }
        guard let pattern = rule.matchCondition.urlPattern, !pattern.isEmpty else {
            return "<Missing URL>"
        }
        if MapLocalPatternFormatter.prefersWildcardPresentation(pattern) {
            return "Wildcard: \(MapLocalPatternFormatter.readablePattern(pattern))"
        }
        return pattern
    }

    func mapFromLabel(for rule: ProxyRule) -> String {
        let prefix = isDirectory(for: rule) ? "Directory: " : "File: "
        let path = filePath(for: rule)
        return prefix + (path.isEmpty ? "<Missing Path>" : abbreviatedPath(path))
    }

    func isDirectory(for rule: ProxyRule) -> Bool {
        if case let .mapLocal(_, _, isDirectory, _) = rule.action {
            return isDirectory
        }
        return false
    }

    func delayLabel(for rule: ProxyRule) -> String {
        if case let .mapLocal(_, _, _, delayMs) = rule.action, delayMs != 0 {
            return MapLocalDelayPreset.from(delayMs: delayMs).displayName
        }
        return ""
    }

    // MARK: Private

    private static let toolEnabledKey = "mapLocalToolEnabled"
    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalViewModel")

    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private func abbreviatedPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return "<Missing Path>"
        }
        let maxLength = 78
        guard path.count > maxLength else {
            return path
        }
        let suffix = path.suffix(maxLength - 3)
        return "...\(suffix)"
    }
}

// MARK: - MapLocalWindowView

struct MapLocalWindowView: View {
    // MARK: Internal

    @State var viewModel = MapLocalViewModel()

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
        .onAppear { consumePendingDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
            consumePendingDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Map Local"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerHint: String {
        let countText = isSearching
            ? String(localized: "\(viewModel.filteredRules.count) of \(viewModel.ruleCount) rules")
            : String(localized: "\(viewModel.ruleCount) rules")
        return "\(countText) · ⌘N \(String(localized: "New Rule")) · ⌘↩ \(String(localized: "Edit"))"
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable Map Local"),
                    isOn: Binding(
                        get: { viewModel.isToolEnabled },
                        set: { viewModel.setToolEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))

                Text(String(localized: "Serve a local file or directory for matching requests."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Search Map Local rules"))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    "Map Local participates in Rockxy's global first-match rule order. A match returns the selected local response without contacting the remote server."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleIDs) {
            TableColumn(String(localized: "Enabled")) { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in viewModel.toggleRule(id: rule.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(62)

            TableColumn(String(localized: "Name")) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.name)
            }
            .width(min: 150, ideal: 190)

            TableColumn(String(localized: "Method")) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
            }
            .width(76)

            TableColumn(String(localized: "Matching Rule")) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(viewModel.matchingRuleLabel(for: rule))
            }
            .width(min: 220, ideal: 300)

            TableColumn(String(localized: "Local Response")) { rule in
                HStack(spacing: 6) {
                    Text(viewModel.mapFromLabel(for: rule))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(viewModel.filePath(for: rule))
                    if !viewModel.delayLabel(for: rule).isEmpty {
                        Text(viewModel.delayLabel(for: rule))
                            .font(toolMetrics.metadataFont(weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 280, ideal: 420)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first,
                  let rule = viewModel.allRules.first(where: { $0.id == id }) else
            {
                return
            }
            openEditor(for: rule)
        }
        .overlay {
            if viewModel.filteredRules.isEmpty {
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No matching rules")
                        : String(localized: "No Map Local rules"),
                    systemImage: isSearching ? "magnifyingglass" : "folder.badge.gearshape",
                    description: Text(
                        isSearching
                            ? String(localized: "Try a different name, method, URL, or local path.")
                            : String(localized: "Click \"+\" or press ⌘N to create a rule.")
                    )
                )
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

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(
                viewModel.isToolEnabled
                    ? "\(viewModel.activeRuleCount) \(String(localized: "ACTIVE"))"
                    : String(localized: "MAP LOCAL OFF")
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .rockxyChipStyle(tint: .green, isActive: viewModel.isToolEnabled)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                openNewEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                viewModel.removeSelectedRules()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
            .help(String(localized: "Remove Selected Rules"))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(
            width: max(43, toolMetrics.compactButtonSize * 2 + 1),
            height: toolMetrics.footerControlHeight
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule")) { openNewEditor() }
                .keyboardShortcut("n", modifiers: .command)
            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.selectedRule {
                    openEditor(for: rule)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Duplicate")) { viewModel.duplicateSelectedRule() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Toggle Enabled")) {
                if let id = viewModel.selectedRuleIDs.first {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRule == nil)
            Divider()
            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeSelectedRules()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate")) {
                viewModel.selectedRuleIDs = [id]
                viewModel.duplicateSelectedRule()
            }
            Divider()
            Button(String(localized: "Delete Rule"), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func openNewEditor(draft: MapLocalDraft? = nil) {
        MapLocalEditorStore.shared.openNew(draft: draft)
        openWindow(id: "mapLocalEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        MapLocalEditorStore.shared.openExisting(rule)
        openWindow(id: "mapLocalEditor")
    }

    private func consumePendingDraftIfNeeded() {
        guard let draft = MapLocalDraftStore.shared.consumePending() else {
            return
        }
        openNewEditor(draft: draft)
    }
}

// MARK: - MapLocalEditorWindowView

struct MapLocalEditorWindowView: View {
    // MARK: Internal

    @State var viewModel = MapLocalEditorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))

                    if let provenance = quickCreateProvenance {
                        provenanceBanner(provenance)
                    }

                    ruleDetailsSection
                    responseSourceSection
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496))
        .frame(height: max(680, toolMetrics.bodyFontSize * 20 + 420))
        .navigationTitle(viewModel.windowTitle)
        .onAppear { viewModel.load(context: editorStore.context) }
        .onChange(of: editorStore.draftVersion) { _, _ in
            viewModel.load(context: editorStore.context)
        }
        .alert(
            String(localized: "Map Local"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var editorStore = MapLocalEditorStore.shared
    @State private var isSaving = false

    private var editorTitle: String {
        viewModel.existingID == nil
            ? String(localized: "New Map Local Rule")
            : String(localized: "Edit Map Local Rule")
    }

    private var quickCreateProvenance: String? {
        guard let draft = viewModel.draft else {
            return nil
        }
        if let sourceURL = draft.sourceURL {
            return String(localized: "Created from \(draft.sourceMethod ?? "ANY") \(sourceURL.absoluteString)")
        }
        return String(localized: "Created from domain \(draft.sourceHost)")
    }

    private var fileStatusColor: Color {
        if viewModel.isCapturedBinary {
            return .blue
        }
        if viewModel.isExternalReference {
            return viewModel.isSelectedFileAvailable ? .green : .orange
        }
        return viewModel.isSelectedFileAvailable ? .green : .secondary
    }

    private var fileStatusMessage: String {
        if viewModel.isCapturedBinary {
            return String(localized: "Captured binary response will be written when the rule is saved.")
        }
        if viewModel.isExternalReference {
            return viewModel.isSelectedFileAvailable
                ? String(localized: "External file available")
                : String(localized: "External file is currently unavailable")
        }
        return viewModel.isSelectedFileAvailable
            ? String(localized: "Rockxy-owned response file available")
            : String(localized: "Rockxy will create this response file when the rule is saved.")
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details"))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Name")) {
                        TextField(String(localized: "Untitled"), text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(String(localized: "Rule name"))
                    }
                    .frame(width: max(250, toolMetrics.fieldWidth(250)))

                    fieldGroup(String(localized: "URL pattern")) {
                        TextField("https://example.com/api/*", text: $viewModel.urlText)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font(monospaced: true))
                            .accessibilityLabel(String(localized: "URL pattern"))
                    }
                    .frame(maxWidth: .infinity)
                }

                if let validationMessage = viewModel.urlValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }

                HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                    inlineField(String(localized: "Method")) {
                        methodMenu
                    }
                    inlineField(String(localized: "Match type")) {
                        matchTypeMenu
                    }

                    if viewModel.matchType == .wildcard {
                        Text(String(localized: "Supports * and ?."))
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if viewModel.matchType == .wildcard {
                    Toggle(
                        String(localized: "Include all subpaths of this URL"),
                        isOn: $viewModel.includeSubpaths
                    )
                    .toggleStyle(.checkbox)
                }

                Divider()

                HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
                    Text(String(localized: "Response delay"))
                        .foregroundStyle(.secondary)
                    delayMenu
                    if viewModel.delayPreset == .custom {
                        Stepper(
                            String(localized: "\(viewModel.customDelaySeconds) seconds"),
                            value: $viewModel.customDelaySeconds,
                            in: 0 ... 300
                        )
                        .frame(width: toolMetrics.fieldWidth(160))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var responseSourceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Response Source"))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Picker(String(localized: "Source type"), selection: $viewModel.targetMode) {
                    Text(MapLocalTargetMode.localFile.displayName).tag(MapLocalTargetMode.localFile)
                    Text(MapLocalTargetMode.localDirectory.displayName).tag(MapLocalTargetMode.localDirectory)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(240))
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                responseStatusRow

                if viewModel.targetMode == .localFile {
                    localFileSection
                } else {
                    localDirectorySection
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var localFileSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            HStack(alignment: .bottom, spacing: toolMetrics.controlSpacing) {
                fieldGroup(String(localized: "Local file")) {
                    Text(viewModel.filePath)
                        .font(toolMetrics.font(monospaced: true))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                        .help(viewModel.filePath)
                }
                .frame(maxWidth: .infinity)

                Button(String(localized: "Choose…")) { viewModel.choosePath() }
                    .frame(height: toolMetrics.formControlHeight)

                fileActionsMenu
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(fileStatusColor)
                    .frame(width: 8, height: 8)
                Text(fileStatusMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.responseContentType)
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Content-Type is inferred from the file extension."))
            }

            if viewModel.isInlineResponseEditable {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Response body"))
                        .foregroundStyle(.secondary)
                    MapLocalHTTPMessageEditor(
                        text: Binding(
                            get: { viewModel.responseBodyText },
                            set: { viewModel.responseBodyText = $0 }
                        ),
                        editorSettings: toolMetrics.codeEditorSettings
                    )
                    .frame(minHeight: 230)
                    .clipped()
                    .overlay {
                        Rectangle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    Text(
                        String(
                            localized:
                            "Rockxy saves the status code and body. Content-Type is inferred from the file extension."
                        )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: viewModel.isCapturedBinary ? "doc.zipper" : "link")
                        .foregroundStyle(.secondary)
                    Text(
                        viewModel.isCapturedBinary
                            ? String(
                                localized:
                                "Captured binary data is preserved byte-for-byte and cannot be edited inline."
                            )
                            : String(
                                localized:
                                "This rule references a user-owned file. Rockxy will never rewrite its contents."
                            )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var responseStatusRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Status code"))
                .foregroundStyle(.secondary)
            TextField(
                "",
                value: Binding(
                    get: { viewModel.responseStatusCode },
                    set: { viewModel.setResponseStatusCode($0) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 84, height: toolMetrics.formControlHeight)
            .accessibilityLabel(String(localized: "HTTP response status code"))
            Text(String(localized: "Applied to every response from this rule. Valid range: 100–599."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var localDirectorySection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            fieldGroup(String(localized: "Local directory")) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    TextField(String(localized: "Choose a directory"), text: $viewModel.directoryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                    Button(String(localized: "Choose…")) { viewModel.choosePath() }
                    Button(String(localized: "Show in Finder")) { viewModel.showSelectedPathInFinder() }
                        .disabled(!viewModel.isDirectoryValid)
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isDirectoryValid ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.isDirectoryValid
                    ? String(localized: "Directory available")
                    : String(localized: "Choose an available directory to continue."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        localized:
                        "Request subpaths resolve inside this directory. Root requests use index.html when it exists."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private var methodMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.methodSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { method in
                    Button { viewModel.method = method } label: {
                        menuCheckmarkLabel(method.rawValue, isSelected: viewModel.method == method)
                    }
                }
                if index < MapLocalEditorMenuContent.methodSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.method.rawValue, width: toolMetrics.menuWidth(90))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(90))
    }

    private var matchTypeMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.matchTypeSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { matchType in
                    Button { viewModel.matchType = matchType } label: {
                        menuCheckmarkLabel(matchType.displayName, isSelected: viewModel.matchType == matchType)
                    }
                }
                if index < MapLocalEditorMenuContent.matchTypeSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.matchType.displayName, width: toolMetrics.menuWidth(150))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(150))
    }

    private var delayMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.delaySections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { preset in
                    Button { viewModel.delayPreset = preset } label: {
                        menuCheckmarkLabel(preset.displayName, isSelected: viewModel.delayPreset == preset)
                    }
                }
                if index < MapLocalEditorMenuContent.delaySections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.delayPreset.displayName, width: toolMetrics.menuWidth(160))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(160))
    }

    private var fileActionsMenu: some View {
        Menu {
            Button(String(localized: "Show in Finder")) { viewModel.showSelectedPathInFinder() }
                .disabled(!viewModel.isSelectedFileAvailable)
            Divider()
            ForEach(MapLocalExternalEditor.allCases) { editor in
                Button(String(localized: "Open with \(editor.displayName)")) {
                    viewModel.openSelectedPath(with: editor)
                }
                .disabled(!viewModel.isSelectedFileAvailable)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: toolMetrics.footerControlHeight, height: toolMetrics.formControlHeight)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help(String(localized: "File Actions"))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                footerButtonLabel(String(localized: "Cancel"))
            }
            .keyboardShortcut(.cancelAction)

            Button {
                saveAndClose()
            } label: {
                footerButtonLabel(
                    isSaving
                        ? String(localized: "Saving…")
                        : viewModel.existingID == nil
                        ? String(localized: "Add")
                        : String(localized: "Save")
                )
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(!viewModel.isSaveEnabled || isSaving)
        }
        .padding(.horizontal, toolMetrics.formHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private func provenanceBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text(message)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(message)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
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

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
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
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func saveAndClose() {
        guard let rule = viewModel.makeRule() else {
            return
        }
        isSaving = true
        Task {
            if viewModel.existingID == nil {
                let accepted = await RulePolicyGate.shared.addRule(rule)
                guard accepted else {
                    viewModel.errorMessage = String(
                        localized:
                        "The active Map Local rule limit was reached. Disable another rule and try again."
                    )
                    isSaving = false
                    return
                }
            } else {
                await RulePolicyGate.shared.updateRule(rule)
            }
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - MapLocalExternalEditor

enum MapLocalExternalEditor: String, CaseIterable, Identifiable {
    case code
    case cursor
    case textEdit
    case xcode

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .code: "Code"
        case .cursor: "Cursor"
        case .textEdit: "TextEdit"
        case .xcode: "Xcode"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .code: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .textEdit: "com.apple.TextEdit"
        case .xcode: "com.apple.dt.Xcode"
        }
    }
}
