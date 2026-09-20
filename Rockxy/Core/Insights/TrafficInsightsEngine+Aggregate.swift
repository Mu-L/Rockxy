import Foundation

// Single-pass aggregation behind the Traffic Insights totals, breakdowns, rankings, and outliers.

extension TrafficInsightsEngine {
    /// Everything the report needs from one walk over the resolved samples. Each request is
    /// visited once and every accumulator is mutated in place, so a session with a hundred
    /// thousand requests costs one pass instead of one pass per card.
    struct Aggregate {
        // MARK: Lifecycle

        init(_ samples: [ResolvedSample], protocols: [TrafficInsightsProtocol], options: TrafficInsightsOptions) {
            let first = samples.first?.timestamp ?? Date()
            let last = samples.last?.timestamp ?? first
            let span = max(0, last.timeIntervalSince(first))
            binWidth = TrafficInsightsEngine.binWidth(forSpan: span, maximumBinCount: options.maximumBinCount)
            binOrigin = (first.timeIntervalSinceReferenceDate / binWidth).rounded(.down) * binWidth
            let binCount = Int(((last.timeIntervalSinceReferenceDate - binOrigin) / binWidth).rounded(.down)) + 1
            buckets = [MutableBin](repeating: MutableBin(), count: max(1, binCount))
            durations.reserveCapacity(samples.count)

            for (index, sample) in samples.enumerated() {
                add(sample, at: index, protocol: protocols[index])
            }
            durations.sort()
        }

        // MARK: Internal

        let binWidth: TimeInterval

        func totals(sampleCount: Int, first: ResolvedSample?, last: ResolvedSample?) -> TrafficInsightsTotals {
            let peakCount = buckets.map(\.requestCount).max() ?? 0
            return TrafficInsightsTotals(
                requestCount: sampleCount,
                completedCount: completed,
                inFlightCount: inFlight,
                errorCount: errors,
                sentBytes: sent,
                receivedBytes: received,
                hostCount: hosts.count,
                appCount: apps.count,
                medianDuration: TrafficInsightsEngine.percentile(durations, fraction: 0.5),
                p95Duration: TrafficInsightsEngine.percentile(durations, fraction: 0.95),
                firstTimestamp: first?.timestamp,
                lastTimestamp: last?.timestamp,
                peakRequestsPerSecond: Double(peakCount) / max(binWidth, 1)
            )
        }

        func bins() -> [TrafficInsightsTimelineBin] {
            buckets.enumerated().map { index, bucket in
                let sorted = bucket.durations.sorted()
                return TrafficInsightsTimelineBin(
                    start: Date(timeIntervalSinceReferenceDate: binOrigin + Double(index) * binWidth),
                    sentBytes: bucket.sentBytes,
                    receivedBytes: bucket.receivedBytes,
                    requestCount: bucket.requestCount,
                    countsByStatusClass: bucket.counts,
                    medianDuration: TrafficInsightsEngine.percentile(sorted, fraction: 0.5),
                    tailDuration: TrafficInsightsEngine.percentile(sorted, fraction: 0.95),
                    transactionIDs: bucket.transactionIDs
                )
            }
        }

        func protocolShares() -> [TrafficInsightsShare<TrafficInsightsProtocol>] {
            TrafficInsightsProtocol.allCases.compactMap { kind in
                protocolCounts[kind].map { TrafficInsightsShare(key: kind, requestCount: $0.count, bytes: $0.bytes) }
            }
        }

        func statusShares() -> [TrafficInsightsShare<TrafficInsightsStatusClass>] {
            TrafficInsightsStatusClass.allCases.compactMap { statusClass in
                statusCounts[statusClass].map {
                    TrafficInsightsShare(key: statusClass, requestCount: $0.count, bytes: $0.bytes)
                }
            }
        }

        func statusCodeShares() -> [TrafficInsightsShare<Int>] {
            statusCodeCounts
                .map { TrafficInsightsShare(key: $0.key, requestCount: $0.value.count, bytes: $0.value.bytes) }
                .sorted { lhs, rhs in
                    if lhs.requestCount != rhs.requestCount {
                        return lhs.requestCount > rhs.requestCount
                    }
                    return lhs.key < rhs.key
                }
        }

        func timingBreakdown() -> TrafficInsightsTimingBreakdown? {
            guard timedCount > 0 else {
                return nil
            }
            let divisor = Double(timedCount)
            return TrafficInsightsTimingBreakdown(
                sampleCount: timedCount,
                dnsLookup: dns / divisor,
                tcpConnection: tcp / divisor,
                tlsHandshake: tls / divisor,
                timeToFirstByte: ttfb / divisor,
                contentTransfer: transfer / divisor
            )
        }

        func contentShares() -> [TrafficInsightsShare<TrafficInsightsContentCategory>] {
            TrafficInsightsContentCategory.allCases.compactMap { category in
                contentCounts[category].map {
                    TrafficInsightsShare(key: category, requestCount: $0.count, bytes: $0.bytes)
                }
            }
        }

        func methodShares() -> [TrafficInsightsShare<String>] {
            methodCounts
                .map { TrafficInsightsShare(key: $0.key, requestCount: $0.value.count, bytes: $0.value.bytes) }
                .sorted { lhs, rhs in
                    if lhs.requestCount != rhs.requestCount {
                        return lhs.requestCount > rhs.requestCount
                    }
                    return lhs.key < rhs.key
                }
        }

        func rankedApps(limit: Int) -> [TrafficInsightsRankedEntry] {
            Self.ranked(appRanks, limit: limit)
        }

        func rankedHosts(limit: Int) -> [TrafficInsightsRankedEntry] {
            Self.ranked(hostRanks, limit: limit)
        }

        func slowestRequests(_ samples: [ResolvedSample], limit: Int) -> [TrafficInsightsTransactionRef] {
            TrafficInsightsEngine.topK(timedIndices, limit: limit) { lhs, rhs in
                (samples[lhs].timedDuration ?? 0) > (samples[rhs].timedDuration ?? 0)
            }
            .map { TrafficInsightsEngine.reference(samples[$0]) }
        }

        func largestResponses(_ samples: [ResolvedSample], limit: Int) -> [TrafficInsightsTransactionRef] {
            TrafficInsightsEngine.topK(bodyIndices, limit: limit) { lhs, rhs in
                samples[lhs].receivedBytes > samples[rhs].receivedBytes
            }
            .map { TrafficInsightsEngine.reference(samples[$0]) }
        }

        // MARK: Private

        private struct Share {
            var count = 0
            var bytes: Int64 = 0

            mutating func add(_ bytes: Int64) {
                count += 1
                self.bytes += bytes
            }
        }

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

            mutating func add(_ sample: ResolvedSample) {
                requestCount += 1
                sentBytes += sample.sentBytes
                receivedBytes += sample.receivedBytes
                if sample.statusClass.isError {
                    errorCount += 1
                }
                if let duration = sample.timedDuration {
                    durations.append(duration)
                }
            }
        }

        private let binOrigin: TimeInterval
        private var buckets: [MutableBin]

        private var completed = 0
        private var inFlight = 0
        private var errors = 0
        private var sent: Int64 = 0
        private var received: Int64 = 0
        private var hosts = Set<String>()
        private var apps = Set<String>()
        private var durations: [TimeInterval] = []

        private var protocolCounts: [TrafficInsightsProtocol: Share] = [:]
        private var statusCounts: [TrafficInsightsStatusClass: Share] = [:]
        private var statusCodeCounts: [Int: Share] = [:]
        private var contentCounts: [TrafficInsightsContentCategory: Share] = [:]
        private var methodCounts: [String: Share] = [:]

        private var timedCount = 0
        private var dns = 0.0
        private var tcp = 0.0
        private var tls = 0.0
        private var ttfb = 0.0
        private var transfer = 0.0

        private var appRanks: [String: MutableRank] = [:]
        private var hostRanks: [String: MutableRank] = [:]
        /// Indices of samples eligible for the slowest and largest lists.
        private var timedIndices: [Int] = []
        private var bodyIndices: [Int] = []

        private static func ranked(_ groups: [String: MutableRank], limit: Int) -> [TrafficInsightsRankedEntry] {
            groups
                .map { name, rank in
                    TrafficInsightsRankedEntry(
                        name: name,
                        requestCount: rank.requestCount,
                        sentBytes: rank.sentBytes,
                        receivedBytes: rank.receivedBytes,
                        errorCount: rank.errorCount,
                        medianDuration: TrafficInsightsEngine.percentile(rank.durations.sorted(), fraction: 0.5)
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

        private mutating func add(_ sample: ResolvedSample, at index: Int, protocol kind: TrafficInsightsProtocol) {
            let statusClass = sample.statusClass
            let totalBytes = sample.totalBytes

            // Totals.
            if statusClass == .pending {
                inFlight += 1
            } else {
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
            if let duration = sample.timedDuration {
                durations.append(duration)
                if !sample.hasWebSocket {
                    timedIndices.append(index)
                }
            }
            if sample.receivedBytes > 0 {
                bodyIndices.append(index)
            }

            // Timeline bin.
            let offset = sample.timestamp.timeIntervalSinceReferenceDate - binOrigin
            let bin = min(max(Int((offset / binWidth).rounded(.down)), 0), buckets.count - 1)
            buckets[bin].sentBytes += sample.sentBytes
            buckets[bin].receivedBytes += sample.receivedBytes
            buckets[bin].requestCount += 1
            buckets[bin].counts[statusClass, default: 0] += 1
            buckets[bin].transactionIDs.append(sample.id)
            if let duration = sample.timedDuration {
                buckets[bin].durations.append(duration)
            }

            // Breakdowns.
            protocolCounts[kind, default: Share()].add(totalBytes)
            statusCounts[statusClass, default: Share()].add(totalBytes)
            if let code = sample.response?.statusCode {
                statusCodeCounts[code, default: Share()].add(totalBytes)
            }
            if sample.response != nil, !sample.isTunneled {
                contentCounts[sample.contentCategory, default: Share()].add(sample.receivedBytes)
            }
            methodCounts[sample.method, default: Share()].add(totalBytes)
            if let timing = sample.timing, timing.totalDuration > 0, !sample.hasWebSocket {
                timedCount += 1
                dns += timing.dnsLookup
                tcp += timing.tcpConnection
                tls += timing.tlsHandshake
                ttfb += timing.timeToFirstByte
                transfer += timing.contentTransfer
            }

            // Rankings. Mutating through the defaulted subscript keeps each duration array in
            // place; a copy-out/copy-in would clone it on every request of a busy host.
            if let app = sample.clientApp?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty {
                appRanks[app, default: MutableRank()].add(sample)
            }
            if !sample.host.isEmpty {
                hostRanks[sample.host, default: MutableRank()].add(sample)
            }
        }
    }
}
