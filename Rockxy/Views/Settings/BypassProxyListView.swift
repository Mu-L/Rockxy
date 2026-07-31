import SwiftUI
import UniformTypeIdentifiers

// MARK: - BypassProxyListView

/// Manages host patterns that normally connect directly instead of using Rockxy's
/// macOS system-proxy configuration.
struct BypassProxyListView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            behaviorNotice
            quickAddBar
            tableContent
            footer
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(720), height: 560)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "rockxy-full-proxy-bypass.json"
        ) { result in
            if case let .failure(error) = result {
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .alert(
            String(localized: "Full Proxy Bypass"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            String(localized: "Remove selected bypass entries?"),
            isPresented: Binding(
                get: { !pendingRemovalIDs.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        pendingRemovalIDs.removeAll()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Remove \(pendingRemovalIDs.count) Entries"),
                role: .destructive
            ) {
                removeDomains(pendingRemovalIDs)
                pendingRemovalIDs.removeAll()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingRemovalIDs.removeAll()
            }
        } message: {
            Text(
                String(
                    localized: "Rockxy will remove these exclusions from the system proxy configuration for new connections."
                )
            )
        }
        .confirmationDialog(
            String(localized: "Replace existing Full Proxy Bypass entries?"),
            isPresented: $isConfirmingImport,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Choose File and Replace…"), role: .destructive) {
                showingImporter = true
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized:
                    "Import replaces the complete list. Export first if you need a backup."
                )
            )
        }
        .onDeleteCommand {
            requestRemoval(selectedDomainIDs)
        }
        .onChange(of: manager.domains.map(\.id)) { _, _ in
            reconcileSelection()
        }
        .onChange(of: searchText) { _, _ in
            reconcileSelection()
        }
    }

    // MARK: Private

    private static let maxImportFileBytes = 1_024 * 1_024

    @State private var manager = BypassProxyManager.shared
    @State private var searchText = ""
    @State private var newPattern = ""
    @State private var validationError: String?
    @State private var selectedDomainIDs: Set<UUID> = []
    @State private var pendingRemovalIDs: Set<UUID> = []
    @State private var showingImporter = false
    @State private var isConfirmingImport = false
    @State private var showingExporter = false
    @State private var exportDocument: BypassJSONFileDocument?
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isPatternFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var filteredDomains: [BypassDomain] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return manager.domains
        }
        return manager.domains.filter {
            $0.domain.localizedCaseInsensitiveContains(query)
        }
    }

    private var activeCount: Int {
        manager.domains.count(where: \.isEnabled)
    }

    private var behaviorNoticeText: String {
        let systemProxyCopy = String(
            localized: "System-proxy clients matching these patterns connect directly and are not captured."
        )
        let manualProxyCopy = String(
            localized: "Manually configured clients that still reach Rockxy remain encrypted and are tunneled."
        )
        return "\(systemProxyCopy) \(manualProxyCopy)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Full Proxy Bypass"))
                    .font(toolMetrics.font(weight: .medium))

                Text(String(localized: "Send matching system traffic directly instead of through Rockxy."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search host patterns"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .frame(width: toolMetrics.fieldWidth(230), height: toolMetrics.formControlHeight)
                .focused($isSearchFocused)
                .accessibilityLabel(String(localized: "Search Full Proxy Bypass entries"))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
    }

    private var behaviorNotice: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)

            Text(behaviorNoticeText)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: toolMetrics.controlSpacing) {
                TextField(
                    String(localized: "Host pattern"),
                    text: $newPattern,
                    prompt: Text(String(localized: "example.com or *.internal"))
                )
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font(monospaced: true))
                .frame(height: toolMetrics.formControlHeight)
                .focused($isPatternFocused)
                .onSubmit(addDomain)
                .onChange(of: newPattern) { _, _ in
                    validationError = nil
                }

                Button(String(localized: "Add Host")) {
                    addDomain()
                }
                .frame(width: toolMetrics.footerButtonWidth)
                .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let validationError {
                Text(validationError)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    String(
                        localized: "A bare domain also covers its subdomains. Use *.domain.com when only subdomains should match."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private var tableContent: some View {
        Table(filteredDomains, selection: $selectedDomainIDs) {
            TableColumn(String(localized: "Enabled")) { domain in
                Toggle("", isOn: Binding(
                    get: { domain.isEnabled },
                    set: { _ in manager.toggleDomain(id: domain.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(String(localized: "Enable \(domain.domain)"))
            }
            .width(72)

            TableColumn(String(localized: "Host Pattern")) { domain in
                Text(domain.domain)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(domain.domain)
                    .opacity(domain.isEnabled ? 1 : 0.5)
            }
            .width(min: 280, ideal: 520)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        }
        .overlay {
            if filteredDomains.isEmpty {
                ContentUnavailableView(
                    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "No Full Proxy Bypass Entries")
                        : String(localized: "No Matching Host Patterns"),
                    systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "arrow.triangle.branch"
                        : "magnifyingglass",
                    description: Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(localized: "Add a host pattern above or choose the local-network presets.")
                            : String(localized: "Try a different host pattern.")
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

            Text(ruleCountText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(activeStatusText)
                .font(toolMetrics.metadataFont(weight: .semibold))
                .foregroundStyle(activeCount == 0 ? Color.secondary : Color.blue)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    (activeCount == 0 ? Color.secondary : Color.blue).opacity(0.12)
                )
                .clipShape(Capsule())
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                isPatternFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "Add Host Pattern"))
            .accessibilityLabel(String(localized: "Add Host Pattern"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                requestRemoval(selectedDomainIDs)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(selectedDomainIDs.isEmpty ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedDomainIDs.isEmpty)
            .help(String(localized: "Remove Selected Entries"))
            .accessibilityLabel(String(localized: "Remove Selected Entries"))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Find…")) {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Add Local Network Presets")) {
                manager.addPresets()
            }

            Divider()

            Button(String(localized: "Import…")) {
                if manager.domains.isEmpty {
                    showingImporter = true
                } else {
                    isConfirmingImport = true
                }
            }

            Button(String(localized: "Export…")) {
                prepareExport()
            }
            .disabled(manager.domains.isEmpty)

            Divider()

            Button(String(localized: "Remove Selected"), role: .destructive) {
                requestRemoval(selectedDomainIDs)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedDomainIDs.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
    }

    private var ruleCountText: String {
        let count = manager.domains.count
        return count == 1
            ? String(localized: "1 host pattern")
            : String(localized: "\(count) host patterns")
    }

    private var activeStatusText: String {
        activeCount == 0
            ? String(localized: "No Enabled Bypasses")
            : String(localized: "\(activeCount) Enabled")
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        if ids.count == 1,
           let id = ids.first,
           let domain = manager.domains.first(where: { $0.id == id })
        {
            Button(
                domain.isEnabled
                    ? String(localized: "Disable")
                    : String(localized: "Enable")
            ) {
                manager.toggleDomain(id: id)
            }
        }

        Divider()

        Button(String(localized: "Remove"), role: .destructive) {
            requestRemoval(ids)
        }
        .disabled(ids.isEmpty)
    }

    private func addDomain() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Self.validationError(for: trimmed) {
            validationError = error
            return
        }

        if manager.domains.contains(where: { $0.domain.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            validationError = String(localized: "This host pattern is already in Full Proxy Bypass.")
            return
        }

        manager.addDomain(trimmed)
        if let added = manager.domains.last(where: {
            $0.domain.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            selectedDomainIDs = [added.id]
        }
        newPattern = ""
        validationError = nil
        isPatternFocused = true
    }

    private func requestRemoval(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }
        if ids.count == 1 {
            removeDomains(ids)
        } else {
            pendingRemovalIDs = ids
        }
    }

    private func removeDomains(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        let orderedIDs = filteredDomains.map(\.id)
        let fallbackIndex = ids
            .compactMap { orderedIDs.firstIndex(of: $0) }
            .min()
            ?? 0

        manager.removeDomains(ids: ids)

        let remainingIDs = filteredDomains.map(\.id)
        if remainingIDs.isEmpty {
            selectedDomainIDs.removeAll()
        } else {
            selectedDomainIDs = [remainingIDs[min(fallbackIndex, remainingIDs.count - 1)]]
        }
    }

    private func reconcileSelection() {
        let visibleIDs = Set(filteredDomains.map(\.id))
        selectedDomainIDs.formIntersection(visibleIDs)
    }

    private func prepareExport() {
        guard let data = manager.exportDomains() else {
            errorMessage = String(localized: "Rockxy could not prepare the Full Proxy Bypass export.")
            return
        }
        exportDocument = BypassJSONFileDocument(data: data)
        showingExporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else {
                return
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile != false else {
                throw BypassProxyListImportError.notRegularFile
            }
            if let fileSize = values.fileSize, fileSize > Self.maxImportFileBytes {
                throw BypassProxyListImportError.fileTooLarge
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= Self.maxImportFileBytes else {
                throw BypassProxyListImportError.fileTooLarge
            }

            let decoded = try JSONDecoder().decode([BypassDomain].self, from: data)
            let uniqueIDs = Set(decoded.map(\.id))
            let normalizedPatterns = decoded.map { $0.domain.lowercased() }
            let uniquePatterns = Set(normalizedPatterns)
            guard uniqueIDs.count == decoded.count,
                  uniquePatterns.count == decoded.count,
                  decoded.allSatisfy({ Self.validationError(for: $0.domain) == nil })
            else {
                throw BypassProxyListImportError.invalidEntries
            }

            try manager.importDomains(from: data)
            selectedDomainIDs.removeAll()
            searchText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func validationError(for value: String) -> String? {
        guard !value.isEmpty else {
            return String(localized: "Enter a host pattern.")
        }
        if value == "*" {
            return String(localized: "Full Proxy Bypass does not support a global * pattern.")
        }
        if BypassDomain.isIPv4PrefixWildcard(value) {
            return nil
        }
        return SSLHostPatternValidation.message(for: value)
    }
}

// MARK: - BypassProxyListImportError

private enum BypassProxyListImportError: LocalizedError {
    case fileTooLarge
    case invalidEntries
    case notRegularFile

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            String(localized: "The import file must be 1 MB or smaller.")
        case .invalidEntries:
            String(localized: "The import contains invalid or duplicate Full Proxy Bypass entries.")
        case .notRegularFile:
            String(localized: "Choose a regular JSON file.")
        }
    }
}

// MARK: - BypassJSONFileDocument

private struct BypassJSONFileDocument: FileDocument {
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
