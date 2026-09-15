import Foundation
import os

// Extends `MainContentCoordinator` with replay behavior for the main workspace.

// MARK: - MainContentCoordinator + Replay

/// Coordinator extension for replaying captured HTTP requests against the original server.
extension MainContentCoordinator {
    // MARK: - Request Replay

    func replaySelectedRequest() {
        guard let transaction = selectedTransaction else {
            return
        }
        performReplay(for: transaction)
    }

    func performReplay(for transaction: HTTPTransaction) {
        guard Self.canReplay(transaction) else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Replay is not supported for this request type.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }
        Task { @MainActor in
            let startedAt = Date()
            do {
                let response = try await RequestReplay.replay(transaction.request)
                Self.logger.info("Replay completed: \(response.statusCode)")
                await recordReplayResult(
                    of: transaction,
                    response: response,
                    startedAt: startedAt,
                    state: .completed
                )
                activeToast = ToastMessage(
                    style: .success,
                    text: String(
                        localized: "Replay completed — \(response.statusCode)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } catch {
                Self.logger.error("Replay failed: \(error.localizedDescription)")
                await recordReplayResult(of: transaction, response: nil, startedAt: startedAt, state: .failed)
                activeToast = ToastMessage(
                    style: .error,
                    text: String(
                        localized: "Replay failed — \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
    }

    /// Appends the replay outcome to the live session as its own row so the new response can be
    /// inspected, diffed, and exported like any captured flow. The request still bypasses the
    /// proxy pipeline (no rules apply), so the row is attributed to Rockxy itself rather than to
    /// the client that sent the original.
    private func recordReplayResult(
        of original: HTTPTransaction,
        response: HTTPResponseData?,
        startedAt: Date,
        state: TransactionState
    ) async {
        guard captureRecordingGate.allowsCapture(),
              await ensureProjectCatalogReadyForDataIntake() else
        {
            return
        }

        let replay = Self.makeReplayTransaction(
            from: original,
            response: response,
            startedAt: startedAt,
            state: state
        )
        replay.assignCaptureContextIfMissing(activeCaptureContext)
        await sessionManager.addTransaction(replay)
    }

    /// Builds the session row for a replay. The request is copied without the original's
    /// capture context so the row routes to the currently active Project instead of being
    /// dropped as a stale delivery.
    nonisolated static func makeReplayTransaction(
        from original: HTTPTransaction,
        response: HTTPResponseData?,
        startedAt: Date,
        state: TransactionState,
        now: Date = Date()
    )
        -> HTTPTransaction
    {
        let source = original.request
        let request = HTTPRequestData(
            method: source.method,
            url: source.url,
            httpVersion: source.httpVersion,
            headers: source.headers,
            body: source.body,
            contentType: source.contentType
        )
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let replay = HTTPTransaction(
            timestamp: startedAt,
            request: request,
            response: response,
            state: state,
            timingInfo: TimingInfo(
                dnsLookup: 0,
                tcpConnection: 0,
                tlsHandshake: 0,
                timeToFirstByte: elapsed,
                contentTransfer: 0
            )
        )
        replay.clientApp = RockxyIdentity.current.displayName
        replay.graphQLInfo = original.graphQLInfo
        return replay
    }

    func editAndReplaySelectedRequest() {
        guard let transaction = selectedTransaction else {
            return
        }
        editAndReplayTransaction(transaction)
    }

    nonisolated static func canReplay(_ transaction: HTTPTransaction) -> Bool {
        transaction.webSocketConnection == nil
            && transaction.request.method.caseInsensitiveCompare("CONNECT") != .orderedSame
    }
}
