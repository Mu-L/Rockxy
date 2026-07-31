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
}
