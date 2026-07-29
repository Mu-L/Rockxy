import SwiftUI

// MARK: - DeveloperSetupSourceList

/// Native macOS sidebar list with system selection + keyboard navigation.
/// Selection is driven by the view model; the parent supplies the search-filtered
/// sections, so this view stays declarative.
struct DeveloperSetupSourceList: View {
    // MARK: Internal

    @Binding var selection: SetupTarget.ID?

    let sections: [SetupTargetSection]
    let isPinned: (SetupTarget) -> Bool
    let onTogglePinned: (SetupTarget) -> Void

    var body: some View {
        List(selection: $selection) {
            if sections.isEmpty {
                emptySearchState
            } else {
                ForEach(sections) { section in
                    Section(section.category.title) {
                        if section.targets.isEmpty {
                            Text(emptySectionTitle(for: section.category))
                                .font(setupMetrics.secondaryFont())
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(section.targets, id: \.id) { target in
                                row(for: target)
                                    .tag(target.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .font(setupMetrics.font())
        .accessibilityLabel(String(localized: "Developer setup targets"))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var emptySearchState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No matching setups"))
                .font(setupMetrics.font(weight: .semibold))
            Text(String(localized: "Try another runtime, browser, framework, environment, or category name."))
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func row(for target: SetupTarget) -> some View {
        HStack(spacing: 10) {
            Image(systemName: target.iconName)
                .font(setupMetrics.font(size: setupMetrics.iconFontSize, weight: .medium))
                .foregroundStyle(selection == target.id ? .primary : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(target.title)
                    .font(setupMetrics.font(weight: selection == target.id ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if target.supportStatus == .guideOnly {
                    Text(target.supportStatus.title)
                        .font(setupMetrics.font(size: setupMetrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isPinned(target) || selection == target.id {
                Button {
                    onTogglePinned(target)
                } label: {
                    Image(systemName: isPinned(target) ? "pin.fill" : "pin")
                        .font(setupMetrics.font(size: setupMetrics.metadataFontSize, weight: .semibold))
                        .foregroundStyle(isPinned(target) ? Color(nsColor: .systemBlue) : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(pinActionTitle(for: target))
                .accessibilityLabel(pinActionTitle(for: target))
            }
        }
        .frame(minHeight: setupMetrics.sidebarRowHeight)
        .contentShape(Rectangle())
        .help(target.shortSummary)
        .accessibilityLabel(target.title)
        .accessibilityValue(target.supportStatus.title)
        .contextMenu {
            Button(pinActionTitle(for: target)) {
                onTogglePinned(target)
            }
        }
    }

    private func pinActionTitle(for target: SetupTarget) -> String {
        if isPinned(target) {
            return String(localized: "Unpin")
        }
        return String(localized: "Pin")
    }

    private func emptySectionTitle(for category: SetupTargetCategory) -> String {
        switch category {
        case .pinned:
            String(localized: "No pinned setups yet")
        default:
            String(localized: "No setups in this section")
        }
    }
}
