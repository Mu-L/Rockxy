import Foundation
@testable import Rockxy
import Testing

// Regression tests for Compose request-history snapshots and persistence.

// MARK: - ComposeHistoryTests

@MainActor
struct ComposeHistoryTests {
    // MARK: Internal

    @Test("HIST_01 recordHistorySnapshotsFullRequest")
    func recordHistorySnapshotsFullRequest() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/orders?expectedTotal=42"
        vm.syncURLToQuery(force: true)
        vm.headers = [
            EditableReplayHeader(name: "Content-Type", value: "application/json"),
            EditableReplayHeader(name: "X-Debug", value: "on", isEnabled: false),
        ]
        vm.body = #"{"expectedTotal":42}"#

        await vm.send()

        let entry = try #require(vm.history.first)
        #expect(entry.method == "POST")
        #expect(entry.url == "https://api.example.com/orders?expectedTotal=42")
        #expect(entry.headers == vm.headers)
        #expect(entry.queryItems == vm.queryItems)
        #expect(entry.body == #"{"expectedTotal":42}"#)
        #expect(entry.bodyContentType == "application/json")
        #expect(entry.statusCode == 200)
    }

    @Test("History records the request that was sent, not edits made while it was running")
    func historySnapshotsInFlightRequest() async throws {
        let releaseContinuation: AsyncStream<Void>.Continuation
        let releaseStream: AsyncStream<Void>
        (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()
        let startedContinuation: AsyncStream<Void>.Continuation
        let startedStream: AsyncStream<Void>
        (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()
        let responseURL = try #require(URL(string: "https://api.example.com/response"))
        let response = try #require(
            HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        let executor = MockComposeExecutor { _, _ in
            startedContinuation.yield()
            startedContinuation.finish()
            for await _ in releaseStream {
                break
            }
            return (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor, historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/original"
        vm.headers = [EditableReplayHeader(name: "X-Request", value: "original")]
        vm.body = #"{"value":"original"}"#

        let sendTask = Task { @MainActor in
            await vm.send()
        }
        for await _ in startedStream {
            break
        }

        vm.method = "PATCH"
        vm.url = "https://api.example.com/edited"
        vm.headers[0].value = "edited"
        vm.body = #"{"value":"edited"}"#

        releaseContinuation.yield()
        releaseContinuation.finish()
        await sendTask.value

        let entry = try #require(vm.history.first)
        #expect(entry.method == "POST")
        #expect(entry.url == "https://api.example.com/original")
        #expect(entry.headers.first?.value == "original")
        #expect(entry.body == #"{"value":"original"}"#)
    }

    @Test("HIST_02 restoreEntryRestoresMethodUrl")
    func restoreEntryRestoresMethodUrl() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "PATCH"
        vm.url = "https://api.example.com/items/1?expectedTotal=41"
        vm.syncURLToQuery(force: true)
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.method = "GET"
        vm.url = "https://api.example.com/other"
        vm.restoreHistoryEntry(id: id)

        #expect(vm.method == "PATCH")
        #expect(vm.url == "https://api.example.com/items/1?expectedTotal=41")
    }

    @Test("HIST_03 restoreEntryRestoresHeaders")
    func restoreEntryRestoresHeaders() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.url = "https://api.example.com/items"
        vm.headers = [
            EditableReplayHeader(name: "Content-Type", value: "application/json"),
            EditableReplayHeader(name: "X-Expected-Total", value: "42"),
        ]
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.headers = [EditableReplayHeader(name: "Accept", value: "text/plain")]
        vm.restoreHistoryEntry(id: id)

        #expect(vm.headers.map(\.name) == ["Content-Type", "X-Expected-Total"])
        #expect(vm.headers.map(\.value) == ["application/json", "42"])
    }

    @Test("HIST_04 restoreEntryRestoresBody")
    func restoreEntryRestoresBody() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/items"
        vm.body = #"{"expectedTotal":42}"#
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.body = #"{"expectedTotal":7}"#
        vm.restoreHistoryEntry(id: id)

        #expect(vm.body == #"{"expectedTotal":42}"#)
    }

    @Test("HIST_05 restoreEntryRestoresQueryItems")
    func restoreEntryRestoresQueryItems() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.url = "https://api.example.com/search?expectedTotal=42&mode=strict"
        vm.syncURLToQuery(force: true)
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.queryItems = [EditableQueryItem(name: "mode", value: "loose")]
        vm.restoreHistoryEntry(id: id)

        #expect(vm.queryItems.map(\.name) == ["expectedTotal", "mode"])
        #expect(vm.queryItems.map(\.value) == ["42", "strict"])
    }

    @Test("HIST_06 restoreEntryRestoresResponsePanel")
    func restoreEntryRestoresResponsePanel() async throws {
        let vm = ComposeViewModel(
            executor: successExecutor(body: #"{"ok":true}"#, headers: ["Content-Type": "application/json"]),
            historyStore: makeStore()
        )
        vm.url = "https://api.example.com/items"
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.applyTemplate(.empty)
        vm.restoreHistoryEntry(id: id)

        if case let .success(response) = vm.responseState {
            #expect(response.statusCode == 200)
            #expect(response.bodyDisplayText == #"{"ok":true}"#)
            #expect(response.headers.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        } else {
            Issue.record("Expected restored response panel")
        }
    }

    @Test("HIST_07 restoreEntryDoesNotPolluteFutureEdits")
    func restoreEntryDoesNotPolluteFutureEdits() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/items"
        vm.headers = [EditableReplayHeader(name: "X-Expected-Total", value: "42")]
        vm.body = #"{"expectedTotal":42}"#
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.restoreHistoryEntry(id: id)
        vm.headers[0].value = "7"
        vm.body = #"{"expectedTotal":7}"#

        let entry = try #require(vm.history.first)
        #expect(entry.headers[0].value == "42")
        #expect(entry.body == #"{"expectedTotal":42}"#)
    }

    @Test("HIST_08 historyDedupeOnIdenticalConsecutiveSends")
    func historyDedupeOnIdenticalConsecutiveSends() async {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/items"
        vm.body = #"{"expectedTotal":42}"#

        await vm.send()
        await vm.send()

        #expect(vm.history.count == 1)
    }

    @Test("HIST_09 historyPersistsAcrossViewModelReset")
    func historyPersistsAcrossViewModelReset() async throws {
        let store = makeStore()
        let firstVM = ComposeViewModel(executor: successExecutor(), historyStore: store)
        firstVM.method = "POST"
        firstVM.url = "https://api.example.com/items"
        firstVM.body = #"{"expectedTotal":42}"#
        await firstVM.send()

        let secondVM = ComposeViewModel(executor: successExecutor(), historyStore: store)

        let entry = try #require(secondVM.history.first)
        #expect(entry.method == "POST")
        #expect(entry.url == "https://api.example.com/items")
        #expect(entry.body == #"{"expectedTotal":42}"#)
    }

    @Test("HIST_10 historyRedactsAuthorizationHeader")
    func historyRedactsAuthorizationHeader() async throws {
        let fileURL = makeHistoryURL()
        let store = ComposeHistoryStore(fileURL: fileURL)
        let firstVM = ComposeViewModel(executor: successExecutor(), historyStore: store)
        firstVM.url = "https://api.example.com/private"
        firstVM.headers = [
            EditableReplayHeader(name: "Authorization", value: "Bearer secret"),
            EditableReplayHeader(name: "Cookie", value: "session=secret"),
            EditableReplayHeader(name: "X-API-Key", value: "api-secret"),
            EditableReplayHeader(name: "X-Trace", value: "kept"),
        ]
        await firstVM.send()

        #expect(firstVM.history[0].headers[0].value == "Bearer secret")

        let persistedData = try Data(contentsOf: fileURL)
        let persistedEntries = try JSONDecoder().decode([ComposeHistoryEntry].self, from: persistedData)
        let headers = try #require(persistedEntries.first?.headers)
        #expect(headers.first { $0.name == "Authorization" }?.value == "<redacted before saving>")
        #expect(headers.first { $0.name == "Cookie" }?.value == "<redacted before saving>")
        #expect(headers.first { $0.name == "X-API-Key" }?.value == "<redacted before saving>")
        #expect(headers.first { $0.name == "Authorization" }?.isEnabled == false)
        #expect(headers.first { $0.name == "Cookie" }?.isEnabled == false)
        #expect(headers.first { $0.name == "X-API-Key" }?.isEnabled == false)
        #expect(headers.first { $0.name == "X-Trace" }?.value == "kept")
    }

    @Test("Newest history save wins across store instances sharing one file")
    func historySaveOrderingAcrossStoreInstances() async throws {
        let fileURL = makeHistoryURL()
        let olderStore = ComposeHistoryStore(fileURL: fileURL)
        let newerStore = ComposeHistoryStore(fileURL: fileURL)
        let olderEntry = ComposeHistoryEntry(
            method: "POST",
            url: "https://api.example.com/older",
            headers: [],
            queryItems: [],
            body: String(repeating: "x", count: 8 * 1_024 * 1_024),
            bodyContentType: "text/plain",
            statusCode: 200,
            timestamp: Date()
        )

        let olderSave = Task { @MainActor in
            try await olderStore.save([olderEntry])
        }
        let observerStore = ComposeHistoryStore(fileURL: fileURL)
        while observerStore.load().first?.url != olderEntry.url {
            await Task.yield()
        }
        try await newerStore.save([])
        try await olderSave.value

        let reopenedStore = ComposeHistoryStore(fileURL: fileURL)
        #expect(reopenedStore.load().isEmpty)
        let persistedData = try Data(contentsOf: fileURL)
        let persistedEntries = try JSONDecoder().decode([ComposeHistoryEntry].self, from: persistedData)
        #expect(persistedEntries.isEmpty)
    }

    @Test("HIST_11 historyEnforcesSizeCap")
    func historyEnforcesSizeCap() async {
        let store = makeStore(maxEntries: 200)
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: store)

        for index in 0 ..< 250 {
            vm.url = "https://api.example.com/items/\(index)"
            await vm.send()
        }

        #expect(vm.history.count == 200)
        #expect(vm.history.first?.url == "https://api.example.com/items/249")
        #expect(vm.history.last?.url == "https://api.example.com/items/50")
    }

    @Test("HIST_12 historyTruncatesLargeBodies")
    func historyTruncatesLargeBodies() async throws {
        let store = makeStore()
        let largeBody = String(repeating: "x", count: 1_048_576)
        let vm = ComposeViewModel(executor: successExecutor(body: largeBody), historyStore: store)
        vm.method = "POST"
        vm.url = "https://api.example.com/large"
        vm.body = largeBody
        await vm.send()

        let inMemoryEntry = try #require(vm.history.first)
        #expect(inMemoryEntry.bodyTruncated == true)
        #expect(inMemoryEntry.responseBodyTruncated == true)
        #expect(Data(inMemoryEntry.body.utf8).count == ComposeHistoryStore.defaultBodySizeLimit)
        #expect(Data((inMemoryEntry.responseBody ?? "").utf8).count == ComposeHistoryStore.defaultBodySizeLimit)

        let reloadedVM = ComposeViewModel(executor: successExecutor(), historyStore: store)
        let entry = try #require(reloadedVM.history.first)
        #expect(entry.bodyTruncated == true)
        #expect(entry.responseBodyTruncated == true)
        #expect(Data(entry.body.utf8).count == ComposeHistoryStore.defaultBodySizeLimit)

        reloadedVM.restoreHistoryEntry(id: entry.id)
        #expect(reloadedVM.body == entry.body)
        #expect(reloadedVM.sourceHasTruncatedHistoryBody == true)
        #expect(reloadedVM.isUnsupportedForReplay == true)
        if case let .success(response) = reloadedVM.responseState {
            #expect(response.bodyTruncated == true)
        } else {
            Issue.record("Expected the truncated historical response to remain inspectable")
        }

        reloadedVM.replaceUnavailableBody(with: "complete replacement")
        #expect(reloadedVM.sourceHasTruncatedHistoryBody == false)
        #expect(reloadedVM.isUnsupportedForReplay == false)
    }

    @Test("A truncated failed request remains visibly restricted after restore")
    func failedTruncatedHistoryRemainsRestricted() async throws {
        let store = makeStore()
        let executor = MockComposeExecutor { _, _ in
            throw URLError(.timedOut)
        }
        let firstVM = ComposeViewModel(executor: executor, historyStore: store)
        firstVM.method = "POST"
        firstVM.url = "https://api.example.com/large"
        firstVM.body = String(repeating: "x", count: ComposeHistoryStore.defaultBodySizeLimit + 1)
        await firstVM.send()

        let reloadedVM = ComposeViewModel(executor: successExecutor(), historyStore: store)
        let entry = try #require(reloadedVM.history.first)
        #expect(entry.statusCode == nil)
        #expect(entry.bodyTruncated == true)

        reloadedVM.restoreHistoryEntry(id: entry.id)

        if case .empty = reloadedVM.responseState {} else {
            Issue.record("Expected failed history to keep the response pane empty")
        }
        #expect(reloadedVM.replayRestrictionMessage?.contains("shortened") == true)
        #expect(reloadedVM.isUnsupportedForReplay == true)
    }

    @Test("HIST_13 historyEntryWithDisabledHeaderRoundTrips")
    func historyEntryWithDisabledHeaderRoundTrips() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.url = "https://api.example.com/items"
        vm.headers = [
            EditableReplayHeader(name: "X-Enabled", value: "yes"),
            EditableReplayHeader(name: "X-Disabled", value: "no", isEnabled: false),
        ]
        await vm.send()
        let id = try #require(vm.history.first?.id)

        vm.headers = []
        vm.restoreHistoryEntry(id: id)

        #expect(vm.headers.count == 2)
        #expect(vm.headers[0].isEnabled == true)
        #expect(vm.headers[1].isEnabled == false)
    }

    @Test("HIST_14 webSocketSessionsExcludedFromHistory")
    func webSocketSessionsExcludedFromHistory() async {
        let transaction = TestFixtures.makeWebSocketTransaction()
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.prefill(from: transaction)

        await vm.send()

        #expect(vm.history.isEmpty)
    }

    @Test("HIST_15 restoreEntryEmitsObservableChangeForBindings")
    func restoreEntryEmitsObservableChangeForBindings() async throws {
        let vm = ComposeViewModel(executor: successExecutor(), historyStore: makeStore())
        vm.method = "POST"
        vm.url = "https://api.example.com/items"
        vm.headers = [EditableReplayHeader(name: "X-Expected-Total", value: "42")]
        vm.body = #"{"expectedTotal":42}"#
        await vm.send()
        let id = try #require(vm.history.first?.id)
        let previousConfirmationID = vm.restoreConfirmationID

        vm.method = "GET"
        vm.url = "https://api.example.com/other"
        vm.headers = []
        vm.body = ""
        vm.restoreHistoryEntry(id: id)

        #expect(vm.restoreConfirmationID != previousConfirmationID)
        #expect(vm.restoreConfirmationMessage == "Restored from history")
        #expect(vm.method == "POST")
        #expect(vm.url == "https://api.example.com/items")
        #expect(vm.headers.count == 1)
        #expect(vm.body == #"{"expectedTotal":42}"#)
    }

    // MARK: Private

    private func makeStore(
        maxEntries: Int = ComposeHistoryStore.defaultMaxEntries,
        bodySizeLimit: Int = ComposeHistoryStore.defaultBodySizeLimit
    ) -> ComposeHistoryStore {
        ComposeHistoryStore(
            fileURL: makeHistoryURL(),
            maxEntries: maxEntries,
            bodySizeLimit: bodySizeLimit
        )
    }

    private func makeHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-compose-history-\(UUID().uuidString)")
            .appendingPathComponent("compose-history.json")
    }

    private func successExecutor(
        statusCode: Int = 200,
        body: String = "ok",
        headers: [String: String] = [:]
    ) -> MockComposeExecutor {
        MockComposeExecutor { _, _ in
            let url = try #require(URL(string: "https://api.example.com/response"))
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                )
            )
            return (Data(body.utf8), response)
        }
    }
}
