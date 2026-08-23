@testable import Rockxy

@MainActor
extension MainContentCoordinator {
    /// Test-only convenience for production-equivalent request-start ownership.
    /// Tests that intentionally exercise stale, inactive, or missing routes call
    /// `processBatch` directly instead.
    func processActiveProjectTestBatch(
        _ batch: [HTTPTransaction],
        generation: UInt? = nil
    ) {
        let context = activeCaptureContext
        for transaction in batch {
            transaction.assignCaptureContextIfMissing(context)
        }
        processBatch(batch, generation: generation ?? sessionGeneration)
    }
}
