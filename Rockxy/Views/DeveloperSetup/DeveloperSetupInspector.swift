import SwiftUI

// MARK: - DeveloperSetupInspector

/// Compact readiness inspector. It reports current proxy/certificate state and
/// either the single active issue (with one issue-specific action) or the last
/// capture-check outcome with a Reveal handoff. It owns no setup-mode selection,
/// validation prose or duplicate capture/settings actions; those live in the
/// relevant detail tabs.
struct DeveloperSetupInspector: View {
    // MARK: Internal

    let snapshot: SetupSnapshot
    let activeIssue: SetupIssue?
    let onIssueAction: (SetupIssue) -> Void
    let onReveal: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                readinessSection
                Divider()
                statusSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "Readiness", bundle: RockxyLocalization.bundle))
            readinessRow(
                title: String(localized: "Proxy", bundle: RockxyLocalization.bundle),
                value: snapshot.proxyRunning ? String(localized: "Running", bundle: RockxyLocalization.bundle) : String(
                    localized: "Stopped",
                    bundle: RockxyLocalization.bundle
                )
            )
            readinessRow(
                title: String(localized: "Recording", bundle: RockxyLocalization.bundle),
                value: snapshot.recordingEnabled ? String(localized: "On", bundle: RockxyLocalization.bundle) : String(
                    localized: "Paused",
                    bundle: RockxyLocalization.bundle
                )
            )
            readinessRow(
                title: String(localized: "Certificate", bundle: RockxyLocalization.bundle),
                value: snapshot.certificateTrusted
                    ? String(localized: "Trusted", bundle: RockxyLocalization.bundle)
                    : String(localized: "Needs attention", bundle: RockxyLocalization.bundle)
            )
            readinessRow(
                title: String(localized: "Port", bundle: RockxyLocalization.bundle),
                value: "\(snapshot.activePort)"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusSection: some View {
        if let activeIssue {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(String(localized: "Current issue", bundle: RockxyLocalization.bundle))
                Text(activeIssue.title)
                    .font(setupMetrics.font(weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(activeIssue.message)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(activeIssue.actionTitle) {
                    onIssueAction(activeIssue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(String(localized: "Last check", bundle: RockxyLocalization.bundle))
                Text(snapshot.verificationState.title)
                    .font(setupMetrics.font(weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if snapshot.verificationState == .success, snapshot.matchedTransactionID != nil {
                    if let host = snapshot.matchedHost, let method = snapshot.matchedMethod {
                        Text("\(method) \(host)")
                            .font(setupMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(String(localized: "Reveal in Main Window", bundle: RockxyLocalization.bundle)) {
                        onReveal()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func readinessRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(title)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(setupMetrics.secondaryFont(weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(setupMetrics.secondaryFont(weight: .medium))
            }
        }
    }
}
