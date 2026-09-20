import Foundation
@testable import Rockxy
import Testing

// Regression tests for the Markdown export of a Traffic Insights report.

// MARK: - TrafficInsightsReportFormatterTests

struct TrafficInsightsReportFormatterTests {
    // MARK: Internal

    @Test("Markdown export includes every populated section and no payload data")
    func markdownIncludesSections() {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let samples = [
            makeSample(
                timestamp: base,
                host: "api.example.com",
                app: "Safari",
                status: 200,
                response: 2_048,
                duration: 0.2
            ),
            makeSample(
                timestamp: base + 2,
                host: "api.example.com",
                app: "Safari",
                status: 500,
                response: 512,
                duration: 1.4
            ),
            makeSample(
                timestamp: base + 4,
                host: "cdn.example.com",
                app: "Chrome",
                status: 200,
                response: 8_192,
                duration: 0.05
            ),
            makeSample(timestamp: base + 6, url: "http://example.com/plain", status: 200, response: 10, duration: 0.05),
        ]
        let report = TrafficInsightsEngine.buildReport(samples: samples, generatedAt: base + 10).report
        let context = TrafficInsightsReportFormatter.Context(
            projectName: "Checkout",
            trafficTabName: "All Traffic",
            generatedAt: base + 10,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC") ?? .current
        )

        let markdown = TrafficInsightsReportFormatter.markdown(for: report, context: context)

        #expect(markdown.hasPrefix("# \(RockxyIdentity.current.displayName) Traffic Insights"))
        #expect(markdown.contains("- Project: Checkout"))
        #expect(markdown.contains("- Traffic Tab: All Traffic"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("| Requests | 4 |"))
        #expect(markdown.contains("## Findings"))
        #expect(markdown.contains("## Protocols"))
        #expect(markdown.contains("## Status"))
        #expect(markdown.contains("## Top Apps"))
        #expect(markdown.contains("| 1 | Safari |") || markdown.contains("| 1 | Chrome |"))
        #expect(markdown.contains("## Top Hosts"))
        #expect(markdown.contains("## Slowest Requests"))
        #expect(markdown.contains("## Largest Responses"))
        #expect(markdown.contains("## Traffic Over Time"))
        #expect(!markdown.contains("Content-Type"))
        #expect(!markdown.contains("0xCD"))
    }

    @Test("Empty report exports only the header and summary")
    func emptyReportExport() {
        let context = TrafficInsightsReportFormatter.Context(
            projectName: "P",
            trafficTabName: "T",
            generatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        let markdown = TrafficInsightsReportFormatter.markdown(for: .empty, context: context)

        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("| Requests | 0 |"))
        #expect(!markdown.contains("## Findings"))
        #expect(!markdown.contains("## Top Hosts"))
        #expect(!markdown.contains("## Traffic Over Time"))
    }

    @Test("Percent formatting rounds and marks sub-one-percent shares")
    func percentFormatting() {
        #expect(TrafficInsightsReportFormatter.formatPercent(0) == "0%")
        #expect(TrafficInsightsReportFormatter.formatPercent(0.004) == "<1%")
        #expect(TrafficInsightsReportFormatter.formatPercent(0.5) == "50%")
        #expect(TrafficInsightsReportFormatter.formatPercent(0.996) == ">99%")
        #expect(TrafficInsightsReportFormatter.formatPercent(1) == "100%")
        #expect(TrafficInsightsReportFormatter.formatPercent(.nan) == "0%")
    }

    @Test("Duration and byte helpers degrade gracefully")
    func helperFormatting() {
        #expect(TrafficInsightsReportFormatter.formatDuration(nil) == "—")
        #expect(TrafficInsightsReportFormatter.formatDuration(0.25) == "250 ms")
        #expect(TrafficInsightsReportFormatter.formatBytes(0).hasPrefix("0"))
        #expect(TrafficInsightsReportFormatter.formatBytes(-5).hasPrefix("0"))
        #expect(TrafficInsightsReportFormatter.formatCount(12_345) == 12_345.formatted(.number.grouping(.automatic)))
    }

    // MARK: Private

    private func makeSample(
        timestamp: Date,
        url: String = "https://api.example.com/test",
        host: String? = nil,
        app: String? = nil,
        status: Int?,
        response: Int64,
        duration: TimeInterval
    )
        -> TrafficInsightsSample
    {
        var resolvedURL = url
        if let host {
            resolvedURL = "https://\(host)/test"
        }
        guard let parsed = URL(string: resolvedURL) else {
            preconditionFailure("Expected valid fixture URL")
        }
        let request = HTTPRequestData(method: "GET", url: parsed, httpVersion: "HTTP/1.1", headers: [])
        let responseData: HTTPResponseData? = status.map { code in
            HTTPResponseData(
                statusCode: code,
                statusMessage: "",
                headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
                body: Data(repeating: 0xCD, count: Int(response)),
                contentType: .json
            )
        }
        return TrafficInsightsSample(
            id: UUID(),
            timestamp: timestamp,
            request: request,
            response: responseData,
            state: .completed,
            isTLSFailure: false,
            isTunneled: false,
            clientApp: app,
            duration: duration,
            timing: nil,
            webSocketSentBytes: 0,
            webSocketReceivedBytes: 0,
            hasWebSocket: false,
            hasGraphQL: false,
            hasWeb3RPC: false,
            matchedRuleName: nil
        )
    }
}
