import Foundation

// Aggregates captured traffic into the Traffic Insights report.

// MARK: - TrafficInsightsOptions

struct TrafficInsightsOptions: Sendable, Equatable {
    var scope: TrafficInsightsScope = .allTraffic
    var timeWindow: TrafficInsightsTimeWindow = .entireSession
    /// Maximum number of contiguous bins the timeline may contain.
    var maximumBinCount = 90
    var rankedListLimit = 10
    var outlierListLimit = 8
    var evidenceLimit = 12
}

// MARK: - TrafficInsightsProtocolCache

/// Remembers each transaction's protocol family so repeated report builds skip body scanning.
/// An entry is reused only while the response presence has not changed, because AI, gRPC,
/// and GraphQL signals can appear once the response lands.
struct TrafficInsightsProtocolCache: Sendable, Equatable {
    // MARK: Internal

    struct Entry: Sendable, Equatable {
        let kind: TrafficInsightsProtocol
        let hasResponse: Bool
        let hasWebSocket: Bool
    }

    static let empty = TrafficInsightsProtocolCache()

    var count: Int {
        entries.count
    }

    func entry(for sample: TrafficInsightsSample) -> Entry? {
        guard let entry = entries[sample.id],
              entry.hasResponse == (sample.response != nil),
              entry.hasWebSocket == sample.hasWebSocket else
        {
            return nil
        }
        return entry
    }

    mutating func store(_ kind: TrafficInsightsProtocol, for sample: TrafficInsightsSample) {
        entries[sample.id] = Entry(
            kind: kind,
            hasResponse: sample.response != nil,
            hasWebSocket: sample.hasWebSocket
        )
    }

    /// Drops entries for transactions that no longer exist so a long session cannot grow the
    /// cache without bound.
    mutating func retain(ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    // MARK: Private

    private var entries: [UUID: Entry] = [:]
}

// MARK: - TrafficInsightsEngine

/// Pure aggregation over `TrafficInsightsSample` values. Runs on any executor; it never touches
/// live transactions, UI state, or the main actor.
nonisolated enum TrafficInsightsEngine {
    // MARK: Internal

    struct Output: Sendable {
        let report: TrafficInsightsReport
        let cache: TrafficInsightsProtocolCache
    }

    /// Candidate bin widths in seconds, from one second up to one hour.
    static let binWidthCandidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1_800, 3_600]

    static let uncompressedTextThreshold: Int64 = 100 * 1_024
    static let largeUploadThreshold: Int64 = 5 * 1_024 * 1_024
    static let slowHostTailThreshold: TimeInterval = 2.0
    static let slowTLSHandshakeThreshold: TimeInterval = 0.3
    static let repeatedRequestThreshold = 5
    static let hostSampleFloor = 5

    static func buildReport(
        samples: [TrafficInsightsSample],
        options: TrafficInsightsOptions = TrafficInsightsOptions(),
        cache: TrafficInsightsProtocolCache = .empty,
        generatedAt: Date = Date()
    )
        -> Output
    {
        var cache = cache
        cache.retain(ids: Set(samples.map(\.id)))

        let ordered = samples.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let windowed = applyTimeWindow(options.timeWindow, to: ordered)

        guard !windowed.isEmpty else {
            var empty = TrafficInsightsReport.empty
            empty = TrafficInsightsReport(
                generatedAt: generatedAt,
                scope: options.scope,
                timeWindow: options.timeWindow,
                totals: empty.totals,
                binWidth: empty.binWidth,
                bins: [],
                protocols: [],
                statusClasses: [],
                statusCodes: [],
                timing: nil,
                contentCategories: [],
                methods: [],
                topApps: [],
                topHosts: [],
                slowestRequests: [],
                largestResponses: [],
                findings: []
            )
            return Output(report: empty, cache: cache)
        }

        var protocolsByID: [UUID: TrafficInsightsProtocol] = [:]
        protocolsByID.reserveCapacity(windowed.count)
        for sample in windowed {
            let kind: TrafficInsightsProtocol
            if let cached = cache.entry(for: sample) {
                kind = cached.kind
            } else {
                kind = classifyProtocol(sample)
                cache.store(kind, for: sample)
            }
            protocolsByID[sample.id] = kind
        }

        let (binWidth, bins) = computeBins(windowed, maximumBinCount: options.maximumBinCount)
        let peakRate = Double(bins.map(\.requestCount).max() ?? 0) / max(binWidth, 1)
        let totals = computeTotals(windowed, peakRequestsPerSecond: peakRate)
        let report = TrafficInsightsReport(
            generatedAt: generatedAt,
            scope: options.scope,
            timeWindow: options.timeWindow,
            totals: totals,
            binWidth: binWidth,
            bins: bins,
            protocols: protocolShares(windowed, protocolsByID: protocolsByID),
            statusClasses: statusShares(windowed),
            statusCodes: statusCodeShares(windowed),
            timing: timingBreakdown(windowed),
            contentCategories: contentShares(windowed),
            methods: methodShares(windowed),
            topApps: rankedApps(windowed, limit: options.rankedListLimit),
            topHosts: rankedHosts(windowed, limit: options.rankedListLimit),
            slowestRequests: slowestRequests(windowed, limit: options.outlierListLimit),
            largestResponses: largestResponses(windowed, limit: options.outlierListLimit),
            findings: findings(windowed, evidenceLimit: options.evidenceLimit)
        )
        return Output(report: report, cache: cache)
    }

    // MARK: - Classification

    static func classifyProtocol(_ sample: TrafficInsightsSample) -> TrafficInsightsProtocol {
        if sample.hasWebSocket || sample.scheme == "ws" || sample.scheme == "wss" {
            return .webSocket
        }
        if sample.isTunneled {
            return .tunneled
        }
        if GRPCDetector.isGRPC(request: sample.request, response: sample.response) {
            return .grpc
        }
        if sample.hasGraphQL {
            return .graphQL
        }
        if sample.hasWeb3RPC {
            return .web3RPC
        }
        let aiSignal = AITrafficDetector.signal(snapshot: AITrafficSnapshot(sample: sample))
        if aiSignal.isLikelyAI {
            return .aiAPI
        }
        return sample.scheme == "http" ? .http : .https
    }

    // MARK: - Statistics

    /// Nearest-rank percentile over an ascending array. `fraction` is in `0...1`.
    static func percentile(_ sortedValues: [TimeInterval], fraction: Double) -> TimeInterval? {
        guard !sortedValues.isEmpty else {
            return nil
        }
        let clamped = min(max(fraction, 0), 1)
        let rank = Int((clamped * Double(sortedValues.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedValues.count - 1)
        return sortedValues[index]
    }

    static func applyTimeWindow(
        _ window: TrafficInsightsTimeWindow,
        to ordered: [TrafficInsightsSample]
    )
        -> [TrafficInsightsSample]
    {
        guard let duration = window.duration, let last = ordered.last else {
            return ordered
        }
        // The window trails the latest captured transaction rather than the wall clock, so an
        // imported or paused session still reports its most recent activity.
        let cutoff = last.timestamp.addingTimeInterval(-duration)
        guard let firstIndex = ordered.firstIndex(where: { $0.timestamp >= cutoff }) else {
            return []
        }
        return Array(ordered[firstIndex...])
    }

    static func binWidth(forSpan span: TimeInterval, maximumBinCount: Int) -> TimeInterval {
        let target = max(2, maximumBinCount)
        for candidate in binWidthCandidates {
            let count = Int((span / candidate).rounded(.down)) + 1
            if count <= target {
                return candidate
            }
        }
        return binWidthCandidates[binWidthCandidates.count - 1]
    }

    // MARK: Private

    private struct MutableBin {
        var sentBytes: Int64 = 0
        var receivedBytes: Int64 = 0
        var requestCount = 0
        var counts: [TrafficInsightsStatusClass: Int] = [:]
        var durations: [TimeInterval] = []
        var transactionIDs: [UUID] = []
    }

    private struct MutableRank {
        var requestCount = 0
        var sentBytes: Int64 = 0
        var receivedBytes: Int64 = 0
        var errorCount = 0
        var durations: [TimeInterval] = []
    }

    private static func computeTotals(
        _ samples: [TrafficInsightsSample],
        peakRequestsPerSecond: Double
    )
        -> TrafficInsightsTotals
    {
        var completed = 0
        var inFlight = 0
        var errors = 0
        var sent: Int64 = 0
        var received: Int64 = 0
        var hosts = Set<String>()
        var apps = Set<String>()
        var durations: [TimeInterval] = []
        durations.reserveCapacity(samples.count)

        for sample in samples {
            let statusClass = sample.statusClass
            switch statusClass {
            case .pending:
                inFlight += 1
            case .success,
                 .redirect,
                 .clientError,
                 .serverError,
                 .failed,
                 .blocked,
                 .other:
                completed += 1
            }
            if statusClass.isError {
                errors += 1
            }
            sent += sample.sentBytes
            received += sample.receivedBytes
            if !sample.host.isEmpty {
                hosts.insert(sample.host)
            }
            if let app = sample.clientApp, !app.isEmpty {
                apps.insert(app)
            }
            if let duration = sample.duration, duration > 0, statusClass != .pending {
                durations.append(duration)
            }
        }
        durations.sort()

        return TrafficInsightsTotals(
            requestCount: samples.count,
            completedCount: completed,
            inFlightCount: inFlight,
            errorCount: errors,
            sentBytes: sent,
            receivedBytes: received,
            hostCount: hosts.count,
            appCount: apps.count,
            medianDuration: percentile(durations, fraction: 0.5),
            p95Duration: percentile(durations, fraction: 0.95),
            firstTimestamp: samples.first?.timestamp,
            lastTimestamp: samples.last?.timestamp,
            peakRequestsPerSecond: peakRequestsPerSecond
        )
    }

    private static func computeBins(
        _ samples: [TrafficInsightsSample],
        maximumBinCount: Int
    )
        -> (TimeInterval, [TrafficInsightsTimelineBin])
    {
        guard let first = samples.first, let last = samples.last else {
            return (1, [])
        }
        let span = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        let width = binWidth(forSpan: span, maximumBinCount: maximumBinCount)
        let origin = (first.timestamp.timeIntervalSinceReferenceDate / width).rounded(.down) * width
        let binCount = Int(((last.timestamp.timeIntervalSinceReferenceDate - origin) / width).rounded(.down)) + 1
        var buckets = [MutableBin](repeating: MutableBin(), count: max(1, binCount))

        for sample in samples {
            let offset = sample.timestamp.timeIntervalSinceReferenceDate - origin
            let index = min(max(Int((offset / width).rounded(.down)), 0), buckets.count - 1)
            buckets[index].sentBytes += sample.sentBytes
            buckets[index].receivedBytes += sample.receivedBytes
            buckets[index].requestCount += 1
            buckets[index].counts[sample.statusClass, default: 0] += 1
            buckets[index].transactionIDs.append(sample.id)
            if let duration = sample.duration, duration > 0, sample.statusClass != .pending {
                buckets[index].durations.append(duration)
            }
        }

        let bins = buckets.enumerated().map { index, bucket in
            let sorted = bucket.durations.sorted()
            return TrafficInsightsTimelineBin(
                start: Date(timeIntervalSinceReferenceDate: origin + Double(index) * width),
                sentBytes: bucket.sentBytes,
                receivedBytes: bucket.receivedBytes,
                requestCount: bucket.requestCount,
                countsByStatusClass: bucket.counts,
                medianDuration: percentile(sorted, fraction: 0.5),
                tailDuration: percentile(sorted, fraction: 0.95),
                transactionIDs: bucket.transactionIDs
            )
        }
        return (width, bins)
    }

    private static func protocolShares(
        _ samples: [TrafficInsightsSample],
        protocolsByID: [UUID: TrafficInsightsProtocol]
    )
        -> [TrafficInsightsShare<TrafficInsightsProtocol>]
    {
        var counts: [TrafficInsightsProtocol: (Int, Int64)] = [:]
        for sample in samples {
            let kind = protocolsByID[sample.id] ?? .https
            let current = counts[kind] ?? (0, 0)
            counts[kind] = (current.0 + 1, current.1 + sample.totalBytes)
        }
        return TrafficInsightsProtocol.allCases.compactMap { kind in
            guard let entry = counts[kind] else {
                return nil
            }
            return TrafficInsightsShare(key: kind, requestCount: entry.0, bytes: entry.1)
        }
    }

    private static func statusShares(
        _ samples: [TrafficInsightsSample]
    )
        -> [TrafficInsightsShare<TrafficInsightsStatusClass>]
    {
        var counts: [TrafficInsightsStatusClass: (Int, Int64)] = [:]
        for sample in samples {
            let current = counts[sample.statusClass] ?? (0, 0)
            counts[sample.statusClass] = (current.0 + 1, current.1 + sample.totalBytes)
        }
        return TrafficInsightsStatusClass.allCases.compactMap { statusClass in
            guard let entry = counts[statusClass] else {
                return nil
            }
            return TrafficInsightsShare(key: statusClass, requestCount: entry.0, bytes: entry.1)
        }
    }

    private static func statusCodeShares(_ samples: [TrafficInsightsSample]) -> [TrafficInsightsShare<Int>] {
        var counts: [Int: (Int, Int64)] = [:]
        for sample in samples {
            guard let code = sample.statusCode else {
                continue
            }
            let current = counts[code] ?? (0, 0)
            counts[code] = (current.0 + 1, current.1 + sample.totalBytes)
        }
        return counts
            .map { TrafficInsightsShare(key: $0.key, requestCount: $0.value.0, bytes: $0.value.1) }
            .sorted { lhs, rhs in
                if lhs.requestCount != rhs.requestCount {
                    return lhs.requestCount > rhs.requestCount
                }
                return lhs.key < rhs.key
            }
    }

    private static func timingBreakdown(_ samples: [TrafficInsightsSample]) -> TrafficInsightsTimingBreakdown? {
        var count = 0
        var dns = 0.0
        var tcp = 0.0
        var tls = 0.0
        var ttfb = 0.0
        var transfer = 0.0
        for sample in samples {
            guard let timing = sample.timing, timing.totalDuration > 0, !sample.hasWebSocket else {
                continue
            }
            count += 1
            dns += timing.dnsLookup
            tcp += timing.tcpConnection
            tls += timing.tlsHandshake
            ttfb += timing.timeToFirstByte
            transfer += timing.contentTransfer
        }
        guard count > 0 else {
            return nil
        }
        let divisor = Double(count)
        return TrafficInsightsTimingBreakdown(
            sampleCount: count,
            dnsLookup: dns / divisor,
            tcpConnection: tcp / divisor,
            tlsHandshake: tls / divisor,
            timeToFirstByte: ttfb / divisor,
            contentTransfer: transfer / divisor
        )
    }

    private static func contentShares(
        _ samples: [TrafficInsightsSample]
    )
        -> [TrafficInsightsShare<TrafficInsightsContentCategory>]
    {
        var counts: [TrafficInsightsContentCategory: (Int, Int64)] = [:]
        for sample in samples where sample.response != nil && !sample.isTunneled {
            let category = sample.contentCategory
            let current = counts[category] ?? (0, 0)
            counts[category] = (current.0 + 1, current.1 + sample.receivedBytes)
        }
        return TrafficInsightsContentCategory.allCases.compactMap { category in
            guard let entry = counts[category] else {
                return nil
            }
            return TrafficInsightsShare(key: category, requestCount: entry.0, bytes: entry.1)
        }
    }

    private static func methodShares(_ samples: [TrafficInsightsSample]) -> [TrafficInsightsShare<String>] {
        var counts: [String: (Int, Int64)] = [:]
        for sample in samples {
            let method = sample.method.uppercased()
            let current = counts[method] ?? (0, 0)
            counts[method] = (current.0 + 1, current.1 + sample.totalBytes)
        }
        return counts
            .map { TrafficInsightsShare(key: $0.key, requestCount: $0.value.0, bytes: $0.value.1) }
            .sorted { lhs, rhs in
                if lhs.requestCount != rhs.requestCount {
                    return lhs.requestCount > rhs.requestCount
                }
                return lhs.key < rhs.key
            }
    }

    private static func rankedApps(_ samples: [TrafficInsightsSample], limit: Int) -> [TrafficInsightsRankedEntry] {
        ranked(samples, limit: limit) { sample in
            guard let app = sample.clientApp?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else {
                return nil
            }
            return app
        }
    }

    private static func rankedHosts(_ samples: [TrafficInsightsSample], limit: Int) -> [TrafficInsightsRankedEntry] {
        ranked(samples, limit: limit) { sample in
            sample.host.isEmpty ? nil : sample.host
        }
    }

    private static func ranked(
        _ samples: [TrafficInsightsSample],
        limit: Int,
        key: (TrafficInsightsSample) -> String?
    )
        -> [TrafficInsightsRankedEntry]
    {
        var groups: [String: MutableRank] = [:]
        for sample in samples {
            guard let name = key(sample) else {
                continue
            }
            var rank = groups[name] ?? MutableRank()
            rank.requestCount += 1
            rank.sentBytes += sample.sentBytes
            rank.receivedBytes += sample.receivedBytes
            if sample.statusClass.isError {
                rank.errorCount += 1
            }
            if let duration = sample.duration, duration > 0, sample.statusClass != .pending {
                rank.durations.append(duration)
            }
            groups[name] = rank
        }

        return groups
            .map { name, rank in
                TrafficInsightsRankedEntry(
                    name: name,
                    requestCount: rank.requestCount,
                    sentBytes: rank.sentBytes,
                    receivedBytes: rank.receivedBytes,
                    errorCount: rank.errorCount,
                    medianDuration: percentile(rank.durations.sorted(), fraction: 0.5)
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalBytes != rhs.totalBytes {
                    return lhs.totalBytes > rhs.totalBytes
                }
                if lhs.requestCount != rhs.requestCount {
                    return lhs.requestCount > rhs.requestCount
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func slowestRequests(
        _ samples: [TrafficInsightsSample],
        limit: Int
    )
        -> [TrafficInsightsTransactionRef]
    {
        samples
            .filter { $0.duration ?? 0 > 0 && $0.statusClass != .pending && !$0.hasWebSocket }
            .sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
            .prefix(limit)
            .map(reference)
    }

    private static func largestResponses(
        _ samples: [TrafficInsightsSample],
        limit: Int
    )
        -> [TrafficInsightsTransactionRef]
    {
        samples
            .filter { $0.receivedBytes > 0 }
            .sorted { $0.receivedBytes > $1.receivedBytes }
            .prefix(limit)
            .map(reference)
    }

    private static func reference(_ sample: TrafficInsightsSample) -> TrafficInsightsTransactionRef {
        TrafficInsightsTransactionRef(
            id: sample.id,
            method: sample.method,
            host: sample.host,
            path: sample.displayPath,
            statusCode: sample.statusCode,
            statusClass: sample.statusClass,
            duration: sample.duration,
            bytes: sample.receivedBytes,
            clientApp: sample.clientApp
        )
    }

    // MARK: - Findings

    private static func findings(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        var findings: [TrafficInsightsFinding] = []
        findings += errorHostFindings(samples, evidenceLimit: evidenceLimit)
        if let finding = failedRequestsFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += slowHostFindings(samples, evidenceLimit: evidenceLimit)
        if let finding = uncompressedTextFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = missingCacheHeadersFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += repeatedRequestFindings(samples, evidenceLimit: evidenceLimit)
        if let finding = plainHTTPFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = tunneledFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = largeUploadFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += slowTLSFindings(samples, evidenceLimit: evidenceLimit)
        if let finding = rulesAppliedFinding(samples, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }

        let kindOrder = Dictionary(
            uniqueKeysWithValues: TrafficInsightsFindingKind.allCases.enumerated().map { ($1, $0) }
        )
        return findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            let lhsOrder = kindOrder[lhs.kind] ?? 0
            let rhsOrder = kindOrder[rhs.kind] ?? 0
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.title < rhs.title
        }
    }

    private static func errorHostFindings(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        struct HostErrors {
            var completed = 0
            var serverErrors: [TrafficInsightsSample] = []
            var clientErrors: [TrafficInsightsSample] = []
        }
        var byHost: [String: HostErrors] = [:]
        for sample in samples where !sample.host.isEmpty && sample.statusClass != .pending {
            var entry = byHost[sample.host] ?? HostErrors()
            entry.completed += 1
            switch sample.statusClass {
            case .serverError:
                entry.serverErrors.append(sample)
            case .clientError:
                entry.clientErrors.append(sample)
            default:
                break
            }
            byHost[sample.host] = entry
        }

        var results: [TrafficInsightsFinding] = []
        let serverHosts = byHost
            .filter { !$0.value.serverErrors.isEmpty }
            .sorted { $0.value.serverErrors.count > $1.value.serverErrors.count }
            .prefix(3)
        for (host, entry) in serverHosts {
            let count = entry.serverErrors.count
            let rate = Double(count) / Double(max(entry.completed, 1))
            results.append(TrafficInsightsFinding(
                kind: .serverErrorHost,
                severity: count >= 3 || rate >= 0.1 ? .warning : .notice,
                title: TrafficInsightsText
                    .inflected(
                        "\(host): 5xx on \(count) of ^[\(entry.completed) request](inflect: true)"
                    ),
                detail: String(
                    localized: "Server-side failures. Compare failing and succeeding requests on this host.",
                    bundle: RockxyLocalization.bundle
                ),
                evidence: entry.serverErrors.prefix(evidenceLimit).map(reference),
                handoff: .focusHost(host)
            ))
        }

        let clientHosts = byHost
            .filter { entry in
                entry.value.completed >= hostSampleFloor
                    && Double(entry.value.clientErrors.count) / Double(entry.value.completed) >= 0.2
            }
            .sorted { $0.value.clientErrors.count > $1.value.clientErrors.count }
            .prefix(3)
        for (host, entry) in clientHosts {
            let count = entry.clientErrors.count
            results.append(TrafficInsightsFinding(
                kind: .clientErrorHost,
                severity: .notice,
                title: TrafficInsightsText
                    .inflected("\(host): 4xx on \(count) of ^[\(entry.completed) request](inflect: true)"),
                detail: String(
                    localized: "Usually expired credentials, a wrong path, or missing parameters.",
                    bundle: RockxyLocalization.bundle
                ),
                evidence: entry.clientErrors.prefix(evidenceLimit).map(reference),
                handoff: .focusHost(host)
            ))
        }
        return results
    }

    private static func failedRequestsFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let failed = samples.filter { $0.statusClass == .failed }
        guard !failed.isEmpty else {
            return nil
        }
        let tlsCount = failed.filter(\.isTLSFailure).count
        let detail = if tlsCount > 0 {
            String(
                localized: "\(tlsCount) failed in the TLS handshake: the client does not trust the Rockxy certificate or pins its own.",
                bundle: RockxyLocalization.bundle
            )
        } else {
            String(
                localized: "Connection closed, timed out, or upstream unreachable.",
                bundle: RockxyLocalization.bundle
            )
        }
        return TrafficInsightsFinding(
            kind: .failedRequests,
            severity: failed.count >= 5 ? .warning : .notice,
            title: TrafficInsightsText
                .inflected("^[\(failed.count) request](inflect: true) failed without a response"),
            detail: detail,
            evidence: failed.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(failed.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func slowHostFindings(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        var durationsByHost: [String: [(TimeInterval, TrafficInsightsSample)]] = [:]
        for sample in samples {
            guard !sample.host.isEmpty, !sample.hasWebSocket,
                  let duration = sample.duration, duration > 0,
                  sample.statusClass != .pending else
            {
                continue
            }
            durationsByHost[sample.host, default: []].append((duration, sample))
        }

        return durationsByHost
            .compactMap { host, entries -> (String, TimeInterval, [TrafficInsightsSample])? in
                guard entries.count >= hostSampleFloor else {
                    return nil
                }
                let sorted = entries.sorted { $0.0 < $1.0 }
                guard let tail = percentile(sorted.map(\.0), fraction: 0.95), tail >= slowHostTailThreshold else {
                    return nil
                }
                return (host, tail, sorted.suffix(evidenceLimit).reversed().map(\.1))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { host, tail, evidence in
                TrafficInsightsFinding(
                    kind: .slowHost,
                    severity: .notice,
                    title: String(
                        localized: "\(host): p95 \(DurationFormatter.format(seconds: tail))",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "1 in 20 requests to this host took at least this long. The Timing tab shows which phase dominates.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: evidence.map(reference),
                    handoff: .focusHost(host)
                )
            }
    }

    private static func uncompressedTextFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let textCategories: Set<TrafficInsightsContentCategory> = [.json, .html, .javascript, .css, .xml, .text]
        let uncompressed = samples.filter { sample in
            guard let response = sample.response, !sample.isTunneled,
                  Int64(response.body?.count ?? 0) >= uncompressedTextThreshold,
                  textCategories.contains(sample.contentCategory) else
            {
                return false
            }
            let encoding = sample.responseContentEncoding ?? ""
            return encoding.isEmpty || encoding == "identity"
        }
        guard !uncompressed.isEmpty else {
            return nil
        }
        let totalBytes = uncompressed.reduce(Int64(0)) { $0 + $1.receivedBytes }
        let sorted = uncompressed.sorted { $0.receivedBytes > $1.receivedBytes }
        return TrafficInsightsFinding(
            kind: .uncompressedText,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(uncompressed.count) text response](inflect: true) ≥ 100 KB without compression (\(SizeFormatter.format(bytes: Int(totalBytes))))"
                ),
            detail: String(
                localized: "No Content-Encoding. gzip or Brotli usually shrinks JSON, HTML, and scripts by 70 percent or more.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: sorted.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(sorted.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func missingCacheHeadersFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let staticCategories: Set<TrafficInsightsContentCategory> = [.image, .javascript, .css, .font]
        let uncached = samples.filter { sample in
            sample.method.uppercased() == "GET"
                && sample.statusClass == .success
                && staticCategories.contains(sample.contentCategory)
                && !sample.hasCacheHeaders
        }
        guard uncached.count >= hostSampleFloor else {
            return nil
        }
        let sorted = uncached.sorted { $0.receivedBytes > $1.receivedBytes }
        return TrafficInsightsFinding(
            kind: .missingCacheHeaders,
            severity: .info,
            title: TrafficInsightsText
                .inflected("^[\(uncached.count) static asset](inflect: true) without cache headers"),
            detail: String(
                localized: "No Cache-Control, ETag, Expires, or Last-Modified, so they download again on every visit.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: sorted.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(sorted.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func repeatedRequestFindings(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        var groups: [String: [TrafficInsightsSample]] = [:]
        for sample in samples where sample.method.uppercased() == "GET" && !sample.hasWebSocket && !sample.isTunneled {
            groups[sample.repeatKey, default: []].append(sample)
        }
        return groups
            .filter { $0.value.count >= repeatedRequestThreshold }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.key < rhs.key
            }
            .prefix(3)
            .compactMap { _, group in
                guard let first = group.first else {
                    return nil
                }
                let count = group.count
                let path = first.displayPath
                return TrafficInsightsFinding(
                    kind: .repeatedRequests,
                    severity: .info,
                    title: String(
                        localized: "GET \(path) repeated \(count)× on \(first.host)",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "Same URL fetched repeatedly: missing client cache, polling, or retries.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: group.prefix(evidenceLimit).map(reference),
                    handoff: .revealTransactions(group.prefix(evidenceLimit).map(\.id))
                )
            }
    }

    private static func plainHTTPFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let plain = samples.filter { $0.scheme == "http" && !$0.hasWebSocket && !$0.isTunneled }
        guard !plain.isEmpty else {
            return nil
        }
        let hosts = Set(plain.map(\.host).filter { !$0.isEmpty })
        let localOnly = hosts.allSatisfy(isLoopbackHost)
        return TrafficInsightsFinding(
            kind: .plainHTTP,
            severity: localOnly ? .info : .notice,
            title: TrafficInsightsText
                .inflected(
                    "^[\(plain.count) request](inflect: true) over plain HTTP (^[\(hosts.count) host](inflect: true))"
                ),
            detail: localOnly
                ? String(
                    localized: "Local addresses only — normal for development servers.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Headers, cookies, and bodies travel unencrypted.",
                    bundle: RockxyLocalization.bundle
                ),
            evidence: plain.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(plain.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func tunneledFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let tunneled = samples.filter(\.isTunneled)
        guard !tunneled.isEmpty else {
            return nil
        }
        let hosts = Set(tunneled.map(\.host).filter { !$0.isEmpty })
        return TrafficInsightsFinding(
            kind: .tunneledHosts,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(tunneled.count) connection](inflect: true) to ^[\(hosts.count) host](inflect: true) not decrypted"
                ),
            detail: String(
                localized: "Only the CONNECT is visible. Enable HTTPS Decryption for these hosts to inspect them.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: tunneled.prefix(evidenceLimit).map(reference),
            handoff: .openHTTPSDecryption
        )
    }

    private static func largeUploadFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let uploads = samples.filter { Int64($0.request.body?.count ?? 0) >= largeUploadThreshold }
        guard !uploads.isEmpty else {
            return nil
        }
        let sorted = uploads.sorted { ($0.request.body?.count ?? 0) > ($1.request.body?.count ?? 0) }
        let largest = Int(sorted.first?.request.body?.count ?? 0)
        return TrafficInsightsFinding(
            kind: .largeUploads,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(uploads.count) upload](inflect: true) over 5 MB (largest \(SizeFormatter.format(bytes: largest)))"
                ),
            detail: String(
                localized: "Large bodies dominate upload time on slow links.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: sorted.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(sorted.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func slowTLSFindings(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        var byHost: [String: [(TimeInterval, TrafficInsightsSample)]] = [:]
        for sample in samples {
            guard !sample.host.isEmpty, let timing = sample.timing,
                  timing.tlsHandshake >= slowTLSHandshakeThreshold else
            {
                continue
            }
            byHost[sample.host, default: []].append((timing.tlsHandshake, sample))
        }
        return byHost
            .filter { $0.value.count >= 3 }
            .map { host, entries -> (String, TimeInterval, [TrafficInsightsSample]) in
                let average = entries.reduce(0) { $0 + $1.0 } / Double(entries.count)
                let evidence = entries.sorted { $0.0 > $1.0 }.prefix(evidenceLimit).map(\.1)
                return (host, average, evidence)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map { host, average, evidence in
                TrafficInsightsFinding(
                    kind: .slowTLSHandshake,
                    severity: .info,
                    title: String(
                        localized: "\(host): TLS handshake avg \(DurationFormatter.format(seconds: average)) over \(evidence.count) connections",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "Repeated handshakes mean connections are not reused.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: evidence.map(reference),
                    handoff: .focusHost(host)
                )
            }
    }

    private static func rulesAppliedFinding(
        _ samples: [TrafficInsightsSample],
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let modified = samples.filter { $0.matchedRuleName != nil }
        guard !modified.isEmpty else {
            return nil
        }
        let ruleNames = Array(Set(modified.compactMap(\.matchedRuleName))).sorted()
        let summary = ruleNames.prefix(3).joined(separator: ", ")
        return TrafficInsightsFinding(
            kind: .rulesApplied,
            severity: .info,
            title: TrafficInsightsText
                .inflected("^[\(modified.count) request](inflect: true) changed by rules: \(summary)"),
            detail: String(
                localized: "Timing and payloads of these requests do not reflect the real server.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: modified.prefix(evidenceLimit).map(reference),
            handoff: .revealTransactions(modified.prefix(evidenceLimit).map(\.id))
        )
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost" || lowered == "::1" || lowered.hasPrefix("127.")
            || lowered.hasSuffix(".local") || lowered.hasSuffix(".localhost")
            || lowered.hasPrefix("10.") || lowered.hasPrefix("192.168.")
            || lowered.hasPrefix("0.0.0.0")
    }
}
