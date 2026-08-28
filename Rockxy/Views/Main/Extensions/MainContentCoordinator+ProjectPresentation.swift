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
                String(localized: "Enter a Project name.", bundle: RockxyLocalization.bundle)
            case .containsControlCharacters:
                String(localized: "Project names cannot contain control characters.", bundle: RockxyLocalization.bundle)
            case let .tooLong(count):
                String(
                    localized: "Project names are limited to \(ProjectStructuralLimits.nameGraphemeRange.upperBound) characters (received \(count)).",
                    bundle: RockxyLocalization.bundle
                )
            case .notCanonical:
                String(
                    localized: "The Project name is not in canonical Unicode form.",
                    bundle: RockxyLocalization.bundle
                )
            }
        case .duplicateName:
            String(localized: "A Project with this name already exists.", bundle: RockxyLocalization.bundle)
        case let .capacityReached(limit):
            String(localized: "This build supports up to \(limit) Projects.", bundle: RockxyLocalization.bundle)
        case let .tabCapacityReached(limit):
            String(
                localized: "A Project can contain up to \(limit) Traffic Tabs in this build.",
                bundle: RockxyLocalization.bundle
            )
        case .projectNotFound:
            String(localized: "The selected Project no longer exists.", bundle: RockxyLocalization.bundle)
        case .cannotDeleteFinalProject:
            String(localized: "Rockxy must keep at least one Project.", bundle: RockxyLocalization.bundle)
        case .captureClearInProgress:
            String(
                localized: "Wait for the active Project capture to finish clearing, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case .storeNotReady:
            String(
                localized: "Projects are not ready. Retry loading the catalog first.",
                bundle: RockxyLocalization.bundle
            )
        case .revisionExhausted:
            String(localized: "The Project catalog revision limit was reached.", bundle: RockxyLocalization.bundle)
        case .invalidTabSnapshot:
            String(
                localized: "A Traffic Tab contains an invalid name or filter configuration. Rename or simplify that tab, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case .reconciledProjectsInvalid:
            String(
                localized: "The reconciled Projects were structurally invalid and were not applied.",
                bundle: RockxyLocalization.bundle
            )
        case .staleRevision:
            String(
                localized: "Projects changed since this update was prepared. Try again.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var projectPersistenceWarningMessage: String? {
        guard case .failed = projectStore.loadState else {
            return nil
        }
        return String(
            localized: "Projects could not be loaded. Traffic Tab and filter changes will not be saved until Projects are repaired.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func nextUntakenProjectName() -> String {
        let base = String(localized: "New Project", bundle: RockxyLocalization.bundle)
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
