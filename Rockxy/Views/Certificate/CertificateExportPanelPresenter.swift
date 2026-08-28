import AppKit
import Foundation

// MARK: - CertificateExportPanelPresenter

@MainActor
struct CertificateExportPanelPresenter {
    // MARK: Internal

    func export(format: CertificateExportFormat) {
        Task {
            do {
                let service = CertificateExportService {
                    try await CertificateManager.shared.exportMaterial()
                }
                let payload = try await service.payload(for: format)

                guard confirmPrivateExportIfNeeded(payload) else {
                    return
                }

                guard let url = saveURL(for: format, defaultFileName: payload.defaultFileName) else {
                    return
                }

                try service.export(payload, to: url)
                if format == .rootCertificatePEM {
                    AppSettingsManager.shared.updateLastExportedRootCAPath(url.path)
                }
                showAlert(
                    title: String(localized: "Certificate Exported", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Rockxy saved the certificate export successfully.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } catch {
                showAlert(
                    title: String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: Private

    private func confirmPrivateExportIfNeeded(_ payload: CertificateExportPayload) -> Bool {
        guard payload.containsPrivateMaterial else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Export Private Certificate Material?", bundle: RockxyLocalization.bundle)
        alert.informativeText = String(
            localized: "This export includes private key material. Store it securely and only share it with people or systems you trust.",
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "Export", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func saveURL(for format: CertificateExportFormat, defaultFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = format.allowedContentTypes
        panel.canCreateDirectories = true
        panel.title = String(localized: "Export Certificate", bundle: RockxyLocalization.bundle)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }
}
