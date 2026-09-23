import Foundation

// MARK: - AITrafficDetector + Tools

/// Declared and invoked tool-call extraction, including streamed argument reassembly.
extension AITrafficDetector {
    // MARK: Tools

    static func declaredTools(from requestJSON: [String: Any]?) -> [AIToolCall] {
        guard let tools = requestJSON?["tools"] as? [[String: Any]] else {
            return []
        }
        var names: [String] = []
        for tool in tools {
            if let name = tool["name"] as? String {
                names.append(name)
            } else if let function = tool["function"] as? [String: Any], let name = function["name"] as? String {
                names.append(name)
            } else if let declarations = tool["functionDeclarations"] as? [[String: Any]] {
                names += declarations.compactMap { $0["name"] as? String }
            } else if let type = tool["type"] as? String, !type.isEmpty {
                names.append(type)
            }
        }
        return names.map { AIToolCall(name: $0, argumentsPreview: nil, state: .declared) }
    }

    static func invokedToolCalls(
        provider: AIProvider,
        responseJSON: [String: Any]?,
        streamEvents: [ParsedStreamEvent]
    )
        -> [AIToolCall]
    {
        var calls = responseToolCalls(from: responseJSON)
        if calls.isEmpty, !streamEvents.isEmpty {
            calls = streamedToolCalls(from: streamEvents)
        }
        return calls
    }

    static func responseToolCalls(from responseJSON: [String: Any]?) -> [AIToolCall] {
        guard let responseJSON else {
            return []
        }

        // OpenAI Responses API
        if let output = responseJSON["output"] as? [[String: Any]] {
            return output.compactMap { item in
                guard (item["type"] as? String)?.contains("call") == true else {
                    return nil
                }
                return AIToolCall(
                    name: item["name"] as? String ?? item["type"] as? String ?? "tool_call",
                    argumentsPreview: item["arguments"] as? String,
                    state: .completed
                )
            }
        }

        // OpenAI Chat Completions
        if let choices = responseJSON["choices"] as? [[String: Any]] {
            return choices.flatMap { choice -> [AIToolCall] in
                let message = choice["message"] as? [String: Any]
                let calls = message?["tool_calls"] as? [[String: Any]] ?? []
                return calls.map { call in
                    let function = call["function"] as? [String: Any]
                    return AIToolCall(
                        name: function?["name"] as? String ?? "tool_call",
                        argumentsPreview: function?["arguments"] as? String,
                        state: .completed
                    )
                }
            }
        }

        // Anthropic Messages
        if let content = responseJSON["content"] as? [[String: Any]] {
            return content.compactMap { block in
                guard block["type"] as? String == "tool_use" else {
                    return nil
                }
                return AIToolCall(
                    name: block["name"] as? String ?? "tool_use",
                    argumentsPreview: block["input"].flatMap(compactJSONString),
                    state: .completed
                )
            }
        }

        // Gemini
        if let candidates = responseJSON["candidates"] as? [[String: Any]] {
            return candidates.flatMap { candidate -> [AIToolCall] in
                let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                return parts.compactMap { part in
                    guard let call = part["functionCall"] as? [String: Any] else {
                        return nil
                    }
                    return AIToolCall(
                        name: call["name"] as? String ?? "functionCall",
                        argumentsPreview: call["args"].flatMap(compactJSONString),
                        state: .completed
                    )
                }
            }
        }

        // Ollama
        if let message = responseJSON["message"] as? [String: Any],
           let calls = message["tool_calls"] as? [[String: Any]]
        {
            return calls.map { call in
                let function = call["function"] as? [String: Any]
                return AIToolCall(
                    name: function?["name"] as? String ?? "tool_call",
                    argumentsPreview: (function?["arguments"]).flatMap(compactJSONString),
                    state: .completed
                )
            }
        }
        return []
    }

    /// Reassembles streamed tool calls whose name arrives in one event and whose arguments
    /// arrive as fragments in later events.
    static func streamedToolCalls(from streamEvents: [ParsedStreamEvent]) -> [AIToolCall] {
        struct Builder {
            var name: String
            var arguments = ""
            var completed = false
        }
        var builders: [Builder] = []
        var indexByKey: [String: Int] = [:]

        func builderIndex(forKey key: String, name: String?) -> Int {
            if let index = indexByKey[key] {
                if let name, builders[index].name.isEmpty {
                    builders[index].name = name
                }
                return index
            }
            builders.append(Builder(name: name ?? ""))
            indexByKey[key] = builders.count - 1
            return builders.count - 1
        }

        for parsed in streamEvents {
            guard let json = parsed.json else {
                continue
            }
            let eventName = (parsed.event.event ?? json["type"] as? String ?? "").lowercased()

            // OpenAI Chat Completions chunks
            if let choices = json["choices"] as? [[String: Any]] {
                for choice in choices {
                    let delta = choice["delta"] as? [String: Any]
                    for call in delta?["tool_calls"] as? [[String: Any]] ?? [] {
                        let function = call["function"] as? [String: Any]
                        let key = "chat:\(intValue(forKey: "index", in: call) ?? 0)"
                        let index = builderIndex(forKey: key, name: function?["name"] as? String)
                        builders[index].arguments += function?["arguments"] as? String ?? ""
                    }
                    if let finish = choice["finish_reason"] as? String, finish == "tool_calls" {
                        for index in builders.indices {
                            builders[index].completed = true
                        }
                    }
                }
                continue
            }

            // OpenAI Responses API
            if eventName == "response.output_item.added",
               let item = json["item"] as? [String: Any],
               (item["type"] as? String)?.contains("call") == true
            {
                let key = "responses:\(item["id"] as? String ?? item["call_id"] as? String ?? UUID().uuidString)"
                let index = builderIndex(forKey: key, name: item["name"] as? String ?? item["type"] as? String)
                builders[index].arguments += item["arguments"] as? String ?? ""
                continue
            }
            if eventName == "response.function_call_arguments.delta", let itemID = json["item_id"] as? String {
                let index = builderIndex(forKey: "responses:\(itemID)", name: nil)
                builders[index].arguments += json["delta"] as? String ?? ""
                continue
            }
            if eventName == "response.function_call_arguments.done", let itemID = json["item_id"] as? String {
                let index = builderIndex(forKey: "responses:\(itemID)", name: nil)
                if let arguments = json["arguments"] as? String {
                    builders[index].arguments = arguments
                }
                builders[index].completed = true
                continue
            }
            if eventName == "response.output_item.done",
               let item = json["item"] as? [String: Any],
               (item["type"] as? String)?.contains("call") == true
            {
                let key = "responses:\(item["id"] as? String ?? item["call_id"] as? String ?? "")"
                let index = builderIndex(forKey: key, name: item["name"] as? String)
                if let arguments = item["arguments"] as? String {
                    builders[index].arguments = arguments
                }
                builders[index].completed = true
                continue
            }

            // Anthropic Messages stream
            if eventName == "content_block_start",
               let block = json["content_block"] as? [String: Any],
               block["type"] as? String == "tool_use"
            {
                let key = "anthropic:\(intValue(forKey: "index", in: json) ?? builders.count)"
                _ = builderIndex(forKey: key, name: block["name"] as? String)
                continue
            }
            if eventName == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               delta["type"] as? String == "input_json_delta"
            {
                let key = "anthropic:\(intValue(forKey: "index", in: json) ?? 0)"
                guard let index = indexByKey[key] else {
                    continue
                }
                builders[index].arguments += delta["partial_json"] as? String ?? ""
                continue
            }
            if eventName == "content_block_stop" {
                let key = "anthropic:\(intValue(forKey: "index", in: json) ?? 0)"
                if let index = indexByKey[key] {
                    builders[index].completed = true
                }
                continue
            }

            // Gemini and Ollama streams carry whole calls per chunk.
            let chunkCalls = responseToolCalls(from: json)
            for (offset, call) in chunkCalls.enumerated() {
                let key = "chunk:\(builders.count + offset):\(call.name)"
                let index = builderIndex(forKey: key, name: call.name)
                builders[index].arguments = call.argumentsPreview ?? ""
                builders[index].completed = true
            }
        }

        return builders.map { builder in
            AIToolCall(
                name: builder.name.isEmpty ? "tool_call" : builder.name,
                argumentsPreview: builder.arguments.isEmpty ? nil : builder.arguments,
                state: builder.completed ? .completed : .streaming
            )
        }
    }
}
