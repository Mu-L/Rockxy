@testable import Rockxy
import Foundation
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
}

// MARK: - LiquidGlassPresentationContractTests

struct LiquidGlassPresentationContractTests {
    @Test("Primary actions use the availability-safe native glass family")
    func primaryActionsUseGlassButtonStyle() throws {
        let sources = try viewSources()
        let joined = sources.values.joined(separator: "\n")

        #expect(!joined.contains(".buttonStyle(.borderedProminent)"))
        #expect(joined.components(separatedBy: ".rockxyGlassButtonStyle(prominent: true)").count > 20)
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

    @Test("Toast geometry and shadow stay tokenized")
    func toastUsesSharedGlassTokens() throws {
        let source = try readProjectFile("Rockxy/Views/Common/ToastView.swift")

        #expect(source.contains("Theme.Glass.toastCornerRadius"))
        #expect(source.contains("Theme.Glass.toastShadowRadius"))
        #expect(source.contains(".rockxyGlassEffect("))
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
