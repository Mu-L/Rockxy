import Foundation

// Defines the UI model for custom request and response preview tabs.

// MARK: - PreviewRenderMode

enum PreviewRenderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case json
    case jsonTree
    case formURLEncoded
    case html
    case htmlPreview
    case css
    case javascript
    case xml
    case images
    case hex
    case jwt
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .json: String(localized: "JSON", bundle: RockxyLocalization.bundle)
        case .jsonTree: String(localized: "JSON Treeview", bundle: RockxyLocalization.bundle)
        case .formURLEncoded: String(localized: "Form URL-Encoded", bundle: RockxyLocalization.bundle)
        case .html: String(localized: "HTML", bundle: RockxyLocalization.bundle)
        case .htmlPreview: String(localized: "HTML Preview", bundle: RockxyLocalization.bundle)
        case .css: String(localized: "CSS", bundle: RockxyLocalization.bundle)
        case .javascript: String(localized: "JavaScript", bundle: RockxyLocalization.bundle)
        case .xml: String(localized: "XML", bundle: RockxyLocalization.bundle)
        case .images: String(localized: "Images", bundle: RockxyLocalization.bundle)
        case .hex: String(localized: "Hex", bundle: RockxyLocalization.bundle)
        case .jwt: String(localized: "JWT", bundle: RockxyLocalization.bundle)
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        }
    }

    var displayOrder: Int {
        Self.allCases.firstIndex(of: self) ?? .max
    }
}

// MARK: - PreviewPanel

enum PreviewPanel: String, Codable, Sendable {
    case request
    case response
}

// MARK: - InspectorPreviewSelectionReconciler

enum InspectorPreviewSelectionReconciler {
    static func retainedSelection(
        _ selection: PreviewTab?,
        availableTabIDs: [UUID]
    )
        -> PreviewTab?
    {
        guard let selection, availableTabIDs.contains(selection.id) else {
            return nil
        }
        return selection
    }
}

// MARK: - PreviewTab

struct PreviewTab: Identifiable, Codable, Hashable, Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String? = nil,
        renderMode: PreviewRenderMode,
        panel: PreviewPanel,
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name ?? renderMode.displayName
        self.renderMode = renderMode
        self.panel = panel
        self.isBuiltIn = isBuiltIn
    }

    // MARK: Internal

    let id: UUID
    var name: String
    var renderMode: PreviewRenderMode
    var panel: PreviewPanel
    var isBuiltIn: Bool
}
