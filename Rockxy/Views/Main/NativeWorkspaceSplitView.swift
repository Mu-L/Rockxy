import AppKit
import SwiftUI

// MARK: - NativeSplitDividerInteraction

/// Keeps thin native dividers visually quiet while giving them a forgiving pointer target.
/// Twelve points follows the interaction footprint of standard macOS splitters without adding
/// visible chrome or stealing meaningful space from either pane.
enum NativeSplitDividerInteraction {
    static let minimumHitThickness: CGFloat = 12
    /// AppKit performs user divider drags at priority 490. Pane holding priorities at
    /// `.defaultHigh` (750) therefore make a divider look draggable while Auto Layout snaps it
    /// straight back. Keep utility panes just above the flexible workspace, but below drag.
    static let utilityPaneHoldingPriority = NSLayoutConstraint.Priority(rawValue: 251)

    static func expandedHitRect(
        systemRect: NSRect,
        drawnRect: NSRect,
        isVertical: Bool
    )
        -> NSRect
    {
        guard systemRect.width.isFinite,
              systemRect.height.isFinite,
              drawnRect.width.isFinite,
              drawnRect.height.isFinite else
        {
            return systemRect
        }

        let expandedDrawnRect: NSRect
        if isVertical {
            let expansion = max(0, minimumHitThickness - drawnRect.width) / 2
            expandedDrawnRect = drawnRect.insetBy(dx: -expansion, dy: 0)
        } else {
            let expansion = max(0, minimumHitThickness - drawnRect.height) / 2
            expandedDrawnRect = drawnRect.insetBy(dx: 0, dy: -expansion)
        }
        return systemRect.union(expandedDrawnRect)
    }
}

// MARK: - NativeWorkspaceSplitView

/// Hosts the source list, workspace, and Context Dock in one native root split.
///
/// Keeping both utility columns as semantic `NSSplitViewItem` instances lets their
/// materials and dividers participate in the full-size unified titlebar exactly like
/// native Mac source lists and inspectors.
struct NativeWorkspaceSplitView<Sidebar: View, Workspace: View, Inspector: View>:
    NSViewControllerRepresentable
{
    // MARK: Lifecycle

    init(
        isSidebarPresented: Binding<Bool>,
        isInspectorPresented: Binding<Bool>,
        autosaveName: String,
        sidebarMinimumWidth: CGFloat,
        sidebarIdealWidth: CGFloat,
        sidebarMaximumWidth: CGFloat,
        workspaceMinimumWidth: CGFloat,
        inspectorMinimumWidth: CGFloat,
        inspectorIdealWidth: CGFloat,
        toolbarConfiguration: NativeWorkspaceToolbarConfiguration? = nil,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder workspace: @escaping () -> Workspace,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        _isSidebarPresented = isSidebarPresented
        _isInspectorPresented = isInspectorPresented
        self.autosaveName = autosaveName
        self.sidebarMinimumWidth = sidebarMinimumWidth
        self.sidebarIdealWidth = sidebarIdealWidth
        self.sidebarMaximumWidth = sidebarMaximumWidth
        self.workspaceMinimumWidth = workspaceMinimumWidth
        self.inspectorMinimumWidth = inspectorMinimumWidth
        self.inspectorIdealWidth = inspectorIdealWidth
        self.toolbarConfiguration = toolbarConfiguration
        self.sidebar = sidebar
        self.workspace = workspace
        self.inspector = inspector
    }

    // MARK: Internal

    // MARK: - Coordinator

    final class Coordinator {
        // MARK: Internal

        func recordInitialPresentation(sidebar: Bool, inspector: Bool) {
            lastAppliedSidebarPresentation = sidebar
            lastAppliedInspectorPresentation = inspector
        }

        func shouldApplySidebarPresentation(_ isPresented: Bool) -> Bool {
            guard lastAppliedSidebarPresentation != isPresented else {
                return false
            }
            lastAppliedSidebarPresentation = isPresented
            return true
        }

        func shouldApplyInspectorPresentation(_ isPresented: Bool) -> Bool {
            guard lastAppliedInspectorPresentation != isPresented else {
                return false
            }
            lastAppliedInspectorPresentation = isPresented
            return true
        }

        // MARK: Private

        private var lastAppliedSidebarPresentation: Bool?
        private var lastAppliedInspectorPresentation: Bool?
    }

    @Binding var isSidebarPresented: Bool
    @Binding var isInspectorPresented: Bool

    let autosaveName: String
    let sidebarMinimumWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaximumWidth: CGFloat
    let workspaceMinimumWidth: CGFloat
    let inspectorMinimumWidth: CGFloat
    let inspectorIdealWidth: CGFloat
    let toolbarConfiguration: NativeWorkspaceToolbarConfiguration?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let workspace: () -> Workspace
    @ViewBuilder let inspector: () -> Inspector

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> NativeWorkspaceSplitViewController {
        let sidebarController = hostingController(content: sidebar)
        let workspaceController = hostingController(content: workspace)
        let inspectorController = hostingController(content: inspector)

        context.coordinator.recordInitialPresentation(
            sidebar: isSidebarPresented,
            inspector: isInspectorPresented
        )

        let controller = NativeWorkspaceSplitViewController()
        controller.toolbarConfiguration = toolbarConfiguration
        controller.configure(
            sidebarController: sidebarController,
            workspaceController: workspaceController,
            inspectorController: inspectorController,
            isSidebarPresented: isSidebarPresented,
            isInspectorPresented: isInspectorPresented,
            layout: NativeWorkspaceSplitLayout(
                autosaveName: autosaveName,
                sidebarMinimumWidth: sidebarMinimumWidth,
                sidebarIdealWidth: sidebarIdealWidth,
                sidebarMaximumWidth: sidebarMaximumWidth,
                workspaceMinimumWidth: workspaceMinimumWidth,
                inspectorMinimumWidth: inspectorMinimumWidth,
                inspectorIdealWidth: inspectorIdealWidth
            )
        )
        updateVisibilityCallbacks(on: controller)
        return controller
    }

    func updateNSViewController(
        _ controller: NativeWorkspaceSplitViewController,
        context: Context
    ) {
        updateVisibilityCallbacks(on: controller)
        if context.coordinator.shouldApplySidebarPresentation(isSidebarPresented) {
            controller.setSidebarPresented(isSidebarPresented, animated: true)
        }
        if context.coordinator.shouldApplyInspectorPresentation(isInspectorPresented) {
            controller.setInspectorPresented(isInspectorPresented, animated: true)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: NativeWorkspaceSplitViewController,
        context: Context
    )
        -> CGSize?
    {
        let naturalWidth = sidebarIdealWidth + workspaceMinimumWidth + inspectorIdealWidth
        let resolved = proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: naturalWidth, height: MainWindowLayoutMetrics.defaultHeight)
        )
        guard resolved.width.isFinite, resolved.height.isFinite else {
            return nil
        }
        return resolved
    }

    // MARK: Private

    private func hostingController<Content: View>(
        content: @escaping () -> Content
    )
        -> NSHostingController<NativeWorkspaceDeferredContent<Content>>
    {
        let controller = NSHostingController(
            rootView: NativeWorkspaceDeferredContent(content: content)
        )
        controller.sizingOptions = []
        return controller
    }

    private func updateVisibilityCallbacks(on controller: NativeWorkspaceSplitViewController) {
        let sidebarPresentation = $isSidebarPresented
        controller.onSidebarVisibilityChanged = { isVisible in
            guard sidebarPresentation.wrappedValue != isVisible else {
                return
            }
            sidebarPresentation.wrappedValue = isVisible
        }

        let inspectorPresentation = $isInspectorPresented
        controller.onInspectorVisibilityChanged = { isVisible in
            guard inspectorPresentation.wrappedValue != isVisible else {
                return
            }
            inspectorPresentation.wrappedValue = isVisible
        }
    }
}

// MARK: - NativeWorkspaceDeferredContent

struct NativeWorkspaceDeferredContent<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}

// MARK: - NativeWorkspaceSplitLayout

struct NativeWorkspaceSplitLayout {
    let autosaveName: String
    let sidebarMinimumWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaximumWidth: CGFloat
    let workspaceMinimumWidth: CGFloat
    let inspectorMinimumWidth: CGFloat
    let inspectorIdealWidth: CGFloat
}

// MARK: - NativeWorkspaceSplitSizing

/// Pure sizing math for the workspace split's initial layout pass.
///
/// Kept free of AppKit state so startup readiness and ideal-divider placement can be
/// verified deterministically without a live window.
enum NativeWorkspaceSplitSizing {
    struct IdealPlacement: Equatable {
        var leadingDividerPosition: CGFloat?
        var trailingDividerPosition: CGFloat?
    }

    /// Bounds are usable once both dimensions are finite and strictly positive.
    ///
    /// Reads the raw stored size rather than `CGRect.width`/`.height`, which standardize a
    /// negative size and report it as positive — a raw-negative provisional frame must be
    /// rejected, not silently accepted.
    static func isLayoutReady(_ bounds: CGRect) -> Bool {
        let width = bounds.size.width
        let height = bounds.size.height
        return width.isFinite
            && height.isFinite
            && width > 0
            && height > 0
    }

    /// Whether `totalWidth` can seat every currently requested presented pane at its declared
    /// minimum thickness, including the workspace minimum and each active divider.
    ///
    /// A merely positive, finite width is not sufficient readiness: an early provisional AppKit
    /// layout pass can report a positive-but-too-narrow width. Consuming pending visibility and
    /// latching the initial layout there seats the panes at their minima and blocks the later,
    /// correctly-sized pass from applying ideal widths.
    static func canSeatRequestedMinima(
        totalWidth: CGFloat,
        dividerThickness: CGFloat,
        sidebarPresented: Bool,
        inspectorPresented: Bool,
        sidebarMinimumWidth: CGFloat,
        workspaceMinimumWidth: CGFloat,
        inspectorMinimumWidth: CGFloat
    )
        -> Bool
    {
        guard totalWidth.isFinite, totalWidth > 0 else {
            return false
        }

        let sidebarWidth = sidebarPresented ? sidebarMinimumWidth : 0
        let inspectorWidth = inspectorPresented ? inspectorMinimumWidth : 0
        let leadingDivider = sidebarPresented ? dividerThickness : 0
        let trailingDivider = inspectorPresented ? dividerThickness : 0

        let required = sidebarWidth
            + inspectorWidth
            + leadingDivider
            + trailingDivider
            + workspaceMinimumWidth
        return totalWidth >= required
    }

    /// Ideal divider positions for the presented panes, or `nil` when the split view is too
    /// narrow to seat every presented pane at its declared minimum thickness (dividers
    /// included). Returning `nil` tells the caller to defer to AppKit constraints instead of
    /// forcing a position that would drive a pane — and its geometry — negative.
    static func idealPlacement(
        totalWidth: CGFloat,
        dividerThickness: CGFloat,
        sidebarPresented: Bool,
        inspectorPresented: Bool,
        sidebarIdealWidth: CGFloat,
        inspectorIdealWidth: CGFloat,
        sidebarMinimumWidth: CGFloat,
        workspaceMinimumWidth: CGFloat,
        inspectorMinimumWidth: CGFloat
    )
        -> IdealPlacement?
    {
        guard totalWidth.isFinite, totalWidth > 0 else {
            return nil
        }

        let sidebarWidth = sidebarPresented ? max(sidebarIdealWidth, sidebarMinimumWidth) : 0
        let inspectorWidth = inspectorPresented ? max(inspectorIdealWidth, inspectorMinimumWidth) : 0
        let leadingDivider = sidebarPresented ? dividerThickness : 0
        let trailingDivider = inspectorPresented ? dividerThickness : 0

        let workspaceWidth = totalWidth
            - sidebarWidth
            - inspectorWidth
            - leadingDivider
            - trailingDivider
        guard workspaceWidth >= workspaceMinimumWidth else {
            return nil
        }

        return IdealPlacement(
            leadingDividerPosition: sidebarPresented ? sidebarWidth : nil,
            trailingDividerPosition: inspectorPresented
                ? totalWidth - inspectorWidth - trailingDivider
                : nil
        )
    }
}

// MARK: - NativeWorkspaceSplitViewController

@MainActor
final class NativeWorkspaceSplitViewController: NSSplitViewController {
    // MARK: Internal

    var onSidebarVisibilityChanged: ((Bool) -> Void)?
    var onInspectorVisibilityChanged: ((Bool) -> Void)?

    var toolbarConfiguration: NativeWorkspaceToolbarConfiguration?

    var isSidebarPresented: Bool {
        sidebarItem.map { !$0.isCollapsed } ?? false
    }

    var isInspectorPresented: Bool {
        inspectorItem.map { !$0.isCollapsed } ?? false
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        installWindowChromeIfNeeded()
        guard !didApplyInitialLayout else {
            return
        }
        let bounds = splitView.bounds
        guard NativeWorkspaceSplitSizing.isLayoutReady(bounds),
              NativeWorkspaceSplitSizing.canSeatRequestedMinima(
                  totalWidth: bounds.width,
                  dividerThickness: splitView.dividerThickness,
                  sidebarPresented: requestedSidebarVisibility,
                  inspectorPresented: requestedInspectorVisibility,
                  sidebarMinimumWidth: sidebarMinimumWidth,
                  workspaceMinimumWidth: workspaceMinimumWidth,
                  inspectorMinimumWidth: inspectorMinimumWidth
              ) else
        {
            return
        }
        didApplyInitialLayout = true

        if let pendingInitialSidebarVisibility {
            self.pendingInitialSidebarVisibility = nil
            setSidebarPresented(pendingInitialSidebarVisibility, animated: false)
        }
        if let pendingInitialInspectorVisibility {
            self.pendingInitialInspectorVisibility = nil
            setInspectorPresented(pendingInitialInspectorVisibility, animated: false)
        }

        if !hasAutosavedFrames {
            applyIdealInitialPositions(totalWidth: bounds.width)
        }
        isApplyingInitialState = false
    }

    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    )
        -> NSRect
    {
        let systemRect = super.splitView(
            splitView,
            effectiveRect: proposedEffectiveRect,
            forDrawnRect: drawnRect,
            ofDividerAt: dividerIndex
        )
        return NativeSplitDividerInteraction.expandedHitRect(
            systemRect: systemRect,
            drawnRect: drawnRect,
            isVertical: splitView.isVertical
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installWindowChromeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.installWindowChromeIfNeeded()
        }
    }

    func configure(
        sidebarController: NSViewController,
        workspaceController: NSViewController,
        inspectorController: NSViewController,
        isSidebarPresented: Bool,
        isInspectorPresented: Bool,
        layout: NativeWorkspaceSplitLayout
    ) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = layout.sidebarMinimumWidth
        sidebarItem.maximumThickness = layout.sidebarMaximumWidth
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .useConstraints
        sidebarItem.isSpringLoaded = true
        sidebarItem.holdingPriority = NativeSplitDividerInteraction.utilityPaneHoldingPriority

        let workspaceItem = NSSplitViewItem(viewController: workspaceController)
        workspaceItem.minimumThickness = layout.workspaceMinimumWidth
        workspaceItem.canCollapse = false
        workspaceItem.holdingPriority = .defaultLow

        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
        inspectorItem.minimumThickness = layout.inspectorMinimumWidth
        // AppKit's semantic inspector item applies a compact default maximum. A large finite
        // value keeps the native inspector behavior while making its real upper bound the
        // window and workspace minimum, without overflowing Auto Layout constraints.
        inspectorItem.maximumThickness = 10_000
        inspectorItem.canCollapse = true
        inspectorItem.collapseBehavior = .useConstraints
        inspectorItem.isSpringLoaded = true
        inspectorItem.holdingPriority = NativeSplitDividerInteraction.utilityPaneHoldingPriority

        addSplitViewItem(sidebarItem)
        addSplitViewItem(workspaceItem)
        addSplitViewItem(inspectorItem)

        let autosave = NSSplitView.AutosaveName(layout.autosaveName)
        hasAutosavedFrames = UserDefaults.standard.object(
            forKey: "NSSplitView Subview Frames \(autosave)"
        ) != nil
        splitView.autosaveName = autosave

        self.sidebarItem = sidebarItem
        self.inspectorItem = inspectorItem
        self.sidebarIdealWidth = layout.sidebarIdealWidth
        self.inspectorIdealWidth = layout.inspectorIdealWidth
        sidebarMinimumWidth = layout.sidebarMinimumWidth
        workspaceMinimumWidth = layout.workspaceMinimumWidth
        inspectorMinimumWidth = layout.inspectorMinimumWidth
        requestedSidebarVisibility = isSidebarPresented
        requestedInspectorVisibility = isInspectorPresented
        pendingInitialSidebarVisibility = isSidebarPresented
        pendingInitialInspectorVisibility = isInspectorPresented
        observeCollapseState(of: sidebarItem, isSidebar: true)
        observeCollapseState(of: inspectorItem, isSidebar: false)
        // Initial collapse/divider state is deferred to the first valid layout pass
        // (`viewDidLayout`). Applying it here, while the controller has zero-sized bounds,
        // is what produced startup `Invalid view geometry` faults.
    }

    func setSidebarPresented(_ isPresented: Bool, animated: Bool) {
        requestedSidebarVisibility = isPresented
        set(item: sidebarItem, presented: isPresented, animated: animated)
    }

    func setInspectorPresented(_ isPresented: Bool, animated: Bool) {
        requestedInspectorVisibility = isPresented
        set(item: inspectorItem, presented: isPresented, animated: animated)
    }

    // MARK: Private

    private weak var sidebarItem: NSSplitViewItem?
    private weak var inspectorItem: NSSplitViewItem?
    private var collapseObservations: [NSKeyValueObservation] = []
    private var sidebarIdealWidth: CGFloat = 250
    private var inspectorIdealWidth: CGFloat = 380
    private var sidebarMinimumWidth: CGFloat = 0
    private var workspaceMinimumWidth: CGFloat = 0
    private var inspectorMinimumWidth: CGFloat = 0
    private var requestedSidebarVisibility = true
    private var requestedInspectorVisibility = false
    private var pendingInitialSidebarVisibility: Bool?
    private var pendingInitialInspectorVisibility: Bool?
    private var hasAutosavedFrames = false
    private var didApplyInitialLayout = false
    private var isApplyingInitialState = true

    private func installWindowChromeIfNeeded() {
        guard let window = view.window else {
            return
        }
        NativeWorkspaceWindowChrome.configure(
            window,
            workspaceSplitController: self,
            toolbarConfiguration: toolbarConfiguration
        )
    }

    private func applyIdealInitialPositions(totalWidth: CGFloat) {
        guard let placement = NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: totalWidth,
            dividerThickness: splitView.dividerThickness,
            sidebarPresented: isSidebarPresented,
            inspectorPresented: isInspectorPresented,
            sidebarIdealWidth: sidebarIdealWidth,
            inspectorIdealWidth: inspectorIdealWidth,
            sidebarMinimumWidth: sidebarMinimumWidth,
            workspaceMinimumWidth: workspaceMinimumWidth,
            inspectorMinimumWidth: inspectorMinimumWidth
        ) else {
            // The window is too narrow to seat every presented pane at its minimum.
            // Skip ideal placement and let AppKit constraints choose a safe layout.
            return
        }

        if let leading = placement.leadingDividerPosition {
            splitView.setPosition(leading, ofDividerAt: 0)
        }
        if let trailing = placement.trailingDividerPosition {
            splitView.setPosition(trailing, ofDividerAt: 1)
        }
    }

    private func set(item: NSSplitViewItem?, presented: Bool, animated: Bool) {
        guard let item, item.isCollapsed == presented else {
            return
        }

        if animated, view.window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                item.animator().isCollapsed = !presented
            }
        } else {
            item.isCollapsed = !presented
        }
    }

    private func observeCollapseState(of item: NSSplitViewItem, isSidebar: Bool) {
        let observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.splitItemVisibilityDidChange(isSidebar: isSidebar)
            }
        }
        collapseObservations.append(observation)
    }

    private func splitItemVisibilityDidChange(isSidebar: Bool) {
        guard !isApplyingInitialState else {
            return
        }

        if isSidebar {
            let isVisible = isSidebarPresented
            guard isVisible != requestedSidebarVisibility else {
                return
            }
            requestedSidebarVisibility = isVisible
            onSidebarVisibilityChanged?(isVisible)
        } else {
            let isVisible = isInspectorPresented
            guard isVisible != requestedInspectorVisibility else {
                return
            }
            requestedInspectorVisibility = isVisible
            onInspectorVisibilityChanged?(isVisible)
        }
    }
}
