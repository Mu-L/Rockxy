import Foundation

// MARK: - MainContentCoordinator + Project Presentation

extension MainContentCoordinator {
    func presentNewProjectEditor() {
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return
        }
        guard projectStore.canCreateProject else {
            lastProjectOperationError = .capacityReached(limit: projectStore.maxProjects)
            return
        }
        projectNameEditorContext = ProjectNameEditorContext(
            mode: .create,
            initialName: nextUntakenProjectName()
        )
    }

    func presentRenameProjectEditor(id: UUID) {
        guard let project = projectStore.projects.first(where: { $0.id == id }) else {
            lastProjectOperationError = .projectNotFound
            return
        }
        projectNameEditorContext = ProjectNameEditorContext(
            mode: .rename(project.id),
            initialName: project.name
        )
    }

    func requestProjectDeletion(_ project: Project) {
        projectDeletionRequest = ProjectDeletionRequest(
            projectID: project.id,
            projectName: project.name
        )
    }

    var projectOperationErrorMessage: String? {
        guard let error = lastProjectOperationError else {
            return nil
        }
        return switch error {
        case let .nameInvalid(reason):
            switch reason {
            case .empty:
                String(localized: "Enter a Project name.")
            case .containsControlCharacters:
                String(localized: "Project names cannot contain control characters.")
            case let .tooLong(count):
                String(
                    localized: "Project names are limited to \(ProjectStructuralLimits.nameGraphemeRange.upperBound) characters (received \(count))."
                )
            case .notCanonical:
                String(localized: "The Project name is not in canonical Unicode form.")
            }
        case .duplicateName:
            String(localized: "A Project with this name already exists.")
        case let .capacityReached(limit):
            String(localized: "This build supports up to \(limit) Projects.")
        case let .tabCapacityReached(limit):
            String(localized: "A Project can contain up to \(limit) Traffic Tabs in this build.")
        case .projectNotFound:
            String(localized: "The selected Project no longer exists.")
        case .cannotDeleteFinalProject:
            String(localized: "Rockxy must keep at least one Project.")
        case .captureClearInProgress:
            String(localized: "Wait for the active Project capture to finish clearing, then try again.")
        case .storeNotReady:
            String(localized: "Projects are not ready. Retry loading the catalog first.")
        case .revisionExhausted:
            String(localized: "The Project catalog revision limit was reached.")
        case .invalidTabSnapshot:
            String(
                localized: "A Traffic Tab contains an invalid name or filter configuration. Rename or simplify that tab, then try again."
            )
        case .reconciledProjectsInvalid:
            String(localized: "The reconciled Projects were structurally invalid and were not applied.")
        case .staleRevision:
            String(localized: "Projects changed since this update was prepared. Try again.")
        }
    }

    var projectPersistenceWarningMessage: String? {
        guard case .failed = projectStore.loadState else {
            return nil
        }
        return String(
            localized: "Projects could not be loaded. Traffic Tab and filter changes will not be saved until Projects are repaired."
        )
    }

    private func nextUntakenProjectName() -> String {
        let base = String(localized: "New Project")
        let used = Set(projectStore.projects.map {
            ProjectNormalization.foldedKey(for: $0.name)
        })
        if !used.contains(ProjectNormalization.foldedKey(for: base)) {
            return base
        }
        for number in 2 ... projectStore.maxProjects + 1 {
            let candidate = "\(base) \(number)"
            if !used.contains(ProjectNormalization.foldedKey(for: candidate)) {
                return candidate
            }
        }
        return base
    }
}
