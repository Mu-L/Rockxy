import Foundation
@testable import Rockxy
import Testing

// MARK: - NativeAssistantProviderTests

struct NativeAssistantProviderTests {
    // MARK: Internal

    @Test("Default assistant networking bypasses the system HTTP proxy")
    func defaultTransportBypassesSystemProxy() {
        let dictionary = URLSessionAssistantHTTPTransport.proxyBypassConfiguration()
            .connectionProxyDictionary

        #expect(dictionary?[kCFNetworkProxiesHTTPEnable as String] as? Bool == false)
        #expect(dictionary?[kCFNetworkProxiesHTTPSEnable as String] as? Bool == false)
    }

    @Test("Shared transport frames CRLF incrementally without leaking delimiters")
    func boundedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 16)
        var lines: [String] = []

        for byte in Data("first\r\n\nlast".utf8) {
            if let line = try framer.append(byte) {
                lines.append(line)
            }
        }
        if let line = try framer.finish() {
            lines.append(line)
        }

        #expect(lines == ["first", "", "last"])
    }

    @Test("Shared transport rejects an oversized line before String allocation")
    func oversizedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 4)

        for byte in Data("four".utf8) {
            #expect(try framer.append(byte) == nil)
        }
        #expect(throws: AssistantProviderError.self) {
            _ = try framer.append(UInt8(ascii: "x"))
        }
    }

    @Test("Shared transport rejects malformed UTF-8")
    func malformedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 4)
        _ = try framer.append(0xFF)

        #expect(throws: AssistantProviderError.self) {
            _ = try framer.append(0x0A)
        }
    }

    @Test("Anthropic discovers models and streams text with usage")
    func anthropicFixture() async throws {
        let modelsData = Data(
            #"{"data":[{"id":"claude-fixture","display_name":"Claude Fixture"}]}"#.utf8
        )
        let transport = NativeProviderFixtureTransport(
            data: modelsData,
            lines: [
                #"data: {"type":"message_start","message":{"id":"msg_fixture","usage":{"input_tokens":12,"cache_read_input_tokens":3}}}"#,
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
                #"data: {"type":"message_delta","usage":{"output_tokens":4}}"#,
                #"data: {"type":"message_stop"}"#,
            ]
        )
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )

        let discovered = try await provider.discoverModels()
        #expect(discovered == [AssistantModel(id: "claude-fixture", displayName: "Claude Fixture")])

        let events = try await collect(provider.stream(fixtureRequest(model: "claude-fixture")))
        #expect(events.contains(.textDelta("Hello")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 12, outputTokens: 4, cachedInputTokens: 3))))
        #expect(events.last == .completed(responseID: "msg_fixture"))

        let requests = await transport.requests()
        let streamRequest = try #require(requests.last)
        #expect(streamRequest.value(forHTTPHeaderField: "x-api-key") == "fixture-secret")
        #expect(streamRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try jsonBody(streamRequest)
        #expect(body["max_tokens"] as? Int == 321)
    }

    @Test("Gemini filters generative models and streams usage")
    func geminiFixture() async throws {
        let models = #"{"models":[{"name":"models/gemini-fixture","displayName":"Gemini Fixture","#
            + #""inputTokenLimit":1000,"outputTokenLimit":100,"supportedGenerationMethods":["generateContent"]},"#
            + #"{"name":"models/embed-fixture","supportedGenerationMethods":["embedContent"]}]}"#
        let transport = NativeProviderFixtureTransport(
            data: Data(models.utf8),
            lines: [
                #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}],"usageMetadata":{"promptTokenCount":8}}"#,
                #"data: {"candidates":[{"content":{"parts":[{"text":"!"}]},"finishReason":"STOP"}],"#
                    + #""usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":2,"#
                    + #""cachedContentTokenCount":1}}"#,
            ]
        )
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: transport
        )

        let discovered = try await provider.discoverModels()
        #expect(discovered.count == 1)
        #expect(discovered.first?.id == "gemini-fixture")
        #expect(discovered.first?.inputTokenLimit == 1_000)

        let events = try await collect(provider.stream(fixtureRequest(model: "gemini-fixture")))
        #expect(events.contains(.textDelta("Hello")))
        #expect(events.contains(.textDelta("!")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 8, outputTokens: 2, cachedInputTokens: 1))))
        #expect(events.last == .completed(responseID: nil))

        let requests = await transport.requests()
        let streamRequest = try #require(requests.last)
        #expect(streamRequest.url?
            .absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-fixture:streamGenerateContent?alt=sse")
        #expect(streamRequest.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-secret")
        let body = try jsonBody(streamRequest)
        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["maxOutputTokens"] as? Int == 321)
    }

    @Test("Runtime blocks captured data from remote cleartext endpoints")
    func insecureRemoteEndpoint() async throws {
        let runtime = AssistantProviderRuntime(
            transport: NativeProviderFixtureTransport(data: Data(), lines: []),
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://models.example.com/v1",
            model: "fixture"
        )

        do {
            _ = try await runtime.discoverModels(configuration: configuration)
            Issue.record("Expected insecure endpoint rejection")
        } catch let error as AssistantProviderError {
            #expect(error == .insecureEndpoint)
        }
    }

    @Test("Runtime can discover models before a profile has selected one")
    func discoveryBeforeModelSelection() async throws {
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"fixture-model"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1"
        )

        let models = try await runtime.discoverModels(configuration: configuration)

        #expect(models.map(\.id) == ["fixture-model"])
    }

    @Test("China cloud presets dispatch through the shared compatible dialect")
    func compatibleChinaProviderDispatch() async throws {
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"deepseek-fixture"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: FixtureAssistantCredentialStorage(value: "fixture-secret")
        )
        let configuration = AssistantProviderConfiguration(
            kind: .deepSeek,
            model: "deepseek-fixture"
        )

        let models = try await runtime.discoverModels(configuration: configuration)

        #expect(models.map(\.id) == ["deepseek-fixture"])
        let request = try #require(await transport.requests().first)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
    }

    @MainActor
    @Test("Model discovery cannot overwrite a provider selected while discovery is in flight")
    func staleModelDiscoveryIsIgnored() async throws {
        let runtime = DelayedSettingsAssistantRuntime()
        let manager = FixtureAssistantSettingsManager()
        let viewModel = AssistantSettingsViewModel(
            manager: manager,
            credentialStorage: EmptyAssistantCredentialStorage(),
            runtime: runtime
        )

        viewModel.fetchModels()
        for _ in 0 ..< 500 {
            if await runtime.hasStarted {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await runtime.hasStarted)

        viewModel.selectProvider(.openAICompatible)
        await runtime.complete(with: [
            AssistantModel(id: "stale-ollama-model", displayName: "Stale Ollama Model"),
        ])
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(viewModel.configuration.kind == .openAICompatible)
        #expect(viewModel.models.isEmpty)
        #expect(!viewModel.isBusy)
        #expect(!viewModel.isRefreshingProviderModels)
    }

    @MainActor
    @Test("Model availability detail matches local and remote providers")
    func modelAvailabilityDetailMatchesProvider() {
        let viewModel = AssistantSettingsViewModel(
            manager: FixtureAssistantSettingsManager(),
            credentialStorage: EmptyAssistantCredentialStorage(),
            runtime: DelayedSettingsAssistantRuntime()
        )

        #expect(viewModel.availableModelsDetail.contains("local downloads"))

        viewModel.selectProvider(.openAICompatible)

        #expect(!viewModel.availableModelsDetail.contains("local downloads"))
        #expect(viewModel.availableModelsDetail.contains(AssistantProviderKind.openAICompatible.title))
    }

    @Test("Anthropic rejects a non-2xx streaming response with a typed error")
    func anthropicStreamRejectsHTTPFailure() async throws {
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"{"error":{"message":"unauthorized"}}"#],
                statusCode: 401
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "claude-fixture"))) { error in
            #expect(error == .authentication)
        }
    }

    @Test("Anthropic stream without message_stop fails instead of presenting partial output")
    func anthropicStreamRejectsPrematureEOF() async throws {
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [
                    #"data: {"type":"message_start","message":{"id":"msg_partial"}}"#,
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}"#,
                ]
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "claude-fixture"))) { error in
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, got \(error)")
                return
            }
        }
    }

    @Test("Gemini rejects a non-2xx streaming response with a typed error")
    func geminiStreamRejectsHTTPFailure() async throws {
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"{"error":{"message":"unauthorized"}}"#],
                statusCode: 401
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "gemini-fixture"))) { error in
            #expect(error == .authentication)
        }
    }

    @Test("Gemini stream without a finish reason fails instead of presenting partial output")
    func geminiStreamRejectsPrematureEOF() async throws {
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}"#]
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "gemini-fixture"))) { error in
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private func fixtureRequest(model: String) -> AssistantCompletionRequest {
        AssistantCompletionRequest(
            instructions: "System fixture",
            input: "User fixture",
            model: model,
            maxOutputTokens: 321,
            storeResponse: false
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<AssistantStreamEvent, Error>
    )
        async throws -> [AssistantStreamEvent]
    {
        var events: [AssistantStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func expectStreamFailure(
        _ stream: AsyncThrowingStream<AssistantStreamEvent, Error>,
        _ validate: (AssistantProviderError) -> Void
    )
        async
    {
        do {
            for try await _ in stream {}
            Issue.record("Expected the stream to fail before completing normally")
        } catch let error as AssistantProviderError {
            validate(error)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - NativeProviderFixtureTransport

private actor NativeProviderFixtureTransport: AssistantHTTPTransport {
    // MARK: Lifecycle

    init(data: Data, lines: [String], statusCode: Int = 200) {
        fixtureData = data
        fixtureLines = lines
        self.statusCode = statusCode
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        return try (fixtureData, response(for: request))
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        capturedRequests.append(request)
        let response = try response(for: request)
        let fixtureLines = fixtureLines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in fixtureLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return AssistantHTTPStream(response: response, lines: stream)
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }

    // MARK: Private

    private let fixtureData: Data
    private let fixtureLines: [String]
    private let statusCode: Int
    private var capturedRequests: [URLRequest] = []

    private func response(for request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: nil
        ))
    }
}

// MARK: - EmptyAssistantCredentialStorage

private struct EmptyAssistantCredentialStorage: AssistantCredentialStorage {
    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        nil
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixtureAssistantCredentialStorage

private struct FixtureAssistantCredentialStorage: AssistantCredentialStorage {
    let value: String

    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        value
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixtureAssistantSettingsManager

@MainActor
private final class FixtureAssistantSettingsManager: AssistantSettingsManaging {
    var settings = AppSettings()

    func updateAssistantConfiguration(
        _ configuration: AssistantProviderConfiguration?,
        enabled: Bool?
    ) {
        settings.assistantProviderConfiguration = configuration
        if let enabled {
            settings.debugAssistantModelAccessEnabled = enabled
        }
    }

    func selectAssistantConfiguration(_ configurationID: UUID) {
        settings.activeAssistantProviderID = configurationID
    }

    func removeAssistantConfiguration(_ configurationID: UUID) {
        settings.assistantProviderConfigurations.removeAll { $0.id == configurationID }
    }
}

// MARK: - DelayedSettingsAssistantRuntime

private actor DelayedSettingsAssistantRuntime: AssistantProviderRuntimeProtocol {
    // MARK: Internal

    var hasStarted = false

    func discoverModels(
        configuration _: AssistantProviderConfiguration
    )
        async throws -> [AssistantModel]
    {
        hasStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            discoveryContinuation = continuation
        }
    }

    func testConnection(
        configuration: AssistantProviderConfiguration
    )
        async throws -> AssistantConnectionTestResult
    {
        AssistantConnectionTestResult(
            provider: configuration.kind.title,
            endpointHost: configuration.endpointHost,
            model: configuration.model,
            discoveredModelCount: 0
        )
    }

    func stream(
        request _: AssistantCompletionRequest,
        configuration _: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(with models: [AssistantModel]) {
        discoveryContinuation?.resume(returning: models)
        discoveryContinuation = nil
    }

    // MARK: Private

    private var discoveryContinuation: CheckedContinuation<[AssistantModel], Error>?
}
