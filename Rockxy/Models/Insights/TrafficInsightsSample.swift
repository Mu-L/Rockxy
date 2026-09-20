import Foundation

// Defines the Sendable snapshot the Traffic Insights engine reads instead of live transactions.

// MARK: - TrafficInsightsProtocol

/// Protocol families reported by Traffic Insights. The order is the fixed legend order and each
/// case keeps its own color no matter which cases are present in a session.
enum TrafficInsightsProtocol: String, CaseIterable, Sendable, Hashable {
    case https
    case http
    case tunneled
    case webSocket
    case graphQL
    case grpc
    case aiAPI
    case web3RPC

    // MARK: Internal

    var displayName: String {
        switch self {
        case .tunneled: String(localized: "Tunneled", bundle: RockxyLocalization.bundle)
        case .aiAPI: String(localized: "AI API", bundle: RockxyLocalization.bundle)
        // Protocol names render verbatim.
        case .https: "HTTPS"
        case .http: "HTTP"
        case .webSocket: "WebSocket"
        case .graphQL: "GraphQL"
        case .grpc: "gRPC"
        case .web3RPC: "Web3 RPC"
        }
    }

    /// The request-list pill that shows exactly this family, or `nil` when the list has no
    /// equivalent filter (tunnels are only visible as CONNECT rows).
    var drillDown: TrafficInsightsDrillDown? {
        switch self {
        case .https: .protocolFilter(.https)
        case .http: .protocolFilter(.http)
        case .webSocket: .protocolFilter(.websocket)
        case .graphQL: .protocolFilter(.graphql)
        case .grpc: .protocolFilter(.grpc)
        case .aiAPI: .protocolFilter(.ai)
        case .web3RPC: .protocolFilter(.web3RPC)
        case .tunneled: nil
        }
    }

    /// Short explanation used by accessibility labels and the export so a share is never
    /// reduced to a bare protocol name.
    var detailDescription: String {
        switch self {
        case .https: String(localized: "Decrypted HTTPS requests", bundle: RockxyLocalization.bundle)
        case .http: String(localized: "Plain HTTP requests", bundle: RockxyLocalization.bundle)
        case .tunneled: String(
                localized: "Encrypted tunnels that were not decrypted",
                bundle: RockxyLocalization.bundle
            )
        case .webSocket: String(localized: "WebSocket connections and frames", bundle: RockxyLocalization.bundle)
        case .graphQL: String(localized: "GraphQL operations", bundle: RockxyLocalization.bundle)
        case .grpc: String(localized: "gRPC calls", bundle: RockxyLocalization.bundle)
        case .aiAPI: String(localized: "Recognized AI model API traffic", bundle: RockxyLocalization.bundle)
        case .web3RPC: String(localized: "Web3 JSON-RPC calls", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - TrafficInsightsStatusClass

/// Outcome buckets for the status breakdown and the per-bin request chart.
enum TrafficInsightsStatusClass: String, CaseIterable, Sendable, Hashable {
    case success
    case redirect
    case clientError
    case serverError
    case failed
    case blocked
    case pending
    case other

    // MARK: Internal

    var displayName: String {
        switch self {
        case .success: String(localized: "Success (2xx)", bundle: RockxyLocalization.bundle)
        case .redirect: String(localized: "Redirect (3xx)", bundle: RockxyLocalization.bundle)
        case .clientError: String(localized: "Client Error (4xx)", bundle: RockxyLocalization.bundle)
        case .serverError: String(localized: "Server Error (5xx)", bundle: RockxyLocalization.bundle)
        case .failed: String(localized: "Failed", bundle: RockxyLocalization.bundle)
        case .blocked: String(localized: "Blocked", bundle: RockxyLocalization.bundle)
        case .pending: String(localized: "In Flight", bundle: RockxyLocalization.bundle)
        case .other: String(localized: "Other", bundle: RockxyLocalization.bundle)
        }
    }

    /// Compact label for chart legends where the full name would wrap.
    var shortDisplayName: String {
        switch self {
        case .success: "2xx"
        case .redirect: "3xx"
        case .clientError: "4xx"
        case .serverError: "5xx"
        case .failed: String(localized: "Failed", bundle: RockxyLocalization.bundle)
        case .blocked: String(localized: "Blocked", bundle: RockxyLocalization.bundle)
        case .pending: String(localized: "In Flight", bundle: RockxyLocalization.bundle)
        case .other: String(localized: "Other", bundle: RockxyLocalization.bundle)
        }
    }

    /// The status pill or Signal that narrows the request list to this outcome.
    var drillDown: TrafficInsightsDrillDown? {
        switch self {
        case .success: .protocolFilter(.status2xx)
        case .redirect: .protocolFilter(.status3xx)
        case .clientError: .protocolFilter(.status4xx)
        case .serverError: .protocolFilter(.status5xx)
        case .failed: .trafficSignal(.errors)
        case .blocked,
             .pending,
             .other: nil
        }
    }

    /// Whether the class counts toward the headline error rate.
    var isError: Bool {
        switch self {
        case .clientError,
             .serverError,
             .failed:
            true
        case .success,
             .redirect,
             .blocked,
             .pending,
             .other:
            false
        }
    }

    static func classify(statusCode: Int?, state: TransactionState, isTLSFailure: Bool) -> Self {
        if isTLSFailure {
            return .failed
        }
        switch state {
        case .failed:
            return .failed
        case .blocked:
            return .blocked
        case .pending,
             .active:
            if statusCode == nil {
                return .pending
            }
        case .completed:
            break
        }
        guard let statusCode else {
            return state == .completed ? .other : .pending
        }
        switch statusCode {
        case 200 ..< 300: return .success
        case 300 ..< 400: return .redirect
        case 400 ..< 500: return .clientError
        case 500 ..< 600: return .serverError
        default: return .other
        }
    }
}

// MARK: - TrafficInsightsContentCategory

/// Response payload categories for the content breakdown. Derived from the normalized
/// `ContentType` plus the raw header for script, style, and font media types.
enum TrafficInsightsContentCategory: String, CaseIterable, Sendable, Hashable {
    case json
    case html
    case image
    case javascript
    case css
    case font
    case xml
    case text
    case form
    case protobuf
    case binary
    case none

    // MARK: Internal

    var displayName: String {
        switch self {
        case .image: String(localized: "Image", bundle: RockxyLocalization.bundle)
        case .font: String(localized: "Font", bundle: RockxyLocalization.bundle)
        case .text: String(localized: "Text", bundle: RockxyLocalization.bundle)
        case .form: String(localized: "Form", bundle: RockxyLocalization.bundle)
        case .binary: String(localized: "Binary / Other", bundle: RockxyLocalization.bundle)
        case .none: String(localized: "No Body", bundle: RockxyLocalization.bundle)
        // Format acronyms render verbatim.
        case .json: "JSON"
        case .html: "HTML"
        case .javascript: "JavaScript"
        case .css: "CSS"
        case .xml: "XML"
        case .protobuf: "Protobuf"
        }
    }

    /// The content pill that narrows the request list to this payload type, when one exists.
    var drillDown: TrafficInsightsDrillDown? {
        switch self {
        case .json: .protocolFilter(.json)
        case .html: .protocolFilter(.document)
        case .image: .protocolFilter(.media)
        case .javascript: .protocolFilter(.js)
        case .css: .protocolFilter(.css)
        case .font: .protocolFilter(.font)
        case .xml: .protocolFilter(.xml)
        case .form: .protocolFilter(.form)
        case .text,
             .protobuf,
             .binary,
             .none: nil
        }
    }

    static func classify(contentType: ContentType?, rawContentTypeHeader: String?, bodyByteCount: Int64) -> Self {
        // These normalized types can only come from media types that the script, style, and
        // font checks below would never match, so they skip the header scan entirely.
        switch contentType {
        case .json: return .json
        case .html: return .html
        case .image: return .image
        case .xml: return .xml
        case .form,
             .multipartForm: return .form
        case .protobuf: return .protobuf
        case .text,
             .binary,
             .unknown,
             nil:
            break
        }
        let header = rawContentTypeHeader?.lowercased() ?? ""
        if header.contains("javascript") || header.contains("ecmascript") {
            return .javascript
        }
        if header.contains("text/css") {
            return .css
        }
        if header.contains("font/") || header.contains("font-woff") || header.contains("x-font-ttf")
            || header.contains("vnd.ms-fontobject") || header.contains("font-sfnt")
        {
            return .font
        }
        switch contentType {
        case .json: return .json
        case .html: return .html
        case .image: return .image
        case .xml: return .xml
        case .text: return .text
        case .form,
             .multipartForm: return .form
        case .protobuf: return .protobuf
        case .binary: return .binary
        case .unknown,
             nil:
            if bodyByteCount == 0, header.isEmpty {
                return .none
            }
            return .binary
        }
    }
}

// MARK: - TrafficInsightsText

/// Localized strings that use automatic grammar agreement (`^[…](inflect: true)`). Plain
/// `String(localized:)` leaves the markup untouched, so inflected copy goes through
/// `AttributedString` exactly like the request list and export scope summaries.
nonisolated enum TrafficInsightsText {
    /// Grammar inflection runs a lexical pass that costs a large fraction of a millisecond, and
    /// the report resolves dozens of these strings on every render (row labels, tooltips,
    /// finding titles). Results are memoized by the resolved, still-marked-up string, which
    /// changes only when a count changes.
    static func inflected(_ value: String.LocalizationValue) -> String {
        let plain = String(localized: value, bundle: RockxyLocalization.bundle, locale: RockxyLocalization.locale)
        let key = "\(RockxyLocalization.locale.identifier)|\(plain)" as NSString
        if let cached = inflectionCache.object(forKey: key) {
            return cached as String
        }
        let resolved = String(AttributedString(
            localized: value,
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
        inflectionCache.setObject(resolved as NSString, forKey: key)
        return resolved
    }

    /// Thread-safe; the engine inflects finding titles off the main actor while views inflect
    /// labels on it.
    nonisolated(unsafe) private static let inflectionCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4_096
        return cache
    }()
}

// MARK: - TrafficInsightsSample

/// Immutable, `Sendable` copy of the fields Traffic Insights needs from one transaction.
///
/// Built on the main actor from a live `HTTPTransaction` and then handed to the engine, which
/// runs off the main actor. Request and response values are copied by reference-counted
/// storage, so snapshotting thousands of transactions costs a few milliseconds and never scans
/// bodies on the main actor; protocol detection happens later inside the engine.
struct TrafficInsightsSample: Sendable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID,
        timestamp: Date,
        request: HTTPRequestData,
        response: HTTPResponseData?,
        state: TransactionState,
        isTLSFailure: Bool,
        isTunneled: Bool,
        clientApp: String?,
        duration: TimeInterval?,
        timing: TimingInfo?,
        webSocketSentBytes: Int64,
        webSocketReceivedBytes: Int64,
        hasWebSocket: Bool,
        hasGraphQL: Bool,
        hasWeb3RPC: Bool,
        matchedRuleName: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.state = state
        self.isTLSFailure = isTLSFailure
        self.isTunneled = isTunneled
        self.clientApp = clientApp
        self.duration = duration
        self.timing = timing
        self.webSocketSentBytes = webSocketSentBytes
        self.webSocketReceivedBytes = webSocketReceivedBytes
        self.hasWebSocket = hasWebSocket
        self.hasGraphQL = hasGraphQL
        self.hasWeb3RPC = hasWeb3RPC
        self.matchedRuleName = matchedRuleName
    }

    @MainActor
    init(transaction: HTTPTransaction) {
        // Running totals on the connection: the snapshot must stay O(1) per transaction even
        // for a socket that has captured thousands of frames.
        let sent = Int64(transaction.webSocketConnection?.sentPayloadSize ?? 0)
        let received = Int64(transaction.webSocketConnection?.receivedPayloadSize ?? 0)
        let isTunneled: Bool = if let mode = transaction.sslCapture {
            mode == .tunneled
        } else {
            transaction.request.method == "CONNECT"
        }
        self.init(
            id: transaction.id,
            timestamp: transaction.timestamp,
            request: transaction.request,
            response: transaction.response,
            state: transaction.state,
            isTLSFailure: transaction.isTLSFailure,
            isTunneled: isTunneled,
            clientApp: transaction.clientApp,
            duration: transaction.timingInfo?.totalDuration ?? transaction.measuredDuration,
            timing: transaction.timingInfo,
            webSocketSentBytes: sent,
            webSocketReceivedBytes: received,
            hasWebSocket: transaction.webSocketConnection != nil,
            hasGraphQL: transaction.graphQLInfo != nil,
            hasWeb3RPC: transaction.web3RPCInfo != nil,
            matchedRuleName: transaction.matchedRuleName
        )
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let request: HTTPRequestData
    let response: HTTPResponseData?
    let state: TransactionState
    let isTLSFailure: Bool
    let isTunneled: Bool
    let clientApp: String?
    let duration: TimeInterval?
    let timing: TimingInfo?
    let webSocketSentBytes: Int64
    let webSocketReceivedBytes: Int64
    let hasWebSocket: Bool
    let hasGraphQL: Bool
    let hasWeb3RPC: Bool
    let matchedRuleName: String?

    var host: String {
        request.host
    }

    var scheme: String {
        request.url.scheme?.lowercased() ?? ""
    }

    var method: String {
        request.method
    }

    /// Bytes the client sent: request body plus outbound WebSocket frames.
    var sentBytes: Int64 {
        Int64(request.body?.count ?? 0) + webSocketSentBytes
    }

    /// Bytes the client received: response body plus inbound WebSocket frames.
    var receivedBytes: Int64 {
        Int64(response?.body?.count ?? 0) + webSocketReceivedBytes
    }

    var totalBytes: Int64 {
        sentBytes + receivedBytes
    }

    var statusCode: Int? {
        response?.statusCode
    }

    var statusClass: TrafficInsightsStatusClass {
        .classify(statusCode: statusCode, state: state, isTLSFailure: isTLSFailure)
    }

    var responseContentTypeHeader: String? {
        response?.headers.first { Self.header($0, isNamed: "Content-Type") }?.value
    }

    var responseContentEncoding: String? {
        response?.headers.first { Self.header($0, isNamed: "Content-Encoding") }?
            .value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether the response carries any freshness or validation header.
    var hasCacheHeaders: Bool {
        guard let response else {
            return false
        }
        return response.headers.contains { header in
            let name = header.name.lowercased()
            return name == "cache-control" || name == "etag" || name == "expires" || name == "last-modified"
        }
    }

    var contentCategory: TrafficInsightsContentCategory {
        .classify(
            contentType: response?.contentType,
            rawContentTypeHeader: responseContentTypeHeader,
            bodyByteCount: Int64(response?.body?.count ?? 0)
        )
    }

    /// Stable key for detecting repeated identical fetches: method plus URL without fragment.
    var repeatKey: String {
        // Dropping the fragment textually costs a substring scan instead of a URLComponents
        // round trip, which matters when every GET in a long session is grouped.
        let absolute = request.url.absoluteString
        let normalized = absolute.firstIndex(of: "#").map { String(absolute[..<$0]) } ?? absolute
        return "\(method) \(normalized)"
    }

    /// Case-insensitive header match with a length pre-check, because the engine resolves
    /// these for every response and most header names are the wrong length anyway.
    private static func header(_ header: HTTPHeader, isNamed name: String) -> Bool {
        header.name.utf8.count == name.utf8.count
            && header.name.caseInsensitiveCompare(name) == .orderedSame
    }

    var displayPath: String {
        let path = request.path
        if let query = request.url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path.isEmpty ? "/" : path
    }
}

// MARK: - AITrafficSnapshot + TrafficInsightsSample

extension AITrafficSnapshot {
    /// Builds the detector snapshot from an insights sample so AI classification can run
    /// inside the engine instead of scanning bodies on the main actor.
    init(sample: TrafficInsightsSample) {
        requestMethod = sample.request.method
        urlString = sample.request.url.absoluteString
        scheme = sample.request.url.scheme ?? ""
        host = sample.request.host
        path = sample.request.path
        requestHeaders = sample.request.headers
        requestBody = sample.request.body
        responseStatusCode = sample.response?.statusCode
        responseHeaders = sample.response?.headers ?? []
        responseBody = sample.response?.body
        duration = sample.duration
    }
}
