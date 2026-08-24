import SwiftUI

// MARK: - SOCKSProxySettingsView

/// Compatibility handoff retained for restored windows and older commands.
/// External Proxy Settings is the single owner of upstream-proxy edits.
struct SOCKSProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "SOCKS5 Proxy"))
                    .font(toolMetrics.font(weight: .medium))

                Text(String(localized: "SOCKS5 now uses the shared External Proxy workflow."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.headerBottomPadding)
            .rockxyFunctionalBar()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.forward.app")
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            localized:
                            "Manage Automatic, HTTP, HTTPS, and SOCKS5 upstream options in one shared settings window."
                        )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(toolMetrics.formHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: toolMetrics.formVerticalPadding)

            Divider()

            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()

                Button(String(localized: "Close")) {
                    dismiss()
                }
                .frame(width: toolMetrics.footerButtonWidth)
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Open External Proxy Settings")) {
                    openWindow(id: "externalProxySettings")
                    dismiss()
                }
                .fixedSize(horizontal: true, vertical: false)
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.footerTopPadding)
            .rockxyFunctionalBar()
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(640), height: 280)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
