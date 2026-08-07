import Foundation
@testable import Rockxy
import Testing

// MARK: - DebugAssistantWorkspaceHelpTests

/// Context-free, workspace-aware product help: current-count questions answered from an
/// aggregate-only `AssistantWorkspaceSummary` without ever attaching captured traffic.
@MainActor
@Suite(.serialized)
struct DebugAssistantWorkspaceHelpTests {
    // MARK: Internal

    @Test("A current-count question with no selection answers from live workspace state, context-free")
    func currentCountQuestionAnsweredFromWorkspaceState() throws {
        let coordinator = MainContentCoordinator(assistantSettingsProvider: { AppSettings() })
        let transactions = (0 ..< 3).map { TestFixtures.makeTransaction(url: "https://api.example.com/req-\($0)") }
        coordinator.transactions = transactions
        coordinator.filteredTransactions = transactions
        coordinator.activeWorkspace.debugAssistantDraft = "how many request we have now?"

        coordinator.sendDebugAssistantMessage()

        let reply = try #require(coordinator.activeWorkspace.debugAssistantMessages.last)
        #expect(reply.role == .assistant)
        #expect(reply.investigation == nil)
        #expect(reply.productHandoff == nil)
        #expect(reply.text.contains("3"))
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext == nil)
        #expect(coordinator.activeWorkspace.debugAssistantReviewPack == nil)
    }

    @Test("A visible count that differs from the retained total is reported without opening Review Data")
    func visibleCountDiffersFromRetained() throws {
        let coordinator = MainContentCoordinator(assistantSettingsProvider: { AppSettings() })
        let transactions = (0 ..< 5).map { TestFixtures.makeTransaction(url: "https://api.example.com/req-\($0)") }
        coordinator.transactions = transactions
        coordinator.filteredTransactions = [transactions[0], transactions[1]]
        coordinator.activeWorkspace.debugAssistantDraft = "how many requests do we have now?"

        coordinator.sendDebugAssistantMessage()

        let reply = try #require(coordinator.activeWorkspace.debugAssistantMessages.last)
        #expect(reply.text.contains("2"))
        #expect(reply.text.contains("5"))
        #expect(coordinator.activeWorkspace.debugAssistantReviewPack == nil)
    }

    @Test("A capability-limit question is not answered as a live count and stays a product answer")
    func capabilityQuestionNotAnsweredAsCount() throws {
        let coordinator = MainContentCoordinator(assistantSettingsProvider: { AppSettings() })
        let transactions = (0 ..< 4).map { TestFixtures.makeTransaction(url: "https://api.example.com/req-\($0)") }
        coordinator.transactions = transactions
        coordinator.filteredTransactions = transactions
        coordinator.activeWorkspace.debugAssistantDraft = "How many requests can Rockxy handle?"

        coordinator.sendDebugAssistantMessage()

        let reply = try #require(coordinator.activeWorkspace.debugAssistantMessages.last)
        #expect(!reply.text.contains("4"))
        #expect(reply.investigation == nil)
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext == nil)
    }

    @Test("A workspace answer keeps context nil, then a later selection starts a normal investigation")
    func workspaceAnswerThenSelectionInvestigates() async throws {
        let coordinator = MainContentCoordinator(assistantSettingsProvider: { AppSettings() })
        let transaction = TestFixtures.makeTransaction(statusCode: 500)
        coordinator.transactions = [transaction]
        coordinator.filteredTransactions = [transaction]
        coordinator.activeWorkspace.debugAssistantDraft = "number of requests"

        coordinator.sendDebugAssistantMessage()
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext == nil)

        coordinator.newDebugAssistantConversation()
        coordinator.selectedTransactionIDs = [transaction.id]
        coordinator.selectTransaction(transaction)
        coordinator.activeWorkspace.debugAssistantDraft = "Why did this fail?"
        coordinator.sendDebugAssistantMessage()
        try await waitUntil {
            if case .result = coordinator.activeWorkspace.debugAssistantState {
                return true
            }
            return false
        }
        #expect(coordinator.activeWorkspace.debugAssistantMessages.last?.investigation != nil)
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext?.primaryTransactionID == transaction.id)
    }

    @Test("A configured-model workspace request carries aggregate facts and no seeded request content")
    func configuredModelWorkspaceRequestCarriesOnlyAggregateFacts() async throws {
        let recorder = WorkspaceHelpRuntimeRecorder()
        let runtime = WorkspaceHelpFixtureRuntime(recorder: recorder, includeToolCall: true)
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://127.0.0.1:1234/v1",
            model: "fixture-model"
        )
        let coordinator = MainContentCoordinator(
            assistantRuntime: runtime,
            assistantSettingsProvider: { Self.makeSettings(configuration: configuration) }
        )
        let seeded = TestFixtures.makeTransaction(url: "https://seed-secret-host.example/private/endpoint")
        seeded.response?.headers = [HTTPHeader(name: "X-Seed-Token", value: "seed-secret-value")]
        coordinator.transactions = [seeded]
        coordinator.filteredTransactions = [seeded]
        ComposeStore.shared.pendingTransaction = nil
        let composeVersion = ComposeStore.shared.draftVersion
        coordinator.activeWorkspace.debugAssistantDraft = "how many requests do we have now?"

        coordinator.sendDebugAssistantMessage()
        try await waitUntil {
            coordinator.activeWorkspace.debugAssistantMessages.count == 2
        }

        let reply = try #require(coordinator.activeWorkspace.debugAssistantMessages.last)
        #expect(reply.modelResult?.blockedToolCallCount == 1)
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext == nil)
        #expect(ComposeStore.shared.draftVersion == composeVersion)
        #expect(ComposeStore.shared.pendingTransaction == nil)

        let request = try #require(await recorder.request)
        #expect(request.instructions.contains("<workspace_facts>"))
        #expect(request.instructions.contains("retained_requests: 1"))
        let review = request.reviewedContentPreview
        #expect(!review.contains("seed-secret-host"))
        #expect(!review.contains("seed-secret-value"))
        #expect(!review.contains("private/endpoint"))
        #expect(!review.contains(seeded.id.uuidString))
    }

    @Test("Empty model output falls back to the deterministic workspace answer")
    func emptyModelOutputFallsBackToWorkspaceAnswer() async throws {
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://127.0.0.1:1234/v1",
            model: "fixture-model"
        )
        let coordinator = MainContentCoordinator(
            assistantRuntime: EmptyWorkspaceHelpRuntime(),
            assistantSettingsProvider: { Self.makeSettings(configuration: configuration) }
        )
        let transactions = (0 ..< 3).map { TestFixtures.makeTransaction(url: "https://api.example.com/req-\($0)") }
        coordinator.transactions = transactions
        coordinator.filteredTransactions = transactions
        coordinator.activeWorkspace.debugAssistantDraft = "how many requests do we have now?"

        coordinator.sendDebugAssistantMessage()
        try await waitUntil {
            coordinator.activeWorkspace.debugAssistantMessages.count == 2
        }

        let reply = try #require(coordinator.activeWorkspace.debugAssistantMessages.last)
        #expect(reply.text.contains("3"))
        #expect(coordinator.activeWorkspace.debugAssistantProductHelpState == .idle)
        #expect(coordinator.activeWorkspace.debugAssistantConversationContext == nil)
    }

    // MARK: Private

    private static func makeSettings(configuration: AssistantProviderConfiguration) -> AppSettings {
        var settings = AppSettings()
        settings.assistantProviderConfiguration = configuration
        settings.debugAssistantModelAccessEnabled = true
        return settings
    }

    private func waitUntil(
        attempts: Int = 500,
        condition: @MainActor () -> Bool
    )
        async throws
    {
        for _ in 0 ..< attempts {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw WorkspaceHelpTestTimeout()
    }
}

// MARK: - WorkspaceHelpTestTimeout

private struct WorkspaceHelpTestTimeout: Error {}

// MARK: - WorkspaceHelpRuntimeRecorder

private actor WorkspaceHelpRuntimeRecorder {
    var request: AssistantCompletionRequest?

    func record(_ request: AssistantCompletionRequest) {
        self.request = request
    }
}

// MARK: - WorkspaceHelpFixtureRuntime

private struct WorkspaceHelpFixtureRuntime: AssistantProviderRuntimeProtocol {
    let recorder: WorkspaceHelpRuntimeRecorder
    var includeToolCall = false

    func discoverModels(configuration: AssistantProviderConfiguration) async throws -> [AssistantModel] {
        [AssistantModel(id: configuration.model, displayName: configuration.model)]
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
            discoveredModelCount: 1
        )
    }

    func stream(
        request: AssistantCompletionRequest,
        configuration _: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    {
        await recorder.record(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(responseID: "workspace-help"))
            continuation.yield(.textDelta("There "))
            continuation.yield(.textDelta("is 1 request."))
            if includeToolCall {
                continuation.yield(.toolCallCompleted(AssistantToolCall(
                    id: "blocked-action",
                    name: "replay_request",
                    arguments: #"{"transaction_id":"all"}"#
                )))
            }
            continuation.yield(.usage(AssistantUsage(inputTokens: 8, outputTokens: 3, cachedInputTokens: 0)))
            continuation.yield(.completed(responseID: "workspace-help"))
            continuation.finish()
        }
    }
}

// MARK: - EmptyWorkspaceHelpRuntime

/// Streams a completed response with no text deltas so the empty-output fallback can be exercised.
private struct EmptyWorkspaceHelpRuntime: AssistantProviderRuntimeProtocol {
    func discoverModels(configuration: AssistantProviderConfiguration) async throws -> [AssistantModel] {
        [AssistantModel(id: configuration.model, displayName: configuration.model)]
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
            discoveredModelCount: 1
        )
    }

    func stream(
        request _: AssistantCompletionRequest,
        configuration _: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(responseID: "empty-response"))
            continuation.yield(.completed(responseID: "empty-response"))
            continuation.finish()
        }
    }
}
