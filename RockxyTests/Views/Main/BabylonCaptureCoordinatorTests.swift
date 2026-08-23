import Foundation
@testable import Rockxy
import Testing

@MainActor
@Suite("Babylon capture coordinator")
struct BabylonCaptureCoordinatorTests {
    @Test("Connection identity creates source-filtered workspace once")
    func createsSourceWorkspaceOnce() async {
        let coordinator = MainContentCoordinator()
        let sessionID = UUID().uuidString
        let identity = BabylonCaptureIdentity(
            clientID: "client",
            sessionID: sessionID,
            projectName: "Checkout",
            bundleIdentifier: "com.example.checkout",
            deviceName: "Test iPhone",
            deviceModel: "iPhone"
        )

        await coordinator.registerBabylonCapture(identity: identity)
        await coordinator.registerBabylonCapture(identity: identity)

        #expect(coordinator.workspaceStore.workspaces.count == 2)
        #expect(coordinator.activeWorkspace.title == "Checkout • Test iPhone")
        #expect(coordinator.activeWorkspace.filterCriteria.sidebarApp == "Checkout • Test iPhone")
    }
}
