import Foundation

struct OllamaAssistantProvider: AssistantModelProvider {
    // MARK: Lifecycle

    init(baseURL: URL, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    // MARK: Internal

    let kind = AssistantProviderKind.ollama
    let capabilities = AssistantProviderCapabilities.ollama

    /// Whether an `/api/tags` entry is served by a remote Ollama host rather than this
    /// runtime. Ollama reports `remote_host`/`remote_model` for cloud-backed models; the
    /// `cloud` tag family (`name:cloud`, `name:120b-cloud`) is also unambiguous.
    static func isRemoteInventoryItem(id: String, remoteHost: String?, remoteModel: String?) -> Bool {
        if isNonEmpty(remoteHost) || isNonEmpty(remoteModel) {
            return true
        }
        return denotesCloudModel(id: id)
    }

    /// `true` only when the tag portion of an Ollama model ID unambiguously marks an
    /// Ollama cloud model. Custom names that merely contain "cloud" stay local.
    static func denotesCloudModel(id: String) -> Bool {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let separator = normalized.lastIndex(of: ":") else {
            return false
        }
        let tag = normalized[normalized.index(after: separator)...]
        return tag == "cloud" || tag.hasSuffix("-cloud")
    }

    func discoverModels() async throws -> [AssistantModel] {
        do {
            let inventory = try await modelInventory()
            var enriched: [AssistantModel] = []
            enriched.reserveCapacity(inventory.count)
            for model in inventory {
                try Task.checkCancellation()
                let enrichedModel = await (try? modelMetadata(for: model)) ?? model
                enriched.append(enrichedModel)
            }
            return enriched
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    func testConnection(model: String) async throws -> Int {
        do {
            let models = try await modelInventory()
            guard let selected = models.first(where: { $0.id == model }) else {
                throw AssistantProviderError.modelNotFound(model)
            }
            _ = try await modelMetadata(for: selected)
            return models.count
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    func stream(_ request: AssistantCompletionRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint("api/chat"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var options: [String: Any] = ["num_predict": request.maxOutputTokens]
                    if let contextWindow = AssistantProviderConfiguration.validContextWindowTokens(
                        request.contextWindowTokens
                    ) {
                        options["num_ctx"] = contextWindow
                    }
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "model": request.model,
                            "messages": [
                                ["role": "system", "content": request.instructions],
                                ["role": "user", "content": request.input],
                            ],
                            "options": options,
                            "stream": true,
                        ],
                        options: [.sortedKeys]
                    )
                    let stream = try await transport.lines(for: urlRequest)
                    guard (200 ... 299).contains(stream.response.statusCode) else {
                        let body = await AssistantHTTPErrorMapper.boundedBody(from: stream.lines)
                        throw AssistantHTTPErrorMapper.error(
                            response: stream.response,
                            body: body,
                            model: request.model
                        )
                    }
                    continuation.yield(.started(responseID: nil))
                    var receivedTerminalEvent = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        for event in try decode(line: line) {
                            if case .completed = event {
                                receivedTerminalEvent = true
                            }
                            continuation.yield(event)
                        }
                    }
                    guard receivedTerminalEvent else {
                        throw AssistantProviderError.malformedResponse(
                            "The Ollama stream ended before done=true"
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AssistantHTTPErrorMapper.translated(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Private

    private static let connectionTimeout: TimeInterval = 5

    private static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let transport: any AssistantHTTPTransport

    private static func isNonEmpty(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func endpoint(_ path: String) -> URL {
        var normalized = baseURL
        if normalized.path.hasSuffix("/v1") {
            normalized.deleteLastPathComponent()
        }
        return normalized.appendingPathComponent(path)
    }

    private func modelMetadata(for model: AssistantModel) async throws -> AssistantModel {
        var request = URLRequest(url: endpoint("api/show"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": model.id],
            options: [.sortedKeys]
        )
        let (data, response) = try await transport.data(for: request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw AssistantHTTPErrorMapper.error(response: response, body: data, model: model.id)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistantProviderError.malformedResponse("Ollama returned invalid model metadata")
        }
        let modelInfo = object["model_info"] as? [String: Any] ?? [:]
        let contextWindow = modelInfo
            .filter { $0.key.hasSuffix(".context_length") }
            .compactMap { ($0.value as? NSNumber)?.intValue }
            .filter { $0 > 0 }
            .max()
        let capabilities = Set(
            (object["capabilities"] as? [String] ?? []).compactMap(AssistantModelCapability.init(rawValue:))
        )
        return AssistantModel(
            id: model.id,
            displayName: model.displayName,
            inputTokenLimit: contextWindow,
            outputTokenLimit: model.outputTokenLimit,
            sizeBytes: model.sizeBytes,
            digest: model.digest,
            parameterSize: model.parameterSize,
            quantizationLevel: model.quantizationLevel,
            capabilities: capabilities
        )
    }

    private func modelInventory() async throws -> [AssistantModel] {
        var request = URLRequest(url: endpoint("api/tags"))
        request.timeoutInterval = Self.connectionTimeout
        let (data, response) = try await transport.data(for: request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw AssistantHTTPErrorMapper.error(response: response, body: data, model: "")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["models"] as? [[String: Any]] else
        {
            throw AssistantProviderError.malformedResponse("Ollama returned no models array")
        }
        return values.compactMap { value -> AssistantModel? in
            guard let id = value["name"] as? String, !id.isEmpty else {
                return nil
            }
            // Cloud-backed entries would silently send reviewed traffic off this Mac.
            guard !Self.isRemoteInventoryItem(
                id: id,
                remoteHost: value["remote_host"] as? String,
                remoteModel: value["remote_model"] as? String
            ) else {
                return nil
            }
            let details = value["details"] as? [String: Any]
            return AssistantModel(
                id: id,
                displayName: id,
                sizeBytes: (value["size"] as? NSNumber)?.int64Value,
                digest: value["digest"] as? String,
                parameterSize: details?["parameter_size"] as? String,
                quantizationLevel: details?["quantization_level"] as? String
            )
        }
    }

    private func decode(line: String) throws -> [AssistantStreamEvent] {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("An Ollama stream event exceeded Rockxy's size limit")
        }
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw AssistantProviderError.malformedResponse("Ollama returned an invalid stream line")
        }
        if let error = object["error"] as? String {
            throw AssistantProviderError.validation(String(error.prefix(1_024)))
        }
        var events: [AssistantStreamEvent] = []
        if let message = object["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.isEmpty
        {
            events.append(.textDelta(content))
        }
        if object["done"] as? Bool == true {
            events.append(.usage(AssistantUsage(
                inputTokens: object["prompt_eval_count"] as? Int ?? 0,
                outputTokens: object["eval_count"] as? Int ?? 0,
                cachedInputTokens: 0
            )))
            events.append(.completed(responseID: nil))
        }
        return events
    }
}
