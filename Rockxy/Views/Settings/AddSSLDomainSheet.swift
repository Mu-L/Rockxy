import SwiftUI

// MARK: - AddSSLDomainSheet

/// Centered popup for adding or editing a single HTTPS decryption rule.
/// Captures both a host pattern and an explicit behavior (Decrypt / Tunnel).
struct AddSSLDomainSheet: View {
    // MARK: Lifecycle

    init(
        editingRule: SSLProxyingRule? = nil,
        existingRules: [SSLProxyingRule],
        onSave: @escaping (String, SSLProxyingListType) -> Bool
    ) {
        self.editingRule = editingRule
        self.existingRules = existingRules
        self.onSave = onSave
        _domain = State(initialValue: editingRule?.domain ?? "")
        _listType = State(initialValue: editingRule?.listType ?? .include)
    }

    // MARK: Internal

    let editingRule: SSLProxyingRule?
    let existingRules: [SSLProxyingRule]
    let onSave: (String, SSLProxyingListType) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(toolMetrics.font(weight: .semibold))
                    Text(explanation)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                fieldRow(String(localized: "Host Pattern", bundle: RockxyLocalization.bundle)) {
                    TextField("", text: $domain, prompt: Text("api.example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                        .frame(height: toolMetrics.formControlHeight)
                        .focused($isHostFocused)
                        .accessibilityLabel(String(localized: "Host pattern", bundle: RockxyLocalization.bundle))
                }

                fieldRow(String(localized: "Behavior", bundle: RockxyLocalization.bundle)) {
                    Picker("", selection: $listType) {
                        Text(SSLProxyingListViewModel.behaviorLabel(for: .include))
                            .tag(SSLProxyingListType.include)
                        Text(SSLProxyingListViewModel.behaviorLabel(for: .exclude))
                            .tag(SSLProxyingListType.exclude)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(height: toolMetrics.formControlHeight)
                    .accessibilityLabel(String(localized: "Rule behavior", bundle: RockxyLocalization.bundle))
                }

                Text(
                    String(
                        localized: "Enter a host: * for all, an exact host or IPv4, or *.domain.com for subdomains.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if hasOppositeBehaviorOverlap {
                    Label(
                        String(
                            localized:
                            "This host also has the opposite behavior. Tunnel Without Decryption takes priority; row order does not affect matching.",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                    if onSave(trimmed, listType) {
                        dismiss()
                    }
                } label: {
                    footerButtonLabel(
                        editingRule != nil ? String(localized: "Save", bundle: RockxyLocalization.bundle) : String(
                            localized: "Add",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!isValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(width: max(420, toolMetrics.fieldWidth(420)))
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { isHostFocused = true }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var domain: String
    @State private var listType: SSLProxyingListType
    @FocusState private var isHostFocused: Bool

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var title: String {
        editingRule != nil
            ? String(localized: "Edit HTTPS Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "Add HTTPS Rule", bundle: RockxyLocalization.bundle)
    }

    private var explanation: String {
        switch listType {
        case .include:
            String(
                localized: "Rockxy decrypts HTTPS for hosts matching this pattern.",
                bundle: RockxyLocalization.bundle
            )
        case .exclude:
            String(
                localized: "Rockxy tunnels matching HTTPS without decrypting, overriding any Decrypt rule.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedDomain.isEmpty && validationMessage == nil
    }

    /// Validates the raw host pattern against the `SSLProxyingRule` matcher contract:
    /// `*`, an exact host / IPv4, or a leading `*.domain` suffix. Schemes, paths,
    /// queries, fragments, ports, IPv6 literals, and whitespace are rejected because
    /// the matcher compares a bare lowercased host.
    private var validationMessage: String? {
        let raw = trimmedDomain
        guard !raw.isEmpty else {
            return nil
        }
        if let message = SSLHostPatternValidation.message(for: raw) {
            return message
        }
        return hasSameBehaviorDuplicate
            ? String(
                localized: "A rule with this host pattern and behavior already exists.",
                bundle: RockxyLocalization.bundle
            )
            : nil
    }

    private var hasSameBehaviorDuplicate: Bool {
        existingRules.contains { rule in
            rule.id != editingRule?.id
                && rule.listType == listType
                && rule.domain.caseInsensitiveCompare(trimmedDomain) == .orderedSame
        }
    }

    private var hasOppositeBehaviorOverlap: Bool {
        existingRules.contains { rule in
            rule.id != editingRule?.id
                && rule.listType != listType
                && rule.domain.caseInsensitiveCompare(trimmedDomain) == .orderedSame
        }
    }

    private func fieldRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .frame(width: toolMetrics.formCompactLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: max(80, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 2))
    }
}
