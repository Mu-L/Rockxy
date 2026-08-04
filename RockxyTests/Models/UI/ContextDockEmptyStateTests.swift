@testable import Rockxy
import Testing

struct ContextDockEmptyStateTests {
    @Test("Captured traffic with visible results prompts to select a request while capturing")
    func selectRequestWhileCapturing() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: true,
            hasVisibleResults: true,
            isCapturing: true
        )

        #expect(state == .selectRequest)
    }

    @Test("Captured traffic with visible results prompts to select a request while stopped")
    func selectRequestWhileStopped() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: true,
            hasVisibleResults: true,
            isCapturing: false
        )

        #expect(state == .selectRequest)
    }

    @Test("Visible workspace results are sufficient even when the global capture list is empty")
    func visibleWorkspaceResultsTakePriority() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: false,
            hasVisibleResults: true,
            isCapturing: false
        )

        #expect(state == .selectRequest)
    }

    @Test("No captured traffic while capturing explains that requests will appear")
    func waitingForTrafficWhileCapturing() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: false,
            hasVisibleResults: false,
            isCapturing: true
        )

        #expect(state == .waitingForTraffic)
    }

    @Test("No captured traffic while stopped prompts to start capture")
    func captureStoppedWithoutTraffic() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: false,
            hasVisibleResults: false,
            isCapturing: false
        )

        #expect(state == .captureStopped)
    }

    @Test("Captured traffic hidden by filters explains that nothing matches the scope")
    func filteredNoResults() {
        let state = ContextDockEmptyState.resolve(
            hasCapturedTraffic: true,
            hasVisibleResults: false,
            isCapturing: true
        )

        #expect(state == .filteredNoResults)
    }
}
