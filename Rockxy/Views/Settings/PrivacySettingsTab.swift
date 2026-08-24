import AppKit
import SwiftUI

/// Privacy settings showing honest disclosure about data storage, exports, and telemetry.
struct PrivacySettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "Data Storage")) {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Local Traffic Storage"))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(
                                String(
                                    localized: "All captured HTTP/HTTPS requests, responses, headers, and bodies are stored in an unencrypted SQLite database on your Mac."
                                )
                            )
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Text("~" + "/Library/Application Support/" + RockxyIdentity.current
                                .appSupportDirectoryName + "/rockxy.sqlite3")
                                .font(settingsMetrics.secondaryFont(monospaced: true))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }

                    Divider()

                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Large Response Bodies"))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(String(localized: "Responses larger than 1 MB are saved as separate files."))
                                .font(settingsMetrics.secondaryFont())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("~" + "/Library/Application Support/" + RockxyIdentity.current
                                .appSupportDirectoryName + "/bodies/")
                                .font(settingsMetrics.secondaryFont(monospaced: true))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            }

            SettingsSection(String(localized: "Exports & Sharing")) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Exports Contain Full Traffic Data"))
                            .font(settingsMetrics.font(weight: .medium))
                        Text(
                            String(
                                localized: """
                                HAR, session, and Gist exports can include captured headers, cookies, \
                                authorization tokens, and request/response bodies. Review exports \
                                before sharing or publishing.
                                """
                            )
                        )
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            SettingsSection(String(localized: "Analytics & Telemetry")) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "No Telemetry"))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(String(localized: "No Data Collected"))
                                .font(settingsMetrics.metadataFont(weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .rockxyChipStyle(tint: .green, isActive: true)
                        }
                        Text(
                            String(
                                localized: """
                                Rockxy does not collect analytics or crash reports. Captured traffic stays on your \
                                machine unless you explicitly export, share, or publish it.
                                """
                            )
                        )
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "Privacy Policy")) {
                    if let url = URL(string: "https://www.rockxy.io/privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
