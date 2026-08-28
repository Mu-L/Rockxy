import AppKit
import SwiftUI

// MARK: - NativeWorkspaceToolbarConfiguration

@MainActor
struct NativeWorkspaceToolbarConfiguration {
    // MARK: Lifecycle

    init(
        coordinator: MainContentCoordinator,
        onOpenDeveloperHub: @escaping () -> Void,
        onOpenToolWindow: @escaping (String) -> Void = { _ in },
        onToggleProxy: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.onOpenDeveloperHub = onOpenDeveloperHub
        self.onOpenToolWindow = onOpenToolWindow
        self.onToggleProxy = onToggleProxy ?? {
            if coordinator.isProxyRunning {
                coordinator.stopProxy()
            } else {
                coordinator.startProxy()
            }
        }
    }

    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenDeveloperHub: () -> Void
    let onOpenToolWindow: (String) -> Void
    let onToggleProxy: () -> Void
}

// MARK: - NativeWorkspaceWindowChrome

enum NativeWorkspaceWindowChrome {
    @MainActor
    static func configure(
        _ window: NSWindow,
        workspaceSplitController: NativeWorkspaceSplitViewController? = nil,
        toolbarConfiguration: NativeWorkspaceToolbarConfiguration? = nil
    ) {
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified

        if let workspaceSplitController,
           let toolbarConfiguration
        {
            workspaceSplitController.installToolbarIfNeeded(
                window: window,
                configuration: toolbarConfiguration
            )
        }

        window.titleVisibility = .hidden
    }
}

// MARK: - NativeWorkspaceToolbar

@MainActor
final class NativeWorkspaceToolbar: NSObject, NSToolbarDelegate {
    // MARK: Lifecycle

    init(
        splitViewController: NativeWorkspaceSplitViewController,
        configuration: NativeWorkspaceToolbarConfiguration,
        toolbarIdentifier: NSToolbar.Identifier? = nil,
        autosavesConfiguration: Bool = true
    ) {
        self.splitViewController = splitViewController
        coordinator = configuration.coordinator
        onOpenDeveloperHub = configuration.onOpenDeveloperHub
        onOpenToolWindow = configuration.onOpenToolWindow
        onToggleProxy = configuration.onToggleProxy
        managedToolbar = NSToolbar(identifier: toolbarIdentifier ?? Self.toolbarIdentifier)
        super.init()

        managedToolbar.delegate = self
        managedToolbar.displayMode = .iconOnly
        managedToolbar.allowsUserCustomization = true
        managedToolbar.autosavesConfiguration = autosavesConfiguration
        managedToolbar.centeredItemIdentifiers = [Self.proxyStatusIdentifier]
    }

    // MARK: Internal

    struct ToolWindowItemDescriptor {
        let identifier: NSToolbarItem.Identifier
        let label: String
        let systemImage: String
        let windowID: String
    }

    static let toolbarIdentifier = NSToolbar.Identifier(
        "\(RockxyIdentity.current.logSubsystem).main.toolbar.customizable.v1"
    )
    static let sidebarToggleIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.toggleSidebar"
    )
    static let sidebarTrackingSeparatorIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.sidebarTrackingSeparator"
    )
    static let proxyStatusIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.proxyStatus"
    )
    static let projectSelectorIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.projectSelector"
    )
    static let proxyToggleIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.toggleProxy"
    )
    static let developerHubIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.developerHub"
    )
    static let bottomInspectorIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.bottomInspector"
    )
    static let contextDockIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.contextDock"
    )
    static let recordingIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.toggleRecording"
    )
    static let composeIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.compose"
    )
    static let clearSessionIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.clearSession"
    )
    static let detachedInspectorIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.detachedInspector"
    )
    static let blockListIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.blockList"
    )
    static let allowListIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.allowList"
    )
    static let mapLocalIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.mapLocal"
    )
    static let mapRemoteIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.mapRemote"
    )
    static let scriptingIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.scripting"
    )
    static let breakpointRulesIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.breakpointRules"
    )
    static let networkConditionsIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.networkConditions"
    )
    static let sslProxyingIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.sslProxying"
    )
    static let bypassProxyIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.bypassProxy"
    )
    static let externalProxyIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.externalProxy"
    )
    static let modifyHeadersIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.modifyHeaders"
    )
    static let diffIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.diff"
    )
    static let customColumnsIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.customColumns"
    )
    static let previewTabsIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.previewTabs"
    )

    /// Stable identifiers for the tool-window items, cached so allowed/customizable
    /// identifier sets stay constant across a language switch even though the
    /// descriptor labels are re-resolved on demand.
    static let toolWindowItemIdentifiers: [NSToolbarItem.Identifier] = toolWindowItemDescriptors.map(\.identifier)

    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = [
        .flexibleSpace,
        sidebarToggleIdentifier,
        sidebarTrackingSeparatorIdentifier,
        projectSelectorIdentifier,
        .flexibleSpace,
        proxyStatusIdentifier,
        .flexibleSpace,
        proxyToggleIdentifier,
        developerHubIdentifier,
        bottomInspectorIdentifier,
        contextDockIdentifier,
    ]

    static let allowedItemIdentifiers: [NSToolbarItem.Identifier] = [
        sidebarToggleIdentifier,
        sidebarTrackingSeparatorIdentifier,
        projectSelectorIdentifier,
        proxyStatusIdentifier,
        proxyToggleIdentifier,
        developerHubIdentifier,
        bottomInspectorIdentifier,
        contextDockIdentifier,
        recordingIdentifier,
        composeIdentifier,
        clearSessionIdentifier,
        detachedInspectorIdentifier,
    ] + toolWindowItemIdentifiers + [
        .space,
        .flexibleSpace,
    ]

    static let userCustomizableItemIdentifiers: [NSToolbarItem.Identifier] = [
        sidebarToggleIdentifier,
        projectSelectorIdentifier,
        proxyStatusIdentifier,
        proxyToggleIdentifier,
        developerHubIdentifier,
        bottomInspectorIdentifier,
        contextDockIdentifier,
        recordingIdentifier,
        composeIdentifier,
        clearSessionIdentifier,
        detachedInspectorIdentifier,
    ] + toolWindowItemIdentifiers

    static var toolWindowItemDescriptors: [ToolWindowItemDescriptor] {
        [
            .init(
                identifier: blockListIdentifier,
                label: String(localized: "Block List", bundle: RockxyLocalization.bundle),
                systemImage: "hand.raised.slash",
                windowID: "blockList"
            ),
            .init(
                identifier: allowListIdentifier,
                label: String(localized: "Allow List", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.shield",
                windowID: "allowList"
            ),
            .init(
                identifier: mapLocalIdentifier,
                label: String(localized: "Map Local", bundle: RockxyLocalization.bundle),
                systemImage: "folder.badge.gearshape",
                windowID: "mapLocal"
            ),
            .init(
                identifier: mapRemoteIdentifier,
                label: String(localized: "Map Remote", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.triangle.branch",
                windowID: "mapRemote"
            ),
            .init(
                identifier: scriptingIdentifier,
                label: String(localized: "Scripting", bundle: RockxyLocalization.bundle),
                systemImage: "curlybraces",
                windowID: "scriptingList"
            ),
            .init(
                identifier: breakpointRulesIdentifier,
                label: String(localized: "Breakpoint Rules", bundle: RockxyLocalization.bundle),
                systemImage: "pause.circle",
                windowID: "breakpointRules"
            ),
            .init(
                identifier: networkConditionsIdentifier,
                label: String(localized: "Network Conditions", bundle: RockxyLocalization.bundle),
                systemImage: "speedometer",
                windowID: "networkConditions"
            ),
            .init(
                identifier: sslProxyingIdentifier,
                label: String(localized: "HTTPS Decryption", bundle: RockxyLocalization.bundle),
                systemImage: "lock.open",
                windowID: "sslProxyingList"
            ),
            .init(
                identifier: bypassProxyIdentifier,
                label: String(localized: "Proxy Bypass", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.uturn.left.circle",
                windowID: "bypassProxyList"
            ),
            .init(
                identifier: externalProxyIdentifier,
                label: String(localized: "External Proxy", bundle: RockxyLocalization.bundle),
                systemImage: "globe",
                windowID: "externalProxySettings"
            ),
            .init(
                identifier: modifyHeadersIdentifier,
                label: String(localized: "Modify Headers", bundle: RockxyLocalization.bundle),
                systemImage: "slider.horizontal.3",
                windowID: "modifyHeaders"
            ),
            .init(
                identifier: diffIdentifier,
                label: String(localized: "Diff", bundle: RockxyLocalization.bundle),
                systemImage: "doc.text.magnifyingglass",
                windowID: "diff"
            ),
            .init(
                identifier: customColumnsIdentifier,
                label: String(localized: "Header Columns", bundle: RockxyLocalization.bundle),
                systemImage: "rectangle.split.3x1",
                windowID: "customColumns"
            ),
            .init(
                identifier: previewTabsIdentifier,
                label: String(localized: "Inspector Preview Tabs", bundle: RockxyLocalization.bundle),
                systemImage: "rectangle.stack",
                windowID: "bodyPreviewerTabs"
            ),
        ]
    }

    let managedToolbar: NSToolbar

    /// Opens AppKit's standard toolbar customization palette for the frontmost
    /// Rockxy workspace window after transient menu windows have closed.
    static func presentCustomizationPalette(preferredWindow: NSWindow? = nil) {
        DispatchQueue.main.async {
            let candidateWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
                + NSApp.orderedWindows
            guard let toolbar = customizationToolbar(
                preferredWindow: preferredWindow,
                fallbackWindows: candidateWindows
            ),
                !toolbar.customizationPaletteIsRunning else
            {
                return
            }
            toolbar.runCustomizationPalette(nil)
        }
    }

    static func customizationToolbar(
        preferredWindow: NSWindow?,
        fallbackWindows: [NSWindow]
    )
        -> NSToolbar?
    {
        let windows = [preferredWindow].compactMap { $0 } + fallbackWindows
        return windows.lazy
            .compactMap(\.toolbar)
            .first {
                $0.identifier == toolbarIdentifier && $0.allowsUserCustomization
            }
    }

    func startObservingState() {
        lastLanguageOptionID = AppLanguageController.shared.selectedOptionID
        syncActionItems()
        guard !isObservingState else {
            return
        }
        isObservingState = true
        armObservation()
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    )
        -> [NSToolbarItem.Identifier]
    {
        Self.defaultItemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    )
        -> [NSToolbarItem.Identifier]
    {
        Self.allowedItemIdentifiers
    }

    func toolbarImmovableItemIdentifiers(
        _ toolbar: NSToolbar
    )
        -> Set<NSToolbarItem.Identifier>
    {
        [Self.sidebarTrackingSeparatorIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    )
        -> NSToolbarItem?
    {
        switch itemIdentifier {
        case Self.sidebarToggleIdentifier:
            return makeSidebarToggleItem()
        case Self.sidebarTrackingSeparatorIdentifier:
            guard let splitView = splitViewController?.splitView else {
                return nil
            }
            let item = NSTrackingSeparatorToolbarItem(
                identifier: Self.sidebarTrackingSeparatorIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )
            item.label = String(localized: "Source List Divider", bundle: RockxyLocalization.bundle)
            // The tracking separator has only a narrow preview cell in AppKit's draggable
            // default-set row. Keep its descriptive toolbar label, but use a compact palette
            // label so it does not collide with Flexible Space and Project labels.
            item.paletteLabel = String(localized: "Divider", bundle: RockxyLocalization.bundle)
            return item
        case Self.projectSelectorIdentifier:
            let item = hostingItem(
                identifier: itemIdentifier,
                rootView: AnyView(ProjectToolbarSelectorView(coordinator: coordinator))
            )
            item.label = String(localized: "Project", bundle: RockxyLocalization.bundle)
            item.paletteLabel = item.label
            item.visibilityPriority = .high
            return item
        case Self.proxyStatusIdentifier:
            let item = hostingItem(
                identifier: itemIdentifier,
                rootView: AnyView(
                    ProxyToolbarStatusView(coordinator: coordinator)
                )
            )
            item.label = String(localized: "Proxy Status", bundle: RockxyLocalization.bundle)
            item.paletteLabel = item.label
            return item
        case Self.proxyToggleIdentifier:
            return makeProxyToggleItem()
        case Self.developerHubIdentifier:
            return makeDeveloperHubItem()
        case Self.bottomInspectorIdentifier:
            return makeBottomInspectorItem()
        case Self.contextDockIdentifier:
            return makeContextDockItem()
        case Self.recordingIdentifier:
            return makeRecordingItem()
        case Self.composeIdentifier:
            return makeComposeItem()
        case Self.clearSessionIdentifier:
            return makeClearSessionItem()
        case Self.detachedInspectorIdentifier:
            return makeDetachedInspectorItem()
        default:
            guard let descriptor = Self.toolWindowItemDescriptors.first(where: {
                $0.identifier == itemIdentifier
            }) else {
                return nil
            }
            return makeToolWindowItem(descriptor)
        }
    }

    // MARK: Private

    private weak var splitViewController: NativeWorkspaceSplitViewController?
    private let coordinator: MainContentCoordinator
    private let onOpenDeveloperHub: () -> Void
    private let onOpenToolWindow: (String) -> Void
    private let onToggleProxy: () -> Void
    private var isObservingState = false
    private var lastLanguageOptionID = AppLanguageController.shared.selectedOptionID

    private var proxyToolTip: String {
        coordinator.isProxyRunning
            ? String(localized: "Stop proxy", bundle: RockxyLocalization.bundle)
            : String(localized: "Start proxy", bundle: RockxyLocalization.bundle)
    }

    private var bottomInspectorToolTip: String {
        guard coordinator.canToggleBottomInspector else {
            return String(localized: "Select a request to use the bottom inspector", bundle: RockxyLocalization.bundle)
        }
        return coordinator.isBottomInspectorEffectivelyPresented
            ? String(localized: "Hide Bottom Inspector", bundle: RockxyLocalization.bundle)
            : String(localized: "Show Bottom Inspector", bundle: RockxyLocalization.bundle)
    }

    private var contextDockToolTip: String {
        coordinator.isContextDockVisible
            ? String(localized: "Hide Context Dock", bundle: RockxyLocalization.bundle)
            : String(localized: "Show Context Dock", bundle: RockxyLocalization.bundle)
    }

    private var recordingToolTip: String {
        guard coordinator.isProxyRunning else {
            return String(localized: "Start the proxy before changing recording", bundle: RockxyLocalization.bundle)
        }
        return coordinator.isRecording
            ? String(localized: "Pause Recording", bundle: RockxyLocalization.bundle)
            : String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
    }

    private var canClearSession: Bool {
        TrafficCommandAvailability.canClearSession(
            transactionCount: coordinator.transactions.count,
            logCount: coordinator.logEntries.count,
            hasSessionProvenance: coordinator.sessionProvenance != nil,
            isClearingSession: coordinator.isClearingSession
        )
    }

    private var canDetachInspector: Bool {
        coordinator.selectedTransaction != nil && coordinator.selectedTransactionIDs.count <= 1
    }

    /// Arms a single-shot observation of the coordinator's toolbar-relevant state and re-arms
    /// after each change. `withObservationTracking` fires `onChange` exactly once, so the handler
    /// re-registers itself. Both the handler and its follow-up task capture `self` weakly, so a
    /// deallocated toolbar simply stops re-arming — nothing keeps the coordinator alive.
    private func armObservation() {
        withObservationTracking {
            _ = coordinator.isProxyRunning
            _ = coordinator.hasPayloadInspectorSelection
            _ = coordinator.isBottomInspectorEffectivelyPresented
            _ = coordinator.isContextDockVisible
            _ = coordinator.isRecording
            _ = coordinator.transactions.count
            _ = coordinator.logEntries.count
            _ = coordinator.sessionProvenance
            _ = coordinator.isClearingSession
            _ = coordinator.selectedTransaction
            _ = coordinator.selectedTransactionIDs
            // Re-arm when the runtime language changes so existing toolbar items refresh
            // their localized labels/palette labels/tooltips in place.
            _ = AppLanguageController.shared.selectedOptionID
        } onChange: { [weak self] in
            // `onChange` runs inside the mutating turn. Hop to a fresh main-actor turn and yield
            // before touching AppKit-owned toolbar items: mutating NSToolbarItem geometry while
            // SwiftUI is still reconciling a hosted view can re-enter NSHostingView layout and
            // leave a newly opened tool window with a skipped (blank) content pass.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else {
                    return
                }
                self.syncActionItems()
                self.refreshLocalizedLabelsIfLanguageChanged()
                self.armObservation()
            }
        }
    }

    /// Re-applies every managed item's localized label, palette label, tooltip, and
    /// possible labels when the runtime language has changed since the last pass. The
    /// toolbar's identifiers, order, customization, actions, and visibility are left
    /// untouched — only the localized text is refreshed on the existing items.
    private func refreshLocalizedLabelsIfLanguageChanged() {
        let current = AppLanguageController.shared.selectedOptionID
        guard current != lastLanguageOptionID else {
            return
        }
        lastLanguageOptionID = current
        for item in managedToolbar.items {
            guard let refreshed = toolbar(
                managedToolbar,
                itemForItemIdentifier: item.itemIdentifier,
                willBeInsertedIntoToolbar: true
            ) else {
                continue
            }
            item.label = refreshed.label
            item.paletteLabel = refreshed.paletteLabel
            if let toolTip = refreshed.toolTip {
                item.toolTip = toolTip
            }
            if !refreshed.possibleLabels.isEmpty {
                item.possibleLabels = refreshed.possibleLabels
            }
        }
    }

    private func makeSidebarToggleItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.sidebarToggleIdentifier,
            label: String(localized: "Source List", bundle: RockxyLocalization.bundle),
            systemImage: "sidebar.leading",
            action: #selector(toggleSidebar(_:))
        )
        item.isBordered = true
        item.toolTip = String(localized: "Show or hide the Source List", bundle: RockxyLocalization.bundle)
        return item
    }

    private func makeProxyToggleItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.proxyToggleIdentifier,
            label: coordinator.isProxyRunning
                ? String(localized: "Stop", bundle: RockxyLocalization.bundle)
                : String(localized: "Start", bundle: RockxyLocalization.bundle),
            paletteLabel: String(localized: "Start or Stop Proxy", bundle: RockxyLocalization.bundle),
            systemImage: coordinator.isProxyRunning ? "stop.fill" : "play.fill",
            action: #selector(toggleProxy(_:))
        )
        item.possibleLabels = [
            String(localized: "Start", bundle: RockxyLocalization.bundle),
            String(localized: "Stop", bundle: RockxyLocalization.bundle)
        ]
        item.visibilityPriority = .high
        item.toolTip = proxyToolTip
        return item
    }

    private func makeDeveloperHubItem() -> NSToolbarItem {
        imageItem(
            identifier: Self.developerHubIdentifier,
            label: String(localized: "Developer Hub", bundle: RockxyLocalization.bundle),
            systemImage: "command",
            action: #selector(openDeveloperHub(_:))
        )
    }

    private func makeBottomInspectorItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.bottomInspectorIdentifier,
            label: String(localized: "Bottom Inspector", bundle: RockxyLocalization.bundle),
            systemImage: "rectangle.split.1x2",
            action: #selector(toggleBottomInspector(_:))
        )
        item.isEnabled = coordinator.canToggleBottomInspector
        item.toolTip = bottomInspectorToolTip
        return item
    }

    private func makeContextDockItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.contextDockIdentifier,
            label: String(localized: "Context Dock", bundle: RockxyLocalization.bundle),
            systemImage: "sidebar.trailing",
            action: #selector(toggleContextDock(_:))
        )
        item.toolTip = contextDockToolTip
        return item
    }

    private func makeRecordingItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.recordingIdentifier,
            label: coordinator.isRecording
                ? String(localized: "Pause Recording", bundle: RockxyLocalization.bundle)
                : String(localized: "Resume Recording", bundle: RockxyLocalization.bundle),
            paletteLabel: String(localized: "Toggle Recording", bundle: RockxyLocalization.bundle),
            systemImage: coordinator.isRecording ? "pause.circle" : "record.circle",
            action: #selector(toggleRecording(_:))
        )
        item.possibleLabels = [
            String(localized: "Pause Recording", bundle: RockxyLocalization.bundle),
            String(localized: "Resume Recording", bundle: RockxyLocalization.bundle),
        ]
        item.isEnabled = coordinator.isProxyRunning
        item.toolTip = recordingToolTip
        return item
    }

    private func makeComposeItem() -> NSToolbarItem {
        imageItem(
            identifier: Self.composeIdentifier,
            label: String(localized: "Compose", bundle: RockxyLocalization.bundle),
            systemImage: "square.and.pencil",
            action: #selector(composeRequest(_:))
        )
    }

    private func makeClearSessionItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.clearSessionIdentifier,
            label: String(localized: "Clear", bundle: RockxyLocalization.bundle),
            paletteLabel: String(localized: "Clear Session", bundle: RockxyLocalization.bundle),
            systemImage: "trash",
            action: #selector(clearSession(_:))
        )
        item.isEnabled = canClearSession
        item.toolTip = String(localized: "Clear the current traffic session", bundle: RockxyLocalization.bundle)
        return item
    }

    private func makeDetachedInspectorItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.detachedInspectorIdentifier,
            label: String(localized: "Detach Inspector", bundle: RockxyLocalization.bundle),
            systemImage: "rectangle.on.rectangle.angled",
            action: #selector(detachInspector(_:))
        )
        item.isEnabled = canDetachInspector
        item.toolTip = canDetachInspector
            ? String(
                localized: "Open the selected request in a separate Inspector window",
                bundle: RockxyLocalization.bundle
            )
            : String(localized: "Select one request to detach its Inspector", bundle: RockxyLocalization.bundle)
        return item
    }

    private func makeToolWindowItem(_ descriptor: ToolWindowItemDescriptor) -> NSToolbarItem {
        imageItem(
            identifier: descriptor.identifier,
            label: descriptor.label,
            systemImage: descriptor.systemImage,
            action: #selector(openToolWindow(_:))
        )
    }

    private func imageItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        paletteLabel: String? = nil,
        systemImage: String,
        action: Selector
    )
        -> NSToolbarItem
    {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = paletteLabel ?? label
        item.toolTip = label
        item.target = self
        item.action = action
        item.autovalidates = false
        item.isBordered = true
        item.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: label
        )
        return item
    }

    private func hostingItem(
        identifier: NSToolbarItem.Identifier,
        rootView: AnyView
    )
        -> NSToolbarItem
    {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.intrinsicContentSize]

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = controller.view
        item.visibilityPriority = .high
        objc_setAssociatedObject(
            item,
            &NativeWorkspaceToolbarHostingAssociation.key,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return item
    }

    private func syncActionItems() {
        let isRunning = coordinator.isProxyRunning
        let label = isRunning ? String(localized: "Stop", bundle: RockxyLocalization.bundle) : String(
            localized: "Start",
            bundle: RockxyLocalization.bundle
        )
        let proxyToggleItem = toolbarItem(identifier: Self.proxyToggleIdentifier)
        proxyToggleItem?.label = label
        proxyToggleItem?.toolTip = proxyToolTip
        proxyToggleItem?.image = NSImage(
            systemSymbolName: isRunning ? "stop.fill" : "play.fill",
            accessibilityDescription: label
        )

        let bottomInspectorItem = toolbarItem(identifier: Self.bottomInspectorIdentifier)
        bottomInspectorItem?.isEnabled = coordinator.canToggleBottomInspector
        bottomInspectorItem?.toolTip = bottomInspectorToolTip

        toolbarItem(identifier: Self.contextDockIdentifier)?.toolTip = contextDockToolTip

        let recordingItem = toolbarItem(identifier: Self.recordingIdentifier)
        let recordingLabel = coordinator.isRecording
            ? String(localized: "Pause Recording", bundle: RockxyLocalization.bundle)
            : String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
        recordingItem?.label = recordingLabel
        recordingItem?.isEnabled = coordinator.isProxyRunning
        recordingItem?.toolTip = recordingToolTip
        recordingItem?.image = NSImage(
            systemSymbolName: coordinator.isRecording ? "pause.circle" : "record.circle",
            accessibilityDescription: recordingLabel
        )

        toolbarItem(identifier: Self.clearSessionIdentifier)?.isEnabled = canClearSession

        let detachedInspectorItem = toolbarItem(identifier: Self.detachedInspectorIdentifier)
        detachedInspectorItem?.isEnabled = canDetachInspector
        detachedInspectorItem?.toolTip = canDetachInspector
            ? String(
                localized: "Open the selected request in a separate Inspector window",
                bundle: RockxyLocalization.bundle
            )
            : String(localized: "Select one request to detach its Inspector", bundle: RockxyLocalization.bundle)
    }

    private func toolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        managedToolbar.items.first { $0.itemIdentifier == identifier }
    }

    @objc
    private func toggleSidebar(_ sender: Any?) {
        guard let splitViewController else {
            return
        }
        splitViewController.setSidebarPresented(
            !splitViewController.isSidebarPresented,
            animated: true
        )
    }

    @objc
    private func toggleProxy(_ sender: Any?) {
        // Starting capture synchronously mutates observable SwiftUI state from this
        // AppKit toolbar action. On macOS 26 that re-enters the toolbar's hosting
        // views and can poison the next tool-window layout pass. Leave the AppKit
        // action turn before beginning the proxy state transition.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.onToggleProxy()
        }
    }

    @objc
    private func openDeveloperHub(_ sender: Any?) {
        // `openWindow` builds another SwiftUI host. Running it inline from an AppKit
        // toolbar target can re-enter SwiftUI layout when capture-state toolbar updates
        // are settling, which macOS records as an invalid configuration and skips.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.onOpenDeveloperHub()
        }
    }

    @objc
    private func toggleBottomInspector(_ sender: Any?) {
        coordinator.toggleInspectorBottom()
    }

    @objc
    private func toggleContextDock(_ sender: Any?) {
        coordinator.toggleInspectorRight()
    }

    @objc
    private func toggleRecording(_ sender: Any?) {
        coordinator.toggleRecording()
    }

    @objc
    private func composeRequest(_ sender: Any?) {
        ComposeStore.shared.requestBlankDraft()
        openToolWindow(id: "compose")
    }

    @objc
    private func clearSession(_ sender: Any?) {
        guard canClearSession else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.coordinator.clearSession()
        }
    }

    @objc
    private func detachInspector(_ sender: Any?) {
        guard canDetachInspector,
              let transaction = coordinator.selectedTransaction else
        {
            return
        }
        DetachedInspectorStore.shared.present(
            transaction: transaction,
            highlightContext: coordinator.activeInspectorHighlightContext()
        )
        openToolWindow(id: "detachedInspector")
    }

    @objc
    private func openToolWindow(_ sender: Any?) {
        guard let item = sender as? NSToolbarItem,
              let descriptor = Self.toolWindowItemDescriptors.first(where: {
                  $0.identifier == item.itemIdentifier
              }) else
        {
            return
        }
        openToolWindow(id: descriptor.windowID)
    }

    private func openToolWindow(id: String) {
        // Opening a SwiftUI scene inline from an AppKit toolbar target can re-enter
        // the unified toolbar's hosted views. Leave the action turn first, matching
        // the existing Developer Hub safety boundary.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.onOpenToolWindow(id)
        }
    }
}

// MARK: - NativeWorkspaceSplitViewController + Toolbar

extension NativeWorkspaceSplitViewController {
    func installToolbarIfNeeded(
        window: NSWindow,
        configuration: NativeWorkspaceToolbarConfiguration
    ) {
        if let nativeToolbar,
           window.toolbar === nativeToolbar.managedToolbar
        {
            return
        }

        let toolbar = NativeWorkspaceToolbar(
            splitViewController: self,
            configuration: configuration
        )
        attachNativeToolbar(toolbar, to: window)
    }

    /// Installs a pre-built toolbar as this controller's owned toolbar. The controller strongly
    /// retains the toolbar through its associated object while the toolbar holds only a weak
    /// reference back, so releasing the controller deallocates both.
    func attachNativeToolbar(_ toolbar: NativeWorkspaceToolbar, to window: NSWindow) {
        nativeToolbar = toolbar
        window.toolbar = toolbar.managedToolbar
        toolbar.startObservingState()
    }

    private(set) var nativeToolbar: NativeWorkspaceToolbar? {
        get {
            objc_getAssociatedObject(
                self,
                &NativeWorkspaceToolbarAssociation.key
            ) as? NativeWorkspaceToolbar
        }
        set {
            objc_setAssociatedObject(
                self,
                &NativeWorkspaceToolbarAssociation.key,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

// MARK: - NativeWorkspaceToolbarAssociation

private enum NativeWorkspaceToolbarAssociation {
    static var key: UInt8 = 0
}

// MARK: - NativeWorkspaceToolbarHostingAssociation

private enum NativeWorkspaceToolbarHostingAssociation {
    static var key: UInt8 = 0
}
