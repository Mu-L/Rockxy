import Foundation
@testable import Rockxy
import Testing

// MARK: - ApplicationSSLProxyingRuleTests

struct ApplicationSSLProxyingRuleTests {
    // MARK: - Identity normalization

    @Test("outer app bundle resolves nested helper to the outermost owning app")
    func outerBundleForNestedHelper() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/" +
            "Google Chrome Framework.framework/Versions/1/Helpers/" +
            "Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let outer = ClientApplicationIdentity.outerAppBundlePath(forExecutablePath: path)
        #expect(outer == "/Applications/Google Chrome.app")
        #expect(ClientApplicationIdentity.appName(fromBundlePath: outer ?? "") == "Google Chrome")
    }

    @Test("outer app bundle is nil for a bare executable path")
    func outerBundleForBareExecutable() {
        #expect(ClientApplicationIdentity.outerAppBundlePath(forExecutablePath: "/usr/bin/curl") == nil)
    }

    @Test("executable identity digest is deterministic and path-sensitive")
    func executableIdentityDeterministic() {
        let a = ClientApplicationIdentity.executable(normalizedPath: "/usr/bin/curl", displayName: "curl")
        let b = ClientApplicationIdentity.executable(normalizedPath: "/usr/bin/curl", displayName: "curl")
        let c = ClientApplicationIdentity.executable(normalizedPath: "/usr/bin/wget", displayName: "wget")

        #expect(a == b)
        #expect(a.identifier == b.identifier)
        #expect(a.identifier != c.identifier)
        #expect(a.identifier.hasPrefix("exec:"))
        #expect(a.kind == .executable)
        #expect(a.bundleIdentifier == nil)
    }

    @Test("executable identity does not embed the raw path")
    func executableIdentityHidesPath() {
        let identity = ClientApplicationIdentity.executable(
            normalizedPath: "/Users/someone/private/tool",
            displayName: "tool"
        )
        #expect(!identity.identifier.contains("/Users/someone"))
        #expect(!identity.displayName.contains("/Users/someone"))
    }

    @Test("bundle identity prefers bundle identifier as the matching key")
    func bundleIdentity() {
        let identity = ClientApplicationIdentity.bundle(identifier: "com.example.App", displayName: "Example")
        #expect(identity.identifier == "com.example.App")
        #expect(identity.bundleIdentifier == "com.example.App")
        #expect(identity.kind == .bundle)
    }

    // MARK: - Rule matching

    @Test("rule matches on stable identifier, not display name")
    func matchesOnIdentifier() {
        let identity = ClientApplicationIdentity.bundle(identifier: "com.example.App", displayName: "Example")
        let rule = ApplicationSSLProxyingRule(identity: identity, listType: .include)

        let renamed = ClientApplicationIdentity.bundle(identifier: "com.example.App", displayName: "Renamed")
        let different = ClientApplicationIdentity.bundle(identifier: "com.other.App", displayName: "Example")

        #expect(rule.matches(identity))
        #expect(rule.matches(renamed))
        #expect(!rule.matches(different))
    }

    @Test("application rule decodes with defaulted optional fields")
    func decodeDefaults() throws {
        let json = """
        {"id":"\(UUID().uuidString)","applicationIdentifier":"com.example.App"}
        """
        let data = Data(json.utf8)
        let rule = try JSONDecoder().decode(ApplicationSSLProxyingRule.self, from: data)
        #expect(rule.applicationIdentifier == "com.example.App")
        #expect(rule.displayName == "com.example.App")
        #expect(rule.isEnabled)
        #expect(rule.listType == .include)
    }
}
