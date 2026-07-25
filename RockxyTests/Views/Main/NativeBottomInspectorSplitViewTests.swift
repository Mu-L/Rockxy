import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct NativeBottomInspectorSplitViewTests {
    // MARK: Internal

    @Test("Bottom inspector sizing preserves the proposed workspace size")
    func proposedSizeIsPreserved() throws {
        let resolved = try #require(NativeBottomInspectorSplitSizing.resolve(
            ProposedViewSize(width: 1_514, height: 894),
            naturalHeight: 400
        ))

        #expect(resolved == CGSize(width: 1_514, height: 894))
    }

    @Test("Bottom inspector uses a native horizontal collapsible split item")
    func nativeHorizontalConfiguration() {
        let controller = makeController(isInspectorPresented: true)

        #expect(!controller.splitView.isVertical)
        #expect(controller.splitView.dividerStyle == .thin)
        #expect(controller.splitViewItems.count == 2)
        #expect(!controller.splitViewItems[0].canCollapse)
        #expect(controller.splitViewItems[1].canCollapse)
        #expect(controller.splitViewItems[0].minimumThickness == 200)
        #expect(controller.splitViewItems[1].minimumThickness == 320)
    }

    @Test("Bottom split collapses without recreating either pane")
    func collapsePreservesPaneControllers() {
        let controller = makeController(isInspectorPresented: true)
        let primaryController = controller.splitViewItems[0].viewController
        let inspectorController = controller.splitViewItems[1].viewController

        controller.setInspectorPresented(false, animated: false)
        #expect(!controller.isInspectorPresented)
        controller.setInspectorPresented(true, animated: false)

        #expect(controller.isInspectorPresented)
        #expect(controller.splitViewItems[0].viewController === primaryController)
        #expect(controller.splitViewItems[1].viewController === inspectorController)
    }

    @Test("Repeated SwiftUI updates do not enqueue duplicate collapse animations")
    func repeatedPresentationUpdatesAreCoalesced() {
        let coordinator = NativeBottomInspectorSplitView<Color, Color>.Coordinator()

        coordinator.recordInitialPresentation(true)
        #expect(!coordinator.shouldApplyPresentation(true))
        #expect(coordinator.shouldApplyPresentation(false))
        #expect(!coordinator.shouldApplyPresentation(false))
        #expect(coordinator.shouldApplyPresentation(true))
    }

    // MARK: - Startup geometry readiness

    @Test("Bottom inspector layout readiness rejects zero and non-finite bounds")
    func layoutReadinessRejectsInvalidBounds() {
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(.zero))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: 0)
        ))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 0, height: 700)
        ))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: CGFloat.infinity)
        ))
        #expect(NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: 700)
        ))
    }

    @Test("Configuring the bottom inspector at zero bounds never produces negative geometry")
    func zeroBoundsProducesNonNegativeGeometry() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)

        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Deferred initial collapse applies once bounds become sufficient")
    func deferredCollapseAppliesAtSufficientBounds() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: false,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        #expect(!controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Insufficient height preserves inspector visibility without negative geometry")
    func insufficientHeightPreservesVisibility() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        // Positive but below the combined primary + inspector minimum height.
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 400))

        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeController(isInspectorPresented: Bool) -> NativeBottomInspectorSplitViewController {
        let controller = makeConfiguredController(
            isInspectorPresented: isInspectorPresented,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))
        return controller
    }

    private func layout(_ controller: NativeBottomInspectorSplitViewController, at frame: CGRect) {
        controller.view.frame = frame
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
    }

    private func makeConfiguredController(
        isInspectorPresented: Bool,
        autosaveName: String
    )
        -> NativeBottomInspectorSplitViewController
    {
        let controller = NativeBottomInspectorSplitViewController()
        controller.configure(
            primaryController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isInspectorPresented: isInspectorPresented,
            autosaveName: autosaveName,
            primaryMinimumHeight: 200,
            inspectorMinimumHeight: 320
        )
        return controller
    }

    private func uniqueAutosaveName() -> String {
        "NativeBottomInspectorSplitViewTests-\(UUID().uuidString)"
    }

    private func expectNonNegativeArrangedGeometry(
        _ controller: NativeBottomInspectorSplitViewController
    ) {
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
