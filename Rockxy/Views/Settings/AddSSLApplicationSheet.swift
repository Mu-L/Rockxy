import AppKit
import SwiftUI

// MARK: - AddSSLApplicationSheet

/// Adds a stable application-scoped HTTPS behavior from apps observed in this live capture.
/// Remote clients are intentionally absent because Rockxy cannot resolve their local process identity.
struct AddSSLApplicationSheet: View {
    // MARK: Lifecycle

    init(
        editingRule: ApplicationSSLProxyingRule? = nil,
        existingRules: [ApplicationSSLProxyingRule],
        onSave: @escaping (ClientApplicationIdentity, SSLProxyingListType) -> Bool
    ) {
        self.editingRule = editingRule
        self.existingRules = existingRules
        self.onSave = onSave
        _selectedIdentifier = State(initialValue: editingRule?.applicationIdentifier)
        _listType = State(initialValue: editingRule?.listType ?? .include)
    }

    // MARK: Internal

    let editingRule: ApplicationSSLProxyingRule?
    let existingRules: [ApplicationSSLProxyingRule]
    let onSave: (ClientApplicationIdentity, SSLProxyingListType) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            controls
            Divider()
            applicationList
            warning
            Divider()
            buttonBar
        }
        .font(toolMetrics.font())
        .frame(width: max(540, toolMetrics.fieldWidth(540)), height: 560)
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onAppear { isSearchFocused = true }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var searchText = ""
    @State private var selectedIdentifier: String?
    @State private var listType: SSLProxyingListType
    @State private var duplicateMessage: String?
    @FocusState private var isSearchFocused: Bool

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var applications: [AppInfo] {
        var candidates = TrafficDomainSnapshot.shared.appEntries.filter { $0.identity != nil }
        if let editingRule,
           !candidates.contains(where: { $0.identity?.identifier == editingRule.applicationIdentifier })
        {
            let identity = ClientApplicationIdentity(
                identifier: editingRule.applicationIdentifier,
                displayName: editingRule.displayName,
                kind: editingRule.bundleIdentifier == nil ? .executable : .bundle,
                bundleIdentifier: editingRule.bundleIdentifier
            )
            candidates.insert(
                AppInfo(name: editingRule.displayName, domains: [], requestCount: 0, identity: identity),
                at: 0
            )
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return candidates
        }
        return candidates.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || app.identity?.identifier.localizedCaseInsensitiveContains(query) == true
                || app.domains.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectedIdentity: ClientApplicationIdentity? {
        guard let selectedIdentifier else {
            return nil
        }
        if let observed = TrafficDomainSnapshot.shared.appEntries
            .compactMap(\.identity)
            .first(where: { $0.identifier == selectedIdentifier })
        {
            return observed
        }
        guard let editingRule, editingRule.applicationIdentifier == selectedIdentifier else {
            return nil
        }
        return ClientApplicationIdentity(
            identifier: editingRule.applicationIdentifier,
            displayName: editingRule.displayName,
            kind: editingRule.bundleIdentifier == nil ? .executable : .bundle,
            bundleIdentifier: editingRule.bundleIdentifier
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(editingRule == nil
                ? String(localized: "Add Application", bundle: RockxyLocalization.bundle)
                : String(localized: "Edit Application Rule", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
            Text(
                String(
                    localized: "Choose an observed local app. The rule follows its stable identity across every HTTPS host it uses.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                String(localized: "Search applications", bundle: RockxyLocalization.bundle),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)

            HStack(spacing: toolMetrics.controlSpacing) {
                Text(String(localized: "Behavior", bundle: RockxyLocalization.bundle))
                    .foregroundStyle(.secondary)

                Picker("", selection: $listType) {
                    Text(SSLProxyingListViewModel.behaviorLabel(for: .include))
                        .tag(SSLProxyingListType.include)
                    Text(SSLProxyingListViewModel.behaviorLabel(for: .exclude))
                        .tag(SSLProxyingListType.exclude)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Rule behavior", bundle: RockxyLocalization.bundle))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var applicationList: some View {
        List(selection: $selectedIdentifier) {
            ForEach(applications) { app in
                if let identity = app.identity {
                    if app.domains.isEmpty {
                        applicationRow(app, identity: identity)
                            .tag(identity.identifier)
                    } else {
                        DisclosureGroup {
                            ForEach(app.domains, id: \.self) { domain in
                                HStack(spacing: 8) {
                                    Image(systemName: "network")
                                        .font(toolMetrics.secondaryFont())
                                        .foregroundStyle(.tertiary)
                                    Text(domain)
                                        .font(toolMetrics.secondaryFont(monospaced: true))
                                        .lineLimit(1)
                                }
                                .padding(.leading, 42)
                            }
                        } label: {
                            applicationRow(app, identity: identity)
                                .tag(identity.identifier)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if applications.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? String(localized: "No Local Applications Observed", bundle: RockxyLocalization.bundle)
                        : String(localized: "No Matching Applications", bundle: RockxyLocalization.bundle),
                    systemImage: searchText.isEmpty ? "app.dashed" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? String(
                                localized: "Capture new traffic from a local app, then return here.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Try a different app, identifier, or host.",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                )
            }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                String(
                    localized: "Applies to new connections after the app reconnects.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            Text(
                String(
                    localized: "Decrypting an entire app can expose sensitive traffic and use more CPU and memory. Add Tunnel rules for exceptions.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .foregroundStyle(.secondary)
            if let duplicateMessage {
                Text(duplicateMessage)
                    .foregroundStyle(.red)
            }
        }
        .font(toolMetrics.secondaryFont())
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var buttonBar: some View {
        HStack {
            Spacer()
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(editingRule == nil
                ? String(localized: "Add", bundle: RockxyLocalization.bundle)
                : String(localized: "Save", bundle: RockxyLocalization.bundle))
            {
                guard let selectedIdentity else {
                    return
                }
                if onSave(selectedIdentity, listType) {
                    dismiss()
                } else {
                    duplicateMessage = String(
                        localized: "A rule with this application and behavior already exists.",
                        bundle: RockxyLocalization.bundle
                    )
                }
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(selectedIdentity == nil)
        }
        .padding(12)
    }

    private func applicationRow(_ app: AppInfo, identity: ClientApplicationIdentity) -> some View {
        HStack(spacing: 10) {
            applicationIcon(for: identity, name: app.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                Text(identity.bundleIdentifier ?? identity.identifier)
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(String(localized: "\(app.domains.count) hosts", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func applicationIcon(for identity: ClientApplicationIdentity, name: String) -> some View {
        if let bundleIdentifier = identity.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
        } else if let icon = AppIconProvider.applicationIcon(named: name, size: 32) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
    }
}
