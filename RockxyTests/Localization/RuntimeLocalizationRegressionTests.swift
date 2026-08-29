import Foundation
@testable import Rockxy
import Testing

// MARK: - RuntimeLocalizationRegressionTests

/// Guards the corrective pass that makes the runtime app-language selection apply to
/// surfaces that previously stayed frozen in the language captured at first use:
/// inflected `AttributedString` counts, cached localized `static let` messages, the
/// native workspace toolbar labels, and the Developer Setup catalog/guide values.
@MainActor
struct RuntimeLocalizationRegressionTests {
    // MARK: Internal

    @Test("Inflected AttributedString counts resolve through the runtime bundle and locale")
    func inflectedCountsUseRuntimeBundleAndLocale() throws {
        let files = [
            "Rockxy/Views/Projects/ProjectPresentation.swift",
            "Rockxy/Views/Import/ImportReviewSheet.swift",
            "Rockxy/Views/RequestList/RequestTableView.swift",
            "Rockxy/Views/Rules/RuleListView.swift",
            "Rockxy/Views/Export/GistPublishConfirmationSheet.swift",
            "Rockxy/Models/UI/ExportScope.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            for range in ranges(of: "AttributedString(", in: source) {
                // Skip AppKit's NSAttributedString(...) which shares the suffix.
                if range.lowerBound > source.startIndex,
                   source[source.index(before: range.lowerBound)] == "N"
                {
                    continue
                }
                let window = callWindow(in: source, from: range.upperBound)
                // Only inflected/localized initializers must carry the runtime bundle/locale.
                guard window.contains("localized:") else {
                    continue
                }
                #expect(
                    window.contains("RockxyLocalization.bundle"),
                    "\(file): AttributedString(localized:) must pass RockxyLocalization.bundle"
                )
                #expect(
                    window.contains("RockxyLocalization.locale"),
                    "\(file): AttributedString(localized:) must pass RockxyLocalization.locale for inflection"
                )
            }
        }
    }

    @Test("Presentation messages are re-resolving computed values, not cached static lets")
    func presentationMessagesAreRecomputed() throws {
        let diff = try readProjectFile("Rockxy/Views/Diff/DiffFormatter.swift")
        #expect(diff.contains("static var captureTruncationNotice: String {"))
        #expect(!diff.contains("static let captureTruncationNotice ="))

        let protobufSettings = try readProjectFile("Rockxy/Views/Rules/ProtobufSettingsWindowView.swift")
        #expect(protobufSettings.contains("static var capabilityNotice: String {"))
        #expect(!protobufSettings.contains("static let capabilityNotice ="))

        let protobufSchemas = try readProjectFile("Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift")
        #expect(protobufSchemas.contains("static var capabilityNotice: String {"))
        #expect(!protobufSchemas.contains("static let capabilityNotice ="))

        let gist = try readProjectFile("Rockxy/Views/Export/GistPublishConfirmationSheet.swift")
        #expect(gist.contains("static var redactionDescription: String {"))
        #expect(gist.contains("static var redactionOffWarning: String {"))
        #expect(gist.contains("static var publicWarning: String {"))
        #expect(!gist.contains("static let redactionDescription ="))
        #expect(!gist.contains("static let publicWarning ="))

        let helper = try readProjectFile("Rockxy/Core/ProxyEngine/HelperManager.swift")
        #expect(helper.contains("static var applicationMustReopenMessage: String {"))
        #expect(helper.contains("static var helperApprovalMessage: String {"))
        #expect(helper.contains("static var helperPackageIncompleteMessage: String {"))
        #expect(!helper.contains("static let applicationMustReopenMessage ="))
        #expect(!helper.contains("static let helperApprovalMessage ="))
        #expect(!helper.contains("static let helperPackageIncompleteMessage ="))
    }

    @Test("Native workspace toolbar re-resolves labels when the runtime language changes")
    func nativeWorkspaceToolbarRefreshesOnLanguageChange() throws {
        let source = try readProjectFile("Rockxy/Views/Common/NativeWorkspaceWindowChrome.swift")

        // Tool-window descriptor labels are re-resolved on demand instead of frozen once.
        #expect(source.contains("static var toolWindowItemDescriptors: [ToolWindowItemDescriptor] {"))
        #expect(!source.contains("static let toolWindowItemDescriptors:"))
        // Stable identifiers stay cached so the allowed/customizable sets never shift.
        #expect(source.contains("static let toolWindowItemIdentifiers:"))

        // The observation tracks the language selection and refreshes existing items in place.
        #expect(source.contains("_ = AppLanguageController.shared.selectedOptionID"))
        #expect(source.contains("func refreshLocalizedLabelsIfLanguageChanged()"))
        #expect(source.contains("for item in managedToolbar.items"))
    }

    @Test("Developer Setup catalog re-resolves target titles and summaries on demand")
    func developerSetupCatalogIsRecomputed() throws {
        let source = try readProjectFile("Rockxy/Models/UI/DeveloperSetupCatalog.swift")

        #expect(source.contains("static var python: SetupTarget {"))
        #expect(source.contains("static var docker: SetupTarget {"))
        #expect(source.contains("static var runtimeTargets: [SetupTarget] {"))
        #expect(!source.contains("static let python ="))
        #expect(!source.contains("static let runtimeTargets:"))
        // Identity list stays a stable constant for pinning defaults.
        #expect(source.contains("static let defaultPinnedTargetIDs:"))
    }

    @Test("Developer Setup guide tips rebind to the runtime bundle and locale")
    func developerSetupGuideTipsRebindToRuntime() throws {
        let source = try readProjectFile("Rockxy/Models/UI/DeveloperSetupGuideCatalog.swift")

        #expect(source
            .contains("func runtimeLocalized(_ resource: LocalizedStringResource) -> LocalizedStringResource"))
        #expect(source.contains(".atURL(RockxyLocalization.bundle.bundleURL)"))
        #expect(source.contains("locale: RockxyLocalization.locale"))
        #expect(source.contains("runtimeLocalized(title)"))
        #expect(source.contains("runtimeLocalized(message)"))
    }

    @Test("Developer Setup selection is tracked by stable identity and re-derived from the catalog")
    func developerSetupSelectionTrackedByStableIdentity() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        // Stored by stable identifier so the selection survives a runtime language switch.
        viewModel.selectedTargetID = .golang
        #expect(viewModel.selectedTarget.id == .golang)
        // Re-derives from the catalog on every read rather than holding a frozen copy.
        #expect(viewModel.selectedTarget == SetupTarget.target(for: .golang))

        // Assigning through the value setter maps back to the stable identifier.
        viewModel.selectedTarget = SetupTarget.docker
        #expect(viewModel.selectedTargetID == .docker)
        #expect(viewModel.selectedTarget.id == .docker)
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// The substring covering a single call starting at `start`, up to the matching
    /// close paren (with a generous cap) so multi-line argument lists are inspected
    /// without depending on the formatter's exact line wrapping.
    private func callWindow(in source: String, from start: String.Index) -> String {
        var depth = 1
        var index = start
        let end = source.endIndex
        while index < end, depth > 0 {
            switch source[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
            default:
                break
            }
            index = source.index(after: index)
        }
        return String(source[start ..< index])
    }

    private func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart ..< haystack.endIndex) {
            result.append(found)
            searchStart = found.upperBound
        }
        return result
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
