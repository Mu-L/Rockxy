import Foundation
@testable import Rockxy
import Testing

// MARK: - ProjectCatalogTests

@Suite("ProjectCatalog")
struct ProjectCatalogTests {
    // MARK: Defaults & invariants

    @Test("default catalog is valid with one non-closable All Traffic tab")
    func defaultCatalogValid() throws {
        let catalog = ProjectCatalog.makeDefault(now: Self.fixedDate)
        try catalog.validate()
        #expect(catalog.projects.count == 1)
        #expect(catalog.schemaVersion == 1)
        #expect(catalog.revision == 1)
        let project = try #require(catalog.activeProject)
        #expect(project.tabs.count == 1)
        #expect(project.tabs[0].isClosable == false)
        #expect(project.activeTabID == project.tabs[0].id)
    }

    // MARK: Catalog-level validation

    @Test("rejects an empty catalog")
    func rejectsEmptyCatalog() {
        let catalog = ProjectCatalog(activeProjectID: UUID(), projects: [])
        #expect(throws: ProjectCatalogValidationError.projectCountOutOfRange(count: 0)) {
            try catalog.validate()
        }
    }

    @Test("rejects duplicate project IDs")
    func rejectsDuplicateProjectIDs() {
        let sharedID = UUID()
        let projects = [
            Self.makeProject(id: sharedID, name: "Alpha"),
            Self.makeProject(id: sharedID, name: "Beta"),
        ]
        let catalog = ProjectCatalog(activeProjectID: sharedID, projects: projects)
        #expect(throws: ProjectCatalogValidationError.duplicateProjectID(sharedID)) {
            try catalog.validate()
        }
    }

    @Test("rejects names that collide after folding")
    func rejectsDuplicateFoldedNames() {
        let projects = [
            Self.makeProject(name: "Café"),
            Self.makeProject(name: "cafe"),
        ]
        let catalog = ProjectCatalog(activeProjectID: projects[0].id, projects: projects)
        #expect(throws: ProjectCatalogValidationError.self) {
            try catalog.validate()
        }
    }

    @Test("rejects an unresolved active project ID")
    func rejectsUnresolvedActiveProject() {
        let projects = [Self.makeProject(name: "Alpha")]
        let catalog = ProjectCatalog(activeProjectID: UUID(), projects: projects)
        #expect(throws: ProjectCatalogValidationError.unresolvedActiveProjectID) {
            try catalog.validate()
        }
    }

    @Test("rejects a stored project name that is not canonical")
    func rejectsNoncanonicalProjectName() {
        // A leading/trailing-space name decodes structurally but is noncanonical.
        let project = Project(
            name: "  Staging  ",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: UUID(),
            tabs: [ProjectTabSnapshot.makeDefaultAllTraffic()]
        )
        var project2 = project
        project2.activeTabID = project.tabs[0].id
        #expect(throws: ProjectCatalogValidationError.projectNameInvalid(.notCanonical)) {
            try project2.validate()
        }
    }

    @Test("rejects a stored tab title that is not canonical")
    func rejectsNoncanonicalTabTitle() {
        let tab = ProjectTabSnapshot(title: "All Traffic ", isClosable: false)
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: tab.id,
            tabs: [tab]
        )
        #expect(throws: ProjectCatalogValidationError.self) {
            try project.validate()
        }
    }

    // MARK: Project-level validation

    @Test("rejects a project with zero tabs")
    func rejectsEmptyProject() {
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: UUID(),
            tabs: []
        )
        #expect(throws: ProjectCatalogValidationError.self) {
            try project.validate()
        }
    }

    @Test("rejects a project with no non-closable tab")
    func rejectsMissingNonClosableTab() {
        let tab = ProjectTabSnapshot(title: "Closable", isClosable: true)
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: tab.id,
            tabs: [tab]
        )
        #expect(throws: ProjectCatalogValidationError.missingNonClosableTab(projectID: project.id)) {
            try project.validate()
        }
    }

    @Test("rejects an unresolved active tab ID")
    func rejectsUnresolvedActiveTab() {
        let tab = ProjectTabSnapshot.makeDefaultAllTraffic()
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: UUID(),
            tabs: [tab]
        )
        #expect(throws: ProjectCatalogValidationError.unresolvedActiveTabID(projectID: project.id)) {
            try project.validate()
        }
    }

    @Test("rejects duplicate tab IDs")
    func rejectsDuplicateTabIDs() {
        let sharedID = UUID()
        let tabs = [
            ProjectTabSnapshot(id: sharedID, title: "All Traffic", isClosable: false),
            ProjectTabSnapshot(id: sharedID, title: "Second", isClosable: true),
        ]
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: sharedID,
            tabs: tabs
        )
        #expect(throws: ProjectCatalogValidationError.duplicateTabID(sharedID)) {
            try project.validate()
        }
    }

    // MARK: Tab normalization

    @Test("normalizedTabs injects a non-closable default when none exists")
    func normalizedTabsInjectsDefault() {
        let closable = ProjectTabSnapshot(title: "One", isClosable: true)
        let (tabs, activeTabID) = Project.normalizedTabs([closable], activeTabID: closable.id, maxTabs: 8)
        #expect(tabs.contains { !$0.isClosable })
        #expect(tabs.contains { $0.id == activeTabID })
        #expect(activeTabID == closable.id)
    }

    @Test("normalizedTabs produces a default tab for an empty input")
    func normalizedTabsFromEmpty() {
        let (tabs, activeTabID) = Project.normalizedTabs([], activeTabID: UUID(), maxTabs: 8)
        #expect(tabs.count == 1)
        #expect(tabs[0].isClosable == false)
        #expect(activeTabID == tabs[0].id)
    }

    @Test("normalizedTabs clamps to capacity while keeping the default tab")
    func normalizedTabsClampsCapacity() {
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let extras = (0 ..< 10).map { ProjectTabSnapshot(title: "Tab \($0)", isClosable: true) }
        let (tabs, _) = Project.normalizedTabs([base] + extras, activeTabID: base.id, maxTabs: 4)
        #expect(tabs.count == 4)
        #expect(tabs.contains { $0.id == base.id })
        #expect(tabs.contains { !$0.isClosable })
    }

    @Test("normalizedTabs drops duplicate tab IDs")
    func normalizedTabsDropsDuplicates() {
        let base = ProjectTabSnapshot.makeDefaultAllTraffic()
        let (tabs, _) = Project.normalizedTabs([base, base], activeTabID: base.id, maxTabs: 8)
        #expect(tabs.count == 1)
    }

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static func makeProject(id: UUID = UUID(), name: String) -> Project {
        Project.makeDefault(id: id, name: name, createdAt: fixedDate, updatedAt: fixedDate)
    }
}
