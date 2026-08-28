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
        Task { @MainActor in
            do {
                let response = try await RequestReplay.replay(transaction.request)
                Self.logger.info("Replay completed: \(response.statusCode)")
                activeToast = ToastMessage(
                    style: .success,
                    text: String(
                        localized: "Replay completed — \(response.statusCode)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } catch {
                Self.logger.error("Replay failed: \(error.localizedDescription)")
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

    func editAndReplaySelectedRequest() {
        guard let transaction = selectedTransaction else {
            return
        }
        editAndReplayTransaction(transaction)
    }
}
