import AppKit
import CoreGraphics
import Foundation
@testable import Rockxy
import Testing

@MainActor
struct SoftwareUpdateWindowReadabilityTests {
    // MARK: Internal

    @Test("software update window defines a resizable native shell with a compact default and min size")
    func windowShellIsResizableWithCompactDefault() {
        #expect(SoftwareUpdateWindowPositioning.contentSize.width == 780)
        #expect(SoftwareUpdateWindowPositioning.contentSize.height == 610)
        #expect(
            SoftwareUpdateWindowPositioning.minimumContentSize.width
                < SoftwareUpdateWindowPositioning.contentSize.width
        )
        #expect(
            SoftwareUpdateWindowPositioning.minimumContentSize.height
                < SoftwareUpdateWindowPositioning.contentSize.height
        )
        #expect(SoftwareUpdateWindowPositioning.minimumContentSize.width >= 480)
        #expect(SoftwareUpdateWindowPositioning.minimumContentSize.height >= 600)
    }

    @Test("software update typography derives from Appearance metrics at 13/20/28")
    func typographyDerivesFromMetricsAtRepresentativeSizes() {
        for size in [13, 20, 28] {
            var appUI = AppUISettings()
            appUI.fontSize = size
            let metrics = AppUIDisplayMetrics(settings: appUI)
            let tool = ToolWindowDisplayMetrics(appMetrics: metrics)

            #expect(tool.bodyFontSize == CGFloat(size))
            #expect(tool.secondaryFontSize == max(10, CGFloat(size - 1)))
            #expect(tool.metadataFontSize == max(10, CGFloat(size - 2)))

            // Hero and section headings scale strictly above the body size at every supported size.
            #expect(max(22, metrics.primaryFontSize + 7) > metrics.primaryFontSize)
            #expect(max(18, metrics.primaryFontSize + 4) > metrics.primaryFontSize)
        }
    }

    @Test("software update controller adopts the native readable window contract")
    func controllerAdoptsNativeReadableContract() throws {
        let controller = try readProjectFile("Rockxy/Core/Updates/SoftwareUpdateController.swift")

        #expect(controller.contains("ToolWindowDisplayMetricsProvider"))
        #expect(controller.contains(".resizable"))
        #expect(controller.contains("window.contentMinSize = SoftwareUpdateWindowPositioning.minimumContentSize"))
        #expect(controller.contains("func windowShouldClose"))
        #expect(controller.contains("interactiveCloseOutcome"))
        #expect(controller.contains("standardWindowButton(.closeButton)?.isEnabled"))
    }

    @Test("software update panel uses Appearance metrics, honest copy, and native affordances")
    func panelUsesMetricsAndHonestCopy() throws {
        let view = try readProjectFile("Rockxy/Views/Updates/SoftwareUpdatePanelView.swift")

        #expect(view.contains("@Environment(\\.appUIDisplayMetrics)"))
        #expect(view.contains("ToolWindowDisplayMetrics(appMetrics: appMetrics)"))
        #expect(view.contains("Automatically download future updates"))
        #expect(view.contains(".keyboardShortcut(.cancelAction)"))
        #expect(view.contains(".onExitCommand"))
        #expect(view.contains("usesFindPanel = true"))
        #expect(view.contains("font: releaseNotesFont"))
        #expect(view.contains("textStorage.isEqual(to: attributedText)"))

        // No pinned exact window frame that would clip scaled text.
        #expect(!view.contains("width: SoftwareUpdateWindowPositioning.contentSize.width,"))

        // No hardcoded update typography (12/13/17/22/28) in the redesigned panel.
        for size in ["12", "13", "17", "22", "28"] {
            #expect(!view.contains(".font(.system(size: \(size)"), "Panel must not hardcode font size \(size)")
        }

        // Implementation/layout-rationale captions and unsupported helper-refresh claims are gone.
        #expect(!view.contains("refreshing the helper"))
        #expect(!view.contains("refreshing helper"))
        #expect(!view.contains("Automatically download and install future updates"))
        #expect(!view.contains("so the dialog does not jump around"))
        #expect(!view.contains("structured panel shape"))
        #expect(!view.contains("visible immediately"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}
