import SwiftUI

// Renders the previewer tab interface for the settings experience.

struct PreviewerTabSettingsView: View {
    // MARK: Internal

    let store: PreviewTabStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            previewMatrix
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(720, toolMetrics.bodyFontSize * 24 + 408),
            minHeight: max(500, toolMetrics.bodyFontSize * 14 + 304)
        )
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var requestEnabledCount: Int {
        PreviewRenderMode.allCases.count {
            store.isEnabled(renderMode: $0, panel: .request)
        }
    }

    private var responseEnabledCount: Int {
        PreviewRenderMode.allCases.count {
            store.isEnabled(renderMode: $0, panel: .response)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Inspector Preview Tabs", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .semibold))
                Text(
                    String(
                        localized: "Choose which built-in format tabs appear in the request and response inspectors.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(localized: "APPLIES IMMEDIATELY", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.metadataFont(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    """
                    Raw includes the request or status line and headers. Other formats focus on body content and may show \
                    an unavailable state when the selected payload does not match.
                    """, bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var previewMatrix: some View {
        Table(PreviewRenderMode.allCases) {
            TableColumn(String(localized: "Format", bundle: RockxyLocalization.bundle)) { mode in
                Text(mode.displayName)
                    .font(toolMetrics.font())
                    .lineLimit(1)
            }
            .width(min: 260, ideal: 360)

            TableColumn(String(localized: "Request", bundle: RockxyLocalization.bundle)) { mode in
                centeredToggle(for: mode, panel: .request)
            }
            .width(120)

            TableColumn(String(localized: "Response", bundle: RockxyLocalization.bundle)) { mode in
                centeredToggle(for: mode, panel: .response)
            }
            .width(120)
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
            Toggle(
                String(localized: "Beautify minified HTML, CSS, and JavaScript", bundle: RockxyLocalization.bundle),
                isOn: Binding(
                    get: { store.autoBeautify },
                    set: { store.autoBeautify = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(toolMetrics.font())

            Spacer()

            Text(
                String(
                    localized:
                    "\(requestEnabledCount) request tabs · \(responseEnabledCount) response tabs",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private func centeredToggle(for mode: PreviewRenderMode, panel: PreviewPanel) -> some View {
        HStack {
            Spacer(minLength: 0)
            Toggle(
                "",
                isOn: Binding(
                    get: { store.isEnabled(renderMode: mode, panel: panel) },
                    set: { enabled in
                        if enabled {
                            store.enableTab(renderMode: mode, panel: panel)
                        } else {
                            store.disableTab(renderMode: mode, panel: panel)
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(
                String(
                    localized:
                    "\(mode.displayName) \(panel == .request ? "Request" : "Response") preview",
                    bundle: RockxyLocalization.bundle
                )
            )
            Spacer(minLength: 0)
        }
    }
}
