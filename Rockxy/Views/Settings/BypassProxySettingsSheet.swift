import SwiftUI

// MARK: - BypassProxySettingsSheet

/// Edits the protected host patterns that should never be decrypted even when
/// they match a normal HTTPS decryption rule.
struct BypassProxySettingsSheet: View {
    // MARK: Lifecycle

    init(manager: SSLProxyingManager) {
        self.manager = manager
        _domainsText = State(initialValue: Self.editableText(from: manager.bypassDomains))
    }

    // MARK: Internal

    let manager: SSLProxyingManager

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                Text(String(localized: "TLS Passthrough Exceptions"))
                    .font(toolMetrics.font(weight: .medium))

                Text(
                    String(
                        localized: "These hosts always stay encrypted when they pass through Rockxy. They do not bypass the proxy."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $domainsText)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(minHeight: max(120, toolMetrics.bodyFontSize * 8))
                    .focused($isEditorFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .onChange(of: domainsText) { _, _ in
                        validationError = nil
                    }

                Text(String(localized: "Enter one host pattern per line. Use * for all hosts or *.domain.com for subdomains."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let validationError {
                    Text(validationError)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: toolMetrics.controlSpacing) {
                Button {
                    domainsText = Self.editableText(from: SSLProxyingManager.defaultBypassDomains)
                } label: {
                    Text(String(localized: "Reset to Default"))
                }

                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .frame(minWidth: toolMetrics.footerButtonWidth)
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save")) {
                    save()
                }
                .frame(minWidth: toolMetrics.footerButtonWidth)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: toolMetrics.fieldWidth(580))
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            isEditorFocused = true
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var domainsText: String
    @State private var validationError: String?
    @FocusState private var isEditorFocused: Bool

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func save() {
        let patterns = Self.patterns(from: domainsText)
        if let invalid = patterns.first(where: { Self.validationError(for: $0) != nil }),
           let error = Self.validationError(for: invalid)
        {
            validationError = String(localized: "\(invalid): \(error)")
            return
        }

        manager.setBypassDomains(patterns.joined(separator: ","))
        dismiss()
    }

    private static func editableText(from storedValue: String) -> String {
        patterns(from: storedValue).joined(separator: "\n")
    }

    private static func patterns(from input: String) -> [String] {
        let rawPatterns = input
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        return rawPatterns.filter { pattern in
            seen.insert(pattern.lowercased()).inserted
        }
    }

    private static func validationError(for value: String) -> String? {
        SSLHostPatternValidation.message(for: value)
    }
}
