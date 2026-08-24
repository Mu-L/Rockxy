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
        configuration: NativeWorkspaceToolbarConfiguration
    ) {
        self.splitViewController = splitViewController
        coordinator = configuration.coordinator
        onOpenDeveloperHub = configuration.onOpenDeveloperHub
        onToggleProxy = configuration.onToggleProxy
        managedToolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        super.init()

        managedToolbar.delegate = self
        managedToolbar.displayMode = .iconOnly
        managedToolbar.allowsUserCustomization = false
        managedToolbar.autosavesConfiguration = false
        managedToolbar.centeredItemIdentifiers = [Self.proxyStatusIdentifier]
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: Internal

    static let toolbarIdentifier = NSToolbar.Identifier(
        "\(RockxyIdentity.current.logSubsystem).main.toolbar"
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
    static let actionGroupIdentifier = NSToolbarItem.Identifier(
        "\(RockxyIdentity.current.logSubsystem).toolbar.actions"
    )

    let managedToolbar: NSToolbar

    func startObservingState() {
        syncActionItems()
        observationTask?.cancel()
        observationTask = Task { [weak self, weak coordinator] in
            guard let coordinator else {
                return
            }
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = coordinator.isProxyRunning
                        _ = coordinator.hasPayloadInspectorSelection
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else {
                    return
                }

                // Observation can resume while SwiftUI is still reconciling one of the
                // toolbar's hosted views. Mutating NSToolbarItem geometry in that turn can
                // make AppKit re-enter NSHostingView layout and leave a newly opened tool
                // window with a skipped (blank) content pass. Give the current render turn
                // back to SwiftUI before updating AppKit-owned toolbar items.
                await Task.yield()
                guard !Task.isCancelled else {
                    return
                }
                self?.syncActionItems()
            }
        }
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Self.sidebarToggleIdentifier,
            Self.sidebarTrackingSeparatorIdentifier,
            Self.projectSelectorIdentifier,
            .flexibleSpace,
            Self.proxyStatusIdentifier,
            .flexibleSpace,
            Self.actionGroupIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sidebarToggleIdentifier:
            return makeSidebarToggleItem()
        case Self.sidebarTrackingSeparatorIdentifier:
            return NSTrackingSeparatorToolbarItem(
                identifier: Self.sidebarTrackingSeparatorIdentifier,
                splitView: splitViewController.splitView,
                dividerIndex: 0
            )
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
            return hostingItem(
                identifier: itemIdentifier,
                rootView: AnyView(
                    ProxyToolbarStatusView(coordinator: coordinator)
                )
            )
        case Self.actionGroupIdentifier:
            return makeActionGroup()
        default:
            return nil
        }
    }

    // MARK: Private

    private let splitViewController: NativeWorkspaceSplitViewController
    private let coordinator: MainContentCoordinator
    private let onOpenDeveloperHub: () -> Void
    private let onToggleProxy: () -> Void
    private var hostingControllers: [
        NSToolbarItem.Identifier: NSHostingController<AnyView>
    ] = [:]
    private var observationTask: Task<Void, Never>?
    private weak var proxyToggleItem: NSToolbarItem?
    private weak var bottomInspectorItem: NSToolbarItem?

    private func makeSidebarToggleItem() -> NSToolbarItem {
        let item = imageItem(
            identifier: Self.sidebarToggleIdentifier,
            label: String(localized: "Toggle Source List"),
            systemImage: "sidebar.leading",
            action: #selector(toggleSidebar(_:))
        )
        item.isBordered = true
        return item
    }

    private func makeActionGroup() -> NSToolbarItemGroup {
        let proxyItem = imageItem(
            identifier: NSToolbarItem.Identifier(
                "\(Self.actionGroupIdentifier.rawValue).proxy"
            ),
            label: coordinator.isProxyRunning
                ? String(localized: "Stop")
                : String(localized: "Start"),
            systemImage: coordinator.isProxyRunning ? "stop.fill" : "play.fill",
            action: #selector(toggleProxy(_:))
        )
        proxyToggleItem = proxyItem

        let developerHubItem = imageItem(
            identifier: NSToolbarItem.Identifier(
                "\(Self.actionGroupIdentifier.rawValue).developerHub"
            ),
            label: String(localized: "Dev Hub"),
            systemImage: "command",
            action: #selector(openDeveloperHub(_:))
        )
        let bottomInspectorItem = imageItem(
            identifier: NSToolbarItem.Identifier(
                "\(Self.actionGroupIdentifier.rawValue).bottomInspector"
            ),
            label: String(localized: "Bottom Inspector"),
            systemImage: "rectangle.split.1x2",
            action: #selector(toggleBottomInspector(_:))
        )
        bottomInspectorItem.isEnabled = coordinator.canToggleBottomInspector
        bottomInspectorItem.toolTip = bottomInspectorToolTip
        self.bottomInspectorItem = bottomInspectorItem
        let contextDockItem = imageItem(
            identifier: NSToolbarItem.Identifier(
                "\(Self.actionGroupIdentifier.rawValue).contextDock"
            ),
            label: String(localized: "Context Dock"),
            systemImage: "sidebar.trailing",
            action: #selector(toggleContextDock(_:))
        )

        let group = NSToolbarItemGroup(itemIdentifier: Self.actionGroupIdentifier)
        group.label = String(localized: "Workspace Actions")
        group.paletteLabel = group.label
        group.subitems = [
            proxyItem,
            developerHubItem,
            bottomInspectorItem,
            contextDockItem,
        ]
        return group
    }

    private func imageItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemImage: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: label
        )
        return item
    }

    private func hostingItem(
        identifier: NSToolbarItem.Identifier,
        rootView: AnyView
    ) -> NSToolbarItem {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.intrinsicContentSize]
        hostingControllers[identifier] = controller

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = controller.view
        item.visibilityPriority = .high
        return item
    }

    private func syncActionItems() {
        let isRunning = coordinator.isProxyRunning
        let label = isRunning ? String(localized: "Stop") : String(localized: "Start")
        proxyToggleItem?.label = label
        proxyToggleItem?.paletteLabel = label
        proxyToggleItem?.toolTip = isRunning
            ? String(localized: "Stop proxy")
            : String(localized: "Start proxy")
        proxyToggleItem?.image = NSImage(
            systemSymbolName: isRunning ? "stop.fill" : "play.fill",
            accessibilityDescription: label
        )
        bottomInspectorItem?.isEnabled = coordinator.canToggleBottomInspector
        bottomInspectorItem?.toolTip = bottomInspectorToolTip
    }

    private var bottomInspectorToolTip: String {
        coordinator.canToggleBottomInspector
            ? String(localized: "Show or hide the bottom inspector panel")
            : String(localized: "Select a request to use the bottom inspector")
    }

    @objc
    private func toggleSidebar(_ sender: Any?) {
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
           window.toolbar === nativeToolbar.managedToolbar {
            return
        }

        let toolbar = NativeWorkspaceToolbar(
            splitViewController: self,
            configuration: configuration
        )
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
