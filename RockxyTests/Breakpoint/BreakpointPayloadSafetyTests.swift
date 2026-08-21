import Foundation
@testable import Rockxy
import Testing

@Suite("Breakpoint Payload Safety")
struct BreakpointPayloadSafetyTests {
    @Test("Missing and valid UTF-8 bodies remain editable")
    func textBodyProjection() {
        let missing = BreakpointRequestData.editableBodyProjection(from: nil)
        #expect(missing.text.isEmpty)
        #expect(missing.isEditable)

        let text = BreakpointRequestData.editableBodyProjection(from: Data("hello".utf8))
        #expect(text.text == "hello")
        #expect(text.isEditable)
    }

    @Test("Binary bodies are protected from lossy breakpoint edits")
    func binaryBodyProjection() {
        let binary = Data([0xFF, 0xFE, 0xFD, 0x00])
        let projection = BreakpointRequestData.editableBodyProjection(from: binary)

        #expect(projection.text.isEmpty)
        #expect(!projection.isEditable)
    }

    @Test("Execute remains available for header edits on a protected body")
    @MainActor
    func protectedBodyCanExecute() async throws {
        let manager = BreakpointManager()
        let data = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [],
            body: "",
            statusCode: 200,
            phase: .response,
            isBodyEditable: false
        )

        let resultTask = Task { @MainActor in
            await manager.enqueueAndWait(data)
        }
        await Task.yield()
        let item = try #require(manager.pausedItems.first)
        manager.resolve(id: item.id, decision: .execute)
        let result = await resultTask.value

        guard case .execute = result.0 else {
            Issue.record("Expected protected body to retain the execute decision")
            return
        }
        #expect(!result.1.isBodyEditable)
    }

    @Test("Protected bodies keep non-body breakpoint controls enabled")
    func protectedBodyKeepsMetadataControlsEnabled() throws {
        let editor = try Self.projectFile(named: "Rockxy/Views/Breakpoint/BreakpointEditorView.swift")
        let window = try Self.projectFile(named: "Rockxy/Views/Breakpoint/BreakpointWindowView.swift")

        #expect(!editor.contains("requestLine(itemId: itemId)\n                    .disabled"))
        #expect(!editor.contains(".disabled(draftFor(itemId)?.isBodyEditable == false)"))
        #expect(window.contains("Request-line, status, and header changes can still be applied."))
    }

    @Test("HTTPS origin-form editing preserves encoded delimiters and Unicode")
    func encodedOriginFormRoundTrip() throws {
        let target = "/objects/a%2Fb?token=a%26b%3Fc&label=caf%C3%A9"
        let updated = try #require(
            BreakpointRequestData.applyingOriginForm(
                target,
                to: "https://api.example.com/old"
            )
        )

        #expect(updated == "https://api.example.com/objects/a%2Fb?token=a%26b%3Fc&label=caf%C3%A9")
    }

    @Test("Raw templates retain fixed HTTPS connection metadata")
    func rawTemplateRetainsHTTPSAuthority() throws {
        let draft = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/old",
            headers: [],
            body: "",
            statusCode: 200,
            phase: .request,
            fixedHTTPSAuthority: "api.example.com"
        )
        let template = BreakpointTemplate(
            kind: .request,
            name: "Origin-form",
            rawMessage: "POST /v1/items HTTP/1.1\nHost: ignored.example\n\n"
        )
        let application = try #require(template.applicationPayload)
        let updated = application.applying(to: draft)

        #expect(updated.url == "/v1/items")
        #expect(updated.fixedHTTPSAuthority == "api.example.com")
    }

    private static func projectFile(named path: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
