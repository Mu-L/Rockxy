import AppKit
import SwiftUI

// MARK: - NativeWorkspaceToolbarConfiguration

@MainActor
struct NativeWorkspaceToolbarConfiguration {
    // MARK: Lifecycle

    init(
        coordinator: MainContentCoordinator,
        onOpenDeveloperHub: @escaping () -> Void,
        onToggleProxy: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.onOpenDeveloperHub = onOpenDeveloperHub
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
    ]

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
            item.label = String(localized: "Source List Divider")
            // The tracking separator has only a narrow preview cell in AppKit's draggable
            // default-set row. Keep its descriptive toolbar label, but use a compact palette
            // label so it does not collide with Flexible Space and Project labels.
            item.paletteLabel = String(localized: "Divider")
            return item
        case Self.projectSelectorIdentifier:
            let item = hostingItem(
                identifier: itemIdentifier,
                rootView: AnyView(ProjectToolbarSelectorView(coordinator: coordinator))
            )
            item.label = String(localized: "Project")
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
            item.label = String(localized: "Proxy Status")
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
        default:
            return nil
        }
    }

    // MARK: Private

    private weak var splitViewController: NativeWorkspaceSplitViewController?
    private let coordinator: MainContentCoordinator
    private let onOpenDeveloperHub: () -> Void
    private let onToggleProxy: () -> Void
    private var isObservingState = false

    private var proxyToolTip: String {
        coordinator.isProxyRunning
            ? String(localized: "Stop proxy")
            : String(localized: "Start proxy")
    }

    private var bottomInspectorToolTip: String {
        guard coordinator.canToggleBottomInspector else {
            return String(localized: "Select a request to use the bottom inspector")
        }
        return coordinator.isBottomInspectorEffectivelyPresented
            ? String(localized: "Hide Bottom Inspector")
            : String(localized: "Show Bottom Inspector")
    }

    private var contextDockToolTip: String {
        coordinator.isContextDockVisible
            ? String(localized: "Hide Context Dock")
            : String(localized: "Show Context Dock")
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
                self.armObservation()
            }
        }
    }

    private func makeSidebarToggleItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.sidebarToggleIdentifier,
            label: String(localized: "Source List"),
            systemImage: "sidebar.leading",
            action: #selector(toggleSidebar(_:))
        )
        item.isBordered = true
        item.isNavigational = true
        item.toolTip = String(localized: "Show or hide the Source List")
        return item
    }

    private func makeProxyToggleItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.proxyToggleIdentifier,
            label: coordinator.isProxyRunning
                ? String(localized: "Stop")
                : String(localized: "Start"),
            paletteLabel: String(localized: "Start or Stop Proxy"),
            systemImage: coordinator.isProxyRunning ? "stop.fill" : "play.fill",
            action: #selector(toggleProxy(_:))
        )
        item.possibleLabels = [String(localized: "Start"), String(localized: "Stop")]
        item.visibilityPriority = .high
        item.toolTip = proxyToolTip
        return item
    }

    private func makeDeveloperHubItem() -> NSToolbarItem {
        imageItem(
            identifier: Self.developerHubIdentifier,
            label: String(localized: "Developer Hub"),
            systemImage: "command",
            action: #selector(openDeveloperHub(_:))
        )
    }

    private func makeBottomInspectorItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.bottomInspectorIdentifier,
            label: String(localized: "Bottom Inspector"),
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
            label: String(localized: "Context Dock"),
            systemImage: "sidebar.trailing",
            action: #selector(toggleContextDock(_:))
        )
        item.toolTip = contextDockToolTip
        return item
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
        let label = isRunning ? String(localized: "Stop") : String(localized: "Start")
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
