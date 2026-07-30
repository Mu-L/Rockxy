import SwiftUI

// Settings tab for the MCP (Model Context Protocol) server.
// Provides enable/disable toggle, connection configuration JSON,
// privacy controls, and status display.

// MARK: - MCPSettingsTab

struct MCPSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSectionCard(String(localized: "MCP Server")) {
                mcpServerSection
            }

            SettingsSectionCard(String(localized: "Client Configuration")) {
                mcpConfigurationSection
            }

            SettingsSectionCard(String(localized: "Privacy")) {
                privacySection
            }

            SettingsSectionCard(String(localized: "About MCP")) {
                aboutSection
            }
        }
        .onChange(of: mcpEnabled) { _, newValue in
            AppSettingsManager.shared.updateMCPServerEnabled(newValue)
            Task {
                if newValue {
                    await mcpCoordinator.startIfEnabled()
                } else {
                    await mcpCoordinator.stop()
                }
            }
        }
        .onChange(of: mcpRedactSensitiveData) { _, newValue in
            AppSettingsManager.shared.updateMCPRedactSensitiveData(newValue)
            mcpCoordinator.updateRedactionSetting(newValue)
        }
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("mcp.serverEnabled")) private var mcpEnabled = false

    @AppStorage(RockxyIdentity.current.defaultsKey("mcp.redactSensitiveData")) private var mcpRedactSensitiveData = true
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var mcpCoordinator: MCPServerCoordinator {
        MCPServerCoordinator.shared
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Helpers

    private var configJSON: String {
        struct ServerEntry: Encodable {
            let command: String
            let args: [String]
            let env: [String: String]
        }
        struct Config: Encodable {
            let mcpServers: [String: ServerEntry]
        }

        let config = Config(mcpServers: [
            "rockxy": ServerEntry(command: binaryPath, args: [], env: [:]),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(config),
              let text = String(data: data, encoding: .utf8) else
        {
            return "{\"mcpServers\":{\"rockxy\":{\"command\":\"rockxy-mcp\",\"args\":[],\"env\":{}}}}"
        }
        return text
    }

    private var binaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("rockxy-mcp")
            .path
    }

    // MARK: - MCP Server Section

    private var mcpServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                String(localized: "Enable MCP Server"),
                isOn: $mcpEnabled
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Start a local HTTP server for Model Context Protocol (MCP) communication with compatible tools."
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if mcpCoordinator.isRunning, let port = mcpCoordinator.activePort {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                    Text(String(localized: "Running on port \(port)"))
                        .font(settingsMetrics.secondaryFont(weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(.leading, 4)
            }

            if let error = mcpCoordinator.lastError {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text(error)
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - MCP Configuration Section

    private var mcpConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Copy this JSON into a compatible client's MCP configuration."))
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    copyConfigToClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(settingsMetrics.metadataFont())
                        Text(String(localized: "Copy"))
                            .font(settingsMetrics.secondaryFont(weight: .medium))
                    }
                }
            }

            ScrollView(.horizontal) {
                Text(configJSON)
                    .font(settingsMetrics.secondaryFont(monospaced: true))
                    .lineSpacing(4)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                String(localized: "Redact Sensitive Data Before Sending to AI"),
                isOn: $mcpRedactSensitiveData
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Automatically redact sensitive information before sending to MCP clients."
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                String(
                    localized: """
                    MCP (Model Context Protocol) allows compatible tools to interact with \
                    Rockxy. The AI can read captured HTTP traffic, inspect request and \
                    response details, export requests as cURL, and view proxy rules and status.
                    """
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.tertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyConfigToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configJSON, forType: .string)
    }
}
