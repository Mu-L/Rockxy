import Foundation
@testable import Rockxy
import Testing

@Suite("Developer setup session setup")
struct DeveloperSetupSessionSetupTests {
    // MARK: Internal

    @Test("Generated setup script exports scoped proxy and certificate hints")
    func generatedSetupScriptExportsScopedProxyAndCertificateHints() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: "/tmp/Rockxy CA.pem",
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("export ROCKXY_SETUP_SESSION=1"))
        #expect(script.contains("export HTTP_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export HTTPS_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export ALL_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export SSL_CERT_FILE=\"$ROCKXY_ROOT_CA_PATH\""))
        #expect(script.contains("export REQUESTS_CA_BUNDLE=\"$ROCKXY_ROOT_CA_PATH\""))
        #expect(script.contains("export NODE_EXTRA_CA_CERTS=\"$ROCKXY_ROOT_CA_PATH\""))
        #expect(script.contains("NODE_OPTIONS"))
    }

    @Test("Java VMs script injects JAVA_TOOL_OPTIONS proxy properties once and preserves the base")
    func javaScriptInjectsProxyPropertiesAndPreservesBase() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("-Dhttp.proxyHost=127.0.0.1"))
        #expect(script.contains("-Dhttp.proxyPort=9090"))
        #expect(script.contains("-Dhttps.proxyHost=127.0.0.1"))
        #expect(script.contains("-Dhttps.proxyPort=9090"))
        #expect(script.contains("export JAVA_TOOL_OPTIONS="))
        #expect(script.contains("${JAVA_TOOL_OPTIONS//$ROCKXY_JAVA_PROXY_OPTS/}"))
        // The proxy option string is emitted exactly once so re-sourcing cannot stack it.
        #expect(script.components(separatedBy: "-Dhttp.proxyHost=127.0.0.1").count - 1 == 1)
    }

    @Test("Non-Java runtime script never injects JAVA_TOOL_OPTIONS")
    func nonJavaScriptOmitsJavaProxyProperties() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .python
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("JAVA_TOOL_OPTIONS") == false)
        #expect(script.contains("-Dhttp.proxyHost") == false)
    }

    @Test("Sourcing the Java script twice keeps existing JAVA_TOOL_OPTIONS and one proxy block")
    func javaScriptPreservesExistingOptionsAcrossReSourcing() throws {
        try assertJavaScriptSourcing(shellPath: "/bin/zsh")
    }

    @Test("Sourcing the Java script twice in bash keeps existing options and one proxy block")
    func javaScriptPreservesExistingOptionsAcrossReSourcingBash() throws {
        try assertJavaScriptSourcing(shellPath: "/bin/bash")
    }

    @Test("Manual source command quotes Application Support paths")
    func manualSourceCommandQuotesApplicationSupportPaths() {
        let scriptURL =
            URL(fileURLWithPath: "/Users/stephen/Library/Application Support/Rockxy/setup/rockxy_env_setup.sh")

        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL)

        #expect(command ==
            "set -a 2>/dev/null || true; source \"/Users/stephen/Library/Application Support/Rockxy/setup/rockxy_env_setup.sh\"; set +a 2>/dev/null || true")
        #expect(!command.contains("__rockxy_setup"))
    }

    @Test("Generated setup command runs in zsh")
    func generatedSetupCommandRunsInZsh() throws {
        try assertGeneratedSetupCommandRuns(shellPath: "/bin/zsh")
    }

    @Test("Generated setup command runs in bash")
    func generatedSetupCommandRunsInBash() throws {
        try assertGeneratedSetupCommandRuns(shellPath: "/bin/bash")
    }

    @Test("Generated setup command reports when the script is missing")
    func generatedSetupCommandReportsWhenTheScriptIsMissing() throws {
        try assertGeneratedSetupCommandReportsMissingScript(shellPath: "/bin/zsh")
    }

    @Test("Generated setup script URL follows the active app support identity")
    func generatedSetupScriptURLFollowsTheActiveAppSupportIdentity() {
        let identity = RockxyIdentity(infoDictionary: [
            "CFBundleIdentifier": "com.amunx.rockxy",
            "RockxyAppSupportDirectoryName": "com.amunx.rockxy",
        ])

        let scriptURL = RockxySetupScriptBuilder.generatedScriptURL(identity: identity)

        #expect(scriptURL.path.contains("/com.amunx.rockxy/setup/rockxy_env_setup.sh"))
        #expect(!scriptURL.path.contains("com.amunx.rockxy.community"))
    }

    @Test("Setup script is written atomically with executable permissions")
    func setupScriptIsWrittenAtomicallyWithExecutablePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-setup-script-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_091,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(permissions?.intValue == 0o700)
        #expect(contents.contains("export HTTP_PROXY=\"http://127.0.0.1:9091\""))
        #expect(contents.contains("Export or trust the Rockxy root certificate"))
    }

    @Test("Firefox setup uses a generated profile proxy preference file")
    func firefoxSetupUsesGeneratedProfileProxyPreferenceFile() {
        let userJS = RockxySetupSessionLauncher.firefoxUserJS(proxyHost: "127.0.0.1", proxyPort: 9_090)

        #expect(userJS.contains("user_pref(\"network.proxy.type\", 1);"))
        #expect(userJS.contains("user_pref(\"network.proxy.http\", \"127.0.0.1\");"))
        #expect(userJS.contains("user_pref(\"network.proxy.ssl_port\", 9090);"))
        #expect(userJS.contains("user_pref(\"network.proxy.no_proxies_on\", \"localhost, 127.0.0.1, ::1\");"))
    }

    // MARK: Private

    private struct ShellResult {
        let exitCode: Int32
        let output: String
    }

    private func assertGeneratedSetupCommandRuns(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let scriptURL = try writeTemporarySetupScript()
        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL) +
            "; printf 'HTTP_PROXY=%s\\nROCKXY_SETUP_SESSION=%s\\n' \"$HTTP_PROXY\" \"$ROCKXY_SETUP_SESSION\""

        let result = try runShell(shellPath: shellPath, command: command)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("HTTP_PROXY=http://127.0.0.1:9092"))
        #expect(result.output.contains("ROCKXY_SETUP_SESSION=1"))
        #expect(result.output.contains("Rockxy setup session is ready: http://127.0.0.1:9092"))
    }

    private func assertJavaScriptSourcing(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let scriptURL = try writeTemporaryJavaSetupScript()
        let sourceCommand = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL)
        // A harmless value added before the first source and another added between
        // sources prove both survive while the Rockxy proxy block remains singular.
        let command = "export JAVA_TOOL_OPTIONS=\"-Dfile.encoding=UTF-8\"; " +
            "\(sourceCommand); " +
            "export JAVA_TOOL_OPTIONS=\"$JAVA_TOOL_OPTIONS -Duser.country=VN\"; " +
            "\(sourceCommand); " +
            "printf 'JAVA_TOOL_OPTIONS=%s\\n' \"$JAVA_TOOL_OPTIONS\""

        let result = try runShell(shellPath: shellPath, command: command)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("-Dfile.encoding=UTF-8"))
        #expect(result.output.contains("-Duser.country=VN"))
        #expect(result.output.contains("-Dhttp.proxyHost=127.0.0.1"))
        let proxyBlockCount = result.output.components(separatedBy: "-Dhttp.proxyHost=127.0.0.1").count - 1
        #expect(proxyBlockCount == 1)
    }

    private func writeTemporaryJavaSetupScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy java setup \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_093,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        return scriptURL
    }

    private func assertGeneratedSetupCommandReportsMissingScript(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy missing setup \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup/rockxy_env_setup.sh")
        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: missingURL)
        let result = try runShell(shellPath: shellPath, command: command)

        #expect(!result.output.contains("Rockxy setup session is ready"))
        #expect(result.output.contains(missingURL.path))
    }

    private func writeTemporarySetupScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy setup command \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_092,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        return scriptURL
    }

    private func runShell(shellPath: String, command: String) throws -> ShellResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let standardOutput = String(data: outputData, encoding: .utf8) ?? ""
        let standardError = String(data: errorData, encoding: .utf8) ?? ""
        let output = standardOutput + standardError
        return ShellResult(exitCode: process.terminationStatus, output: output)
    }
}
