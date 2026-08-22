import AppKit
import SwiftUI

// MARK: - Project Presentation Models

struct ProjectNameEditorContext: Identifiable, Equatable {
    enum Mode: Equatable {
        case create
        case rename(UUID)
    }

    let id = UUID()
    let mode: Mode
    let initialName: String

    var title: String {
        switch mode {
        case .create:
            String(localized: "New Project")
        case .rename:
            String(localized: "Rename Project")
        }
    }

    var actionTitle: String {
        switch mode {
        case .create:
            String(localized: "Create")
        case .rename:
            String(localized: "Rename")
        }
    }
}

struct ProjectDeletionRequest: Identifiable, Equatable {
    let projectID: UUID
    let projectName: String

    var id: UUID { projectID }
}

// MARK: - ProjectToolbarSelectorView

enum ProjectToolbarSelectorMetrics {
    static let minimumWidth: CGFloat = 104
    static let maximumWidth: CGFloat = 240
    static let nonTextWidth: CGFloat = 48

    static func preferredWidth(
        for projectName: String,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    )
        -> CGFloat
    {
        let textWidth = ceil(
            (projectName as NSString).size(withAttributes: [.font: font]).width
        )
        return min(maximumWidth, max(minimumWidth, textWidth + nonTextWidth))
    }
}

struct ProjectToolbarSelectorView: View {
    @Bindable var coordinator: MainContentCoordinator

    var body: some View {
        Menu {
            ForEach(coordinator.projectStore.projects) { project in
                Button {
                    guard coordinator.switchToProject(id: project.id) else {
                        return
                    }
                    RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
                } label: {
                    if project.id == coordinator.projectStore.activeProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
                .disabled(!canTransitionProjects)
            }

            Divider()

            Button(String(localized: "New Project…")) {
                coordinator.presentNewProjectEditor()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!canCreateProject)

            Button(String(localized: "Rename Project…")) {
                coordinator.presentRenameProjectEditor(id: coordinator.projectStore.activeProjectID)
            }
            .disabled(!canTransitionProjects)

            Button(String(localized: "Manage Projects…")) {
                coordinator.isProjectManagerPresented = true
            }

            if case .failed = coordinator.projectStore.loadState {
                Divider()
                Button(String(localized: "Repair Projects…")) {
                    coordinator.isProjectRecoveryPresented = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: projectStatusSymbol)
                    .foregroundStyle(projectStatusColor)
                Text(coordinator.projectStore.activeProject.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .frame(width: preferredWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .help(String(localized: "Active Project: \(coordinator.projectStore.activeProject.name)"))
        .accessibilityLabel(String(localized: "Active Project"))
        .accessibilityValue(coordinator.projectStore.activeProject.name)
    }

    private var preferredWidth: CGFloat {
        ProjectToolbarSelectorMetrics.preferredWidth(
            for: coordinator.projectStore.activeProject.name
        )
    }

    private var canCreateProject: Bool {
        coordinator.projectStore.canCreateProject && !coordinator.isClearingSession
    }

    private var canTransitionProjects: Bool {
        coordinator.projectStore.isMutable && !coordinator.isClearingSession
    }

    private var projectStatusSymbol: String {
        switch coordinator.projectStore.loadState {
        case .failed:
            "folder.badge.questionmark"
        case .loading:
            "folder"
        case .idle, .ready:
            "folder.fill"
        }
    }

    private var projectStatusColor: Color {
        if case .failed = coordinator.projectStore.loadState {
            return .orange
        }
        return .accentColor
    }
}

// MARK: - ProjectNameEditorSheet

struct ProjectNameEditorSheet: View {
    init(context: ProjectNameEditorContext, coordinator: MainContentCoordinator) {
        self.context = context
        self.coordinator = coordinator
        _name = State(initialValue: context.initialName)
        _operationErrorMessage = State(initialValue: nil)
    }

    let context: ProjectNameEditorContext
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.title)
                        .font(.headline)
                    Text(String(localized: "Projects keep Traffic Tab layouts and filters together."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(String(localized: "Project Name"))
                    .font(.subheadline.weight(.medium))
                TextField(String(localized: "For example: Checkout API"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in
                        operationErrorMessage = nil
                    }
                Text(editorMessage)
                    .font(.caption)
                    .foregroundStyle(hasEditorError ? Color.orange : Color.secondary)
            }
            .padding(18)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(context.actionTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
        }
        .frame(width: 460)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var operationErrorMessage: String?

    private var editorMessage: String {
        validationMessage
            ?? operationErrorMessage
            ?? String(
                localized: "1–\(ProjectStructuralLimits.nameGraphemeRange.upperBound) characters. Names must be unique."
            )
    }

    private var hasEditorError: Bool {
        validationMessage != nil || operationErrorMessage != nil
    }

    private var normalizedName: String? {
        try? ProjectNormalization.normalizedDisplayName(name)
    }

    private var validationMessage: String? {
        guard let normalizedName else {
            return String(localized: "Enter a name without control characters.")
        }
        let key = ProjectNormalization.foldedKey(for: normalizedName)
        let excludedID: UUID? = switch context.mode {
        case .create: nil
        case let .rename(id): id
        }
        if coordinator.projectStore.projects.contains(where: {
            $0.id != excludedID && ProjectNormalization.foldedKey(for: $0.name) == key
        }) {
            return String(localized: "A Project with this name already exists.")
        }
        return nil
    }

    private func submit() {
        guard let normalizedName else {
            return
        }
        let succeeded: Bool = switch context.mode {
        case .create:
            coordinator.createProject(named: normalizedName) != nil
        case let .rename(id):
            coordinator.renameProject(id: id, to: normalizedName)
        }
        guard succeeded else {
            operationErrorMessage = coordinator.projectOperationErrorMessage
                ?? String(localized: "The Project could not be updated. Try again.")
            return
        }
        RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
        dismiss()
    }
}

// MARK: - ProjectManagerSheet

struct ProjectManagerSheet: View {
    init(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        _selection = State(initialValue: coordinator.projectStore.activeProjectID)
    }

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                projectSidebar
                    .frame(minWidth: 230, idealWidth: 250, maxWidth: 300)
                detail
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            actionBar
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(720, toolMetrics.bodyFontSize * 20 + 460),
            idealWidth: max(780, toolMetrics.bodyFontSize * 22 + 494),
            minHeight: max(500, toolMetrics.bodyFontSize * 14 + 318),
            idealHeight: max(540, toolMetrics.bodyFontSize * 16 + 340)
        )
        .confirmationDialog(
            String(localized: "Delete Project?"),
            isPresented: deleteConfirmation,
            titleVisibility: .visible,
            presenting: coordinator.projectDeletionRequest
        ) { request in
            Button(String(localized: "Delete \(request.projectName)"), role: .destructive) {
                delete(request)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(
                String(localized: "This removes the Project, its in-memory traffic history, and its saved Traffic Tab configuration.")
                    + " "
                    + String(localized: "Manually saved session files, rules, and favorites are not deleted.")
            )
        }
        .sheet(item: Binding(
            get: { coordinator.projectNameEditorContext },
            set: { coordinator.projectNameEditorContext = $0 }
        )) { context in
            ProjectNameEditorSheet(context: context, coordinator: coordinator)
        }
        .onChange(of: coordinator.projectStore.activeProjectID) { _, activeProjectID in
            selection = activeProjectID
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var selection: UUID?

    private var selectedProject: Project? {
        coordinator.projectStore.projects.first { $0.id == selection }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var canCreateProject: Bool {
        coordinator.projectStore.canCreateProject && !coordinator.isClearingSession
    }

    private var canTransitionProjects: Bool {
        coordinator.projectStore.isMutable && !coordinator.isClearingSession
    }

    private var canExportSelectedProject: Bool {
        canTransitionProjects && selectedProject != nil
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Projects"))
                    .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                Text(String(localized: "Organize Project-scoped traffic and durable Traffic Tab layouts."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.top, toolMetrics.headerTopPadding)
            .padding(.bottom, toolMetrics.headerBottomPadding)

            Divider()

            List(selection: $selection) {
                ForEach(coordinator.projectStore.projects) { project in
                    HStack(spacing: 8) {
                        Image(systemName: project.id == coordinator.projectStore.activeProjectID
                            ? "folder.fill"
                            : "folder")
                            .foregroundStyle(selection == project.id ? Color.primary : Color.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(trafficTabCountText(project.tabs.count))
                                .font(toolMetrics.metadataFont())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if project.id == coordinator.projectStore.activeProjectID {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: toolMetrics.smallIconFontSize))
                                .foregroundStyle(selection == project.id ? Color.primary : Color.accentColor)
                                .help(String(localized: "Active Project"))
                                .accessibilityLabel(String(localized: "Active Project"))
                        }
                    }
                    .tag(project.id)
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(project.name)
                    .accessibilityValue(projectAccessibilityValue(project))
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: toolMetrics.controlSpacing) {
                addRemoveControl

                Spacer()

                Text("\(coordinator.projectStore.projects.count)/\(coordinator.projectStore.maxProjects)")
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Project capacity"))
                    .accessibilityValue(
                        String(
                            localized:
                            "\(coordinator.projectStore.projects.count) of \(coordinator.projectStore.maxProjects) Projects"
                        )
                    )
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.footerTopPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let project = selectedProject {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(project.id == coordinator.projectStore.activeProjectID
                            ? String(localized: "Active Project")
                            : String(localized: "Local Project"))
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if project.id != coordinator.projectStore.activeProjectID {
                        Button(String(localized: "Open Project")) {
                            open(project)
                        }
                        .disabled(!canTransitionProjects)
                    }
                    Button(String(localized: "Rename…")) {
                        coordinator.presentRenameProjectEditor(id: project.id)
                    }
                    .disabled(!canTransitionProjects)
                }
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.headerBottomPadding)

                Divider()

                VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                    HStack {
                        Text(String(localized: "Traffic Tabs"))
                            .font(toolMetrics.font(weight: .medium))
                        Spacer()
                        Text(trafficTabCountText(project.tabs.count))
                            .font(toolMetrics.metadataFont(monospaced: true))
                            .foregroundStyle(.secondary)
                    }

                    List {
                        ForEach(project.tabs) { tab in
                            HStack(spacing: toolMetrics.controlSpacing) {
                                Image(systemName: tab.isClosable ? "rectangle" : "rectangle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(tab.title)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if tab.id == project.activeTabID {
                                    Label(String(localized: "Current"), systemImage: "checkmark")
                                        .font(toolMetrics.metadataFont())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: toolMetrics.tableRowHeight)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(tab.title)
                            .accessibilityValue(
                                tab.id == project.activeTabID
                                    ? String(localized: "Current Traffic Tab")
                                    : String(localized: "Traffic Tab")
                            )
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(toolMetrics.contentHorizontalPadding)

                Divider()
                infoBanner
            }
        } else {
            ContentUnavailableView(
                String(localized: "Select a Project"),
                systemImage: "folder",
                description: Text(String(localized: "Choose a Project to view its Traffic Tabs."))
            )
        }
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                coordinator.presentNewProjectEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(canCreateProject ? .primary : .tertiary)
                    .frame(
                        width: toolMetrics.compactButtonSize - 5,
                        height: toolMetrics.compactButtonSize - 5
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help(String(localized: "New Project"))
            .accessibilityLabel(String(localized: "New Project"))
            .disabled(!canCreateProject)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                guard let selectedProject else {
                    return
                }
                coordinator.requestProjectDeletion(selectedProject)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(canDeleteSelectedProject ? .primary : .tertiary)
                    .frame(
                        width: toolMetrics.compactButtonSize - 5,
                        height: toolMetrics.compactButtonSize - 5
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Delete Project"))
            .accessibilityLabel(String(localized: "Delete Project"))
            .disabled(!canDeleteSelectedProject)
        }
        .frame(
            width: max(43, toolMetrics.compactButtonSize * 2 + 1),
            height: toolMetrics.footerControlHeight
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var canDeleteSelectedProject: Bool {
        canTransitionProjects
            && selectedProject != nil
            && coordinator.projectStore.projects.count > 1
    }

    private var infoBanner: some View {
        Label(
            String(localized: "Projects save tab names, filters, and layout. Each Project keeps separate in-memory traffic."),
            systemImage: "info.circle"
        )
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var actionBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            if case .failed = coordinator.projectStore.loadState {
                Label(
                    String(localized: "Projects could not be loaded. Changes will not be saved."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.orange)
            } else if case .failed = coordinator.projectStore.persistenceStatus {
                Label(String(localized: "Could not save Projects"), systemImage: "exclamationmark.triangle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
            } else {
                Text(String(localized: "Projects are stored locally on this Mac."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Import…")) {
                importProjectConfiguration()
            }
            .help(String(localized: "Import Project Configuration"))
            .disabled(!canCreateProject)

            Button(String(localized: "Export…")) {
                exportSelectedProjectConfiguration()
            }
            .help(String(localized: "Export Selected Project Configuration"))
            .disabled(!canExportSelectedProject)

            Button(String(localized: "Done")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .frame(minHeight: 48)
    }

    private func trafficTabCountText(_ count: Int) -> String {
        let inflected = AttributedString(localized: "^[\(count) Traffic Tab](inflect: true)")
        return String(inflected.characters)
    }

    private func projectAccessibilityValue(_ project: Project) -> String {
        let count = trafficTabCountText(project.tabs.count)
        if project.id == coordinator.projectStore.activeProjectID {
            return String(localized: "\(count), Active Project")
        }
        return count
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(
            get: { coordinator.projectDeletionRequest != nil },
            set: {
                if !$0 {
                    coordinator.projectDeletionRequest = nil
                }
            }
        )
    }

    private func open(_ project: Project) {
        guard coordinator.switchToProject(id: project.id) else {
            return
        }
        selection = project.id
        RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
    }

    private func importProjectConfiguration() {
        guard coordinator.importProjectConfiguration() else {
            return
        }
        selection = coordinator.projectStore.activeProjectID
        RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
    }

    private func exportSelectedProjectConfiguration() {
        guard let selectedProject else {
            return
        }
        _ = coordinator.exportProjectConfiguration(id: selectedProject.id)
    }

    private func delete(_ request: ProjectDeletionRequest) {
        let wasActive = request.projectID == coordinator.projectStore.activeProjectID
        guard coordinator.deleteProject(id: request.projectID) else {
            return
        }
        coordinator.projectDeletionRequest = nil
        if selection == request.projectID {
            selection = coordinator.projectStore.activeProjectID
        }
        if wasActive {
            RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
        }
    }
}

// MARK: - ProjectRecoverySheet

struct ProjectRecoverySheet: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Projects Could Not Be Loaded"))
                        .font(.headline)
                    Text(
                        String(localized: "Rockxy kept the existing catalog unchanged and disabled Project edits to avoid overwriting data.")
                    )
                    .foregroundStyle(.secondary)
                    Text(coordinator.projectStore.loadFailureMessage ?? String(localized: "Unknown catalog error"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            HStack {
                Button(String(localized: "Close"), role: .cancel) {
                    coordinator.isProjectRecoveryPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Reset Projects…"), role: .destructive) {
                    confirmsReset = true
                }
                Button(String(localized: "Retry")) {
                    retry()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .frame(width: 540)
        .alert(String(localized: "Reset Projects?"), isPresented: $confirmsReset) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset Projects"), role: .destructive) {
                reset()
            }
        } message: {
            Text(
                // swiftlint:disable:next line_length
                "Rockxy will replace the current catalog with one default Project. A bounded regular catalog is preserved as catalog.recovery.json. Captured traffic, sessions, rules, and favorites are not deleted."
            )
        }
    }

    @State private var confirmsReset = false

    private func retry() {
        Task { @MainActor in
            await coordinator.hydrateProjectsOnLaunch()
            if coordinator.projectStore.loadState == .ready {
                coordinator.isProjectRecoveryPresented = false
                RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
            }
        }
    }

    private func reset() {
        Task { @MainActor in
            await coordinator.projectStore.resetToDefaultCatalog()
            await coordinator.hydrateProjectsOnLaunch()
            if coordinator.projectStore.loadState == .ready {
                coordinator.isProjectRecoveryPresented = false
                RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
            }
        }
    }
}
