import Foundation

// MARK: - DebugAssistantEngine

/// Deterministic first layer for Debug Assistant. It only reasons over immutable captured values.
struct DebugAssistantEngine {
    // MARK: Internal

    func investigate(
        recipe: DebugAssistantRecipe,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        throws -> InvestigationResult
    {
        guard let primary = selected.first else {
            throw DebugAssistantEngineError.noSelection
        }

        return switch recipe {
        case .explainRequest:
            explainRequest(primary: primary, selected: selected, session: session)
        case .explainFailure:
            explainFailure(primary: primary, selected: selected, session: session)
        case .compareWithSuccess:
            compareWithSuccess(primary: primary, selected: selected, session: session)
        case .checkAuthentication:
            checkAuthentication(primary: primary, selected: selected, session: session)
        case .prepareBugReport:
            prepareBugReport(primary: primary, selected: selected, session: session)
        }
    }

    // MARK: Private

    private func explainRequest(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let scope = boundedScope(
            primary: primary,
            selected: selected,
            related: nearbyTransactions(to: primary, in: session)
        )
        var evidence = [InvestigationEvidence(
            id: "flow:\(primary.id):request.identity",
            kind: .observed,
            title: "\(primary.request.method) \(requestTarget(primary))",
            detail: String(localized: "Captured request method and destination.", bundle: RockxyLocalization.bundle),
            sourceTransactionID: primary.id
        )]

        if let response = primary.response {
            evidence.append(InvestigationEvidence(
                id: "flow:\(primary.id):response.status",
                kind: .observed,
                title: "HTTP \(response.statusCode) \(response.statusMessage)",
                detail: String(localized: "Captured response status.", bundle: RockxyLocalization.bundle),
                sourceTransactionID: primary.id
            ))
        } else {
            evidence.append(InvestigationEvidence(
                id: "flow:\(primary.id):response.unavailable",
                kind: .unknown,
                title: String(localized: "No completed response was captured", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Rockxy cannot confirm the request outcome from this transaction.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if primary.request.method.caseInsensitiveCompare("CONNECT") == .orderedSame {
            evidence.append(InvestigationEvidence(
                id: "flow:\(primary.id):protocol.connect",
                kind: .derived,
                title: String(localized: "CONNECT opens a proxy tunnel", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "The CONNECT exchange establishes a tunnel; application HTTPS payloads belong to traffic inside that tunnel.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))

            let tunnelWasEstablished = primary.statusCode.map { (200 ..< 300).contains($0) } == true
                && !primary.isFailed
            return InvestigationResult(
                recipe: .explainRequest,
                selectedTransactionID: primary.id,
                scopeTransactionIDs: scope.map(\.id),
                scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
                summary: tunnelWasEstablished
                    ? String(
                        localized: "This CONNECT request established a proxy tunnel to \(connectTarget(primary)).",
                        bundle: RockxyLocalization.bundle
                    )
                    :
                    String(
                        localized: "This CONNECT request asked the proxy to open a tunnel to \(connectTarget(primary)).",
                        bundle: RockxyLocalization.bundle
                    ),
                evidence: evidence,
                nextStep: tunnelWasEstablished
                    ? String(
                        localized: "No CONNECT failure is shown. Inspect the HTTPS requests inside this tunnel only if the app still behaved unexpectedly.",
                        bundle: RockxyLocalization.bundle
                    )
                    :
                    String(
                        localized: "Inspect the captured status and transport state to determine why the tunnel was not established.",
                        bundle: RockxyLocalization.bundle
                    )
            )
        }

        let outcome = if let status = primary.statusCode {
            if primary.isSuccessful {
                String(
                    localized: "The captured response was HTTP \(status), so Rockxy shows a completed request.",
                    bundle: RockxyLocalization.bundle
                )
            } else {
                String(localized: "The captured response was HTTP \(status).", bundle: RockxyLocalization.bundle)
            }
        } else {
            String(
                localized: "Rockxy did not capture a completed response for this request.",
                bundle: RockxyLocalization.bundle
            )
        }

        return InvestigationResult(
            recipe: .explainRequest,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: String(
                localized: "This \(primary.request.method) request targets \(requestTarget(primary)). \(outcome)",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence,
            nextStep: primary.isSuccessful
                ?
                String(
                    localized: "No failure is proven by this exchange. Open Details only if you want to inspect headers, timing, or payloads.",
                    bundle: RockxyLocalization.bundle
                )
                :
                String(
                    localized: "Open Details to inspect the response, timing, and nearby requests before drawing a conclusion.",
                    bundle: RockxyLocalization.bundle
                )
        )
    }

    private func explainFailure(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let related = nearbyTransactions(to: primary, in: session)
        let scope = boundedScope(primary: primary, selected: selected, related: related)
        let repeated = scope.filter {
            $0.request.host == primary.request.host
                && $0.request.method == primary.request.method
                && $0.request.path == primary.request.path
        }
        var evidence: [InvestigationEvidence] = []

        if let response = primary.response {
            evidence.append(.init(
                id: "flow:\(primary.id):response.status",
                kind: .observed,
                title: "HTTP \(response.statusCode)",
                detail: String(
                    localized: "Captured response status \(response.statusMessage).",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        } else {
            evidence.append(.init(
                id: "flow:\(primary.id):response.unavailable",
                kind: .unknown,
                title: String(localized: "No completed response was captured", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Rockxy cannot inspect response headers or payload for this request.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if let retryAfter = primary.responseHeader(named: "Retry-After")?.value {
            evidence.append(.init(
                id: "flow:\(primary.id):response.header.retry-after",
                kind: .observed,
                title: String(localized: "Retry-After: \(retryAfter)", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "The response explicitly supplied a retry delay.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if repeated.count > 1 {
            let interval = repeated.map(\.timestamp).max().map {
                $0.timeIntervalSince(repeated.map(\.timestamp).min() ?? $0)
            } ?? 0
            evidence.append(.init(
                id: "scope:repeated-requests",
                kind: .derived,
                title: String(
                    localized: "\(repeated.count) similar requests in \(formatDuration(interval))",
                    bundle: RockxyLocalization.bundle
                ),
                detail: String(
                    localized: "Same host, method, and path in the bounded investigation scope.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if let duration = primary.duration, duration >= 1 {
            evidence.append(.init(
                id: "flow:\(primary.id):timing.total",
                kind: .observed,
                title: String(localized: "Completed in \(formatDuration(duration))", bundle: RockxyLocalization.bundle),
                detail: String(localized: "Captured total request duration.", bundle: RockxyLocalization.bundle),
                sourceTransactionID: primary.id
            ))
        }

        if primary.statusCode == 429 {
            evidence.append(.init(
                id: "flow:\(primary.id):inference.rate-limit",
                kind: .inferred,
                title: String(localized: "Rate limiting is the leading hypothesis", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "HTTP 429 and nearby repeated requests support this hypothesis; application policy remains unknown.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.retry-policy",
                kind: .unknown,
                title: String(localized: "Application retry policy is not visible", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Captured traffic cannot confirm whether the client retries automatically.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if primary.response?.bodyTruncated == true {
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.truncated-response",
                kind: .unknown,
                title: String(localized: "Response body is incomplete", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Rockxy withholds body-level conclusions because capture truncated the response.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .explainFailure,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: failureSummary(primary, repeatedCount: repeated.count),
            evidence: evidence,
            nextStep: nextStepForFailure(primary)
        )
    }

    private func compareWithSuccess(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let explicitComparison = selected.dropFirst().first
        let nearbySuccess = nearbyTransactions(to: primary, in: session).first {
            $0.isSuccessful
                && $0.request.method == primary.request.method
                && $0.request.path == primary.request.path
        }
        guard let comparison = explicitComparison ?? nearbySuccess else {
            return InvestigationResult(
                recipe: .compareWithSuccess,
                selectedTransactionID: primary.id,
                scopeTransactionIDs: [primary.id],
                scopeSummary: String(localized: "Selected request", bundle: RockxyLocalization.bundle),
                summary: String(
                    localized: "No comparable successful request was found in the current session.",
                    bundle: RockxyLocalization.bundle
                ),
                evidence: [InvestigationEvidence(
                    id: "flow:\(primary.id):unknown.comparison",
                    kind: .unknown,
                    title: String(localized: "Successful baseline unavailable", bundle: RockxyLocalization.bundle),
                    detail: String(
                        localized: "Capture another request with the same method and path, or select exactly two requests.",
                        bundle: RockxyLocalization.bundle
                    ),
                    sourceTransactionID: primary.id
                )],
                nextStep: String(
                    localized: "Select a successful request with the same method and path, then run Compare again.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }

        var evidence = [
            InvestigationEvidence(
                id: "flow:\(primary.id):comparison.status",
                kind: .observed,
                title: String(
                    localized: "Selected: HTTP \(primary.statusCode.map(String.init) ?? "—")",
                    bundle: RockxyLocalization.bundle
                ),
                detail: primary.request.host + primary.request.path,
                sourceTransactionID: primary.id
            ),
            InvestigationEvidence(
                id: "flow:\(comparison.id):comparison.status",
                kind: .observed,
                title: String(
                    localized: "Baseline: HTTP \(comparison.statusCode.map(String.init) ?? "—")",
                    bundle: RockxyLocalization.bundle
                ),
                detail: comparison.request.host + comparison.request.path,
                sourceTransactionID: comparison.id
            ),
        ]

        if let selectedDuration = primary.duration, let baselineDuration = comparison.duration {
            let difference = selectedDuration - baselineDuration
            evidence.append(.init(
                id: "scope:comparison.duration",
                kind: .derived,
                title: difference >= 0
                    ? String(
                        localized: "Selected request was \(formatDuration(difference)) slower",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(
                        localized: "Selected request was \(formatDuration(abs(difference))) faster",
                        bundle: RockxyLocalization.bundle
                    ),
                detail: String(
                    localized: "Difference between captured total durations.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        let selectedHeaderNames = Set(primary.request.headers.map { $0.name.lowercased() })
        let comparisonHeaderNames = Set(comparison.request.headers.map { $0.name.lowercased() })
        let missing = comparisonHeaderNames.subtracting(selectedHeaderNames).sorted()
        if !missing.isEmpty {
            evidence.append(.init(
                id: "scope:comparison.request-headers",
                kind: .derived,
                title: String(
                    localized: "\(missing.count) baseline request headers are absent",
                    bundle: RockxyLocalization.bundle
                ),
                detail: missing.prefix(4).joined(separator: ", "),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .compareWithSuccess,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: [primary.id, comparison.id],
            scopeSummary: String(localized: "2 compared requests", bundle: RockxyLocalization.bundle),
            summary: String(
                localized: "The selected request differs from a captured successful baseline.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence,
            nextStep: String(
                localized: "Open the selected request in Compose and review every change before sending.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    private func checkAuthentication(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let scope = boundedScope(
            primary: primary,
            selected: selected,
            related: nearbyTransactions(to: primary, in: session)
        )
        let hasAuthorization = primary.requestHeader(named: "Authorization") != nil
        let hasCookie = primary.requestHeader(named: "Cookie") != nil
        var evidence: [InvestigationEvidence] = []

        if hasAuthorization {
            evidence.append(.init(
                id: "flow:\(primary.id):request.header.authorization",
                kind: .observed,
                title: String(localized: "Authorization header is present", bundle: RockxyLocalization.bundle),
                detail: String(localized: "The credential value remains hidden.", bundle: RockxyLocalization.bundle),
                sourceTransactionID: primary.id
            ))
        } else if hasCookie {
            evidence.append(.init(
                id: "flow:\(primary.id):request.header.cookie",
                kind: .observed,
                title: String(localized: "Cookie-based credentials may be present", bundle: RockxyLocalization.bundle),
                detail: String(localized: "Cookie values remain hidden.", bundle: RockxyLocalization.bundle),
                sourceTransactionID: primary.id
            ))
        } else {
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.authentication-input",
                kind: .unknown,
                title: String(localized: "No common credential header was captured", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Authentication may use a query value, body field, client certificate, or external state.",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }

        if let status = primary.statusCode, status == 401 || status == 403 {
            evidence.append(.init(
                id: "flow:\(primary.id):response.status.auth",
                kind: .observed,
                title: String(localized: "Server returned HTTP \(status)", bundle: RockxyLocalization.bundle),
                detail: status == 401
                    ? String(localized: "The request was not authenticated.", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "The authenticated identity may not have permission.",
                        bundle: RockxyLocalization.bundle
                    ),
                sourceTransactionID: primary.id
            ))
            if hasAuthorization || hasCookie {
                evidence.append(.init(
                    id: "flow:\(primary.id):inference.auth-rejected",
                    kind: .inferred,
                    title: String(
                        localized: "Credential rejection or insufficient scope is likely",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "A credential signal was present, but captured traffic cannot verify its validity or server-side policy.",
                        bundle: RockxyLocalization.bundle
                    ),
                    sourceTransactionID: primary.id
                ))
            }
        }

        if let challenge = primary.responseHeader(named: "WWW-Authenticate")?.value {
            evidence.append(.init(
                id: "flow:\(primary.id):response.header.www-authenticate",
                kind: .observed,
                title: String(localized: "Authentication challenge captured", bundle: RockxyLocalization.bundle),
                detail: bounded(challenge, characters: 160),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .checkAuthentication,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: authenticationSummary(primary, hasCredentialSignal: hasAuthorization || hasCookie),
            evidence: evidence,
            nextStep: String(
                localized: "Compare the credential scheme and required scope without exposing the credential value.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    private func prepareBugReport(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let scope = boundedScope(
            primary: primary,
            selected: selected,
            related: nearbyTransactions(to: primary, in: session)
        )
        var evidence = [InvestigationEvidence(
            id: "flow:\(primary.id):bug-report.request",
            kind: .observed,
            title: "\(primary.request.method) \(primary.request.path)",
            detail: primary.request.host,
            sourceTransactionID: primary.id
        )]
        if let status = primary.statusCode {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.status",
                kind: .observed,
                title: String(localized: "HTTP \(status) response", bundle: RockxyLocalization.bundle),
                detail: primary.response?.statusMessage ?? String(
                    localized: "Captured response",
                    bundle: RockxyLocalization.bundle
                ),
                sourceTransactionID: primary.id
            ))
        }
        if let clientApp = primary.clientApp {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.client",
                kind: .observed,
                title: String(localized: "Captured from \(clientApp)", bundle: RockxyLocalization.bundle),
                detail: String(localized: "Client attribution reported by Rockxy.", bundle: RockxyLocalization.bundle),
                sourceTransactionID: primary.id
            ))
        }
        if let rule = primary.matchedRuleName {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.rule",
                kind: .observed,
                title: String(localized: "Rule affected this request: \(rule)", bundle: RockxyLocalization.bundle),
                detail: primary
                    .matchedRuleActionSummary ?? String(
                        localized: "Review the matched rule before sharing.",
                        bundle: RockxyLocalization.bundle
                    ),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .prepareBugReport,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: String(
                localized: "Rockxy prepared a bounded evidence package for this captured failure.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence,
            nextStep: String(
                localized: "Review the exact redacted payload before copying or sharing any evidence.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    private func nearbyTransactions(
        to primary: InvestigationTransactionSnapshot,
        in session: [InvestigationTransactionSnapshot]
    )
        -> [InvestigationTransactionSnapshot]
    {
        session
            .filter { $0.id != primary.id && $0.request.host == primary.request.host }
            .sorted {
                abs($0.timestamp.timeIntervalSince(primary.timestamp))
                    < abs($1.timestamp.timeIntervalSince(primary.timestamp))
            }
    }

    private func boundedScope(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        related: [InvestigationTransactionSnapshot]
    )
        -> [InvestigationTransactionSnapshot]
    {
        var values: [InvestigationTransactionSnapshot] = [primary]
        let candidates = Array(selected.dropFirst()) + related
        for candidate in candidates where !values.contains(where: { $0.id == candidate.id }) {
            values.append(candidate)
            if values.count == InvestigationContextLimits.default.maxTransactions {
                break
            }
        }
        return values
    }

    private func failureSummary(_ primary: InvestigationTransactionSnapshot, repeatedCount: Int) -> String {
        switch primary.statusCode {
        case 429:
            if repeatedCount > 1 {
                return String(
                    localized: "Server returned HTTP 429 after repeated requests.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "Server returned HTTP 429 for the selected request.",
                bundle: RockxyLocalization.bundle
            )
        case let status? where status >= 500:
            return String(
                localized: "Server returned HTTP \(status) for the selected request.",
                bundle: RockxyLocalization.bundle
            )
        case 401,
             403:
            return String(
                localized: "The selected request was rejected by an authentication or authorization check.",
                bundle: RockxyLocalization.bundle
            )
        case let status? where status >= 400:
            return String(
                localized: "Server returned HTTP \(status) for the selected request.",
                bundle: RockxyLocalization.bundle
            )
        case nil where primary.isFailed:
            return String(
                localized: "The selected request failed before a completed response was captured.",
                bundle: RockxyLocalization.bundle
            )
        default:
            return String(
                localized: "Rockxy found no captured HTTP failure status for the selected request.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func authenticationSummary(
        _ primary: InvestigationTransactionSnapshot,
        hasCredentialSignal: Bool
    )
        -> String
    {
        if primary.statusCode == 401 {
            return hasCredentialSignal
                ? String(
                    localized: "A credential signal was present, but the server did not authenticate it.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "The server requested authentication and no common credential header was captured.",
                    bundle: RockxyLocalization.bundle
                )
        }
        if primary.statusCode == 403 {
            return String(
                localized: "The server denied access; captured traffic cannot verify the required permission policy.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Rockxy found no captured 401 or 403 response for this request.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func nextStepForFailure(_ primary: InvestigationTransactionSnapshot) -> String {
        if primary.request.method.caseInsensitiveCompare("CONNECT") == .orderedSame,
           primary.statusCode.map({ (200 ..< 300).contains($0) }) == true,
           !primary.isFailed
        {
            return String(
                localized: "No CONNECT failure is shown. Inspect the tunneled HTTPS requests only if the app still behaved unexpectedly.",
                bundle: RockxyLocalization.bundle
            )
        }
        switch primary.statusCode {
        case 401:
            return primary.requestHeader(named: "Authorization") != nil
                ? String(
                    localized: "Refresh or replace the credential, then retry the request.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Add the required authentication credential, then retry the request.",
                    bundle: RockxyLocalization.bundle
                )
        case 403:
            return String(
                localized: "Check that the credential has permission for this endpoint, then retry the request.",
                bundle: RockxyLocalization.bundle
            )
        case 429:
            return primary.responseHeader(named: "Retry-After") != nil
                ? String(
                    localized: "Wait for the server-specified Retry-After delay, then retry the request once.",
                    bundle: RockxyLocalization.bundle
                )
                : String(localized: "Wait briefly, then retry the request once.", bundle: RockxyLocalization.bundle)
        case let status? where status >= 500:
            return String(
                localized: "Retry once. If it fails again, compare the server response with a successful request.",
                bundle: RockxyLocalization.bundle
            )
        default:
            return String(
                localized: "Open the request details and check the highlighted evidence.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func requestTarget(_ transaction: InvestigationTransactionSnapshot) -> String {
        let path = transaction.request.path
        return path.isEmpty || path == "/"
            ? transaction.request.host
            : transaction.request.host + path
    }

    private func connectTarget(_ transaction: InvestigationTransactionSnapshot) -> String {
        "\(transaction.request.host):\(transaction.request.url.port ?? 443)"
    }

    private func scopeSummary(selectedCount: Int, requestCount: Int) -> String {
        if selectedCount > 1 {
            return String(localized: "\(selectedCount) selected requests", bundle: RockxyLocalization.bundle)
        }
        let relatedCount = max(0, requestCount - 1)
        return relatedCount == 0
            ? String(localized: "Selected request", bundle: RockxyLocalization.bundle)
            : String(
                localized: "Selected request + \(relatedCount) related requests",
                bundle: RockxyLocalization.bundle
            )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1_000)
        }
        return String(format: "%.2f s", duration)
    }

    private func bounded(_ value: String, characters: Int) -> String {
        guard value.count > characters else {
            return value
        }
        return String(value.prefix(characters)) + "…"
    }
}

// MARK: - DebugAssistantEngineError

enum DebugAssistantEngineError: LocalizedError, Equatable {
    case noSelection

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noSelection:
            String(localized: "Select at least one request to investigate.", bundle: RockxyLocalization.bundle)
        }
    }
}
