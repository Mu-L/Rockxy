import Foundation
@testable import Rockxy
import Testing

// MARK: - MacCertificateSetupGuideViewTests

@MainActor
struct MacCertificateSetupGuideViewTests {
    // MARK: Internal

    @Test("Mac Setup Guide adopts native tool-window structure")
    func nativeToolWindowStructure() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let source = try readProjectFile("Rockxy/Views/Certificate/MacCertificateSetupGuideView.swift")

        let sceneStart = try #require(appSource.range(of: "private struct MacCertificateSetupGuideWindowScene"))
        let scenesAfter = appSource[sceneStart.lowerBound...]
        let nextScene = try #require(scenesAfter.range(of: "// MARK: - DeveloperSetupWindowScene"))
        let sceneSource = scenesAfter[..<nextScene.lowerBound]

        #expect(sceneSource.contains("String(localized: \"Mac Setup Guide\", bundle: RockxyLocalization.bundle)"))
        #expect(sceneSource.contains("id: \"certificateSetup\""))
        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(sceneSource.contains(".windowResizability(.contentMinSize)"))
        #expect(sceneSource.contains("restorationBehavior(.disabled)"))
        #expect(source.contains("@Environment(\\.appUIDisplayMetrics)"))
        #expect(source.contains("ToolWindowDisplayMetrics(appMetrics: appMetrics)"))
        #expect(!source.contains("Text(String(localized: \"Mac Setup Guide\", bundle: RockxyLocalization.bundle))"))
        #expect(!source.contains(".font(.title3"))
        #expect(!source.contains(".font(.callout"))
        #expect(!source.contains(".font(.system(size: 28"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        #expect(source.contains("ScrollView(.horizontal)"))
        #expect(source.contains(".keyboardShortcut(.defaultAction)"))
        #expect(source.contains(".keyboardShortcut(\"c\", modifiers: [.command, .shift])"))
        #expect(source.contains("NSApplication.didBecomeActiveNotification"))

        for label in ["Certificate Readiness", "Certificate Details", "Current Status"] {
            #expect(source.contains("localized: \"\(label)\""))
        }
        for label in ["Keychain Access", "Terminal"] {
            #expect(source.contains("String(localized: \"\(label)\", bundle: RockxyLocalization.bundle)"))
        }
    }

    @Test("Mac Setup Guide preserves the complete certificate workflow")
    func completeCertificateWorkflow() throws {
        let source = try readProjectFile("Rockxy/Views/Certificate/MacCertificateSetupGuideView.swift")

        for field in [
            "hasGeneratedCertificate",
            "isInstalledInKeychain",
            "hasTrustSettings",
            "isSystemTrustValidated",
            "lastValidationErrorMessage",
            "notValidBefore",
            "notValidAfter",
            "commonName",
        ] {
            #expect(source.contains(field))
        }
        for copy in ["Generate, Install & Trust", "Repair Trust", "Checking Certificate"] {
            #expect(source.contains("localized: \"\(copy)\""))
        }
        for action in ["Export PEM", "Generate Certificate", "Open Keychain Access"] {
            #expect(source.contains("localized: \"\(action)\""))
        }

        #expect(source.contains("withBundleIdentifier: \"com.apple.keychainaccess\""))
        #expect(source.contains("NSWorkspace.shared.open(url)"))
        #expect(source.contains("try await CertificateManager.shared.ensureRootCA()"))
        #expect(source.contains("CertificateManager.shared.installAndTrust()"))
        #expect(source.contains("CertificateManager.shared.rootCAStatusSnapshot(performValidation: validate)"))
        #expect(source.contains("CertificateExportPanelPresenter().export(format: .rootCertificatePEM)"))
        #expect(source.contains("NSPasteboard.general.setString(manualTrustCommand, forType: .string)"))
        #expect(source.contains("CertificateStore.rootCACertificateURL.path"))
        #expect(source.contains("RockxySettingsTab.select(.general)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
