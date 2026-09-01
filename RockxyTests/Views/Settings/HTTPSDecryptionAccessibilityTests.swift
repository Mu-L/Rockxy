import Foundation
import Testing

// MARK: - HTTPSDecryptionAccessibilityTests

struct HTTPSDecryptionAccessibilityTests {
    @Test("HTTPS Decryption icon controls expose complete accessibility labels")
    func managementControlsHaveLabels() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/SSLProxyingListView.swift")

        #expect(source.contains(
            #".accessibilityLabel(String(localized: "Add Application…", bundle: RockxyLocalization.bundle))"#
        ))
        #expect(source.contains(
            #".accessibilityLabel(String(localized: "Add Rule", bundle: RockxyLocalization.bundle))"#
        ))
        #expect(source.contains(
            #".accessibilityLabel(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle))"#
        ))
        #expect(source.contains("Choose an application, host pattern, or observed hosts."))
    }

    @Test("Encrypted CONNECT application behavior menu describes its action")
    func connectBehaviorMenuHasLabelAndHint() throws {
        let source = try readProjectFile("Rockxy/Views/Inspector/HTTPSInspectionPromptView.swift")

        #expect(source.contains(".accessibilityLabel(scope.actionDescription)"))
        #expect(source.contains("Choose Decrypt or Tunnel behavior for new application connections."))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var projectRoot = URL(fileURLWithPath: #filePath)
        while projectRoot.lastPathComponent != "RockxyTests", projectRoot.path != "/" {
            projectRoot.deleteLastPathComponent()
        }
        projectRoot.deleteLastPathComponent()
        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
