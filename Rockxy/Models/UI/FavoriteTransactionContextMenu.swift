import Foundation

// Defines the testable action model for Pinned/Saved transaction context menus.

// MARK: - FavoriteTransactionSection

enum FavoriteTransactionSection: String, CaseIterable {
    case pinned
    case saved
    case notes

    // MARK: Internal

    var deleteTitle: String {
        switch self {
        case .pinned,
             .saved:
            String(localized: "Delete", bundle: RockxyLocalization.bundle)
        case .notes:
            String(localized: "Remove Note", bundle: RockxyLocalization.bundle)
        }
    }

    var displayName: String {
        switch self {
        case .pinned:
            String(localized: "Pinned", bundle: RockxyLocalization.bundle)
        case .saved:
            String(localized: "Saved", bundle: RockxyLocalization.bundle)
        case .notes:
            String(localized: "Notes", bundle: RockxyLocalization.bundle)
        }
    }

    var fallbackSidebarItem: SidebarItem {
        switch self {
        case .pinned:
            .allPinned
        case .saved:
            .allSaved
        case .notes:
            .allNotes
        }
    }

    func sidebarItem(for id: UUID) -> SidebarItem {
        switch self {
        case .pinned:
            .pinnedTransaction(id: id)
        case .saved:
            .savedTransaction(id: id)
        case .notes:
            .noteTransaction(id: id)
        }
    }
}

// MARK: - FavoriteTransactionToolAction

enum FavoriteTransactionToolAction: String, CaseIterable {
    case breakpoint
    case mapLocal
    case mapRemote
    case blockList
    case allowList
    case networkConditions

    // MARK: Internal

    var title: String {
        switch self {
        case .breakpoint:
            String(localized: "Breakpoint...", bundle: RockxyLocalization.bundle)
        case .mapLocal:
            String(localized: "Map Local...", bundle: RockxyLocalization.bundle)
        case .mapRemote:
            String(localized: "Map Remote...", bundle: RockxyLocalization.bundle)
        case .blockList:
            String(localized: "Block List...", bundle: RockxyLocalization.bundle)
        case .allowList:
            String(localized: "Allow List...", bundle: RockxyLocalization.bundle)
        case .networkConditions:
            String(localized: "Network Conditions...", bundle: RockxyLocalization.bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .breakpoint:
            "pause.circle"
        case .mapLocal:
            "doc.on.clipboard"
        case .mapRemote:
            "arrow.triangle.swap"
        case .blockList:
            "nosign"
        case .allowList:
            "line.3.horizontal.decrease.circle"
        case .networkConditions:
            "wifi.exclamationmark"
        }
    }
}

// MARK: - FavoriteTransactionExportFormat

enum FavoriteTransactionExportFormat: String, CaseIterable {
    case rockxySession
    case har
    case rawRequestAndResponse
    case requestBody
    case responseBody

    // MARK: Internal

    var title: String {
        switch self {
        case .rockxySession:
            String(localized: "as Rockxy Session...", bundle: RockxyLocalization.bundle)
        case .har:
            String(localized: "as HAR (HTTP Archive)...", bundle: RockxyLocalization.bundle)
        case .rawRequestAndResponse:
            String(localized: "Raw Request & Response...", bundle: RockxyLocalization.bundle)
        case .requestBody:
            String(localized: "Request Body...", bundle: RockxyLocalization.bundle)
        case .responseBody:
            String(localized: "Response Body...", bundle: RockxyLocalization.bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .rockxySession:
            "star.circle"
        case .har:
            "doc.badge.gearshape"
        case .rawRequestAndResponse:
            "doc.plaintext"
        case .requestBody:
            "arrow.up.doc"
        case .responseBody:
            "arrow.down.doc"
        }
    }

    var fileExtension: String {
        switch self {
        case .rockxySession:
            "rockxysession"
        case .har:
            "har"
        case .rawRequestAndResponse:
            "txt"
        case .requestBody,
             .responseBody:
            "bin"
        }
    }
}

// MARK: - FavoriteTransactionMenuOption

struct FavoriteTransactionMenuOption<Action: Hashable>: Hashable {
    // MARK: Lifecycle

    init(
        action: Action,
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        disabledReason: String? = nil
    ) {
        self.action = action
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }

    // MARK: Internal

    let action: Action
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let disabledReason: String?
}

// MARK: - FavoriteTransactionContextMenuModel

struct FavoriteTransactionContextMenuModel: Hashable {
    // MARK: Lifecycle

    init(
        transaction: HTTPTransaction,
        section: FavoriteTransactionSection,
        isSSLProxyingEnabled: Bool
    ) {
        self.section = section
        self.deleteTitle = section.deleteTitle
        self.sslProxyingTitle = isSSLProxyingEnabled
            ? String(localized: "Disable SSL Proxying", bundle: RockxyLocalization.bundle)
            : String(localized: "Enable SSL Proxying", bundle: RockxyLocalization.bundle)

        let hasHost = !transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.canToggleSSLProxying = hasHost
        self.sslProxyingDisabledReason = hasHost ? nil : String(
            localized: "This request has no host.",
            bundle: RockxyLocalization.bundle
        )

        self.tools = FavoriteTransactionToolAction.allCases.map {
            FavoriteTransactionMenuOption(action: $0, title: $0.title, systemImage: $0.systemImage)
        }

        self.exports = [
            FavoriteTransactionMenuOption(
                action: .rockxySession,
                title: FavoriteTransactionExportFormat.rockxySession.title,
                systemImage: FavoriteTransactionExportFormat.rockxySession.systemImage
            ),
            FavoriteTransactionMenuOption(
                action: .har,
                title: FavoriteTransactionExportFormat.har.title,
                systemImage: FavoriteTransactionExportFormat.har.systemImage
            ),
            FavoriteTransactionMenuOption(
                action: .rawRequestAndResponse,
                title: FavoriteTransactionExportFormat.rawRequestAndResponse.title,
                systemImage: FavoriteTransactionExportFormat.rawRequestAndResponse.systemImage,
                isEnabled: transaction.response != nil,
                disabledReason: transaction.response == nil
                    ? String(
                        localized: "No response has been captured for this request.",
                        bundle: RockxyLocalization.bundle
                    )
                    : nil
            ),
            FavoriteTransactionMenuOption(
                action: .requestBody,
                title: FavoriteTransactionExportFormat.requestBody.title,
                systemImage: FavoriteTransactionExportFormat.requestBody.systemImage,
                isEnabled: transaction.request.body != nil,
                disabledReason: transaction.request.body == nil
                    ? String(localized: "This request has no body.", bundle: RockxyLocalization.bundle)
                    : nil
            ),
            FavoriteTransactionMenuOption(
                action: .responseBody,
                title: FavoriteTransactionExportFormat.responseBody.title,
                systemImage: FavoriteTransactionExportFormat.responseBody.systemImage,
                isEnabled: transaction.response?.body != nil,
                disabledReason: transaction.response?.body == nil
                    ? String(localized: "This response has no body.", bundle: RockxyLocalization.bundle)
                    : nil
            ),
        ]
    }

    // MARK: Internal

    let section: FavoriteTransactionSection
    let deleteTitle: String
    let sslProxyingTitle: String
    let canToggleSSLProxying: Bool
    let sslProxyingDisabledReason: String?
    let tools: [FavoriteTransactionMenuOption<FavoriteTransactionToolAction>]
    let exports: [FavoriteTransactionMenuOption<FavoriteTransactionExportFormat>]
}
