import Foundation
@testable import Rockxy
import Testing

// Regression tests for `TrafficInsightsEngine` aggregation, classification, and findings.

// MARK: - TrafficInsightsEngineTests

struct TrafficInsightsEngineTests {
    // MARK: Internal

    // MARK: - Totals and bins

    @Test("Empty input produces an empty report with the requested scope")
    func emptyInputProducesEmptyReport() {
        var options = TrafficInsightsOptions()
        options.scope = .visibleTraffic
        options.timeWindow = .lastMinute

        let output = TrafficInsightsEngine.buildReport(samples: [], options: options)

        #expect(output.report.isEmpty)
        #expect(output.report.scope == .visibleTraffic)
        #expect(output.report.timeWindow == .lastMinute)
        #expect(output.report.bins.isEmpty)
        #expect(output.report.findings.isEmpty)
    }

    @Test("Totals count bytes, hosts, apps, errors, and in-flight requests")
    func totalsAggregateCoreCounters() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let samples = [
            makeSample(
                timestamp: base,
                host: "api.example.com",
                app: "Safari",
                status: 200,
                request: 100,
                response: 900
            ),
            makeSample(timestamp: base + 1, host: "api.example.com", app: "Safari", status: 500, response: 50),
            makeSample(timestamp: base + 2, host: "cdn.example.com", app: "Chrome", status: 404, response: 10),
            makeSample(timestamp: base + 3, host: "cdn.example.com", app: nil, status: nil, state: .pending),
        ]

        let totals = TrafficInsightsEngine.buildReport(samples: samples).report.totals

        #expect(totals.requestCount == 4)
        #expect(totals.completedCount == 3)
        #expect(totals.inFlightCount == 1)
        #expect(totals.errorCount == 2)
        #expect(totals.sentBytes == 100)
        #expect(totals.receivedBytes == 960)
        #expect(totals.hostCount == 2)
        #expect(totals.appCount == 2)
        #expect(totals.firstTimestamp == base)
        #expect(totals.lastTimestamp == base + 3)
        #expect(abs(totals.errorRate - 2.0 / 3.0) < 0.0001)
    }

    @Test("Bins are contiguous, aligned to the bin width, and never exceed the maximum count")
    func binsAreContiguousAndBounded() {
        let base = Date(timeIntervalSinceReferenceDate: 12_345)
        var samples: [TrafficInsightsSample] = []
        for second in stride(from: 0, through: 600, by: 3) {
            samples.append(makeSample(timestamp: base + TimeInterval(second), response: 10))
        }

        var options = TrafficInsightsOptions()
        options.maximumBinCount = 90
        let report = TrafficInsightsEngine.buildReport(samples: samples, options: options).report

        #expect(report.bins.count <= 90)
        #expect(report.binWidth == 10)
        #expect(report.bins.first?.start.timeIntervalSinceReferenceDate == 12_340)
        for (index, bin) in report.bins.enumerated() {
            let expected = 12_340 + Double(index) * report.binWidth
            #expect(bin.start.timeIntervalSinceReferenceDate == expected)
        }
        #expect(report.bins.reduce(0) { $0 + $1.requestCount } == samples.count)
    }

    @Test("A single transaction produces one bin and a one-second width")
    func singleTransactionProducesOneBin() {
        let report = TrafficInsightsEngine.buildReport(samples: [makeSample(response: 5)]).report

        #expect(report.binWidth == 1)
        #expect(report.bins.count == 1)
        #expect(report.bins.first?.requestCount == 1)
    }

    @Test("Bin width grows with the span so the timeline stays readable")
    func binWidthGrowsWithSpan() {
        #expect(TrafficInsightsEngine.binWidth(forSpan: 0, maximumBinCount: 90) == 1)
        #expect(TrafficInsightsEngine.binWidth(forSpan: 60, maximumBinCount: 90) == 1)
        #expect(TrafficInsightsEngine.binWidth(forSpan: 100, maximumBinCount: 90) == 2)
        #expect(TrafficInsightsEngine.binWidth(forSpan: 3_600, maximumBinCount: 90) == 60)
        #expect(TrafficInsightsEngine.binWidth(forSpan: 86_400 * 2, maximumBinCount: 90) == 3_600)
    }

    @Test("Nearest-rank percentile matches the documented definition")
    func percentileUsesNearestRank() {
        let values: [TimeInterval] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

        #expect(TrafficInsightsEngine.percentile(values, fraction: 0.5) == 5)
        #expect(TrafficInsightsEngine.percentile(values, fraction: 0.95) == 10)
        #expect(TrafficInsightsEngine.percentile(values, fraction: 0) == 1)
        #expect(TrafficInsightsEngine.percentile(values, fraction: 1) == 10)
        #expect(TrafficInsightsEngine.percentile([], fraction: 0.5) == nil)
    }

    // MARK: - Time window

    @Test("Time window trails the latest sample rather than the wall clock")
    func timeWindowTrailsLatestSample() {
        let base = Date(timeIntervalSinceReferenceDate: 500)
        let samples = [
            makeSample(timestamp: base, response: 1),
            makeSample(timestamp: base + 30, response: 1),
            makeSample(timestamp: base + 100, response: 1),
            makeSample(timestamp: base + 150, response: 1),
        ]
        var options = TrafficInsightsOptions()
        options.timeWindow = .lastMinute

        let report = TrafficInsightsEngine.buildReport(samples: samples, options: options).report

        #expect(report.totals.requestCount == 2)
        #expect(report.totals.firstTimestamp == base + 100)
    }

    @Test("Unsorted input is ordered by timestamp before binning")
    func unsortedInputIsOrdered() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let samples = [
            makeSample(timestamp: base + 40, response: 1),
            makeSample(timestamp: base, response: 1),
            makeSample(timestamp: base + 20, response: 1),
        ]

        let report = TrafficInsightsEngine.buildReport(samples: samples).report

        #expect(report.totals.firstTimestamp == base)
        #expect(report.totals.lastTimestamp == base + 40)
        #expect(report.bins.first?.start == base)
    }

    // MARK: - Classification

    @Test("Protocol classification prefers WebSocket, tunnel, gRPC, GraphQL, Web3, AI, then scheme")
    func protocolClassificationPriority() {
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(isTunneled: true, hasWebSocket: true)) == .webSocket)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(method: "CONNECT", isTunneled: true)) == .tunneled)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(
            url: "https://api.example.com/svc.Users/Get",
            requestHeaders: [HTTPHeader(name: "Content-Type", value: "application/grpc")]
        )) == .grpc)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(hasGraphQL: true)) == .graphQL)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(hasWeb3RPC: true)) == .web3RPC)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(
            url: "https://api.openai.com/v1/chat/completions",
            method: "POST"
        )) == .aiAPI)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(url: "http://example.com/a")) == .http)
        #expect(TrafficInsightsEngine.classifyProtocol(makeSample(url: "https://example.com/a")) == .https)
    }

    @Test("Status classes map codes and lifecycle states")
    func statusClassMapping() {
        #expect(TrafficInsightsStatusClass
            .classify(statusCode: 204, state: .completed, isTLSFailure: false) == .success)
        #expect(TrafficInsightsStatusClass
            .classify(statusCode: 301, state: .completed, isTLSFailure: false) == .redirect)
        #expect(TrafficInsightsStatusClass
            .classify(statusCode: 404, state: .completed, isTLSFailure: false) == .clientError)
        #expect(TrafficInsightsStatusClass
            .classify(statusCode: 503, state: .completed, isTLSFailure: false) == .serverError)
        #expect(TrafficInsightsStatusClass.classify(statusCode: 101, state: .completed, isTLSFailure: false) == .other)
        #expect(TrafficInsightsStatusClass.classify(statusCode: nil, state: .pending, isTLSFailure: false) == .pending)
        #expect(TrafficInsightsStatusClass.classify(statusCode: nil, state: .active, isTLSFailure: false) == .pending)
        #expect(TrafficInsightsStatusClass.classify(statusCode: nil, state: .failed, isTLSFailure: false) == .failed)
        #expect(TrafficInsightsStatusClass.classify(statusCode: 200, state: .completed, isTLSFailure: true) == .failed)
        #expect(TrafficInsightsStatusClass.classify(statusCode: 403, state: .blocked, isTLSFailure: false) == .blocked)
    }

    @Test("Content categories use the raw header for scripts, styles, and fonts")
    func contentCategoryClassification() {
        #expect(TrafficInsightsContentCategory.classify(
            contentType: .text,
            rawContentTypeHeader: "application/javascript; charset=utf-8",
            bodyByteCount: 10
        ) == .javascript)
        #expect(TrafficInsightsContentCategory.classify(
            contentType: .text,
            rawContentTypeHeader: "text/css",
            bodyByteCount: 10
        ) == .css)
        #expect(TrafficInsightsContentCategory.classify(
            contentType: .unknown,
            rawContentTypeHeader: "font/woff2",
            bodyByteCount: 10
        ) == .font)
        #expect(TrafficInsightsContentCategory.classify(
            contentType: .json,
            rawContentTypeHeader: "application/json",
            bodyByteCount: 10
        ) == .json)
        #expect(TrafficInsightsContentCategory.classify(
            contentType: nil,
            rawContentTypeHeader: nil,
            bodyByteCount: 0
        ) == .none)
        #expect(TrafficInsightsContentCategory.classify(
            contentType: .unknown,
            rawContentTypeHeader: "application/octet-stream",
            bodyByteCount: 10
        ) == .binary)
    }

    @Test("Protocol shares keep the fixed legend order and drop absent families")
    func protocolSharesKeepFixedOrder() {
        let samples = [
            makeSample(url: "http://example.com/a", response: 10),
            makeSample(url: "https://example.com/b", response: 20),
            makeSample(url: "https://example.com/c", response: 30, hasWebSocket: true),
        ]

        let report = TrafficInsightsEngine.buildReport(samples: samples).report

        #expect(report.protocols.map(\.key) == [.https, .http, .webSocket])
        #expect(report.protocols.map(\.requestCount) == [1, 1, 1])
        #expect(report.protocols.first { $0.key == .webSocket }?.bytes == 30)
    }

    @Test("Protocol cache reuses entries only while the response presence is unchanged")
    func protocolCacheInvalidatesOnResponseArrival() {
        let pending = makeSample(
            url: "https://api.openai.com/v1/chat/completions",
            method: "POST",
            status: nil,
            state: .pending
        )
        var cache = TrafficInsightsProtocolCache.empty
        cache.store(.https, for: pending)

        #expect(cache.entry(for: pending)?.kind == .https)

        let completed = TrafficInsightsSample(
            id: pending.id,
            timestamp: pending.timestamp,
            request: pending.request,
            response: TestFixtures.makeResponse(statusCode: 200),
            state: .completed,
            isTLSFailure: false,
            isTunneled: false,
            clientApp: nil,
            duration: 0.2,
            timing: nil,
            webSocketSentBytes: 0,
            webSocketReceivedBytes: 0,
            hasWebSocket: false,
            hasGraphQL: false,
            hasWeb3RPC: false,
            matchedRuleName: nil
        )

        #expect(cache.entry(for: completed) == nil)

        let output = TrafficInsightsEngine.buildReport(samples: [completed], cache: cache)
        #expect(output.cache.entry(for: completed)?.kind == .aiAPI)
        #expect(output.cache.count == 1)
    }

    @Test("Cache retains only transactions that still exist")
    func cacheDropsRemovedTransactions() {
        let kept = makeSample()
        let removed = makeSample()
        var cache = TrafficInsightsProtocolCache.empty
        cache.store(.https, for: kept)
        cache.store(.https, for: removed)

        let output = TrafficInsightsEngine.buildReport(samples: [kept], cache: cache)

        #expect(output.cache.count == 1)
        #expect(output.cache.entry(for: removed) == nil)
    }

    // MARK: - Ranked lists and outliers

    @Test("Top hosts and apps rank by transferred bytes and carry error and latency summaries")
    func rankedListsOrderByBytes() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let samples = [
            makeSample(
                timestamp: base,
                host: "big.example.com",
                app: "Safari",
                status: 200,
                response: 5_000,
                duration: 0.4
            ),
            makeSample(
                timestamp: base + 1,
                host: "big.example.com",
                app: "Safari",
                status: 500,
                response: 5_000,
                duration: 0.2
            ),
            makeSample(
                timestamp: base + 2,
                host: "small.example.com",
                app: "Chrome",
                status: 200,
                response: 100,
                duration: 0.1
            ),
            makeSample(timestamp: base + 3, host: "tiny.example.com", app: nil, status: 200, response: 1),
        ]

        let report = TrafficInsightsEngine.buildReport(samples: samples).report

        #expect(report.topHosts.map(\.name) == ["big.example.com", "small.example.com", "tiny.example.com"])
        #expect(report.topHosts.first?.errorCount == 1)
        #expect(report.topHosts.first?.medianDuration == 0.2)
        #expect(report.topApps.map(\.name) == ["Safari", "Chrome"])
        #expect(report.topApps.first?.totalBytes == 10_000)
    }

    @Test("Ranked lists honor the configured limit")
    func rankedListsHonorLimit() {
        let samples = (0 ..< 15).map { index in
            makeSample(host: "host-\(index).example.com", response: Int64(100 - index))
        }
        var options = TrafficInsightsOptions()
        options.rankedListLimit = 3

        let report = TrafficInsightsEngine.buildReport(samples: samples, options: options).report

        #expect(report.topHosts.count == 3)
        #expect(report.topHosts.first?.name == "host-0.example.com")
    }

    @Test("Slowest requests exclude WebSocket and in-flight rows; largest responses require bytes")
    func outliersFilterCorrectly() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let samples = [
            makeSample(timestamp: base, host: "a.example.com", status: 200, response: 10, duration: 3.0),
            makeSample(timestamp: base + 1, host: "b.example.com", status: 200, response: 5_000, duration: 0.5),
            makeSample(timestamp: base + 2, host: "ws.example.com", response: 20, duration: 9.0, hasWebSocket: true),
            makeSample(timestamp: base + 3, host: "pending.example.com", status: nil, state: .pending, duration: 20.0),
            makeSample(timestamp: base + 4, host: "empty.example.com", status: 204, response: 0, duration: 0.1),
        ]

        let report = TrafficInsightsEngine.buildReport(samples: samples).report

        #expect(report.slowestRequests.map(\.host) == ["a.example.com", "b.example.com", "empty.example.com"])
        #expect(report.largestResponses.map(\.host) == ["b.example.com", "ws.example.com", "a.example.com"])
    }

    @Test("Exact status codes, timing averages, peak rate, and bin transaction IDs are reported")
    func statusCodesTimingAndRates() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let timing = TimingInfo(dnsLookup: 0.01, tcpConnection: 0.02, tlsHandshake: 0.03, timeToFirstByte: 0.1, contentTransfer: 0.04)
        let samples = [
            makeSample(timestamp: base, status: 200, response: 1, timing: timing),
            makeSample(timestamp: base, status: 200, response: 1, timing: timing),
            makeSample(timestamp: base, status: 404, response: 1),
            makeSample(timestamp: base + 2, status: 503, response: 1),
        ]

        let report = TrafficInsightsEngine.buildReport(samples: samples).report

        #expect(report.statusCodes.map(\.key) == [200, 404, 503])
        #expect(report.statusCodes.first?.requestCount == 2)
        #expect(report.timing?.sampleCount == 2)
        #expect(report.timing.map { abs($0.tlsHandshake - 0.03) < 0.0001 } == true)
        #expect(report.timing.map { abs($0.total - 0.2) < 0.0001 } == true)
        #expect(report.totals.peakRequestsPerSecond == 3)
        #expect(abs(report.totals.averageRequestsPerSecond - 2) < 0.0001)
        #expect(report.bins.first?.transactionIDs.count == 3)
        #expect(report.bins.last?.transactionIDs == [samples[3].id])
    }

    @Test("Drill-down mappings point at the request-list pills that exist")
    func drillDownMappings() {
        #expect(TrafficInsightsProtocol.https.drillDown == .protocolFilter(.https))
        #expect(TrafficInsightsProtocol.tunneled.drillDown == nil)
        #expect(TrafficInsightsStatusClass.serverError.drillDown == .protocolFilter(.status5xx))
        #expect(TrafficInsightsStatusClass.failed.drillDown == .trafficSignal(.errors))
        #expect(TrafficInsightsStatusClass.pending.drillDown == nil)
        #expect(TrafficInsightsContentCategory.html.drillDown == .protocolFilter(.document))
        #expect(TrafficInsightsContentCategory.binary.drillDown == nil)
    }

    // MARK: - Findings

    @Test("Server errors on a host produce a warning finding with a host handoff")
    func serverErrorFindingIsWarning() {
        let samples = (0 ..< 6).map { index in
            makeSample(host: "api.example.com", status: index < 3 ? 503 : 200, response: 10)
        }

        let findings = TrafficInsightsEngine.buildReport(samples: samples).report.findings
        let finding = findings.first { $0.kind == .serverErrorHost }

        #expect(finding?.severity == .warning)
        #expect(finding?.handoff == .focusHost("api.example.com"))
        #expect(finding?.evidence.count == 3)
        #expect(finding?.title.contains("api.example.com") == true)
    }

    @Test("Client error finding needs enough samples and a 20 percent share")
    func clientErrorFindingThreshold() {
        let quiet = (0 ..< 4).map { _ in makeSample(host: "a.example.com", status: 401, response: 1) }
        #expect(!TrafficInsightsEngine.buildReport(samples: quiet).report.findings
            .contains { $0.kind == .clientErrorHost })

        let loud = (0 ..< 10).map { index in
            makeSample(host: "b.example.com", status: index < 3 ? 401 : 200, response: 1)
        }
        let finding = TrafficInsightsEngine.buildReport(samples: loud).report.findings
            .first { $0.kind == .clientErrorHost }
        #expect(finding?.severity == .notice)
        #expect(finding?.handoff == .focusHost("b.example.com"))
    }

    @Test("Failed requests finding escalates to warning at five failures and reports TLS failures")
    func failedRequestsFinding() {
        let few = [makeSample(status: nil, state: .failed)]
        let fewFinding = TrafficInsightsEngine.buildReport(samples: few).report.findings
            .first { $0.kind == .failedRequests }
        #expect(fewFinding?.severity == .notice)

        let many = (0 ..< 5).map { _ in makeSample(status: nil, state: .failed, isTLSFailure: true) }
        let manyFinding = TrafficInsightsEngine.buildReport(samples: many).report.findings
            .first { $0.kind == .failedRequests }
        #expect(manyFinding?.severity == .warning)
        #expect(manyFinding?.detail.contains("TLS") == true)
        if case let .revealTransactions(ids) = manyFinding?.handoff {
            #expect(ids.count == 5)
        } else {
            Issue.record("Expected a reveal handoff")
        }
    }

    @Test("Slow host finding requires five samples and a two second p95")
    func slowHostFinding() {
        let fast = (0 ..< 6).map { _ in makeSample(host: "fast.example.com", status: 200, response: 1, duration: 0.3) }
        #expect(!TrafficInsightsEngine.buildReport(samples: fast).report.findings.contains { $0.kind == .slowHost })

        let slow = (0 ..< 6).map { index in
            makeSample(host: "slow.example.com", status: 200, response: 1, duration: index == 5 ? 4.0 : 0.3)
        }
        let finding = TrafficInsightsEngine.buildReport(samples: slow).report.findings.first { $0.kind == .slowHost }
        #expect(finding?.severity == .notice)
        #expect(finding?.handoff == .focusHost("slow.example.com"))
        #expect(finding?.evidence.first?.duration == 4.0)
    }

    @Test("Uncompressed text finding ignores encoded, small, and binary responses")
    func uncompressedTextFinding() {
        let large = 200 * 1_024
        let samples = [
            makeSample(host: "a.example.com", status: 200, response: Int64(large)),
            makeSample(
                host: "b.example.com",
                status: 200,
                responseHeaders: [
                    HTTPHeader(name: "Content-Type", value: "application/json"),
                    HTTPHeader(name: "Content-Encoding", value: "gzip"),
                ],
                response: Int64(large)
            ),
            makeSample(host: "c.example.com", status: 200, response: 1_000),
            makeSample(
                host: "d.example.com",
                status: 200,
                responseHeaders: [HTTPHeader(name: "Content-Type", value: "image/png")],
                response: Int64(large)
            ),
        ]

        let finding = TrafficInsightsEngine.buildReport(samples: samples).report.findings
            .first { $0.kind == .uncompressedText }

        #expect(finding?.severity == .info)
        #expect(finding?.evidence.map(\.host) == ["a.example.com"])
    }

    @Test("Missing cache header finding counts uncached static assets only")
    func missingCacheHeadersFinding() {
        let uncached = (0 ..< 5).map { index in
            makeSample(
                url: "https://cdn.example.com/asset-\(index).js",
                status: 200,
                responseHeaders: [HTTPHeader(name: "Content-Type", value: "application/javascript")],
                response: 10
            )
        }
        let cached = makeSample(
            url: "https://cdn.example.com/cached.js",
            status: 200,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/javascript"),
                HTTPHeader(name: "Cache-Control", value: "max-age=3600"),
            ],
            response: 10
        )

        let finding = TrafficInsightsEngine.buildReport(samples: uncached + [cached]).report.findings
            .first { $0.kind == .missingCacheHeaders }

        #expect(finding != nil)
        #expect(finding?.evidence.count == 5)
        #expect(finding?.evidence.contains { $0.path.contains("cached.js") } == false)
    }

    @Test("Repeated request finding groups identical GETs and ignores fragments")
    func repeatedRequestFinding() {
        var samples = (0 ..< 5).map { index in
            makeSample(url: "https://api.example.com/config?v=1#\(index)", status: 200, response: 1)
        }
        samples.append(makeSample(url: "https://api.example.com/config?v=2", status: 200, response: 1))
        samples.append(makeSample(url: "https://api.example.com/config?v=1", method: "POST", status: 200, response: 1))

        let finding = TrafficInsightsEngine.buildReport(samples: samples).report.findings
            .first { $0.kind == .repeatedRequests }

        #expect(finding?.title.contains("5×") == true)
        #expect(finding?.evidence.count == 5)
    }

    @Test("Plain HTTP finding is informational for local hosts and a notice otherwise")
    func plainHTTPFindingSeverity() {
        let local = [makeSample(url: "http://localhost:3000/api", response: 1)]
        let localFinding = TrafficInsightsEngine.buildReport(samples: local).report.findings
            .first { $0.kind == .plainHTTP }
        #expect(localFinding?.severity == .info)

        let remote = [makeSample(url: "http://example.com/api", response: 1)]
        let remoteFinding = TrafficInsightsEngine.buildReport(samples: remote).report.findings
            .first { $0.kind == .plainHTTP }
        #expect(remoteFinding?.severity == .notice)
    }

    @Test("Tunneled connections produce an HTTPS Decryption handoff")
    func tunneledFinding() {
        let samples = [
            makeSample(url: "https://secure.example.com:443", method: "CONNECT", status: 200, isTunneled: true),
            makeSample(url: "https://other.example.com:443", method: "CONNECT", status: 200, isTunneled: true),
        ]

        let finding = TrafficInsightsEngine.buildReport(samples: samples).report.findings
            .first { $0.kind == .tunneledHosts }

        #expect(finding?.handoff == .openHTTPSDecryption)
        #expect(finding?.title.contains("2 hosts") == true)
    }

    @Test("Large upload, slow TLS, and rules-applied findings fire on their thresholds")
    func remainingFindingsFire() {
        let upload = makeSample(method: "POST", status: 200, request: 6 * 1_024 * 1_024, response: 1)
        let tls = (0 ..< 3).map { _ in
            makeSample(
                host: "tls.example.com",
                status: 200,
                response: 1,
                timing: TimingInfo(
                    dnsLookup: 0,
                    tcpConnection: 0,
                    tlsHandshake: 0.5,
                    timeToFirstByte: 0.1,
                    contentTransfer: 0
                )
            )
        }
        let ruled = makeSample(status: 200, response: 1, matchedRuleName: "Map Local: config")

        let findings = TrafficInsightsEngine.buildReport(samples: [upload] + tls + [ruled]).report.findings

        #expect(findings.contains { $0.kind == .largeUploads })
        #expect(findings.contains { $0.kind == .slowTLSHandshake && $0.handoff == .focusHost("tls.example.com") })
        #expect(findings.contains { $0.kind == .rulesApplied && $0.title.contains("Map Local: config") })
    }

    @Test("Findings are ordered by severity, then by rule order")
    func findingsAreOrderedBySeverity() {
        var samples = (0 ..< 6).map { index in
            makeSample(host: "api.example.com", status: index < 3 ? 503 : 200, response: 10)
        }
        samples.append(makeSample(url: "http://localhost/api", response: 1))
        samples.append(makeSample(status: nil, state: .failed))

        let findings = TrafficInsightsEngine.buildReport(samples: samples).report.findings

        #expect(findings.first?.kind == .serverErrorHost)
        let severities = findings.map(\.severity.rawValue)
        #expect(severities == severities.sorted(by: >))
    }

    // MARK: Private

    private func makeSample(
        timestamp: Date = Date(timeIntervalSinceReferenceDate: 0),
        url: String = "https://api.example.com/test",
        method: String = "GET",
        host: String? = nil,
        app: String? = nil,
        status: Int? = 200,
        state: TransactionState = .completed,
        requestHeaders: [HTTPHeader] = [],
        responseHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        request: Int64 = 0,
        response: Int64 = 0,
        duration: TimeInterval? = 0.1,
        timing: TimingInfo? = nil,
        isTLSFailure: Bool = false,
        isTunneled: Bool = false,
        hasWebSocket: Bool = false,
        hasGraphQL: Bool = false,
        hasWeb3RPC: Bool = false,
        matchedRuleName: String? = nil
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
        let requestData = HTTPRequestData(
            method: method,
            url: parsed,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: request > 0 ? Data(repeating: 0xAB, count: Int(request)) : nil,
            contentType: nil
        )
        let responseData: HTTPResponseData? = status.map { code in
            var data = HTTPResponseData(
                statusCode: code,
                statusMessage: "",
                headers: responseHeaders,
                body: response > 0 ? Data(repeating: 0xCD, count: Int(response)) : nil
            )
            data.contentType = ContentType.detect(
                from: responseHeaders.first { $0.name.lowercased() == "content-type" }?.value
            )
            return data
        }
        return TrafficInsightsSample(
            id: UUID(),
            timestamp: timestamp,
            request: requestData,
            response: responseData,
            state: state,
            isTLSFailure: isTLSFailure,
            isTunneled: isTunneled,
            clientApp: app,
            duration: timing?.totalDuration ?? duration,
            timing: timing,
            webSocketSentBytes: 0,
            webSocketReceivedBytes: 0,
            hasWebSocket: hasWebSocket,
            hasGraphQL: hasGraphQL,
            hasWeb3RPC: hasWeb3RPC,
            matchedRuleName: matchedRuleName
        )
    }
}
