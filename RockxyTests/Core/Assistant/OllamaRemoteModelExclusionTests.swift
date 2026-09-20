import Foundation
@testable import Rockxy
import Testing

// MARK: - OllamaRemoteModelExclusionTests

struct OllamaRemoteModelExclusionTests {
    @Test("Cloud tags are recognized only from the tag portion of the model ID")
    func cloudTagDetection() {
        #expect(OllamaAssistantProvider.denotesCloudModel(id: "gpt-oss:120b-cloud"))
        #expect(OllamaAssistantProvider.denotesCloudModel(id: "qwen3.5:cloud"))
        #expect(OllamaAssistantProvider.denotesCloudModel(id: "GLM-4.6:Cloud"))
        #expect(OllamaAssistantProvider.denotesCloudModel(id: "registry.example/team/model:397b-cloud"))

        #expect(!OllamaAssistantProvider.denotesCloudModel(id: "qwen3.5:4b"))
        #expect(!OllamaAssistantProvider.denotesCloudModel(id: "cloud-notes:latest"))
        #expect(!OllamaAssistantProvider.denotesCloudModel(id: "my-cloud-model:7b"))
        #expect(!OllamaAssistantProvider.denotesCloudModel(id: "cloud"))
        #expect(!OllamaAssistantProvider.denotesCloudModel(id: "qwen3.5:cloudy"))
    }

    @Test("Remote host or remote model metadata marks an inventory item as remote")
    func remoteMetadataDetection() {
        #expect(OllamaAssistantProvider.isRemoteInventoryItem(
            id: "qwen3.5:4b",
            remoteHost: "https://ollama.com",
            remoteModel: nil
        ))
        #expect(OllamaAssistantProvider.isRemoteInventoryItem(
            id: "qwen3.5:4b",
            remoteHost: nil,
            remoteModel: "qwen3.5:397b"
        ))
        #expect(!OllamaAssistantProvider.isRemoteInventoryItem(
            id: "qwen3.5:4b",
            remoteHost: "",
            remoteModel: "   "
        ))
        #expect(!OllamaAssistantProvider.isRemoteInventoryItem(
            id: "qwen3.5:4b",
            remoteHost: nil,
            remoteModel: nil
        ))
    }

    @Test("Discovery drops remote-backed inventory items and keeps local models")
    func discoveryExcludesRemoteModels() async throws {
        let transport = OllamaRemoteFixtureTransport()
        let provider = try OllamaAssistantProvider(
            baseURL: #require(URL(string: "http://127.0.0.1:11434")),
            transport: transport
        )

        let models = try await provider.discoverModels()

        #expect(models.map(\.id) == ["qwen3.5:4b", "my-cloud-model:7b"])
        #expect(await transport.shownModelIDs() == ["qwen3.5:4b", "my-cloud-model:7b"])
    }

    @Test("Connection test refuses a remote-backed model even when Ollama lists it")
    func connectionTestRejectsRemoteModel() async throws {
        let transport = OllamaRemoteFixtureTransport()
        let provider = try OllamaAssistantProvider(
            baseURL: #require(URL(string: "http://127.0.0.1:11434")),
            transport: transport
        )

        do {
            _ = try await provider.testConnection(model: "gpt-oss:120b-cloud")
            Issue.record("Expected the cloud model to be rejected")
        } catch let error as AssistantProviderError {
            #expect(error == .modelNotFound("gpt-oss:120b-cloud"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.shownModelIDs().isEmpty)

        #expect(try await provider.testConnection(model: "qwen3.5:4b") == 2)
    }
}

// MARK: - OllamaRemoteFixtureTransport

private actor OllamaRemoteFixtureTransport: AssistantHTTPTransport {
    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw AssistantProviderError.invalidEndpoint
        }
        switch url.path {
        case "/api/tags":
            return (Data(Self.tagsJSON.utf8), response)
        case "/api/show":
            if let body = request.httpBody,
               let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
               let model = object["model"] as? String
            {
                shown.append(model)
            }
            return (
                Data(#"{"capabilities":["completion"],"model_info":{"qwen3.context_length":32768}}"#.utf8),
                response
            )
        default:
            throw AssistantProviderError.invalidEndpoint
        }
    }

    func lines(for _: URLRequest) async throws -> AssistantHTTPStream {
        throw AssistantProviderError.invalidEndpoint
    }

    func shownModelIDs() -> [String] {
        shown
    }

    // MARK: Private

    private static let tagsJSON = """
    {"models":[
      {"name":"qwen3.5:4b","size":3400000000,"details":{"parameter_size":"4B","quantization_level":"Q4_K_M"}},
      {"name":"gpt-oss:120b-cloud","size":0,"remote_host":"https://ollama.com","remote_model":"gpt-oss:120b"},
      {"name":"kimi-k2:cloud","size":0},
      {"name":"private-mirror:7b","size":4000000000,"remote_host":"http://10.0.0.5:11434"},
      {"name":"my-cloud-model:7b","size":4000000000,"remote_host":"","remote_model":""}
    ]}
    """

    private var shown: [String] = []
}
