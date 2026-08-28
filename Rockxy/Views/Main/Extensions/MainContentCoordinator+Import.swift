import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with import behavior for the main workspace.

// MARK: - MainContentCoordinator + Import

/// Coordinator extension for importing sessions from native `.rockxysession` files
/// and HAR archives. Both flows show an `ImportReviewSheet` for user confirmation
/// before performing any destructive session replacement.
extension MainContentCoordinator {
    // MARK: - Open Session

    func openSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.rockxySession]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a .rockxysession file to open", bundle: RockxyLocalization.bundle)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxSessionFileSize
        ) {
            Self.logger.error("Session import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "Session Too Large", bundle: RockxyLocalization.bundle),
                message: sizeError.localizedDescription
            )
            return
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0

            let data = try Data(contentsOf: url)
            let session = try SessionSerializer.deserialize(from: data)

            let preview = ImportPreview(
                fileName: url.lastPathComponent,
                fileType: .rockxysession,
                transactionCount: session.transactions.count,
                logEntryCount: session.logEntries?.count ?? 0,
                fileSize: fileSize,
                captureStartDate: session.metadata.captureStartDate,
                captureEndDate: session.metadata.captureEndDate,
                rockxyVersion: session.metadata.rockxyVersion,
                sourceURL: url
            )

            importPreview = preview
        } catch let error as SessionSerializerError {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Invalid Session File", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "\"\(url.lastPathComponent)\" could not be read.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not read \"\(url.lastPathComponent)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: - Import HAR

    func importHAR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.har, .json]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a HAR file to import", bundle: RockxyLocalization.bundle)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxHARFileSize
        ) {
            Self.logger.error("HAR import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "HAR File Too Large", bundle: RockxyLocalization.bundle),
                message: sizeError.localizedDescription
            )
            return
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0

            let data = try Data(contentsOf: url)
            let importer = HARImporter()
            let importedTransactions = try importer.importData(data)

            let preview = ImportPreview(
                fileName: url.lastPathComponent,
                fileType: .har,
                transactionCount: importedTransactions.count,
                logEntryCount: 0,
                fileSize: fileSize,
                captureStartDate: nil,
                captureEndDate: nil,
                rockxyVersion: nil,
                sourceURL: url
            )

            importPreview = preview
        } catch {
            Self.logger.error("Failed to pre-parse HAR: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "HAR Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not import \"\(url.lastPathComponent)\".\n\nThe file may not be a valid HAR archive. \(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: - Execute Import

    func executeImport(_ preview: ImportPreview) {
        importPreview = nil

        Task { @MainActor in
            guard await ensureProjectCatalogReadyForDataIntake() else {
                showImportError(
                    title: String(localized: "Import Unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Projects could not be loaded. Repair Projects before importing captured traffic.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                return
            }
            switch preview.fileType {
            case .har:
                await executeHARImport(from: preview.sourceURL, fileName: preview.fileName)
            case .rockxysession:
                await executeSessionImport(from: preview.sourceURL, fileName: preview.fileName)
            }
        }
    }

    func cancelImport() {
        importPreview = nil
    }

    // MARK: - Private

    private func executeHARImport(from url: URL, fileName: String) async {
        do {
            let data = try Data(contentsOf: url)
            let importer = HARImporter()
            let importedTransactions = try importer.importData(data)

            await clearSession()
            let captureContext = activeCaptureContext

            for transaction in importedTransactions {
                transaction.assignCaptureContextIfMissing(captureContext)
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }
            transactionsByProjectID[projectStore.activeProjectID] = transactions
            nextSequenceNumberByProjectID[projectStore.activeProjectID] = nextSequenceNumber
            let overflow = max(0, transactions.count - liveHistoryLimit)
            if overflow > 0 {
                evictOldestTransactions(count: overflow)
            }
            rebuildObservedDomainsByApp()
            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)
            TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: importedTransactions.count,
                logEntryCount: 0,
                importedAt: Date()
            )
            sessionProvenanceByProjectID[projectStore.activeProjectID] = sessionProvenance

            activeToast = ToastMessage(
                style: .success,
                text: String(
                    localized: "Imported \(importedTransactions.count) transactions from \(fileName)",
                    bundle: RockxyLocalization.bundle
                )
            )

            Self.logger.info("Imported HAR from \(fileName): \(importedTransactions.count) transactions")
        } catch {
            Self.logger.error("Failed to import HAR: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "HAR Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not import \"\(fileName)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func executeSessionImport(from url: URL, fileName: String) async {
        do {
            let data = try Data(contentsOf: url)
            let session = try SessionSerializer.deserialize(from: data)

            await clearSession()
            let captureContext = activeCaptureContext

            for codableTransaction in session.transactions {
                let transaction = codableTransaction.toLiveModel()
                transaction.assignCaptureContextIfMissing(captureContext)
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }
            transactionsByProjectID[projectStore.activeProjectID] = transactions
            nextSequenceNumberByProjectID[projectStore.activeProjectID] = nextSequenceNumber
            let overflow = max(0, transactions.count - liveHistoryLimit)
            if overflow > 0 {
                evictOldestTransactions(count: overflow)
            }
            rebuildObservedDomainsByApp()

            if let codableLogEntries = session.logEntries {
                logEntries = codableLogEntries.map { $0.toLiveModel() }
            }
            let maxLogs = AppSettingsStorage.load().maxLogBufferSize
            if logEntries.count > maxLogs {
                logEntries.removeFirst(logEntries.count - maxLogs)
            }
            logEntriesByProjectID[projectStore.activeProjectID] = logEntries

            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)
            TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: session.transactions.count,
                logEntryCount: session.logEntries?.count ?? 0,
                importedAt: Date()
            )
            sessionProvenanceByProjectID[projectStore.activeProjectID] = sessionProvenance

            activeToast = ToastMessage(
                style: .success,
                text: String(
                    localized: "Opened session with \(session.transactions.count) transactions",
                    bundle: RockxyLocalization.bundle
                )
            )

            Self.logger.info("Opened session from \(fileName): \(session.transactions.count) transactions")
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not read \"\(fileName)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func showImportError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }
}
