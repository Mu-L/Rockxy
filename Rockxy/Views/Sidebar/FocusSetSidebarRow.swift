import SwiftUI

// MARK: - FocusSetSidebarRow

/// Compact source-list row that keeps a Focus Set scannable while exposing its exact rules on demand.
struct FocusSetSidebarRow: View {
    // MARK: Internal

    let focusSet: FocusSet
    let isActive: Bool
    @Binding var isExpanded: Bool

    let onApply: () -> Void

    var body: some View {
        if focusSet.hasSidebarRuleDetails {
            DisclosureGroup(isExpanded: $isExpanded) {
                ruleDetails
            } label: {
                rowLabel
            }
        } else {
            rowLabel
        }
    }

    // MARK: Private

    @ViewBuilder private var leadingIcon: some View {
        if focusSet.appName.isEmpty {
            Image(systemName: "scope")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
        } else {
            CapturedApplicationIconView(name: focusSet.appName, size: 20)
        }
    }

    private var rowLabel: some View {
        Button(action: onApply) {
            HStack(alignment: .top, spacing: 7) {
                leadingIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(focusSet.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !isExpanded, let summary = focusSet.sidebarScopeSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 6)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(String(localized: "Active"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive
            ? String(localized: "This Focus Set is active. Click to reapply it.")
            : String(localized: "Apply this Focus Set."))
        .accessibilityValue(
            focusSet.ruleCount == 1
                ? String(localized: "1 condition")
                : String(localized: "\(focusSet.ruleCount) conditions")
        )
    }

    @ViewBuilder private var ruleDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !focusSet.sidebarIncludedRules.isEmpty {
                ruleGroup(
                    title: String(localized: "Show when all match"),
                    systemImage: "checkmark.circle",
                    rules: focusSet.sidebarIncludedRules
                )
            }
            if !focusSet.sidebarExcludedRules.isEmpty {
                ruleGroup(
                    title: String(localized: "Hide when any match"),
                    systemImage: "eye.slash",
                    rules: focusSet.sidebarExcludedRules
                )
            }
        }
        .padding(.top, 4)
        .padding(.leading, 2)
    }

    private func ruleGroup(
        title: String,
        systemImage: String,
        rules: [FocusSetRuleDescriptor]
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rules) { rule in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ruleLabel(rule.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .leading)
                    Text(rule.pattern)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(rule.pattern)
                }
            }
        }
    }

    private func ruleLabel(_ kind: FocusSetRuleDescriptor.Kind) -> String {
        switch kind {
        case .application:
            String(localized: "Application")
        case .domain:
            String(localized: "Domain")
        case .pathPrefix:
            String(localized: "Path")
        }
    }
}
