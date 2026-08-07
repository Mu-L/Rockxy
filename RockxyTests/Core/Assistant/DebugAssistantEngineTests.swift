import Foundation
@testable import Rockxy
import Testing

@MainActor
struct DebugAssistantEngineTests {
    // MARK: Internal

    @Test("A successful CONNECT is explained as an established tunnel, not a failed request")
    func explainSuccessfulConnect() throws {
        let transaction = makeTransaction(
            method: "CONNECT",
            url: "https://api.apple-cloudkit.com:443",
            statusCode: 200,
            statusMessage: "Connection Established"
        )
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainRequest,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.summary.contains("established a proxy tunnel"))
        #expect(!result.summary.localizedCaseInsensitiveContains("failed"))
        #expect(result.evidence.contains { $0.id.contains("protocol.connect") && $0.kind == .derived })
        #expect(result.nextStep.contains("No CONNECT failure is shown"))
    }

    @Test("Generic questions explain the request while explicit failure questions use failure analysis")
    func naturalLanguageIntentRouting() {
        #expect(DebugAssistantRecipe.suggestedRecipe(for: "what's that?") == .explainRequest)
        #expect(DebugAssistantRecipe.suggestedRecipe(for: "explain this request") == .explainRequest)
        #expect(DebugAssistantRecipe.suggestedRecipe(for: "why did this fail?") == .explainFailure)
    }

    @Test("429 investigation separates observed, derived, inferred, and unknown evidence")
    func explainRateLimit() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let primary = makeTransaction(
            timestamp: base,
            statusCode: 429,
            responseHeaders: [HTTPHeader(name: "Retry-After", value: "20")]
        )
        let related = (1 ... 3).map { offset in
            makeTransaction(timestamp: base.addingTimeInterval(Double(offset)), statusCode: 429)
        }
        let snapshots = ([primary] + related).map(InvestigationTransactionSnapshot.init(transaction:))

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshots[0]],
            session: snapshots
        )

        #expect(result.scopeTransactionIDs.count == 4)
        #expect(result.summary.contains("429"))
        #expect(result.evidence.contains { $0.kind == .observed && $0.title == "Retry-After: 20" })
        #expect(result.evidence.contains { $0.kind == .derived && $0.title.contains("similar requests") })
        #expect(result.evidence.contains { $0.kind == .inferred && $0.title.contains("Rate limiting") })
        #expect(result.evidence.contains { $0.kind == .unknown && $0.title.contains("retry policy") })
    }

    @Test("Comparison uses an explicitly selected successful baseline")
    func compareExplicitBaseline() throws {
        let failed = makeTransaction(statusCode: 500)
        failed.measuredDuration = 1.5
        let successful = makeTransaction(statusCode: 200)
        successful.measuredDuration = 0.25
        let selected = [failed, successful].map(InvestigationTransactionSnapshot.init(transaction:))

        let result = try DebugAssistantEngine().investigate(
            recipe: .compareWithSuccess,
            selected: selected,
            session: selected
        )

        #expect(result.scopeTransactionIDs == [failed.id, successful.id])
        #expect(result.evidence.contains { $0.kind == .derived && $0.title.contains("slower") })
        #expect(result.scopeSummary == "2 compared requests")
    }

    @Test("Authentication investigation never exposes credential values")
    func authenticationValueStaysHidden() throws {
        let transaction = makeTransaction(
            statusCode: 401,
            requestHeaders: [HTTPHeader(name: "Authorization", value: "Bearer synthetic-secret")],
            responseHeaders: [HTTPHeader(name: "WWW-Authenticate", value: "Bearer realm=api")]
        )
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .checkAuthentication,
            selected: [snapshot],
            session: [snapshot]
        )
        let renderedEvidence = result.evidence.map { $0.title + $0.detail }.joined()

        #expect(renderedEvidence.contains("Authorization header is present"))
        #expect(!renderedEvidence.contains("synthetic-secret"))
        #expect(result.evidence.contains { $0.kind == .inferred })
    }

    @Test("A 401 with a captured credential points the user at refreshing it, never exposing the value")
    func failureNextStep401WithAuthorization() throws {
        let transaction = makeTransaction(
            statusCode: 401,
            requestHeaders: [HTTPHeader(name: "Authorization", value: "Bearer synthetic-secret")]
        )
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.nextStep == "Refresh or replace the credential, then retry the request.")
        #expect(!result.nextStep.contains("synthetic-secret"))
    }

    @Test("A 401 without a captured credential asks the user to add one")
    func failureNextStep401WithoutAuthorization() throws {
        let transaction = makeTransaction(statusCode: 401)
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.nextStep == "Add the required authentication credential, then retry the request.")
    }

    @Test("A 403 next step is framed as a permission check, not a comparison")
    func failureNextStep403() throws {
        let transaction = makeTransaction(statusCode: 403)
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result
            .nextStep == "Check that the credential has permission for this endpoint, then retry the request.")
    }

    @Test("A 429 with Retry-After tells the user to wait for the server delay without leaking the value")
    func failureNextStep429WithRetryAfter() throws {
        let transaction = makeTransaction(
            statusCode: 429,
            responseHeaders: [HTTPHeader(name: "Retry-After", value: "20")]
        )
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.nextStep == "Wait for the server-specified Retry-After delay, then retry the request once.")
        #expect(!result.nextStep.contains("20"))
    }

    @Test("A 429 without Retry-After tells the user to wait briefly then retry once")
    func failureNextStep429WithoutRetryAfter() throws {
        let transaction = makeTransaction(statusCode: 429)
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.nextStep == "Wait briefly, then retry the request once.")
    }

    @Test("A 5xx next step is a single retry with a fallback comparison")
    func failureNextStep5xx() throws {
        let transaction = makeTransaction(statusCode: 503)
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result
            .nextStep == "Retry once. If it fails again, compare the server response with a successful request.")
    }

    @Test("A non-auth, non-rate-limit failure falls back to opening request details")
    func failureNextStepFallback() throws {
        let transaction = makeTransaction(statusCode: 404)
        let snapshot = InvestigationTransactionSnapshot(transaction: transaction)

        let result = try DebugAssistantEngine().investigate(
            recipe: .explainFailure,
            selected: [snapshot],
            session: [snapshot]
        )

        #expect(result.nextStep == "Open the request details and check the highlighted evidence.")
    }

    // MARK: Private

    private func makeTransaction(
        timestamp: Date = Date(),
        method: String = "POST",
        url: String = "https://api.example.com/v1/responses",
        statusCode: Int,
        statusMessage: String? = nil,
        requestHeaders: [HTTPHeader] = [],
        responseHeaders: [HTTPHeader] = []
    )
        -> HTTPTransaction
    {
        guard let requestURL = URL(string: url) else {
            preconditionFailure("Invalid test URL: \(url)")
        }
        let request = HTTPRequestData(
            method: method,
            url: requestURL,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: nil
        )
        let response = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusMessage ?? (statusCode == 200 ? "OK" : "Error"),
            headers: responseHeaders,
            body: nil
        )
        return HTTPTransaction(
            timestamp: timestamp,
            request: request,
            response: response,
            state: .completed
        )
    }
}
