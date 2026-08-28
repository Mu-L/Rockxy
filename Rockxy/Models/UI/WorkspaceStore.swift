import Foundation
import os

// Persists and coordinates workspace tabs and the active workspace selection.

@MainActor @Observable
final class WorkspaceStore {
    // MARK: Lifecycle

    init(
        maxWorkspaces: Int = 8,
        layoutPreferences: WorkspaceLayoutPreferences = WorkspaceLayoutPreferences()
    ) {
        self.maxWorkspaces = Self.clampCreationCapacity(maxWorkspaces)
        self.layoutPreferences = layoutPreferences
        let defaultWorkspace = Self.makeWorkspace(
            title: ProjectStructuralLimits.defaultTabTitle,
            isClosable: false,
            filter: .empty,
            layoutPreferences: layoutPreferences
        )
        self.workspaces = [defaultWorkspace]
        self.activeWorkspaceID = defaultWorkspace.id
    }

    // MARK: Internal

    /// Effective tab *creation* capacity. Gates new/duplicated tabs only; it never
    /// truncates hydrated tabs, which are retained up to the structural upper bound.
    /// Refreshable at runtime via ``refreshCapacity(maxWorkspaces:)``.
    private(set) var maxWorkspaces: Int

    var workspaces: [WorkspaceState]
    var activeWorkspaceID: UUID

    var activeWorkspace: WorkspaceState {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    var activeWorkspaceIndex: Int {
        workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
    }

    var canCreateWorkspace: Bool {
        workspaces.count < maxWorkspaces
    }

    /// Re-sets the effective tab *creation* capacity at runtime. Existing tabs are
    /// never closed or truncated by a lower limit; only future create/duplicate
    /// actions observe the new bound. Clamped into the structural tab range so a
    /// bad or expanded policy can never authorize creating more live tabs than the
    /// structural upper bound (which snapshot persistence would later truncate).
    func refreshCapacity(maxWorkspaces newValue: Int) {
        maxWorkspaces = Self.clampCreationCapacity(newValue)
    }

    @discardableResult
    func createWorkspace(
        title: String = String(localized: "New Tab", bundle: RockxyLocalization.bundle),
        filter: FilterCriteria = .empty
    )
        -> WorkspaceState
    {
        guard canCreateWorkspace else {
            Self.logger.warning("Maximum workspace count (\(self.maxWorkspaces)) reached")
            return activeWorkspace
        }
        guard let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(title) else {
            Self.logger.warning("Refused to create a workspace with an invalid title")
            return activeWorkspace
        }
        let workspace = Self.makeWorkspace(
            title: normalizedTitle,
            isClosable: true,
            filter: filter,
            layoutPreferences: layoutPreferences
        )
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        Self.logger.info("Created workspace: \(normalizedTitle)")
        return workspace
    }

    func closeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.isClosable else
        {
            return
        }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasActive = id == activeWorkspaceID
        workspaces.remove(at: index)

        if wasActive {
            let newIndex = min(index, workspaces.count - 1)
            activeWorkspaceID = workspaces[newIndex].id
        }
        Self.logger.info("Closed workspace: \(workspace.title)")
    }

    func selectWorkspace(id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else {
            return
        }
        activeWorkspaceID = id
    }

    func selectWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else {
            return
        }
        activeWorkspaceID = workspaces[index].id
    }

    func selectPreviousWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex > 0 ? currentIndex - 1 : workspaces.count - 1
        activeWorkspaceID = workspaces[newIndex].id
    }

    func selectNextWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex < workspaces.count - 1 ? currentIndex + 1 : 0
        activeWorkspaceID = workspaces[newIndex].id
    }

    func moveWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count,
              sourceIndex != destinationIndex else
        {
            return
        }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destinationIndex)
    }

    func reorderWorkspaces(toWorkspaceIDs orderedIDs: [UUID]) {
        guard !orderedIDs.isEmpty else {
            return
        }

        var remaining = workspaces
        var reordered: [WorkspaceState] = []
        reordered.reserveCapacity(workspaces.count)

        for id in orderedIDs {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else {
                continue
            }
            reordered.append(remaining.remove(at: index))
        }

        reordered.append(contentsOf: remaining)
        guard reordered.count == workspaces.count else {
            return
        }
        workspaces = reordered
    }

    func duplicateWorkspace(id: UUID) -> WorkspaceState? {
        guard let source = workspaces.first(where: { $0.id == id }),
              canCreateWorkspace else
        {
            return nil
        }
        let suffix = " " + String(localized: "Copy", bundle: RockxyLocalization.bundle)
        let maximumBaseCount = max(
            1,
            ProjectStructuralLimits.nameGraphemeRange.upperBound - suffix.count
        )
        let candidateTitle = source.title.boundedToGraphemes(maximumBaseCount) + suffix
        guard let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(candidateTitle) else {
            Self.logger.warning("Refused to duplicate a workspace with an invalid title")
            return nil
        }
        let duplicate = WorkspaceState(
            title: normalizedTitle,
            isClosable: true,
            initialFilter: source.filterCriteria
        )
        duplicate.activeMainTab = source.activeMainTab
        duplicate.inspectorLayout = source.inspectorLayout
        duplicate.isContextDockVisible = source.isContextDockVisible
        duplicate.contextDockTab = source.contextDockTab
        duplicate.allowsAutomaticInspectorReveal = source.allowsAutomaticInspectorReveal
        duplicate.focusNavigatorMode = source.focusNavigatorMode
        duplicate.activeTrafficSignal = source.activeTrafficSignal
        duplicate.focusSets = source.focusSets
        duplicate.activeFocusSetID = source.activeFocusSetID
        duplicate.mutedTrafficSources = source.mutedTrafficSources
        duplicate.filterRules = source.filterRules
        duplicate.isFilterBarVisible = source.isFilterBarVisible

        if let sourceIndex = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces.insert(duplicate, at: sourceIndex + 1)
        } else {
            workspaces.append(duplicate)
        }
        activeWorkspaceID = duplicate.id
        return duplicate
    }

    func closeOtherWorkspaces(except id: UUID) {
        workspaces.removeAll { $0.id != id && $0.isClosable }
        if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces[0].id
        }
    }

    func renameWorkspace(id: UUID, to newTitle: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(newTitle) else
        {
            Self.logger.warning("Refused to rename a workspace with an invalid title")
            return
        }
        workspace.title = normalizedTitle
    }

    // MARK: Project snapshot seams

    /// Captures the durable, bounded configuration of the current traffic tabs.
    /// Live transactions, rows, selections, sort descriptors, sidebar indexes,
    /// logs, and assistant state are intentionally excluded.
    func captureTabSnapshots() -> [ProjectTabSnapshot] {
        workspaces.map { ProjectTabSnapshot(capturing: $0) }
    }

    /// Replaces all traffic tabs with hydrated snapshots for a Project switch.
    /// Always restores at least one non-closable default tab and a valid active
    /// ID, even if given an empty or malformed set. Hydration retains up to the
    /// structural tab upper bound — not the lower creation limit — so a Project
    /// carrying more tabs than the current creation capacity is restored intact.
    func applyTabSnapshots(_ snapshots: [ProjectTabSnapshot], activeTabID: UUID) {
        var hydrated = snapshots.map { $0.hydrateWorkspaceState() }

        if hydrated.isEmpty {
            hydrated = [Self.makeWorkspace(
                title: ProjectStructuralLimits.defaultTabTitle,
                isClosable: false,
                filter: .empty,
                layoutPreferences: layoutPreferences
            )]
        } else if !hydrated.contains(where: { !$0.isClosable }) {
            hydrated.insert(
                Self.makeWorkspace(
                    title: ProjectStructuralLimits.defaultTabTitle,
                    isClosable: false,
                    filter: .empty,
                    layoutPreferences: layoutPreferences
                ),
                at: 0
            )
        }

        let retentionCap = ProjectStructuralLimits.tabCountRange.upperBound
        if hydrated.count > retentionCap {
            // Bound only by the structural upper limit: keep the non-closable
            // default and the earliest tabs. The creation limit never truncates
            // retained tabs here.
            let defaultIndex = hydrated.firstIndex { !$0.isClosable } ?? 0
            let keeper = hydrated.remove(at: defaultIndex)
            hydrated = [keeper] + hydrated.prefix(retentionCap - 1)
        }

        workspaces = hydrated
        activeWorkspaceID = hydrated.contains { $0.id == activeTabID }
            ? activeTabID
            : hydrated[0].id
    }

    func rememberBottomInspectorVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberBottomInspectorVisibility(isVisible)
    }

    func rememberContextDockVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberContextDockVisibility(isVisible)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceStore")

    private let layoutPreferences: WorkspaceLayoutPreferences

    /// Clamps a requested tab creation capacity into the structural tab range
    /// (`ProjectStructuralLimits.tabCountRange`). Both the lower and upper bound are
    /// enforced: at least one tab is always creatable, and never more than the
    /// structural upper bound that durable snapshots retain.
    private static func clampCreationCapacity(_ value: Int) -> Int {
        let range = ProjectStructuralLimits.tabCountRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func makeWorkspace(
        title: String,
        isClosable: Bool,
        filter: FilterCriteria,
        layoutPreferences: WorkspaceLayoutPreferences
    )
        -> WorkspaceState
    {
        let preferredBottomVisibility = layoutPreferences.preferredBottomInspectorVisibility
        return WorkspaceState(
            title: title,
            isClosable: isClosable,
            initialFilter: filter,
            inspectorLayout: preferredBottomVisibility == true ? .bottom : .hidden,
            isContextDockVisible: layoutPreferences.preferredContextDockVisibility,
            allowsAutomaticInspectorReveal: preferredBottomVisibility == nil
        )
    }
}
