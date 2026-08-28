import SwiftUI

/// At-a-glance summary of a transaction: method, URL, host, path, HTTP version,
/// response status, content type, size, duration, and originating client app.
struct SynopsisInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                synopsisRow(String(localized: "Method", bundle: RockxyLocalization.bundle), transaction.request.method)
                synopsisRow(
                    String(localized: "URL", bundle: RockxyLocalization.bundle),
                    transaction.request.url.absoluteString
                )
                synopsisRow(String(localized: "Host", bundle: RockxyLocalization.bundle), transaction.request.host)
                synopsisRow(String(localized: "Path", bundle: RockxyLocalization.bundle), transaction.request.path)
                synopsisRow("HTTP Version", transaction.request.httpVersion)

                if let matchedRuleName = transaction.matchedRuleName {
                    Divider()
                    synopsisRow(String(localized: "Matched Rule", bundle: RockxyLocalization.bundle), matchedRuleName)
                    if let actionSummary = transaction.matchedRuleActionSummary {
                        synopsisRow(String(localized: "Rule Action", bundle: RockxyLocalization.bundle), actionSummary)
                    }
                    if let pattern = transaction.matchedRulePattern {
                        synopsisRow(String(localized: "Rule Pattern", bundle: RockxyLocalization.bundle), pattern)
                    }
                }

                if let response = transaction.response {
                    Divider()
                    synopsisRow(
                        String(localized: "Status", bundle: RockxyLocalization.bundle),
                        "\(response.statusCode) \(response.statusMessage)"
                    )
                    if let contentType = response.contentType {
                        synopsisRow("Content-Type", contentType.rawValue)
                    }
                    if let body = response.body {
                        synopsisRow(
                            String(localized: "Response Size", bundle: RockxyLocalization.bundle),
                            "\(body.count) bytes"
                        )
                    }
                }

                if let timing = transaction.timingInfo {
                    Divider()
                    synopsisRow(
                        String(localized: "Duration", bundle: RockxyLocalization.bundle),
                        DurationFormatter.format(seconds: timing.totalDuration)
                    )
                }

                if let clientApp = transaction.clientApp {
                    Divider()
                    synopsisRow(String(localized: "Client App", bundle: RockxyLocalization.bundle), clientApp)
                }
            }
            .padding()
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func synopsisRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
