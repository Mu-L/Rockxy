import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// MARK: - MainContentCoordinator + Project Transfer

/// Native import/export orchestration for the public config-only
/// `.rockxyproject` format. Import is always non-destructive: it previews the
/// categories, creates a new Project, and never replaces existing capture data.
extension MainContentCoordinator {
    @discardableResult
    func exportActiveProjectConfiguration() -> Bool {
        exportProjectConfiguration(id: projectStore.activeProjectID)
    }

    /// Exports the Project selected by a management surface. Only the active
    /// Project needs a pre-export workspace flush; inactive Projects already hold
    /// their last durable Traffic Tab snapshot in the catalog.
    @discardableResult
    func exportProjectConfiguration(id: UUID) -> Bool {
        guard projectStore.isMutable,
              let project = projectStore.projects.first(where: { $0.id == id }) else
        {
            return false
        }
        if id == projectStore.activeProjectID, !flushProjectTabSnapshot() {
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rockxyProject]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeProjectFileStem(project.name)).rockxyproject"
        panel
            .message =
            String(
                localized: "Exports tabs, filters, and layout only. Captured traffic is excluded. Filter text may be sensitive; review it before sharing."
            )
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            // Resolve again after the modal panel returns. Project lifecycle
            // actions are synchronous on the main actor, but this keeps the
            // selected identity authoritative if a future presentation changes.
            guard let currentProject = projectStore.projects.first(where: { $0.id == id }) else {
                return false
            }
            try PortableProjectDocument.write(currentProject, to: url)
            activeToast = ToastMessage(
                style: .success,
                text: String(localized: "Exported Project configuration")
            )
            return true
        } catch {
            presentProjectTransferError(
                title: String(localized: "Project Export Failed"),
                error: error
            )
            return false
        }
    }

    @discardableResult
    func importProjectConfiguration() -> Bool {
        guard !isClearingSession else {
            lastProjectOperationError = .captureClearInProgress
            return false
        }
        guard projectStore.canCreateProject else {
            lastProjectOperationError = .capacityReached(limit: projectStore.maxProjects)
            return false
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.rockxyProject, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a configuration-only .rockxyproject file")
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            let portable = try PortableProjectDocument.read(from: url)
            guard confirmPortableProjectImport(portable, fileName: url.lastPathComponent) else {
                return false
            }
            guard !isClearingSession else {
                lastProjectOperationError = .captureClearInProgress
                return false
            }
            cacheActiveProjectCaptureState()
            guard flushProjectTabSnapshot() else {
                return false
            }
            _ = try projectStore.importProject(portable)
            activateCurrentProject()
            lastProjectOperationError = nil
            activeToast = ToastMessage(
                style: .success,
                text: String(localized: "Imported \(portable.name) as a new Project")
            )
            return true
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            presentProjectTransferError(title: String(localized: "Project Import Failed"), error: error)
            return false
        } catch {
            presentProjectTransferError(title: String(localized: "Project Import Failed"), error: error)
            return false
        }
    }

    // MARK: Private

    private func confirmPortableProjectImport(_ portable: PortableProject, fileName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Import \(portable.name) as a New Project?")
        alert.informativeText = String(
            localized: "\(fileName) contains \(portable.tabs.count) traffic tab(s), user-authored filter text, host/path patterns, and layout preferences. It contains no captured traffic, bodies, headers, cookies, scripts, or local file paths. Filter text may be sensitive. Existing Projects will not be replaced."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func safeProjectFileStem(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let components = name.components(separatedBy: invalid).filter { !$0.isEmpty }
        let stem = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Rockxy-Project" : stem
    }

    private func presentProjectTransferError(title: String, error: Error) {
        Self.logger.error("Project transfer failed: \(String(describing: error))")
        let alert = NSAlert()
        alert.messageText = title
        alert
            .informativeText =
            String(localized: "The Project configuration could not be processed safely. \(String(describing: error))")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
