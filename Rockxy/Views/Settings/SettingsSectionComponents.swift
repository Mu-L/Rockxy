import SwiftUI

// MARK: - SettingsPane

/// Shared scroll surface for standard Settings panes.
/// Keeping the outer insets here prevents individual categories from drifting
/// when they are hosted inside the common sidebar/content shell.
struct SettingsPane<Content: View>: View {
    // MARK: Lifecycle

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: Internal

    let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: settingsMetrics.sectionSpacing) {
                content
            }
            .padding(.horizontal, settingsMetrics.contentPadding)
            .padding(.vertical, settingsMetrics.paneContentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsSectionCard

/// Shared grouping for dense Settings panes.
/// A restrained native `GroupBox` — the section title is the group label and
/// fields align via `SettingsFieldRow` / `SettingsIndentedContent`.
struct SettingsSectionCard<Content: View>: View {
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
        GroupBox {
            VStack(alignment: .leading, spacing: settingsMetrics.sectionContentSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Text(title)
                .font(settingsMetrics.font(weight: .medium))
        }
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
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(settingsMetrics.font(weight: .medium))
                .frame(width: settingsMetrics.labelWidth, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 3)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsIndentedContent

struct SettingsIndentedContent<Content: View>: View {
    // MARK: Internal

    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: settingsMetrics.rowLeading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
