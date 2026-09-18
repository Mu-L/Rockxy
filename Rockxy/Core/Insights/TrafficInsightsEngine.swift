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
    /// Uncached samples per parallel classification chunk; smaller batches classify inline.
    static let parallelClassificationChunkSize = 512

    /// Builds the report, or returns `nil` when `isCancelled` turns true between passes so a
    /// superseded live rebuild stops burning CPU instead of finishing a result nobody applies.
    static func buildReport(
        samples: [TrafficInsightsSample],
        options: TrafficInsightsOptions = TrafficInsightsOptions(),
        cache: TrafficInsightsProtocolCache = .empty,
        generatedAt: Date = Date(),
        isCancelled: () -> Bool
    )
        -> Output?
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
        guard !isCancelled() else {
            return nil
        }

        // Every derived field is resolved exactly once; the passes below only read them.
        let resolved = windowed.map(ResolvedSample.init)
        guard !isCancelled() else {
            return nil
        }

        let protocols = classifyProtocols(windowed, cache: &cache, isCancelled: isCancelled)
        guard let protocols else {
            return nil
        }

        // One pass feeds every headline number, breakdown, ranking, and outlier list.
        let aggregate = Aggregate(resolved, protocols: protocols, options: options)
        guard !isCancelled() else {
            return nil
        }
        let findings = findings(resolved, evidenceLimit: options.evidenceLimit, isCancelled: isCancelled)
        guard let findings else {
            return nil
        }

        let report = TrafficInsightsReport(
            generatedAt: generatedAt,
            scope: options.scope,
            timeWindow: options.timeWindow,
            totals: aggregate.totals(sampleCount: resolved.count, first: resolved.first, last: resolved.last),
            binWidth: aggregate.binWidth,
            bins: aggregate.bins(),
            protocols: aggregate.protocolShares(),
            statusClasses: aggregate.statusShares(),
            statusCodes: aggregate.statusCodeShares(),
            timing: aggregate.timingBreakdown(),
            contentCategories: aggregate.contentShares(),
            methods: aggregate.methodShares(),
            topApps: aggregate.rankedApps(limit: options.rankedListLimit),
            topHosts: aggregate.rankedHosts(limit: options.rankedListLimit),
            slowestRequests: aggregate.slowestRequests(resolved, limit: options.outlierListLimit),
            largestResponses: aggregate.largestResponses(resolved, limit: options.outlierListLimit),
            findings: findings
        )
        return Output(report: report, cache: cache)
    }

    static func buildReport(
        samples: [TrafficInsightsSample],
        options: TrafficInsightsOptions = TrafficInsightsOptions(),
        cache: TrafficInsightsProtocolCache = .empty,
        generatedAt: Date = Date()
    )
        -> Output
    {
        // Never cancelled, so the optional build always yields a value.
        buildReport(samples: samples, options: options, cache: cache, generatedAt: generatedAt) { false }
            ?? Output(report: .empty, cache: cache)
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

    /// Protocol per sample in input order. Uncached samples are classified in parallel because
    /// body scanning dominates a cold build of a large imported session.
    private static func classifyProtocols(
        _ samples: [TrafficInsightsSample],
        cache: inout TrafficInsightsProtocolCache,
        isCancelled: () -> Bool
    )
        -> [TrafficInsightsProtocol]?
    {
        var kinds = [TrafficInsightsProtocol](repeating: .https, count: samples.count)
        var uncachedIndices: [Int] = []
        for (index, sample) in samples.enumerated() {
            if let cached = cache.entry(for: sample) {
                kinds[index] = cached.kind
            } else {
                uncachedIndices.append(index)
            }
        }
        guard !uncachedIndices.isEmpty else {
            return kinds
        }

        let classified = classifyInParallel(samples, indices: uncachedIndices, isCancelled: isCancelled)
        guard let classified else {
            return nil
        }
        for (slot, index) in uncachedIndices.enumerated() {
            kinds[index] = classified[slot]
            cache.store(classified[slot], for: samples[index])
        }
        return kinds
    }

    private static func classifyInParallel(
        _ samples: [TrafficInsightsSample],
        indices: [Int],
        isCancelled: () -> Bool
    )
        -> [TrafficInsightsProtocol]?
    {
        let chunkSize = parallelClassificationChunkSize
        guard indices.count > chunkSize else {
            var kinds: [TrafficInsightsProtocol] = []
            kinds.reserveCapacity(indices.count)
            for (offset, index) in indices.enumerated() {
                if offset % 256 == 0, isCancelled() {
                    return nil
                }
                kinds.append(classifyProtocol(samples[index]))
            }
            return kinds
        }

        // Worker threads have no task context, so cancellation is checked once the parallel
        // pass returns; each chunk is bounded so that latency stays small.
        let chunkCount = (indices.count + chunkSize - 1) / chunkSize
        let results = ProtocolResultBuffer(count: indices.count)
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let start = chunk * chunkSize
            let end = min(start + chunkSize, indices.count)
            for slot in start ..< end {
                results.storage[slot] = classifyProtocol(samples[indices[slot]])
            }
        }
        guard !isCancelled() else {
            return nil
        }
        return Array(results.storage)
    }

    /// Fixed-size slots written by disjoint index ranges from parallel chunks; no two chunks
    /// touch the same slot, so the buffer needs no lock.
    private final class ProtocolResultBuffer: @unchecked Sendable {
        let storage: UnsafeMutableBufferPointer<TrafficInsightsProtocol>

        init(count: Int) {
            storage = .allocate(capacity: count)
            storage.initialize(repeating: .https)
        }

        deinit {
            storage.deallocate()
        }
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

    /// One sample plus every derived field the passes read. Resolved once per build so URL
    /// parsing, header scans, and status classification never repeat across passes, and so
    /// the passes can group by index instead of copying samples around.
    struct ResolvedSample {
        // MARK: Lifecycle

        init(_ sample: TrafficInsightsSample) {
            self.sample = sample
            host = sample.host
            scheme = sample.scheme
            method = sample.method.uppercased()
            statusClass = sample.statusClass
            sentBytes = sample.sentBytes
            receivedBytes = sample.receivedBytes
            if let duration = sample.duration, duration > 0, statusClass != .pending {
                timedDuration = duration
            } else {
                timedDuration = nil
            }
            contentCategory = sample.response == nil ? .none : sample.contentCategory
        }

        // MARK: Internal

        let sample: TrafficInsightsSample
        let host: String
        let scheme: String
        /// Uppercased so method grouping and GET checks agree regardless of client casing.
        let method: String
        let statusClass: TrafficInsightsStatusClass
        let sentBytes: Int64
        let receivedBytes: Int64
        /// Duration that counts toward latency statistics: positive and not still in flight.
        let timedDuration: TimeInterval?
        let contentCategory: TrafficInsightsContentCategory

        var id: UUID { sample.id }
        var timestamp: Date { sample.timestamp }
        var request: HTTPRequestData { sample.request }
        var response: HTTPResponseData? { sample.response }
        var clientApp: String? { sample.clientApp }
        var timing: TimingInfo? { sample.timing }
        var hasWebSocket: Bool { sample.hasWebSocket }
        var isTunneled: Bool { sample.isTunneled }
        var isTLSFailure: Bool { sample.isTLSFailure }
        var matchedRuleName: String? { sample.matchedRuleName }
        var totalBytes: Int64 { sentBytes + receivedBytes }
    }

    /// The first `limit` elements of `items` in `areInIncreasingOrder` order, with ties kept in
    /// input order exactly like a stable sort followed by `prefix`, but without sorting or
    /// copying the whole array.
    static func topK<T>(
        _ items: [T],
        limit: Int,
        areInIncreasingOrder: (T, T) -> Bool
    )
        -> [T]
    {
        guard limit > 0 else {
            return []
        }
        var best: [T] = []
        best.reserveCapacity(limit + 1)
        for item in items {
            if best.count >= limit, let last = best.last, !areInIncreasingOrder(item, last) {
                continue
            }
            let slot = best.firstIndex { areInIncreasingOrder(item, $0) } ?? best.count
            best.insert(item, at: slot)
            if best.count > limit {
                best.removeLast()
            }
        }
        return best
    }

    static func reference(_ sample: ResolvedSample) -> TrafficInsightsTransactionRef {
        TrafficInsightsTransactionRef(
            id: sample.id,
            method: sample.sample.method,
            host: sample.host,
            path: sample.sample.displayPath,
            statusCode: sample.response?.statusCode,
            statusClass: sample.statusClass,
            duration: sample.sample.duration,
            bytes: sample.receivedBytes,
            clientApp: sample.clientApp
        )
    }
}
