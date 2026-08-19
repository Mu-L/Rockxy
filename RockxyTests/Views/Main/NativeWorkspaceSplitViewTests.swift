import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct NativeWorkspaceSplitViewTests {
    // MARK: Internal

    @Test("Workspace defaults favor the Context Dock over the navigation sidebar")
    func flexibleInspectorWidthPolicy() {
        #expect(MainWindowLayoutMetrics.sidebarMinimumWidth == 200)
        #expect(MainWindowLayoutMetrics.sidebarIdealWidth == 250)
        #expect(MainWindowLayoutMetrics.sidebarMaximumWidth == 350)
        #expect(MainWindowLayoutMetrics.workspaceMinimumWidth == 320)
        #expect(MainWindowLayoutMetrics.contextDockMinimumWidth == 260)
        #expect(MainWindowLayoutMetrics.contextDockIdealWidth == 320)
        #expect(MainWindowLayoutMetrics.sidebarIdealWidth < MainWindowLayoutMetrics.contextDockIdealWidth)
    }

    @Test("Workspace uses one native vertical split for both utility columns")
    func nativeThreePaneConfiguration() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)

        #expect(controller.splitView.isVertical)
        #expect(controller.splitView.dividerStyle == .thin)
        #expect(controller.splitViewItems.count == 3)
        #expect(controller.splitViewItems[0].canCollapse)
        #expect(!controller.splitViewItems[1].canCollapse)
        #expect(controller.splitViewItems[2].canCollapse)
        #expect(controller.splitViewItems[0].minimumThickness == 200)
        #expect(controller.splitViewItems[0].maximumThickness == 350)
        #expect(controller.splitViewItems[1].minimumThickness == 320)
        #expect(controller.splitViewItems[2].minimumThickness == 220)
        #expect(controller.splitViewItems[2].maximumThickness == 10_000)
    }

    @Test("Context Dock sizing policy permits widths beyond the former maximum")
    func contextDockSupportsWideResize() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let availableInspectorWidth = 1_600
            - controller.splitView.dividerThickness * 2
            - controller.splitViewItems[0].minimumThickness
            - controller.splitViewItems[1].minimumThickness

        #expect(availableInspectorWidth > 520)
        #expect(controller.splitViewItems[2].maximumThickness >= availableInspectorWidth)
    }

    @Test("Vertical dividers have a forgiving horizontal drag target")
    func verticalDividerHitTarget() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let drawnRect = NSRect(x: 800, y: 0, width: 1, height: 700)
        let effectiveRect = controller.splitView(
            controller.splitView,
            effectiveRect: drawnRect,
            forDrawnRect: drawnRect,
            ofDividerAt: 1
        )

        #expect(effectiveRect.width >= NativeSplitDividerInteraction.minimumHitThickness)
        #expect(effectiveRect.minX < drawnRect.minX)
        #expect(effectiveRect.maxX > drawnRect.maxX)
    }

    @Test("Context Dock divider moves through a useful width range after layout")
    func contextDockDividerMovesAfterLayout() {
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_600, height: 700))

        controller.splitView.setPosition(900, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        let wideInspectorWidth = controller.splitViewItems[2].viewController.view.frame.width

        controller.splitView.setPosition(1_250, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        let compactInspectorWidth = controller.splitViewItems[2].viewController.view.frame.width

        #expect(wideInspectorWidth > compactInspectorWidth)
        #expect(wideInspectorWidth > 600)
        #expect(compactInspectorWidth >= 220)
    }

    @Test("Collapsing utility columns preserves all hosted pane controllers")
    func collapsePreservesPaneControllers() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let paneControllers = controller.splitViewItems.map(\.viewController)

        controller.setSidebarPresented(false, animated: false)
        controller.setInspectorPresented(false, animated: false)
        #expect(!controller.isSidebarPresented)
        #expect(!controller.isInspectorPresented)

        controller.setSidebarPresented(true, animated: false)
        controller.setInspectorPresented(true, animated: false)
        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        #expect(controller.splitViewItems.map(\.viewController).elementsEqual(
            paneControllers,
            by: { $0 === $1 }
        ))
    }

    @Test("Repeated SwiftUI updates coalesce both utility column presentations")
    func repeatedPresentationUpdatesAreCoalesced() {
        let coordinator = NativeWorkspaceSplitView<Color, Color, Color>.Coordinator()

        coordinator.recordInitialPresentation(sidebar: true, inspector: false)
        #expect(!coordinator.shouldApplySidebarPresentation(true))
        #expect(coordinator.shouldApplySidebarPresentation(false))
        #expect(!coordinator.shouldApplySidebarPresentation(false))
        #expect(!coordinator.shouldApplyInspectorPresentation(false))
        #expect(coordinator.shouldApplyInspectorPresentation(true))
        #expect(!coordinator.shouldApplyInspectorPresentation(true))
    }

    @Test("Workspace window chrome supports full-height native split materials")
    func fullSizeWindowChrome() {
        let window = NSWindow()

        NativeWorkspaceWindowChrome.configure(window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
    }

    @Test("Main toolbar places the sidebar toggle before its tracking separator")
    func nativeSidebarToolbarChrome() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let coordinator = MainContentCoordinator()
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: {}
            )
        )
        let window = NSWindow(contentViewController: controller)

        window.toolbar = toolbar.managedToolbar

        let identifiers = toolbar.managedToolbar.items.map(\.itemIdentifier)
        let toggleIndex = identifiers.firstIndex(
            of: NativeWorkspaceToolbar.sidebarToggleIdentifier
        )
        let trackingSeparatorIndex = identifiers.firstIndex(
            of: NativeWorkspaceToolbar.sidebarTrackingSeparatorIdentifier
        )

        #expect(identifiers.first == .flexibleSpace)
        #expect(toggleIndex != nil)
        #expect(trackingSeparatorIndex == toggleIndex.map { $0 + 1 })
        #expect(!identifiers.contains {
            $0.rawValue.hasSuffix(".toolbar.workspaceTitle")
        })
        if let trackingSeparatorIndex {
            #expect(
                toolbar.managedToolbar.items[trackingSeparatorIndex]
                    is NSTrackingSeparatorToolbarItem
            )
        }
    }

    @Test("Native toolbar toggle collapses and restores the sidebar split item")
    func nativeToolbarTogglesSidebar() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        guard let toggleItem = toolbar.managedToolbar.items.first(where: {
            $0.itemIdentifier == NativeWorkspaceToolbar.sidebarToggleIdentifier
        }),
            let action = toggleItem.action else
        {
            Issue.record("Sidebar toolbar item was not installed")
            return
        }

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(!controller.isSidebarPresented)

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(controller.isSidebarPresented)
    }

    // MARK: - Startup geometry readiness

    @Test("Layout readiness rejects zero, negative, and non-finite bounds")
    func layoutReadinessRejectsInvalidBounds() {
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(.zero))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 0, height: 700)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 1_300, height: 0)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: -10, height: 700)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 700)
        ))
        #expect(NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 1_300, height: 700)))
    }

    @Test("Ideal placement seats every presented pane at or above its minimum")
    func idealPlacementRespectsMinimums() throws {
        let placement = try #require(NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        let sidebarWidth = try #require(placement.leadingDividerPosition)
        let trailing = try #require(placement.trailingDividerPosition)
        let inspectorWidth = 1_300 - trailing - 1
        let workspaceWidth = trailing - (sidebarWidth + 1)

        #expect(sidebarWidth >= 200)
        #expect(inspectorWidth >= 300)
        #expect(workspaceWidth >= 600)
    }

    @Test("Ideal placement is skipped when the window cannot seat the workspace minimum")
    func idealPlacementSkippedWhenTooNarrow() {
        let placement = NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_150,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        )

        #expect(placement == nil)
    }

    @Test("Ideal placement omits the divider for a collapsed pane")
    func idealPlacementForSinglePresentedPane() throws {
        let placement = try #require(NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: false,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        #expect(placement.leadingDividerPosition == 250)
        #expect(placement.trailingDividerPosition == nil)
    }

    @Test("Configuring at zero bounds never produces negative arranged geometry")
    func zeroBoundsProducesNonNegativeGeometry() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)

        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Moving from a zero frame to a sufficient frame preserves visibility and safe geometry")
    func deferredLayoutPreservesVisibilityAndSafeGeometry() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Minima readiness rejects raw-invalid and too-narrow widths but accepts a minimum-capable width")
    func minimaReadinessGuardsInitialLatch() {
        // Raw-negative width must be rejected, not standardized to a positive value.
        #expect(!NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: -1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // 200 + 600 + 300 + two dividers = 1_102 required; 900 cannot seat the minima.
        #expect(!NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 900,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // 1_150 seats the minima (1_102) even though it cannot seat the ideals.
        #expect(NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 1_150,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // A collapsed inspector drops its pane and divider from the requirement.
        #expect(NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 810,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: false,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))
    }

    @Test("A provisional too-narrow pass stays safe when the workspace later expands")
    func provisionalTooNarrowPassStaysSafeAcrossExpansion() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        // Positive and finite, but too narrow to seat sidebar + workspace + inspector minima
        // plus dividers. The provisional pass and the later expanded pass must both keep
        // every arranged pane in valid geometry.
        layout(controller, at: CGRect(x: 0, y: 0, width: 900, height: 700))
        expectNonNegativeArrangedGeometry(controller)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("A window too narrow for ideal placement preserves visibility without negative geometry")
    func insufficientWidthPreservesVisibility() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: CGRect(x: 0, y: 0, width: 1_150, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeController(
        sidebarPresented: Bool,
        inspectorPresented: Bool
    )
        -> NativeWorkspaceSplitViewController
    {
        let controller = makeConfiguredController(
            sidebarPresented: sidebarPresented,
            inspectorPresented: inspectorPresented,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))
        return controller
    }

    private func layout(_ controller: NativeWorkspaceSplitViewController, at frame: CGRect) {
        controller.view.frame = frame
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
    }

    private func makeConfiguredController(
        sidebarPresented: Bool,
        inspectorPresented: Bool,
        autosaveName: String
    )
        -> NativeWorkspaceSplitViewController
    {
        let controller = NativeWorkspaceSplitViewController()
        controller.configure(
            sidebarController: NSHostingController(rootView: Color.clear),
            workspaceController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isSidebarPresented: sidebarPresented,
            isInspectorPresented: inspectorPresented,
            layout: NativeWorkspaceSplitLayout(
                autosaveName: autosaveName,
                sidebarMinimumWidth: 200,
                sidebarIdealWidth: 250,
                sidebarMaximumWidth: 350,
                workspaceMinimumWidth: 320,
                inspectorMinimumWidth: 220,
                inspectorIdealWidth: 380
            )
        )
        return controller
    }

    private func uniqueAutosaveName() -> String {
        "NativeWorkspaceSplitViewTests-\(UUID().uuidString)"
    }

    private func expectNonNegativeArrangedGeometry(_ controller: NativeWorkspaceSplitViewController) {
        for item in controller.splitViewItems {
            let frame = item.viewController.view.frame
            #expect(frame.width.isFinite)
            #expect(frame.height.isFinite)
            #expect(frame.width >= 0)
            #expect(frame.height >= 0)
        }
    }

    private func removeSplitViewAutosaveDefaults(_ autosaveName: String) {
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(autosaveName)")
    }
}
