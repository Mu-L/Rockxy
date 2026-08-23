import AppKit
import Foundation
@testable import Rockxy
import SwiftUI
import Testing

// Pure-policy tests for `LiquidGlassRenderingPolicy`. Every branch of the resolver is exercised
// directly through its inputs — no snapshots, and no mutation of system accessibility settings.

// MARK: - LiquidGlassRenderingPolicyTests

struct LiquidGlassRenderingPolicyTests {
    // MARK: - Liquid Glass

    @Test("Liquid Glass is chosen only when available and no accessibility preference forces opacity")
    func liquidGlassWhenAvailableAndNoOpacityRequired() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: true,
            reduceTransparency: false,
            increaseContrast: false
        ) == .liquidGlass)
    }

    // MARK: - System material

    @Test("System material is chosen on older systems when accessibility does not require opacity")
    func systemMaterialWhenUnavailableAndNoOpacityRequired() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: false,
            reduceTransparency: false,
            increaseContrast: false
        ) == .systemMaterial)
    }

    // MARK: - Opaque color (accessibility wins)

    @Test("Reduce Transparency forces opaque even when Liquid Glass is available")
    func opaqueWhenReduceTransparencyAndAvailable() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: true,
            reduceTransparency: true,
            increaseContrast: false
        ) == .opaqueColor)
    }

    @Test("Increase Contrast forces opaque even when Liquid Glass is available")
    func opaqueWhenIncreaseContrastAndAvailable() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: true,
            reduceTransparency: false,
            increaseContrast: true
        ) == .opaqueColor)
    }

    @Test("Reduce Transparency forces opaque on older systems instead of system material")
    func opaqueWhenReduceTransparencyAndUnavailable() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: false,
            reduceTransparency: true,
            increaseContrast: false
        ) == .opaqueColor)
    }

    @Test("Increase Contrast forces opaque on older systems instead of system material")
    func opaqueWhenIncreaseContrastAndUnavailable() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: false,
            reduceTransparency: false,
            increaseContrast: true
        ) == .opaqueColor)
    }

    @Test("Both accessibility preferences together resolve to opaque regardless of availability")
    func opaqueWhenBothAccessibilityPreferencesRegardlessOfAvailability() {
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: true,
            reduceTransparency: true,
            increaseContrast: true
        ) == .opaqueColor)
        #expect(LiquidGlassRenderingPolicy.resolve(
            liquidGlassAvailable: false,
            reduceTransparency: true,
            increaseContrast: true
        ) == .opaqueColor)
    }

    @Test("Every live appearance input changes the native glass identity")
    func glassIdentityTracksAppearanceInputs() {
        let light = LiquidGlassAppearanceIdentity(
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        )

        #expect(light != LiquidGlassAppearanceIdentity(
            isDark: true,
            reduceTransparency: false,
            increaseContrast: false
        ))
        #expect(light != LiquidGlassAppearanceIdentity(
            isDark: false,
            reduceTransparency: true,
            increaseContrast: false
        ))
        #expect(light != LiquidGlassAppearanceIdentity(
            isDark: false,
            reduceTransparency: false,
            increaseContrast: true
        ))
        #expect(light == LiquidGlassAppearanceIdentity(
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        ))
    }
}

// MARK: - AppThemeApplierTests

struct AppThemeApplierTests {
    @Test("App themes resolve independently from the macOS appearance")
    func appThemePresentationScheme() {
        #expect(AppTheme.system.resolvedColorScheme(inheriting: .dark) == .dark)
        #expect(AppTheme.system.resolvedColorScheme(inheriting: .light) == .light)
        #expect(AppTheme.light.resolvedColorScheme(inheriting: .dark) == .light)
        #expect(AppTheme.dark.resolvedColorScheme(inheriting: .light) == .dark)
    }

    @MainActor
    @Test("Theme transitions refresh existing native toolbar controls")
    func themeTransitionRefreshesExistingToolbarControls() throws {
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let staleDarkAppearance = try #require(NSAppearance(named: .darkAqua))
        let window = NSWindow()
        let container = NSView()
        let control = NSSegmentedControl(
            labels: ["Overview", "Guide"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )

        window.contentView = container
        container.addSubview(control)
        window.appearance = lightAppearance
        control.appearance = staleDarkAppearance

        #expect(control.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        AppThemeApplier.refreshToolbarView(control, appearance: lightAppearance)

        #expect(control.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }

    @MainActor
    @Test("System theme clears explicit toolbar appearance")
    func systemThemeRestoresToolbarInheritance() throws {
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let staleDarkAppearance = try #require(NSAppearance(named: .darkAqua))
        let window = NSWindow()
        let container = NSView()
        let control = NSButton(title: "Set Up…", target: nil, action: nil)

        window.contentView = container
        container.addSubview(control)
        window.appearance = lightAppearance
        control.appearance = staleDarkAppearance

        AppThemeApplier.refreshToolbarView(control, appearance: nil)

        #expect(control.appearance == nil)
        #expect(control.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }
}

// MARK: - LiquidGlassPresentationContractTests

struct LiquidGlassPresentationContractTests {
    @Test("Every scene provider propagates theme into SwiftUI-hosted toolbar chrome")
    func sceneProviderPropagatesTheme() throws {
        let source = try readProjectFile("Rockxy/Models/UI/AppUIDisplayMetrics.swift")

        #expect(source.contains(".environment("))
        #expect(source.contains("\\.colorScheme,"))
        #expect(source.contains(
            "settingsManager.appTheme.resolvedColorScheme(inheriting: inheritedColorScheme)"
        ))
    }

    @Test("Visible action buttons use the availability-safe native glass family")
    func actionButtonsUseGlassButtonStyle() throws {
        let sources = try viewSources()
        let joined = sources.values.joined(separator: "\n")

        #expect(!joined.contains(".buttonStyle(.borderedProminent)"))
        #expect(!joined.contains(".buttonStyle(.bordered)"))
        #expect(joined.components(separatedBy: ".rockxyGlassButtonStyle(prominent: true)").count > 20)
        #expect(joined.components(separatedBy: ".rockxyGlassButtonStyle()").count > 30)
    }

    @Test("Shared semantic chips own active footer and filter state")
    func sharedSemanticChipsOwnActiveState() throws {
        let requiredFiles = [
            "Rockxy/Views/Toolbar/FilterPillButton.swift",
            "Rockxy/Views/Toolbar/ActiveFilterSummaryBar.swift",
            "Rockxy/Views/RequestList/StatusBarView.swift",
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift",
            "Rockxy/Views/Scripting/ScriptingListWindowView.swift",
            "Rockxy/Views/Settings/SSLProxyingListView.swift",
            "Rockxy/Views/Settings/BypassProxyListView.swift",
        ]

        for file in requiredFiles {
            let source = try readProjectFile(file)
            #expect(source.contains(".rockxyChipStyle("), "Missing shared semantic chip in \(file)")
        }
    }

    @Test("Protocol filter pills always emit their readable label")
    func protocolFilterPillsEmitLabels() throws {
        let source = try readProjectFile("Rockxy/Views/Toolbar/FilterPillButton.swift")

        #expect(source.contains("Text(title)"))
        #expect(!source.contains("let label = Text(title)"))
        #expect(source.contains(".rockxyChipStyle(isActive: isActive)"))
    }

    @Test("Toast geometry uses the native glass effect without a painted shadow")
    func toastUsesSharedGlassTokens() throws {
        let source = try readProjectFile("Rockxy/Views/Common/ToastView.swift")

        #expect(source.contains("Theme.Glass.toastCornerRadius"))
        #expect(source.contains(".rockxyGlassEffect("))
        #expect(!source.contains(".shadow("))
    }

    @Test("Workspace and feature bars use native floating Liquid Glass surfaces")
    func functionalLayersUseNativeGlassSurfaces() throws {
        let glassSource = try readProjectFile("Rockxy/Theme/LiquidGlass.swift")
        let shelfSource = try readProjectFile("Rockxy/Views/Toolbar/TrafficControlShelf.swift")
        let footerSource = try readProjectFile("Rockxy/Views/RequestList/StatusBarView.swift")

        #expect(glassSource.contains("RockxyFunctionalBarModifier"))
        #expect(glassSource.contains("RockxyGlassButtonStyleModifier"))
        #expect(glassSource.contains("LiquidGlassAppearanceIdentity"))
        #expect(glassSource.components(separatedBy: ".id(appearanceIdentity)").count >= 5)
        #expect(glassSource.contains("Theme.Glass.functionalBarHorizontalInset"))
        #expect(!glassSource.contains("func rockxyFunctionalBar() -> some View {\n        background(.bar)"))
        #expect(shelfSource.contains("RockxyGlassEffectGroup"))
        #expect(!shelfSource.contains("shelfTint"))
        #expect(!shelfSource.contains(".strokeBorder("))
        #expect(!shelfSource.contains(".shadow("))
        #expect(shelfSource.components(separatedBy: "shelfSurface {").count >= 4)
        #expect(footerSource.contains("Theme.Glass.footerCornerRadius"))
        #expect(footerSource.contains("RockxyGlassEffectGroup"))
    }

    private func viewSources() throws -> [String: String] {
        let viewsURL = projectRoot().appendingPathComponent("Rockxy/Views", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(
            at: viewsURL,
            includingPropertiesForKeys: nil
        ))
        var result: [String: String] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result[url.path] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }
}
