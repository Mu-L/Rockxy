import Foundation

// MARK: - AITrafficDetector + Output

/// Finish reasons, assembled assistant output, and per-event summaries.
extension AITrafficDetector {
    // MARK: Finish reason and output

    static func finishReason(
        provider: AIProvider,
        responseJSON: [String: Any]?,
        streamEvents: [ParsedStreamEvent]
    )
        -> String?
    {
        if let reason = finishReason(in: responseJSON) {
            return reason
        }
        var last: String?
        for parsed in streamEvents {
            if let reason = finishReason(in: parsed.json) {
                last = reason
            }
        }
        return last
    }

    static func finishReason(in json: [String: Any]?) -> String? {
        guard let json else {
            return nil
        }
        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let reason = choice["finish_reason"] as? String {
                    return reason
                }
            }
        }
        if let reason = json["stop_reason"] as? String {
            return reason
        }
        if let delta = json["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
            return reason
        }
        if let reason = json["done_reason"] as? String {
            return reason
        }
        if let candidates = json["candidates"] as? [[String: Any]] {
            for candidate in candidates {
                if let reason = candidate["finishReason"] as? String {
                    return reason.lowercased()
                }
            }
        }
        if let response = json["response"] as? [String: Any] {
            if let status = response["status"] as? String, status != "in_progress" {
                if status == "incomplete",
                   let details = response["incomplete_details"] as? [String: Any],
                   let reason = details["reason"] as? String
                {
                    return "incomplete (\(reason))"
                }
                return status
            }
        } else if let status = json["status"] as? String, json["object"] as? String == "response",
                  status != "in_progress"
        {
            if status == "incomplete",
               let details = json["incomplete_details"] as? [String: Any],
               let reason = details["reason"] as? String
            {
                return "incomplete (\(reason))"
            }
            return status
        }
        return nil
    }

    /// Concatenates the assistant text visible in the captured response. Streams are
    /// reassembled from their deltas; non-streamed bodies use the first text part.
    static func assembledOutput(
        provider: AIProvider,
        responseJSON: [String: Any]?,
        streamEvents: [ParsedStreamEvent]
    )
        -> String?
    {
        var output = ""
        if !streamEvents.isEmpty {
            for parsed in streamEvents {
                guard let json = parsed.json else {
                    continue
                }
                // Responses API emits both deltas and the final text; skip the aggregate events.
                let eventName = (parsed.event.event ?? json["type"] as? String ?? "").lowercased()
                if eventName.hasSuffix(".done") || eventName == "response.completed" || eventName == "message_stop" {
                    continue
                }
                output += textDelta(in: json)
                if output.count > maxAssembledOutputCharacters {
                    break
                }
            }
        } else if let responseJSON {
            output = responseText(in: responseJSON)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maxAssembledOutputCharacters))
    }

    static func textDelta(in json: [String: Any]) -> String {
        // OpenAI Chat Completions chunk
        if let choices = json["choices"] as? [[String: Any]] {
            return choices.compactMap { choice -> String? in
                let delta = choice["delta"] as? [String: Any]
                return delta?["content"] as? String
            }.joined()
        }
        // OpenAI Responses API delta
        if let type = json["type"] as? String, type == "response.output_text.delta",
           let delta = json["delta"] as? String
        {
            return delta
        }
        // Anthropic Messages stream
        if let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta" {
            return delta["text"] as? String ?? ""
        }
        // Gemini stream chunk
        if json["candidates"] != nil {
            return responseText(in: json)
        }
        // Ollama NDJSON chunk
        if let message = json["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        if let response = json["response"] as? String, json["done"] != nil {
            return response
        }
        return ""
    }

    static func responseText(in json: [String: Any]) -> String {
        if let output = json["output"] as? [[String: Any]] {
            return output.compactMap { item -> String? in
                guard item["type"] as? String == "message",
                      let content = item["content"] as? [[String: Any]] else
                {
                    return nil
                }
                return content.compactMap { $0["text"] as? String }.joined()
            }.joined(separator: "\n")
        }
        if let choices = json["choices"] as? [[String: Any]] {
            return choices.compactMap { choice -> String? in
                let message = choice["message"] as? [String: Any]
                return message?["content"] as? String ?? choice["text"] as? String
            }.joined(separator: "\n")
        }
        if let content = json["content"] as? [[String: Any]] {
            return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        }
        if let candidates = json["candidates"] as? [[String: Any]] {
            return candidates.compactMap { candidate -> String? in
                let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                return parts.compactMap { $0["text"] as? String }.joined()
            }.joined(separator: "\n")
        }
        if let message = json["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        if let response = json["response"] as? String {
            return response
        }
        return ""
    }

    // MARK: Events

    static func eventSummaries(
        snapshot: AITrafficSnapshot,
        responseJSON: [String: Any]?,
        streamEvents: [ParsedStreamEvent],
        toolCalls: [AIToolCall],
        finishReason: String?
    )
        -> [AIEventSummary]
    {
        if !streamEvents.isEmpty {
            return streamEvents.enumerated().map { index, parsed in
                let classified = classifyStreamEvent(parsed)
                return AIEventSummary(
                    id: "stream-\(index)",
                    title: classified.title,
                    detail: parsed.event.data,
                    offsetLabel: "#\(index + 1)",
                    category: classified.category,
                    severity: classified.severity,
                    preview: classified.preview,
                    byteCount: parsed.event.data.utf8.count
                )
            }
        }

        var events: [AIEventSummary] = [
            AIEventSummary(
                id: "request",
                title: "model request",
                detail: snapshot.urlString,
                offsetLabel: "request",
                category: .request,
                severity: .normal,
                preview: nil,
                byteCount: snapshot.requestBody?.count ?? 0
            ),
        ]
        events += toolCalls.enumerated().map { index, tool in
            AIEventSummary(
                id: "tool-\(index)",
                title: tool.name,
                detail: tool.argumentsPreview ?? tool.state.displayName,
                offsetLabel: tool.state.displayName,
                category: .tool,
                severity: .normal,
                preview: tool.argumentsPreview,
                byteCount: tool.argumentsPreview?.utf8.count ?? 0
            )
        }
        if let status = snapshot.responseStatusCode {
            let detail = responseJSON?["status"] as? String ?? finishReason.map { "HTTP \(status) · \($0)" } ?? "HTTP \(status)"
            events.append(AIEventSummary(
                id: "response",
                title: "response",
                detail: detail,
                offsetLabel: "\(status)",
                category: .response,
                severity: status >= 400 ? .error : .normal,
                preview: finishReason,
                byteCount: snapshot.responseBody?.count ?? 0
            ))
        }
        return events
    }

    static func classifyStreamEvent(
        _ parsed: ParsedStreamEvent
    )
        -> (title: String, category: AIEventCategory, severity: AIEventSeverity, preview: String?)
    {
        let json = parsed.json
        let explicitName = parsed.event.event ?? json?["type"] as? String
        let lowered = explicitName?.lowercased() ?? ""

        if lowered.contains("error") || json?["error"] != nil {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            return (explicitName ?? "error", .stream, .error, message)
        }

        if let json {
            // OpenAI Chat Completions chunks carry no event name; derive one from the delta.
            if let choices = json["choices"] as? [[String: Any]] {
                if json["usage"] != nil, choices.isEmpty {
                    return ("usage", .stream, .normal, usagePreview(json["usage"]))
                }
                let choice = choices.first
                let delta = choice?["delta"] as? [String: Any]
                if let finish = choice?["finish_reason"] as? String {
                    return ("finish", .stream, .normal, finish)
                }
                if let calls = delta?["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                    let function = calls.first?["function"] as? [String: Any]
                    let preview = function?["name"] as? String ?? function?["arguments"] as? String
                    return ("tool_call.delta", .tool, .normal, preview)
                }
                if let content = delta?["content"] as? String, !content.isEmpty {
                    return ("text.delta", .stream, .normal, content)
                }
                if delta?["role"] != nil {
                    return ("role", .stream, .normal, delta?["role"] as? String)
                }
                return ("chunk", .stream, .normal, nil)
            }
            if json["candidates"] != nil {
                let text = responseText(in: json)
                let finish = finishReason(in: json)
                return (
                    finish == nil ? "candidate.delta" : "candidate.finish",
                    .stream,
                    .normal,
                    text.isEmpty ? finish : text
                )
            }
            if json["done"] != nil {
                let done = boolValue(forKey: "done", in: json) == true
                let text = textDelta(in: json)
                return (done ? "done" : "message.delta", .stream, .normal, done ? json["done_reason"] as? String : text)
            }
        }

        let title = explicitName ?? "data"
        let category: AIEventCategory = lowered.contains("tool")
            || lowered.contains("function_call")
            || (json?["content_block"] as? [String: Any])?["type"] as? String == "tool_use"
            || (json?["delta"] as? [String: Any])?["type"] as? String == "input_json_delta"
            ? .tool : .stream
        let preview: String? = if let json {
            streamPreview(in: json)
        } else {
            nil
        }
        return (title, category, .normal, preview)
    }

    static func streamPreview(in json: [String: Any]) -> String? {
        let text = textDelta(in: json)
        if !text.isEmpty {
            return text
        }
        if let delta = json["delta"] as? [String: Any] {
            if let partial = delta["partial_json"] as? String {
                return partial
            }
            if let reason = delta["stop_reason"] as? String {
                return reason
            }
        }
        if let delta = json["delta"] as? String {
            return delta
        }
        if let block = json["content_block"] as? [String: Any] {
            return block["name"] as? String ?? block["type"] as? String
        }
        if let item = json["item"] as? [String: Any] {
            return item["name"] as? String ?? item["type"] as? String
        }
        if let arguments = json["arguments"] as? String {
            return arguments
        }
        if let usage = json["usage"] {
            return usagePreview(usage)
        }
        if let message = json["message"] as? [String: Any] {
            if let usage = message["usage"] {
                return usagePreview(usage)
            }
            return message["model"] as? String
        }
        if let response = json["response"] as? [String: Any] {
            return response["status"] as? String
        }
        return nil
    }

    static func usagePreview(_ value: Any?) -> String? {
        guard let raw = value as? [String: Any] else {
            return nil
        }
        let pairs = raw.compactMap { key, value -> String? in
            guard let number = value as? NSNumber else {
                return nil
            }
            return "\(key)=\(number.intValue)"
        }.sorted()
        return pairs.isEmpty ? nil : pairs.joined(separator: " ")
    }
}
