import Foundation
import os

// MARK: - BreakpointTemplateStore

// Persists and coordinates breakpoint request/response templates.

@MainActor @Observable
final class BreakpointTemplateStore {
    // MARK: Lifecycle

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = RockxyIdentity.current.defaultsKey("breakpointTemplates"),
        seedDefaults: Bool = true
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.seedDefaults = seedDefaults
        load()
        reconcileSelection(preferredID: nil, preferredKind: selectedKind)
    }

    // MARK: Internal

    static let shared = BreakpointTemplateStore()

    private(set) var templates: [BreakpointTemplate] = []

    var selectedKind: BreakpointTemplateKind = .request {
        didSet {
            guard !isSynchronizingSelection, selectedKind != oldValue else {
                return
            }
            isSynchronizingSelection = true
            selectedTemplateID = templates(for: selectedKind).first?.id
            isSynchronizingSelection = false
        }
    }

    var selectedTemplateID: UUID? {
        didSet {
            guard !isSynchronizingSelection,
                  selectedTemplateID != oldValue,
                  let selectedTemplateID,
                  let kind = templates.first(where: { $0.id == selectedTemplateID })?.kind,
                  kind != selectedKind else
            {
                return
            }
            isSynchronizingSelection = true
            selectedKind = kind
            isSynchronizingSelection = false
        }
    }

    var requestTemplates: [BreakpointTemplate] {
        templates(for: .request)
    }

    var responseTemplates: [BreakpointTemplate] {
        templates(for: .response)
    }

    var selectedTemplates: [BreakpointTemplate] {
        templates(for: selectedKind)
    }

    var selectedTemplate: BreakpointTemplate? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first { $0.id == selectedTemplateID }
    }

    var selectedValidation: BreakpointTemplateValidation {
        selectedTemplate?.validation ?? .invalid(message: String(
            localized: "No template selected.",
            bundle: RockxyLocalization.bundle
        ))
    }

    @discardableResult
    func addTemplate(kind: BreakpointTemplateKind? = nil) -> BreakpointTemplate {
        let templateKind = kind ?? selectedKind
        let template = BreakpointTemplate(
            kind: templateKind,
            name: uniqueName(for: templateKind),
            rawMessage: templateKind.sampleMessage
        )
        templates.append(template)
        selectedKind = templateKind
        selectedTemplateID = template.id
        save()
        Self.logger.info("Added breakpoint \(templateKind.rawValue) template")
        return template
    }

    func deleteSelectedTemplate() {
        guard let selectedTemplateID else {
            return
        }
        deleteTemplate(id: selectedTemplateID)
    }

    func deleteTemplate(id: UUID) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            return
        }
        let kind = templates[index].kind
        templates.remove(at: index)
        if selectedTemplateID == id {
            selectedTemplateID = templates(for: kind).first?.id ?? templates.first?.id
        }
        save()
    }

    func updateTemplate(id: UUID, name: String? = nil, rawMessage: String? = nil) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let name {
            templates[index].name = sanitizedName(name, fallback: templates[index].kind.emptyName)
        }
        if let rawMessage {
            templates[index].rawMessage = rawMessage
        }
        templates[index].updatedAt = Date()
        save()
    }

    func renameSelectedTemplate(to name: String) {
        guard let selectedTemplateID else {
            return
        }
        updateTemplate(id: selectedTemplateID, name: name)
    }

    func updateSelectedRawMessage(_ rawMessage: String) {
        guard let selectedTemplateID else {
            return
        }
        updateTemplate(id: selectedTemplateID, rawMessage: rawMessage)
    }

    @discardableResult
    func duplicateSelectedTemplate() -> BreakpointTemplate? {
        guard let selectedTemplate else {
            return nil
        }
        var duplicate = BreakpointTemplate(
            kind: selectedTemplate.kind,
            name: String(localized: "Copy of \(selectedTemplate.name)", bundle: RockxyLocalization.bundle),
            rawMessage: selectedTemplate.rawMessage
        )
        duplicate.updatedAt = Date()
        templates.append(duplicate)
        selectedKind = duplicate.kind
        selectedTemplateID = duplicate.id
        save()
        return duplicate
    }

    func resetSelectedTemplateToSample() {
        guard let selectedTemplate else {
            return
        }
        updateTemplate(id: selectedTemplate.id, rawMessage: selectedTemplate.kind.sampleMessage)
    }

    func validation(for templateID: UUID) -> BreakpointTemplateValidation {
        templates.first { $0.id == templateID }?.validation
            ?? .invalid(message: String(localized: "Template is missing.", bundle: RockxyLocalization.bundle))
    }

    func applicationPayload(for templateID: UUID) -> BreakpointTemplateApplication? {
        templates.first { $0.id == templateID }?.applicationPayload
    }

    func selectedApplicationPayload() -> BreakpointTemplateApplication? {
        guard let selectedTemplateID else {
            return nil
        }
        return applicationPayload(for: selectedTemplateID)
    }

    func reload() {
        let previousID = selectedTemplateID
        let previousKind = selectedKind
        load()
        reconcileSelection(preferredID: previousID, preferredKind: previousKind)
    }

    func templates(for kind: BreakpointTemplateKind) -> [BreakpointTemplate] {
        templates.filter { $0.kind == kind }
    }

    func removeSelectedTemplate() {
        deleteSelectedTemplate()
    }

    func updateSelected(name: String? = nil, rawMessage: String? = nil) {
        if let name {
            renameSelectedTemplate(to: name)
        }
        if let rawMessage {
            updateSelectedRawMessage(rawMessage)
        }
    }

    func resetSelectedTemplate() {
        resetSelectedTemplateToSample()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BreakpointTemplateStore"
    )

    private let defaults: UserDefaults
    private let storageKey: String
    private let seedDefaults: Bool
    private var isSynchronizingSelection = false

    private var seedMarkerKey: String {
        "\(storageKey).seeded"
    }

    private func reconcileSelection(
        preferredID: UUID?,
        preferredKind: BreakpointTemplateKind
    ) {
        let replacement = preferredID.flatMap { preferredID in
            templates.first(where: { $0.id == preferredID })
        } ?? templates(for: preferredKind).first ?? templates.first
        selectedTemplateID = replacement?.id
    }

    private func uniqueName(for kind: BreakpointTemplateKind) -> String {
        let base = kind.emptyName
        let names = Set(templates(for: kind).map(\.name))
        guard names.contains(base) else {
            return base
        }
        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func sanitizedName(_ name: String, fallback: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(templates)
            defaults.set(data, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to save breakpoint templates: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            if seedDefaults, !defaults.bool(forKey: seedMarkerKey) {
                templates = BreakpointTemplate.defaultTemplates
                defaults.set(true, forKey: seedMarkerKey)
                save()
            } else {
                templates = []
            }
            return
        }

        do {
            let decoded = try JSONDecoder().decode([BreakpointTemplate].self, from: data)
            templates = decoded
        } catch {
            Self.logger.error("Failed to load breakpoint templates: \(error.localizedDescription)")
            templates = seedDefaults ? BreakpointTemplate.defaultTemplates : []
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
