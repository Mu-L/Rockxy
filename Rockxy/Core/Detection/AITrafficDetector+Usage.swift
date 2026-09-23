import Foundation

// MARK: - AITrafficDetector + Usage

/// Token usage extraction for OpenAI, Anthropic, Gemini, and Ollama response shapes.
extension AITrafficDetector {
    // MARK: Usage

    static func usage(
        provider: AIProvider,
        responseJSON: [String: Any]?,
        streamEvents: [ParsedStreamEvent]
    )
        -> AIUsage?
    {
        if let usage = usageObject(in: responseJSON) {
            return usage
        }

        // Streams report usage across several events (Anthropic: `message_start` carries the
        // input side, `message_delta` the output side; OpenAI: the final chunk). Merge every
        // usage object in order so later cumulative counts override earlier partial ones.
        var merged: AIUsage?
        for event in streamEvents {
            guard let json = event.json else {
                continue
            }
            let candidates: [[String: Any]?] = [
                json,
                json["message"] as? [String: Any],
                json["response"] as? [String: Any],
            ]
            for candidate in candidates {
                if let usage = usageObject(in: candidate) {
                    merged = merged.map { $0.merging(usage) } ?? usage
                }
            }
        }
        return merged
    }

    static func usageObject(in json: [String: Any]?) -> AIUsage? {
        guard let json else {
            return nil
        }
        if let raw = json["usage"] as? [String: Any] {
            return usage(fromUsageDictionary: raw)
        }
        if let raw = json["usageMetadata"] as? [String: Any] {
            return usage(fromGeminiUsage: raw)
        }
        if json["prompt_eval_count"] != nil || json["eval_count"] != nil {
            return usage(fromOllama: json)
        }
        return nil
    }

    static func usage(fromUsageDictionary raw: [String: Any]) -> AIUsage? {
        let promptDetails = raw["prompt_tokens_details"] as? [String: Any]
        let inputDetails = raw["input_tokens_details"] as? [String: Any]
        let outputDetails = raw["output_tokens_details"] as? [String: Any]
            ?? raw["completion_tokens_details"] as? [String: Any]

        let cacheRead = intValue(forKey: "cache_read_input_tokens", in: raw)
        let cacheCreation = intValue(forKey: "cache_creation_input_tokens", in: raw)
        let cachedSubset = intValue(forKey: "cached_tokens", in: promptDetails)
            ?? intValue(forKey: "cached_tokens", in: inputDetails)

        var input = intValue(forKey: "input_tokens", in: raw)
            ?? intValue(forKey: "prompt_tokens", in: raw)
        // Anthropic reports cache reads/writes beside `input_tokens`; normalize to the
        // OpenAI convention where the input count already includes cached tokens.
        if cacheRead != nil || cacheCreation != nil {
            input = (input ?? 0) + (cacheRead ?? 0) + (cacheCreation ?? 0)
        }
        let cached = cachedSubset ?? cacheRead
        let output = intValue(forKey: "output_tokens", in: raw)
            ?? intValue(forKey: "completion_tokens", in: raw)
        let reasoning = intValue(forKey: "reasoning_tokens", in: outputDetails)
        let total = intValue(forKey: "total_tokens", in: raw)
            ?? [input, output].compactMap { $0 }.reduce(0, +)

        guard input != nil || output != nil || total > 0 else {
            return nil
        }
        return AIUsage(
            inputTokens: input,
            cachedTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total
        )
    }

    static func usage(fromGeminiUsage raw: [String: Any]) -> AIUsage? {
        let input = intValue(forKey: "promptTokenCount", in: raw)
        let output = intValue(forKey: "candidatesTokenCount", in: raw)
        let cached = intValue(forKey: "cachedContentTokenCount", in: raw)
        let reasoning = intValue(forKey: "thoughtsTokenCount", in: raw)
        let total = intValue(forKey: "totalTokenCount", in: raw)
            ?? [input, output, reasoning].compactMap { $0 }.reduce(0, +)
        guard input != nil || output != nil || total > 0 else {
            return nil
        }
        return AIUsage(
            inputTokens: input,
            cachedTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total
        )
    }

    static func usage(fromOllama json: [String: Any]) -> AIUsage? {
        let input = intValue(forKey: "prompt_eval_count", in: json)
        let output = intValue(forKey: "eval_count", in: json)
        guard input != nil || output != nil else {
            return nil
        }
        return AIUsage(
            inputTokens: input,
            cachedTokens: nil,
            outputTokens: output,
            reasoningTokens: nil,
            totalTokens: [input, output].compactMap { $0 }.reduce(0, +)
        )
    }
}
