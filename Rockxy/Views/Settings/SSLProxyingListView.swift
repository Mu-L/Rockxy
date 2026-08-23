import SwiftUI
import UniformTypeIdentifiers

// MARK: - SSLProxyingListView

/// HTTPS Decryption management window. Presents every `SSLProxyingRule` in one
/// unified native `Table` with an explicit per-row behavior column, following the
/// AllowListWindowView / NetworkConditionsWindowView shell pattern.
struct SSLProxyingListView: View {
    // MARK: Internal

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
        .frame(width: toolMetrics.fieldWidth(880), height: 620)
        .onChange(of: viewModel.manager.rules) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .sheet(isPresented: $viewModel.showAddDomainSheet) {
            viewModel.editingRule = nil
        } content: {
            AddSSLDomainSheet(
                editingRule: viewModel.editingRule,
                existingRules: viewModel.manager.rules
            ) { domain, listType in
                if let editing = viewModel.editingRule {
                    let didUpdate = viewModel.updateRule(id: editing.id, domain: domain, listType: listType)
                    if didUpdate {
                        viewModel.editingRule = nil
                    }
                    return didUpdate
                } else {
                    return viewModel.addRule(domain: domain, listType: listType)
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddAppSheet) {
            AddSSLAppDomainSheet(existingRules: viewModel.manager.rules) { domains, listType in
                viewModel.addRules(domains, listType: listType)
            }
        }
        .sheet(isPresented: $viewModel.showBypassSheet) {
            BypassProxySettingsSheet(manager: viewModel.manager)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "ssl-proxying-settings.json"
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .xml, .propertyList],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            String(localized: "Replace existing HTTPS decryption settings?"),
            isPresented: Binding(
                get: { pendingImportSource != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingImportSource = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Choose File and Replace…"), role: .destructive) {
                guard let pendingImportSource else {
                    return
                }
                importSource = pendingImportSource
                self.pendingImportSource = nil
                showImporter = true
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingImportSource = nil
            }
        } message: {
            Text(importConfirmationMessage)
        }
        .alert(
            String(localized: "HTTPS Decryption"),
            isPresented: Binding(
                get: { importError != nil },
                set: { newValue in
                    if !newValue {
                        importError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .onDeleteCommand {
            viewModel.removeSelected()
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Private

    private enum ImportSource: Equatable {
        case rockxy
        case charlesProxy
        case proxyman
        case httpToolkit
    }

    private static let maxImportFileBytes = 1_024 * 1_024

    @State private var viewModel = SSLProxyingListViewModel()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: SSLProxyingJSONDocument?
    @State private var importError: String?
    @State private var importSource: ImportSource = .rockxy
    @State private var pendingImportSource: ImportSource?

    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var canInterceptHTTPS: Bool {
        ReadinessCoordinator.shared.canInterceptHTTPS
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var infoBannerMessage: String {
        if !viewModel.isSSLProxyingEnabled {
            return String(
                localized:
                "HTTPS decryption is off. All HTTPS connections are tunneled unread; individual rules keep their state."
            )
        }
        if canInterceptHTTPS {
            return String(
                localized:
                "Decrypt rules apply to new HTTPS connections. Tunnel rules take priority on overlaps; row order does not affect matching."
            )
        }
        return String(
            localized:
            "HTTPS decryption is unavailable until the Rockxy root certificate is trusted. HTTPS is tunneled unread for now."
        )
    }

    private var footerHint: String {
        let countText = isSearching
            ? String(localized: "\(viewModel.filteredRules.count) of \(viewModel.ruleCount) rules")
            : String(localized: "\(viewModel.ruleCount) rules")
        let breakdown = String(
            localized: "\(viewModel.decryptCount) decrypt · \(viewModel.tunnelCount) tunnel"
        )
        return "\(countText) · \(breakdown)"
    }

    private var statusCapsuleText: String {
        if !viewModel.isSSLProxyingEnabled {
            return String(localized: "TOOL OFF")
        }
        if !canInterceptHTTPS {
            return String(localized: "PASSTHROUGH ACTIVE")
        }
        if viewModel.enabledDecryptCount == 0 {
            return String(localized: "NO DECRYPT RULES")
        }
        return String(localized: "DECRYPTION READY")
    }

    private var statusCapsuleColor: Color {
        if !viewModel.isSSLProxyingEnabled || viewModel.enabledDecryptCount == 0 {
            return .secondary
        }
        return canInterceptHTTPS ? .green : .orange
    }

    private var statusCapsuleIsActive: Bool {
        viewModel.isSSLProxyingEnabled && viewModel.enabledDecryptCount > 0
    }

    private var importConfirmationMessage: String {
        if pendingImportSource == .rockxy {
            return String(
                localized:
                "Rockxy import replaces the current rules, master state, and TLS passthrough exceptions. Export first if you need a backup."
            )
        }
        return String(
            localized:
            "This import replaces the current HTTPS rules. The master state and TLS passthrough exceptions remain unchanged."
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable HTTPS Decryption"),
                    isOn: Binding(
                        get: { viewModel.isSSLProxyingEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))
                .help(
                    String(
                        localized:
                        "When off, Rockxy tunnels all HTTPS without decrypting it. Individual rules keep their state."
                    )
                )

                Text(
                    String(
                        localized:
                        "Rules decide which HTTPS hosts Rockxy decrypts. Other hosts still pass through Rockxy as opaque TLS tunnels."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            TextField(String(localized: "Search rules"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .focused($isSearchFocused)
                .accessibilityLabel(String(localized: "Search HTTPS decryption rules"))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: infoBannerSystemImage)
                .foregroundStyle(infoBannerColor)
            Text(infoBannerMessage)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(canInterceptHTTPS || !viewModel.isSSLProxyingEnabled ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !canInterceptHTTPS {
                Button(String(localized: "Open Advanced Proxy Settings…")) {
                    openWindow(id: "advancedProxySettings")
                }
                .buttonStyle(.link)
                .font(toolMetrics.secondaryFont())
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background {
            if canInterceptHTTPS || !viewModel.isSSLProxyingEnabled {
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            } else {
                Color.orange.opacity(0.12)
            }
        }
    }

    private var infoBannerSystemImage: String {
        if !viewModel.isSSLProxyingEnabled {
            return "pause.circle"
        }
        return canInterceptHTTPS ? "info.circle" : "exclamationmark.triangle.fill"
    }

    private var infoBannerColor: Color {
        canInterceptHTTPS || !viewModel.isSSLProxyingEnabled ? .secondary : .orange
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Enabled")) { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { viewModel.setRuleEnabled(id: rule.id, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(String(localized: "Enable \(rule.domain)"))
            }
            .width(62)

            TableColumn(String(localized: "Host Pattern")) { rule in
                Text(rule.domain)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.domain)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 220, ideal: 340)

            TableColumn(String(localized: "Behavior")) { rule in
                HStack(spacing: 6) {
                    Image(systemName: rule.listType == .include ? "lock.open" : "lock")
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(rule.listType == .include ? Color.accentColor : Color.secondary)
                    Text(SSLProxyingListViewModel.behaviorLabel(for: rule.listType))
                        .lineLimit(1)
                    if hasOppositeBehaviorOverlap(for: rule) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(toolMetrics.metadataFont())
                            .foregroundStyle(.orange)
                            .help(
                                String(
                                    localized:
                                    "This host has both behaviors. Tunnel Without Decryption takes priority."
                                )
                            )
                    }
                }
                .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 190, ideal: 220)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            if let id = ids.first {
                viewModel.presentEditor(for: id)
            }
        }
        .overlay {
            if viewModel.filteredRules.isEmpty {
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No matching rules")
                        : String(localized: "No HTTPS decryption rules"),
                    systemImage: isSearching ? "magnifyingglass" : "lock.shield",
                    description: Text(
                        isSearching
                            ? String(localized: "Try a different host pattern or behavior.")
                            : String(localized: "Add a host pattern or observed domains to decrypt their HTTPS.")
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(statusCapsuleText)
                .font(toolMetrics.metadataFont(weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .rockxyChipStyle(tint: statusCapsuleColor, isActive: statusCapsuleIsActive)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Menu {
                Button(String(localized: "Add Host Pattern…")) {
                    viewModel.editingRule = nil
                    viewModel.showAddDomainSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button(String(localized: "Add Observed Domains…")) {
                    viewModel.showAddAppSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Add Rule"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                viewModel.removeSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(viewModel.selectedRuleID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule"))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: toolMetrics.compactButtonSize * 2 + 1, height: toolMetrics.footerControlHeight)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Edit…")) {
                viewModel.presentEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(viewModel.enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Section(String(localized: "Bypass")) {
                Button(String(localized: "TLS Passthrough Exceptions…")) {
                    viewModel.showBypassSheet = true
                }
                .help(
                    String(
                        localized:
                        "Hosts here skip decryption but still flow through Rockxy. It never disables Rockxy proxying."
                    )
                )

                Button(String(localized: "Full Proxy Bypass…")) {
                    openWindow(id: "bypassProxyList")
                }
                .help(
                    String(
                        localized:
                        "System-proxy clients connect directly. Manually configured clients that still reach Rockxy are tunneled without decryption."
                    )
                )
            }

            Divider()

            Menu(String(localized: "Import Settings")) {
                Button(String(localized: "From Rockxy…")) {
                    requestImport(from: .rockxy)
                }

                Divider()

                Button(String(localized: "From Proxyman…")) {
                    requestImport(from: .proxyman)
                }

                Button(String(localized: "From Charles Proxy…")) {
                    requestImport(from: .charlesProxy)
                }

                Button(String(localized: "From HTTP Toolkit…")) {
                    requestImport(from: .httpToolkit)
                }
            }

            Button(String(localized: "Export Settings…")) {
                prepareExport()
            }

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
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
        .buttonStyle(.bordered)
        .fixedSize()
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit…")) {
                viewModel.presentEditor(for: id)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button(viewModel.toggleLabel(for: id)) {
                viewModel.toggleRule(id: id)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.selectedRuleID = id
                viewModel.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    // MARK: - Import / Export

    private func hasOppositeBehaviorOverlap(for rule: SSLProxyingRule) -> Bool {
        viewModel.manager.rules.contains {
            $0.id != rule.id
                && $0.listType != rule.listType
                && $0.domain.caseInsensitiveCompare(rule.domain) == .orderedSame
        }
    }

    private func prepareExport() {
        guard let data = viewModel.manager.exportRules() else {
            importError = String(localized: "Rockxy could not prepare the HTTPS Decryption export.")
            return
        }
        exportDocument = SSLProxyingJSONDocument(data: data)
        showExporter = true
    }

    private func requestImport(from source: ImportSource) {
        pendingImportSource = source
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize, fileSize > Self.maxImportFileBytes {
                    importError = String(localized: "File is too large to import (max 1 MB).")
                    return
                }
                let data = try Data(contentsOf: url)
                guard data.count <= Self.maxImportFileBytes else {
                    importError = String(localized: "File is too large to import (max 1 MB).")
                    return
                }
                switch importSource {
                case .rockxy:
                    try viewModel.manager.importRules(from: data)
                case .charlesProxy:
                    let rules = try CharlesSSLImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                case .proxyman:
                    let rules = try ProxymanSSLImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                case .httpToolkit:
                    let rules = try HTTPToolkitImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                }
            } catch {
                importError = error.localizedDescription
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - SSLProxyingJSONDocument

struct SSLProxyingJSONDocument: FileDocument {
    // MARK: Lifecycle

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
