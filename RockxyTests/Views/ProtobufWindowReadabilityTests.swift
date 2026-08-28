import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufWindowReadabilityTests

/// Source-level contracts for the redesigned Protobuf mapping and local-schema tool windows.
/// These assert truthful local-only copy, native adaptive surfaces, honest action routing, and
/// the absence of the old dead controls, fake console, and pinned legacy frames.
@MainActor
struct ProtobufWindowReadabilityTests {
    // MARK: Internal

    @Test("Protobuf windows use the approved native, honest local-only structure")
    func protobufWindowsUseApprovedNativeStructure() throws {
        let mapping = try readProjectFile("Rockxy/Views/Rules/ProtobufSettingsWindowView.swift")
        let schema = try readProjectFile("Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift")
        let grpc = try readProjectFile("Rockxy/Views/Inspector/GRPCInspectorView.swift")
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        for source in [mapping, schema] {
            require(source, [
                "ProtobufLocalOnlyNotice", "ContentUnavailableView", "Color(nsColor: .textBackgroundColor)",
                "RoundedRectangle(cornerRadius: 6)", ".stroke(Color(nsColor: .separatorColor), lineWidth: 1)",
                ".padding(.vertical, toolMetrics.footerTopPadding)", "minWidth: max(", "minHeight: max(",
            ])
        }

        require(mapping, [
            "not applied to captured traffic", "stored locally",
            "minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)", "Not applied",
            "focused($focusedField", "inlineError", "footerButtonLabel", ".keyboardShortcut(.cancelAction)",
            ".keyboardShortcut(.defaultAction)", "withEditedFields", "Missing Schema", "ViewThatFits",
            ".accessibilityLabel(String(localized: \"HTTP method\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Match type\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Local schema\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Payload encoding\", bundle: RockxyLocalization.bundle))",
        ])
        forbid(mapping, [
            ".frame(width: 1_240, height: 660)", "Test your Rule", "questionmark.circle",
            ".keyboardShortcut(.space, modifiers: [])", ".onDeleteCommand",
        ])

        require(schema, [
            "Schema-aware decoding is unavailable", "minWidth: max(760,", "minHeight: max(520,",
            "importAvailability", "policyUnavailable", "limitReached", "storageUnavailable",
            "UTType(filenameExtension: \"proto\")", "ProtobufSchemaSourceValidator.loadValidatedSource",
            "Schema Import Unavailable", "Schema Limit Reached", "Schema Storage Unavailable",
            "No Local Schemas", "Local schema import is unavailable", #"Click \"+\" or press ⌘N to import"#,
            ".confirmationDialog(", "referenceCount(forSchema:", "detachSchema(id:",
        ])
        forbid(schema, [
            ".frame(width: 1_000, height: 860)", "Protobuf Console Log", "Empty Console Log",
            "consoleLines", "appendConsole", "How to get *.proto file",
            "Schema upload unavailable", "rejects schema uploads", "app policy",
        ])

        require(grpc, [
            "This view uses heuristic Protobuf decoding", "not applied to gRPC traffic",
            "onOpenToolWindow(\"protobufSettings\")", "Wire-format heuristic",
            "Field numbers are inferred heuristically",
        ])
        forbid(
            grpc,
            ["Add Descriptor", "protobufSchemaList", "Schema: heuristic fallback", "Schema needed for field names"]
        )

        require(app, [".defaultSize(width: 940, height: 620)", ".defaultSize(width: 820, height: 560)"])
    }

    // MARK: Private

    private func require(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(source.contains(needle), "missing \(needle)")
        }
    }

    private func forbid(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(!source.contains(needle), "kept \(needle)")
        }
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
