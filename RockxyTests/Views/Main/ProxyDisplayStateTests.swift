import Foundation
@testable import Rockxy
import Testing

@MainActor
struct ProxyDisplayStateTests {
    @Test("Coordinator reports stopped by default")
    func stoppedByDefault() {
        let coordinator = MainContentCoordinator()

        #expect(coordinator.proxyDisplayState == .stopped)
    }

    @Test("Coordinator reports starting while proxy startup is in flight")
    func startingDuringProxyStartup() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyStarting = true

        #expect(coordinator.proxyDisplayState == .starting)
    }

    @Test("Coordinator reports running after proxy start")
    func runningAfterProxyStart() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyRunning = true
        coordinator.isRecording = true

        #expect(coordinator.proxyDisplayState == .running)
    }

    @Test("Coordinator reports paused when proxy runs but recording is off")
    func pausedWhenRecordingOff() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyRunning = true
        coordinator.isRecording = false

        #expect(coordinator.proxyDisplayState == .paused)
    }

    @Test("Recording cannot be toggled while the proxy is stopped")
    func recordingToggleRequiresRunningProxy() {
        let coordinator = MainContentCoordinator()
        coordinator.isRecording = true

        coordinator.toggleRecording()

        #expect(coordinator.isRecording)

        coordinator.isProxyRunning = true
        coordinator.toggleRecording()

        #expect(!coordinator.isRecording)
    }

    @Test("Coordinator reports stopped after failed start clears startup state")
    func stoppedAfterFailedStart() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyStarting = false
        coordinator.isProxyRunning = false

        #expect(coordinator.proxyDisplayState == .stopped)
    }

    @Test("Capture presentation explains wildcard reachability and stopped readiness")
    func stoppedCapturePresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .stopped,
            listenAddress: "0.0.0.0",
            port: 8_888,
            certReadiness: .trusted,
            helperReadiness: .installedCompatible,
            isSystemProxyConfigured: false
        )

        #expect(presentation.title == "Capture Stopped")
        #expect(presentation.listener == "0.0.0.0:8888")
        #expect(presentation.listenerScope == "This Mac and local network")
        #expect(presentation.https.level == .ready)
        #expect(presentation.systemRouting.level == .ready)
        #expect(presentation.actionTitle == "Start Capture")
        #expect(presentation.isActionEnabled)
    }

    @Test("Running capture surfaces degraded readiness without relying on color")
    func degradedRunningCapturePresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .running,
            listenAddress: "127.0.0.1",
            port: 9_090,
            certReadiness: .installedNotTrusted,
            helperReadiness: .notInstalled,
            isSystemProxyConfigured: false
        )

        #expect(presentation.listenerScope == "This Mac only")
        #expect(presentation.https.level == .attention)
        #expect(presentation.https.value == "Root CA installed but not trusted")
        #expect(presentation.systemRouting.level == .attention)
        #expect(presentation.systemRouting.value == "Manual app setup")
        #expect(presentation.actionTitle == "Stop Capture")
    }

    @Test("Capture listener formats IPv6 endpoints without ambiguity")
    func ipv6ListenerFormatting() {
        #expect(CaptureStatusPresentation.listener(address: "::1", port: 8_888) == "[::1]:8888")
    }
}
