import Foundation

// MARK: - AssistantLocalRuntimeIntegrationTier

/// How deeply Rockxy integrates with a local inference runtime. The tier describes
/// Rockxy's integration depth only; it is not a quality ranking of the runtimes.
enum AssistantLocalRuntimeIntegrationTier: String, CaseIterable, Equatable, Sendable {
    /// Rockxy can check the runtime, list, download, and remove models through its native API.
    case managed
    /// A named preset whose default endpoint and setup steps are documented and verified.
    case optimized
    /// Works through the OpenAI-compatible adapter with a documented default endpoint.
    case compatible
}

// MARK: - AssistantLocalRuntimePreset

/// A provider-neutral preset for a local inference runtime. Presets only seed an
/// `AssistantProviderConfiguration` (kind, base URL, and a provider-neutral preset
/// identity); every non-Ollama runtime still goes through the same editable
/// OpenAI-compatible endpoint and existing endpoint security.
struct AssistantLocalRuntimePreset: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    private init(id: ID) {
        self.id = id
        switch id {
        case .ollama:
            name = "Ollama"
            integrationTier = .managed
            providerKind = .ollama
            defaultBaseURL = "http://127.0.0.1:11434"
            apiSurface = "Ollama native API"
            setupSummary = String(
                localized: "Install Ollama and keep it running. Rockxy checks the runtime, lists installed models, and can download or remove models for you.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://docs.ollama.com/api")
            managesModelDownloads = true
        case .lmStudio:
            name = "LM Studio"
            integrationTier = .optimized
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:1234/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Load a model in LM Studio, start its local server from the Developer tab, then pick the loaded model here.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://lmstudio.ai/docs/developer/openai-compat")
            managesModelDownloads = false
        case .llamaCppServer:
            name = "llama.cpp server"
            integrationTier = .optimized
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:8080/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Run llama-server with a GGUF model. The model list reflects whatever the server loaded at launch.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md")
            managesModelDownloads = false
        case .jan:
            name = "Jan"
            integrationTier = .compatible
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:1337/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Start the local API server from Jan's settings and enable the model you want to use.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://jan.ai/docs/desktop/api-server")
            managesModelDownloads = false
        case .localAI:
            name = "LocalAI"
            integrationTier = .compatible
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:8080/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Run LocalAI with at least one installed model and keep its API reachable on this Mac.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://localai.io/docs/getting-started/models/")
            managesModelDownloads = false
        case .mlxLMServer:
            name = "MLX-LM server"
            integrationTier = .compatible
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:8080/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Run mlx_lm.server with a model on Apple silicon. Enter the model name manually if the server does not list it.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://github.com/ml-explore/mlx-lm")
            managesModelDownloads = false
        case .gpt4All:
            name = "GPT4All"
            integrationTier = .compatible
            providerKind = .openAICompatible
            defaultBaseURL = "http://127.0.0.1:4891/v1"
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Enable the local API server in GPT4All settings and load a model before connecting.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = URL(string: "https://docs.gpt4all.io/gpt4all_api_server/home.html")
            managesModelDownloads = false
        case .openAICompatible:
            name = String(localized: "Other OpenAI-compatible runtime", bundle: RockxyLocalization.bundle)
            integrationTier = .compatible
            providerKind = .openAICompatible
            defaultBaseURL = nil
            apiSurface = "OpenAI-compatible Chat Completions API"
            setupSummary = String(
                localized: "Enter the base URL of any runtime that serves the Chat Completions API on this Mac or over HTTPS.",
                bundle: RockxyLocalization.bundle
            )
            documentationURL = nil
            managesModelDownloads = false
        }
    }

    // MARK: Internal

    /// Stable identifier. Never rename existing values; UI selection and tests key on them.
    enum ID: String, CaseIterable, Codable, Equatable, Sendable {
        case ollama
        case lmStudio
        case llamaCppServer
        case jan
        case localAI
        case mlxLMServer
        case gpt4All
        case openAICompatible
    }

    /// Recomputed on access so runtime language changes refresh the localized summaries.
    static var all: [AssistantLocalRuntimePreset] {
        ID.allCases.map(AssistantLocalRuntimePreset.init(id:))
    }

    let id: ID
    let name: String
    let integrationTier: AssistantLocalRuntimeIntegrationTier
    let providerKind: AssistantProviderKind
    /// Documented default base URL, or `nil` when the runtime has no single documented default.
    let defaultBaseURL: String?
    let apiSurface: String
    let setupSummary: String
    let documentationURL: URL?
    /// Whether Rockxy can download and remove models through the runtime itself.
    let managesModelDownloads: Bool

    static func preset(id: ID) -> AssistantLocalRuntimePreset {
        AssistantLocalRuntimePreset(id: id)
    }

    /// Resolves the preset a saved configuration was most likely created from.
    ///
    /// Ollama configurations always map to the Ollama preset. OpenAI-compatible
    /// configurations map to a named preset only when the base URL matches exactly one
    /// documented default; endpoints shared by several runtimes (for example port 8080)
    /// stay unresolved so the UI never mislabels a runtime. Any other OpenAI-compatible
    /// endpoint resolves to the generic preset.
    static func matching(_ configuration: AssistantProviderConfiguration) -> AssistantLocalRuntimePreset? {
        switch configuration.kind {
        case .ollama:
            return preset(id: .ollama)
        case .openAICompatible:
            if let savedID = configuration.localRuntimePresetID {
                let savedPreset = preset(id: savedID)
                if savedPreset.providerKind == configuration.kind {
                    return savedPreset
                }
            }
            guard let endpoint = configuration.endpointURL else {
                return preset(id: .openAICompatible)
            }
            let candidates = all.filter { preset in
                preset.providerKind == .openAICompatible
                    && preset.id != .openAICompatible
                    && preset.defaultEndpointURL.map { Self.isSameEndpoint($0, endpoint) } == true
            }
            switch candidates.count {
            case 0: return preset(id: .openAICompatible)
            case 1: return candidates[0]
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Builds a fresh configuration seeded from this preset. Only `kind` and `baseURL`
    /// come from the preset; the model stays empty until the runtime reports one.
    func makeConfiguration(id: UUID = UUID()) -> AssistantProviderConfiguration {
        AssistantProviderConfiguration(
            id: id,
            kind: providerKind,
            baseURL: defaultBaseURL,
            localRuntimePresetID: self.id
        )
    }

    /// Applies this preset's kind and default base URL to an existing configuration.
    /// The model is cleared only when the target runtime changes so an edited endpoint
    /// never silently keeps a model ID from a different runtime.
    func applied(to configuration: AssistantProviderConfiguration) -> AssistantProviderConfiguration {
        var updated = configuration
        if id == .openAICompatible, updated.kind == .openAICompatible {
            updated.localRuntimePresetID = id
            return updated
        }
        let baseURL = defaultBaseURL ?? providerKind.defaultBaseURL
        let changed = updated.kind != providerKind || updated.baseURL != baseURL
        updated.kind = providerKind
        updated.baseURL = baseURL
        updated.localRuntimePresetID = id
        if changed {
            updated.model = ""
        }
        return updated
    }

    // MARK: Private

    private var defaultEndpointURL: URL? {
        defaultBaseURL.flatMap(URL.init(string:))
    }

    private static func isSameEndpoint(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedHost(lhs.host) == normalizedHost(rhs.host)
            && lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.port == rhs.port
            && normalizedPath(lhs.path) == normalizedPath(rhs.path)
    }

    private static func normalizedHost(_ host: String?) -> String {
        let value = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? ""
        return value == "localhost" || value == "::1" ? "127.0.0.1" : value
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}
