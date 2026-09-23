import Foundation

// MARK: - AITrafficDetector + Warnings

/// Retrieval matches, redaction/retry warnings, and unavailable-field reporting.
extension AITrafficDetector {
    // MARK: Retrieval, warnings, availability

    static func retrievalMatches(
        snapshot: AITrafficSnapshot,
        responseJSON: [String: Any]?
    )
        -> [AIRetrievalMatch]
    {
        let path = snapshot.path.lowercased()
        guard path.contains("search") || path.contains("embedding") || path.contains("retrieval") else {
            return []
        }

        let matches = responseJSON?["matches"] as? [[String: Any]]
            ?? responseJSON?["data"] as? [[String: Any]]
            ?? []
        return matches.prefix(8).enumerated().map { index, match in
            let source = match["id"] as? String ?? "match-\(index + 1)"
            let score = (match["score"] as? NSNumber)?.doubleValue
            return AIRetrievalMatch(
                source: source,
                score: score,
                signal: path.contains("embedding") ? "embedding" : "retrieval",
                risk: (match[
                    "snippet"
                ] as? String)?.lowercased().contains("secret") == true ? "sensitive-context" : "visible"
            )
        }
    }

    static func warnings(
        snapshot: AITrafficSnapshot,
        requestJSON: [String: Any]?,
        responseJSON: [String: Any]?,
        toolCalls: [AIToolCall],
        retrieval: [AIRetrievalMatch]
    )
        -> [AIWarning]
    {
        var warnings: [AIWarning] = []
        if let status = snapshot.responseStatusCode, status >= 400 {
            let message = providerErrorMessage(in: responseJSON)
            warnings.append(AIWarning(
                message: message
                    .map { "Provider returned HTTP \(status): \($0)" } ?? "Provider returned HTTP \(status).",
                severity: .error
            ))
            if status == 429 || status == 503 {
                warnings.append(AIWarning(
                    message: rateLimitSummary(headers: snapshot.responseHeaders),
                    severity: .retry
                ))
            }
        }
        if let retryCount = headerValue(named: "x-stainless-retry-count", in: snapshot.requestHeaders),
           let count = Int(retryCount), count > 0
        {
            warnings.append(AIWarning(message: "SDK retry attempt \(count) for this request.", severity: .retry))
        }
        if headerValue(named: "authorization", in: snapshot.requestHeaders) != nil
            || headerValue(named: "x-api-key", in: snapshot.requestHeaders) != nil
            || headerValue(named: "x-goog-api-key", in: snapshot.requestHeaders) != nil
            || snapshot.urlString.lowercased().contains("key=")
        {
            warnings.append(AIWarning(
                message: "Authentication credential is present in this request.",
                severity: .redaction
            ))
        }
        if requestJSON?["input"] != nil || requestJSON?["messages"] != nil || requestJSON?["contents"] != nil ||
            requestJSON?["prompt"] != nil
        {
            warnings.append(AIWarning(message: "Prompt content may require redaction.", severity: .redaction))
        }
        if !toolCalls.isEmpty {
            warnings.append(AIWarning(message: "Tool arguments may contain sensitive data.", severity: .redaction))
        }
        if retrieval.contains(where: { $0.risk == "sensitive-context" }) {
            warnings.append(AIWarning(
                message: "Retrieved context includes sensitive-looking snippets.",
                severity: .redaction
            ))
        }
        return warnings
    }

    static func providerErrorMessage(in responseJSON: [String: Any]?) -> String? {
        guard let responseJSON else {
            return nil
        }
        if let error = responseJSON["error"] as? [String: Any] {
            let message = error["message"] as? String
            let type = error["code"] as? String ?? error["type"] as? String ?? error["status"] as? String
            switch (message, type) {
            case let (message?, type?): return "\(message) (\(type))"
            case let (message?, nil): return message
            case let (nil, type?): return type
            default: return nil
            }
        }
        if let error = responseJSON["error"] as? String {
            return error
        }
        return responseJSON["message"] as? String
    }

    static func rateLimitSummary(headers: [HTTPHeader]) -> String {
        var parts: [String] = []
        if let retryAfter = headerValue(named: "retry-after", in: headers) {
            parts.append("Retry-After \(retryAfter)")
        }
        for name in [
            "x-ratelimit-remaining-requests",
            "x-ratelimit-remaining-tokens",
            "x-ratelimit-reset-requests",
            "x-ratelimit-reset-tokens",
            "anthropic-ratelimit-requests-remaining",
            "anthropic-ratelimit-tokens-remaining",
            "anthropic-ratelimit-requests-reset",
        ] {
            if let value = headerValue(named: name, in: headers) {
                parts.append("\(name.replacingOccurrences(of: "anthropic-", with: "")) \(value)")
            }
        }
        if parts.isEmpty {
            return "Rate limited without Retry-After or rate-limit headers; back off before retrying."
        }
        return "Rate limited: " + parts.joined(separator: " · ")
    }

    static func unavailableFields(
        usage: AIUsage?,
        events: [AIEventSummary],
        declaredTools: [AIToolCall],
        invokedTools: [AIToolCall],
        isStreaming: Bool
    )
        -> [String]
    {
        var fields: [String] = []
        if usage == nil {
            fields.append("usage")
        }
        if isStreaming, events.allSatisfy({ $0.category != .stream && $0.category != .tool }) {
            fields.append("stream events")
        }
        if !declaredTools.isEmpty, invokedTools.isEmpty {
            fields.append("tool calls")
        }
        return fields
    }
}
