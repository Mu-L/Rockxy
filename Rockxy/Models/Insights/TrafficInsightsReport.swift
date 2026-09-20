import Foundation

// Defines the immutable report that the Insights report view renders.

// MARK: - TrafficInsightsScope

/// Which transactions the report reads from the active Traffic Tab.
enum TrafficInsightsScope: String, CaseIterable, Sendable, Hashable {
    /// Every transaction captured into the active Traffic Tab.
    case allTraffic
    /// Only transactions currently visible through the Traffic Tab's filters, focus, and noise controls.
    case visibleTraffic

    // MARK: Internal

    var displayName: String {
        switch self {
        case .allTraffic: String(localized: "All Traffic", bundle: RockxyLocalization.bundle)
        case .visibleTraffic: String(localized: "Visible Traffic", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - TrafficInsightsTimeWindow

/// Trailing time window applied before aggregation.
enum TrafficInsightsTimeWindow: String, CaseIterable, Sendable, Hashable {
    case entireSession
    case lastMinute
    case lastFiveMinutes
    case lastFifteenMinutes
    case lastHour

    // MARK: Internal

    var displayName: String {
        switch self {
        case .entireSession: String(localized: "Entire Session", bundle: RockxyLocalization.bundle)
        case .lastMinute: String(localized: "Last Minute", bundle: RockxyLocalization.bundle)
        case .lastFiveMinutes: String(localized: "Last 5 Minutes", bundle: RockxyLocalization.bundle)
        case .lastFifteenMinutes: String(localized: "Last 15 Minutes", bundle: RockxyLocalization.bundle)
        case .lastHour: String(localized: "Last Hour", bundle: RockxyLocalization.bundle)
        }
    }

    /// Duration of the trailing window, or `nil` for the whole session.
    var duration: TimeInterval? {
        switch self {
        case .entireSession: nil
        case .lastMinute: 60
        case .lastFiveMinutes: 5 * 60
        case .lastFifteenMinutes: 15 * 60
        case .lastHour: 60 * 60
        }
    }
}

// MARK: - TrafficInsightsTimelineMetric

/// The series family shown in the traffic-over-time chart.
enum TrafficInsightsTimelineMetric: String, CaseIterable, Sendable, Hashable {
    case bytes
    case requests
    case latency

    // MARK: Internal

    var displayName: String {
        switch self {
        case .bytes: String(localized: "Bytes", bundle: RockxyLocalization.bundle)
        case .requests: String(localized: "Requests", bundle: RockxyLocalization.bundle)
        case .latency: String(localized: "Latency", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - TrafficInsightsShareBasis

/// Whether a share breakdown is weighted by request count or transferred bytes.
enum TrafficInsightsShareBasis: String, CaseIterable, Sendable, Hashable {
    case requests
    case bytes

    // MARK: Internal

    var displayName: String {
        switch self {
        case .requests: String(localized: "Requests", bundle: RockxyLocalization.bundle)
        case .bytes: String(localized: "Bytes", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - TrafficInsightsTimelineBin

/// One aggregated time bucket. Bins are contiguous, so an empty bin still exists with zeros.
struct TrafficInsightsTimelineBin: Sendable, Equatable, Identifiable {
    let start: Date
    let sentBytes: Int64
    let receivedBytes: Int64
    let requestCount: Int
    let countsByStatusClass: [TrafficInsightsStatusClass: Int]
    let medianDuration: TimeInterval?
    let tailDuration: TimeInterval?
    /// Transactions that started in this bin, in capture order, so a click on the chart can
    /// select exactly these rows in the request list.
    let transactionIDs: [UUID]

    var id: Date {
        start
    }

    var totalBytes: Int64 {
        sentBytes + receivedBytes
    }

    var errorCount: Int {
        countsByStatusClass.reduce(into: 0) { partial, entry in
            if entry.key.isError {
                partial += entry.value
            }
        }
    }
}

// MARK: - TrafficInsightsShare

/// One slice of a share breakdown (protocols, status classes, content, methods).
struct TrafficInsightsShare<Key: Hashable & Sendable>: Sendable, Equatable, Identifiable {
    let key: Key
    let requestCount: Int
    let bytes: Int64

    var id: Key {
        key
    }
}

// MARK: - TrafficInsightsTimingBreakdown

/// Average time per request spent in each connection phase, over requests that carry timing.
struct TrafficInsightsTimingBreakdown: Sendable, Equatable {
    let sampleCount: Int
    let dnsLookup: TimeInterval
    let tcpConnection: TimeInterval
    let tlsHandshake: TimeInterval
    let timeToFirstByte: TimeInterval
    let contentTransfer: TimeInterval

    var total: TimeInterval {
        dnsLookup + tcpConnection + tlsHandshake + timeToFirstByte + contentTransfer
    }
}

// MARK: - TrafficInsightsRankedEntry

/// One row of a Top Apps or Top Hosts list.
struct TrafficInsightsRankedEntry: Sendable, Equatable, Identifiable {
    let name: String
    let requestCount: Int
    let sentBytes: Int64
    let receivedBytes: Int64
    let errorCount: Int
    let medianDuration: TimeInterval?

    var id: String {
        name
    }

    var totalBytes: Int64 {
        sentBytes + receivedBytes
    }

    var errorRate: Double {
        requestCount == 0 ? 0 : Double(errorCount) / Double(requestCount)
    }
}

// MARK: - TrafficInsightsTransactionRef

/// A transaction the report points back to (slowest request, largest response, finding evidence).
struct TrafficInsightsTransactionRef: Sendable, Equatable, Identifiable {
    let id: UUID
    let url: String
    let method: String
    let host: String
    let path: String
    let statusCode: Int?
    let statusClass: TrafficInsightsStatusClass
    let duration: TimeInterval?
    let bytes: Int64
    let clientApp: String?
}

// MARK: - TrafficInsightsFindingSeverity

enum TrafficInsightsFindingSeverity: Int, Sendable, Comparable {
    case info = 0
    case notice = 1
    case warning = 2

    // MARK: Internal

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - TrafficInsightsFindingKind

/// Stable identity for a deterministic finding rule so the UI and tests can address it.
enum TrafficInsightsFindingKind: String, Sendable, CaseIterable {
    case serverErrorHost
    case clientErrorHost
    case failedRequests
    case slowHost
    case uncompressedText
    case missingCacheHeaders
    case repeatedRequests
    case plainHTTP
    case tunneledHosts
    case largeUploads
    case slowTLSHandshake
    case rulesApplied
}

// MARK: - TrafficInsightsFindingHandoff

/// The main-window action a finding offers. Findings never mutate traffic; they only focus it.
enum TrafficInsightsFindingHandoff: Sendable, Equatable {
    case focusHost(String)
    case focusApp(String)
    case revealTransactions([UUID])
    case openHTTPSDecryption
    case none
}

// MARK: - TrafficInsightsFinding

struct TrafficInsightsFinding: Sendable, Equatable, Identifiable {
    let kind: TrafficInsightsFindingKind
    let severity: TrafficInsightsFindingSeverity
    let title: String
    let detail: String
    let evidence: [TrafficInsightsTransactionRef]
    let handoff: TrafficInsightsFindingHandoff

    var id: String {
        "\(kind.rawValue)|\(title)"
    }
}

// MARK: - TrafficInsightsTotals

struct TrafficInsightsTotals: Sendable, Equatable {
    let requestCount: Int
    let completedCount: Int
    let inFlightCount: Int
    let errorCount: Int
    let sentBytes: Int64
    let receivedBytes: Int64
    let hostCount: Int
    let appCount: Int
    let medianDuration: TimeInterval?
    let p95Duration: TimeInterval?
    let firstTimestamp: Date?
    let lastTimestamp: Date?
    /// Highest requests-per-second observed in any timeline bin.
    let peakRequestsPerSecond: Double

    var totalBytes: Int64 {
        sentBytes + receivedBytes
    }

    /// Average requests per second over the captured span (0 for a single request).
    var averageRequestsPerSecond: Double {
        span > 0 ? Double(requestCount) / span : 0
    }

    var errorRate: Double {
        completedCount == 0 ? 0 : Double(errorCount) / Double(completedCount)
    }

    var span: TimeInterval {
        guard let firstTimestamp, let lastTimestamp else {
            return 0
        }
        return max(0, lastTimestamp.timeIntervalSince(firstTimestamp))
    }
}

// MARK: - TrafficInsightsReport

/// Complete, immutable result of one engine run.
struct TrafficInsightsReport: Sendable, Equatable {
    static let empty = TrafficInsightsReport(
        generatedAt: .distantPast,
        scope: .allTraffic,
        timeWindow: .entireSession,
        totals: TrafficInsightsTotals(
            requestCount: 0,
            completedCount: 0,
            inFlightCount: 0,
            errorCount: 0,
            sentBytes: 0,
            receivedBytes: 0,
            hostCount: 0,
            appCount: 0,
            medianDuration: nil,
            p95Duration: nil,
            firstTimestamp: nil,
            lastTimestamp: nil,
            peakRequestsPerSecond: 0
        ),
        binWidth: 1,
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

    let generatedAt: Date
    let scope: TrafficInsightsScope
    let timeWindow: TrafficInsightsTimeWindow
    let totals: TrafficInsightsTotals
    let binWidth: TimeInterval
    let bins: [TrafficInsightsTimelineBin]
    let protocols: [TrafficInsightsShare<TrafficInsightsProtocol>]
    let statusClasses: [TrafficInsightsShare<TrafficInsightsStatusClass>]
    /// Exact status codes by descending count, for the outcome tooltips and export.
    let statusCodes: [TrafficInsightsShare<Int>]
    let timing: TrafficInsightsTimingBreakdown?
    let contentCategories: [TrafficInsightsShare<TrafficInsightsContentCategory>]
    let methods: [TrafficInsightsShare<String>]
    let topApps: [TrafficInsightsRankedEntry]
    let topHosts: [TrafficInsightsRankedEntry]
    let slowestRequests: [TrafficInsightsTransactionRef]
    let largestResponses: [TrafficInsightsTransactionRef]
    let findings: [TrafficInsightsFinding]

    var isEmpty: Bool {
        totals.requestCount == 0
    }
}
