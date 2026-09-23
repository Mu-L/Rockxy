import Foundation

// MARK: - AITrafficSnapshot

struct AITrafficSnapshot: Sendable {
    // MARK: Lifecycle

    init(transaction: HTTPTransaction) {
        requestMethod = transaction.request.method
        urlString = transaction.request.url.absoluteString
        scheme = transaction.request.url.scheme ?? ""
        host = transaction.request.host
        path = transaction.request.path
        requestHeaders = transaction.request.headers
        requestBody = transaction.request.body
        responseStatusCode = transaction.response?.statusCode
        responseHeaders = transaction.response?.headers ?? []
        responseBody = transaction.response?.decodedBody(limit: AITrafficDetector.maxBodyBytes)
        duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration
    }

    // MARK: Internal

    let requestMethod: String
    let urlString: String
    let scheme: String
    let host: String
    let path: String
    let requestHeaders: [HTTPHeader]
    let requestBody: Data?
    let responseStatusCode: Int?
    let responseHeaders: [HTTPHeader]
    let responseBody: Data?
    let duration: TimeInterval?
}

// MARK: - AIInspection

struct AIInspection: Equatable, Sendable {
    let provider: AIProvider
    let kind: AITrafficSignalKind
    let evidence: [String]
    /// The model the client asked for (or the model in the Gemini path).
    let model: String?
    /// The model the provider reported, when it differs from the requested one
    /// (for example a dated snapshot behind an alias).
    let servedModel: String?
    let endpoint: String
    let isStreaming: Bool
    let streamTransport: AIStreamTransport
    let httpStatusCode: Int?
    let duration: TimeInterval?
    let requestID: String?
    /// Provider finish reason (`stop`, `length`, `tool_calls`, `end_turn`, `max_tokens`, …).
    let finishReason: String?
    let usage: AIUsage?
    let toolCalls: [AIToolCall]
    let events: [AIEventSummary]
    let retrieval: [AIRetrievalMatch]
    let warnings: [AIWarning]
    /// Assistant text reassembled from stream deltas or read from the response body.
    let assembledOutput: String?
    let unavailableFields: [String]

    /// Tool calls the model actually emitted, excluding tools merely declared by the request.
    var invokedToolCalls: [AIToolCall] {
        toolCalls.filter { $0.state != .declared }
    }
}

// MARK: - AIStreamTransport

enum AIStreamTransport: String, Equatable, Sendable {
    case none
    case sse
    case ndjson
}

// MARK: - AIProvider

enum AIProvider: String, Sendable {
    case openAICompatible
    case anthropic
    case gemini
    case ollama
    case chatGPT
    case claude

    // MARK: Internal

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }
}

// MARK: - AITrafficSignalKind

enum AITrafficSignalKind: String, Equatable, Sendable {
    case none
    case api
    case session
    case heuristic
}

// MARK: - AITrafficSignal

struct AITrafficSignal: Equatable, Sendable {
    let isLikelyAI: Bool
    let provider: AIProvider?
    let kind: AITrafficSignalKind
    let evidence: [String]

    var tableLabel: String {
        guard isLikelyAI else {
            return ""
        }
        switch kind {
        case .api:
            return "AI API"
        case .session:
            return "AI Session"
        case .heuristic:
            return "Likely AI"
        case .none:
            return "AI"
        }
    }

    var accessibilityLabel: String {
        guard isLikelyAI else {
            return ""
        }
        if let provider {
            let evidenceLabel = evidence.isEmpty ? "" : " (\(evidence.joined(separator: ", ")))"
            return "\(tableLabel): \(provider.displayName)\(evidenceLabel)"
        }
        return tableLabel
    }
}

// MARK: - AIUsage

struct AIUsage: Equatable, Sendable {
    /// Prompt-side tokens including any cached portion.
    let inputTokens: Int?
    /// Cached prompt tokens; a subset of `inputTokens`.
    let cachedTokens: Int?
    let outputTokens: Int?
    /// Reasoning/thinking tokens, when the provider itemizes them.
    let reasoningTokens: Int?
    let totalTokens: Int

    func merging(_ other: AIUsage) -> AIUsage {
        let input = other.inputTokens ?? inputTokens
        let cached = other.cachedTokens ?? cachedTokens
        let output = other.outputTokens ?? outputTokens
        let reasoning = other.reasoningTokens ?? reasoningTokens
        let total = max(other.totalTokens, [input, output].compactMap { $0 }.reduce(0, +))
        return AIUsage(
            inputTokens: input,
            cachedTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total
        )
    }
}

// MARK: - AIToolCall

struct AIToolCall: Equatable, Sendable {
    let name: String
    let argumentsPreview: String?
    let state: AIToolCallState
}

// MARK: - AIToolCallState

enum AIToolCallState: String, Sendable {
    case declared
    case streaming
    case completed
    case partial

    // MARK: Internal

    var displayName: String {
        rawValue
    }
}

// MARK: - AIEventSummary

struct AIEventSummary: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let offsetLabel: String
    let category: AIEventCategory
    let severity: AIEventSeverity
    /// Short human-readable excerpt (text delta, tool name, finish reason) for list rows.
    let preview: String?
    /// Captured payload size of this event; the only per-event magnitude the proxy records.
    let byteCount: Int
}

// MARK: - AIEventCategory

enum AIEventCategory: String, Sendable {
    case request
    case stream
    case tool
    case response
}

// MARK: - AIEventSeverity

enum AIEventSeverity: String, Sendable {
    case normal
    case warning
    case error
}

// MARK: - AIRetrievalMatch

struct AIRetrievalMatch: Equatable, Sendable {
    let source: String
    let score: Double?
    let signal: String
    let risk: String
}

// MARK: - AIWarning

struct AIWarning: Equatable, Sendable {
    let message: String
    let severity: AIWarningSeverity
}

// MARK: - AIWarningSeverity

enum AIWarningSeverity: String, Sendable {
    case redaction
    case error
    /// Retry and rate-limit guidance derived from response headers.
    case retry
}

// MARK: - AIStreamEvent

struct AIStreamEvent: Equatable {
    let event: String?
    let data: String
}
