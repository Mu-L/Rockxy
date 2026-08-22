import Foundation
@testable import Rockxy
import Testing

@Suite("TrafficCaptureContext")
struct TrafficCaptureContextTests {
    @Test("lock-backed store publishes complete snapshots")
    func storeSnapshots() {
        let first = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 1)
        let second = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 2)
        let store = TrafficCaptureContextStore(first)

        #expect(store.snapshot() == first)
        store.update(second)
        #expect(store.snapshot() == second)
        store.update(nil)
        #expect(store.snapshot() == nil)
    }

    @Test("transaction inherits request-start ownership and cannot be reassigned")
    func transactionOwnershipIsStable() throws {
        let original = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 4)
        let replacement = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 9)
        let request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://example.com")),
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil,
            captureContext: original
        )
        let transaction = HTTPTransaction(request: request)

        transaction.assignCaptureContextIfMissing(replacement)

        #expect(transaction.captureContext == original)
    }

    @Test("single-argument script mutation preserves request-start ownership")
    func scriptContextPreservesOwnership() throws {
        let context = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 3)
        var request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://example.com/one")),
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil,
            captureContext: context
        )
        var script = ScriptRequestContext(from: request)
        script.method = "POST"

        script.apply(to: &request, pluginID: "test.capture-context")

        #expect(request.method == "POST")
        #expect(request.captureContext == context)
    }

    @Test("runtime ownership is excluded from portable session JSON")
    func ownershipIsNotSerialized() throws {
        let context = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 7)
        let request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://example.com")),
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil,
            captureContext: context
        )
        let transaction = HTTPTransaction(request: request)
        let data = try JSONEncoder().encode(CodableTransaction(from: transaction))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains(context.projectID.uuidString))
        #expect(!json.contains(context.sessionID.uuidString))
        #expect(!json.contains("captureContext"))
    }
}
