import SwiftUI

// MARK: - SettingsPane

/// Shared scroll surface for standard Settings panes.
/// Keeping the outer insets here prevents individual categories from drifting
/// when they are hosted inside the common sidebar/content shell.
struct SettingsPane<Content: View>: View {
    // MARK: Internal

    @ViewBuilder let content: Content

    var body: some View {
        let scrollView = ScrollView {
            VStack(alignment: .leading, spacing: settingsMetrics.sectionSpacing) {
                content
            }
            .padding(.horizontal, settingsMetrics.contentPadding)
            .padding(.vertical, settingsMetrics.paneContentPadding)
            .frame(maxWidth: settingsMetrics.contentMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            scrollView.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            scrollView
        }
        #else
        scrollView
        #endif
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsSection

/// Shared grouping for dense Settings panes.
/// A flat settings section modeled after Developer Setup. The title establishes
/// hierarchy while the content remains on the opaque reading plane; adding a
/// card or glass background here would create a nested surface inside the
/// window's native Liquid Glass chrome.
struct SettingsSection<Content: View>: View {
    // MARK: Lifecycle

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    // MARK: Internal

    let title: String
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(settingsMetrics.sectionTitleFont())
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: settingsMetrics.sectionContentSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsFieldRow

struct SettingsFieldRow<Content: View>: View {
    // MARK: Lifecycle

    init(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    // MARK: Internal

    let label: String
    let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: settingsMetrics.fieldSpacing) {
                fieldLabel
                    .frame(width: settingsMetrics.labelWidth, alignment: .trailing)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 7) {
                fieldLabel
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var fieldLabel: some View {
        Text(label)
            .font(settingsMetrics.font(weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - SettingsIndentedContent

struct SettingsIndentedContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
