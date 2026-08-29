import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapLocalModelTests {
    @Test("captured draft replaces stale tester state with the selected transaction")
    func capturedDraftResetsTesterState() throws {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.urlText = "http://127.0.0.1:18081/api/old"
        vm.testURLText = "http://127.0.0.1:18081/api/old"
        vm.testRule()
        #expect(vm.testResult == .matched)
        vm.errorMessage = "stale"

        let sourceURL = try #require(URL(string: "http://127.0.0.1:18082/api/profile.json"))
        let draft = MapLocalDraft(
            origin: .selectedTransaction,
            suggestedName: "Profile",
            sourceURL: sourceURL,
            sourceHost: "127.0.0.1",
            sourcePath: "/api/profile.json",
            sourceMethod: "POST",
            responseBody: Data(#"{"plan":"free"}"#.utf8),
            responseContentType: "application/json",
            inferredExtension: "json",
            responseStatusCode: 200
        )

        vm.load(context: MapLocalEditorContext(draft: draft))

        #expect(vm.testURLText == sourceURL.absoluteString)
        #expect(vm.testMethod == .post)
        #expect(vm.httpMessageText.hasPrefix("HTTP/1.1 200 OK\n"))
        #expect(vm.testResult == nil)
        #expect(vm.visibleTestResult == nil)
        #expect(vm.errorMessage == nil)

        vm.load(context: .blank)
        #expect(vm.testURLText.isEmpty)
        #expect(vm.testMethod == .get)
        #expect(vm.testResult == nil)
    }

    @Test("rule tester evaluates wildcard URL and method semantics")
    func ruleTesterEvaluatesAuthoredCondition() {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.urlText = "http://example.test/api/*"
        vm.matchType = .wildcard
        vm.includeSubpaths = false
        vm.method = .post
        vm.testMethod = .post
        vm.testURLText = "http://example.test/api/users"

        vm.testRule()
        #expect(vm.testResult == .matched)
        #expect(vm.visibleTestResult == .matched)

        vm.testMethod = .get
        #expect(vm.visibleTestResult == nil)
        vm.testRule()
        #expect(vm.testResult == .notMatched)
    }

    @Test("rule tester gives question-mark wildcard the same full-URL boundary as Proxyman")
    func ruleTesterQuestionMarkBoundary() {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.urlText = "http://example.test/api/item?"
        vm.matchType = .wildcard
        vm.includeSubpaths = false
        vm.testURLText = "http://example.test/api/items"

        vm.testRule()
        #expect(vm.testResult == .matched)

        vm.testURLText = "http://example.test/api/items?source=origin"
        vm.testRule()
        #expect(vm.testResult == .notMatched)
    }

    @Test("regex directory editor requires a capture group")
    func regexDirectoryRequiresCaptureGroup() {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Regex directory"
        vm.urlText = #"http://example\.test/assets/.*"#
        vm.matchType = .regex
        vm.targetMode = .localDirectory
        vm.directoryPath = FileManager.default.temporaryDirectory.path

        #expect(vm.directoryRegexValidationMessage != nil)
        #expect(vm.isSaveEnabled == false)

        vm.urlText = #"http://example\.test/assets/(.*)"#
        #expect(vm.directoryRegexValidationMessage == nil)
        #expect(vm.isSaveEnabled == true)
    }

    @Test("filter matches name, method, URL, and local path")
    func filterMatchesVisibleColumns() {
        let vm = MapLocalViewModel()
        let apiRule = ProxyRule(
            name: "Users",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/users", method: "POST"),
            action: .mapLocal(filePath: "/tmp/users.json")
        )
        let assetRule = ProxyRule(
            name: "Assets",
            matchCondition: RuleMatchCondition(urlPattern: "https://cdn.example.com/.*", method: "GET"),
            action: .mapLocal(filePath: "/tmp/app.js")
        )
        vm.allRules = [apiRule, assetRule]

        vm.searchText = "post"
        #expect(vm.filteredRules.map(\.id) == [apiRule.id])

        vm.searchText = "app.js"
        #expect(vm.filteredRules.map(\.id) == [assetRule.id])
    }

    @Test("visible Map Local row labels match the management table")
    func visibleRowLabelsMatchManagementTable() {
        let vm = MapLocalViewModel()
        let pattern = MapLocalPatternFormatter.wildcardToRegex("https://media-hls.growcdnssedge.com/*")
        let rule = ProxyRule(
            name: "Untitled",
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .mapLocal(
                filePath: "/tmp/rockxy-map-local/default_message.json"
            )
        )

        #expect(vm.methodLabel(for: rule) == "ANY")
        #expect(vm.matchingRuleLabel(for: rule) == "Wildcard: https://media-hls.growcdnssedge.com/*")
        #expect(vm.mapFromLabel(for: rule).hasPrefix("File: "))
        #expect(vm.mapFromLabel(for: rule).contains("default_message.json"))
    }

    @Test("editor menus match the reference order and grouping")
    func editorMenusMatchReferenceOrderAndGrouping() {
        #expect(MapLocalEditorMenuContent.methodSections == [
            [.any],
            [.get, .post, .put, .delete, .patch],
            [.head, .options, .trace],
        ])
        #expect(MapLocalEditorMenuContent.matchTypeSections == [
            [.wildcard, .regex],
        ])
        #expect(MapLocalEditorMenuContent.delaySections == [
            [.none],
            [.oneSecond, .twoSeconds, .threeSeconds, .fiveSeconds, .tenSeconds, .thirtySeconds, .sixtySeconds],
            [.random],
            [.custom],
        ])
    }

    @Test("remove selected Map Local rows preserves unrelated rules")
    func removeSelectedPreservesOtherRules() async {
        await RuleTestLock.shared.acquire()
        let snapshot = await RuleEngine.shared.allRules
        await RuleEngine.shared.replaceAll([])

        let vm = MapLocalViewModel()
        let mapLocal = ProxyRule(
            name: "Local",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapLocal(filePath: "/tmp/local.json")
        )
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
            action: .block(statusCode: 403)
        )
        vm.allRules = [mapLocal, block]
        vm.selectedRuleIDs = [mapLocal.id]

        vm.removeSelectedRules()

        #expect(vm.allRules.map(\.id) == [block.id])
        #expect(vm.selectedRuleIDs.isEmpty)

        await RuleEngine.shared.replaceAll(snapshot)
        await RuleTestLock.shared.release()
    }

    @Test("editor saves local file rule with method, delay, status, and preserved header condition")
    func editorCreatesRulePreservingHeaderFields() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalEditor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")
        // A file outside Rockxy's Map Local directory is a user-owned reference.
        try Data(#"{"original":true}"#.utf8).write(to: fileURL, options: .atomic)

        let existing = ProxyRule(
            name: "Existing",
            isEnabled: false,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://old.example.com/.*",
                method: "GET",
                headerName: "X-Debug",
                headerValue: "1"
            ),
            action: .mapLocal(filePath: fileURL.path, statusCode: 200, delayMs: 1_000),
            priority: 42
        )
        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(existingRule: existing))
        vm.name = "Updated"
        vm.urlText = "https://api.example.com/v1/*"
        vm.matchType = .wildcard
        vm.method = .post
        vm.filePath = fileURL.path
        vm.delayPreset = .fiveSeconds
        vm.httpMessageText = """
        HTTP/1.1 202 Accepted
        Content-Type: application/json

        {"ok":true}
        """

        let rule = try #require(vm.makeRule())

        #expect(rule.id == existing.id)
        #expect(rule.name == "Updated")
        #expect(rule.isEnabled == false)
        #expect(rule.priority == 42)
        #expect(rule.matchCondition.method == "POST")
        #expect(rule.matchCondition.headerName == "X-Debug")
        #expect(rule.matchCondition.headerValue == "1")
        #expect(rule.matchCondition.urlPattern == RulePatternBuilder.regexSource(
            rawPattern: "https://api.example.com/v1/*",
            matchType: .wildcard,
            includeSubpaths: false
        ))

        if case let .mapLocal(path, statusCode, isDirectory, delayMs, _) = rule.action {
            #expect(path == fileURL.path)
            #expect(statusCode == 202)
            #expect(isDirectory == false)
            #expect(delayMs == 5_000)
        } else {
            Issue.record("Expected .mapLocal")
        }

        // The referenced external file is left byte-for-byte untouched on save.
        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == #"{"original":true}"#)
    }

    @Test("editor menu selections persist method match type and delay")
    func editorMenuSelectionsPersistMethodMatchTypeAndDelay() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalMenu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Menu Flow"
        vm.urlText = "https://api.example.com/v2/*"
        vm.matchType = .wildcard
        vm.method = .delete
        vm.filePath = fileURL.path
        vm.delayPreset = .thirtySeconds
        vm.httpMessageText = """
        HTTP/1.1 204 No Content

        """

        let rule = try #require(vm.makeRule())
        #expect(rule.matchCondition.method == "DELETE")
        #expect(rule.matchCondition.urlPattern == RulePatternBuilder.regexSource(
            rawPattern: "https://api.example.com/v2/*",
            matchType: .wildcard,
            includeSubpaths: false
        ))
        if case let .mapLocal(path, statusCode, isDirectory, delayMs, _) = rule.action {
            #expect(path == fileURL.path)
            #expect(statusCode == 204)
            #expect(isDirectory == false)
            #expect(delayMs == 30_000)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("editor opens an existing local file rule with filled data")
    func editorLoadsExistingLocalFileRuleWithFilledData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("default_message.json")
        try #"{"status":"ok"}"#.write(to: fileURL, atomically: true, encoding: .utf8)

        let existing = ProxyRule(
            name: "Untitled",
            matchCondition: RuleMatchCondition(
                urlPattern: MapLocalPatternFormatter.wildcardToRegex("https://api.example.com/v1/*"),
                method: "PATCH"
            ),
            action: .mapLocal(filePath: fileURL.path, statusCode: 201, delayMs: 3_000)
        )

        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(existingRule: existing))

        #expect(vm.existingID == existing.id)
        #expect(vm.name == "Untitled")
        #expect(vm.method == .patch)
        #expect(vm.matchType == .wildcard)
        #expect(vm.urlText == "https://api.example.com/v1/*")
        #expect(vm.targetMode == .localFile)
        #expect(vm.localFileEnabled)
        #expect(vm.filePath == fileURL.path)
        #expect(vm.delayPreset == .threeSeconds)
        #expect(vm.httpMessageText.contains("HTTP/1.1 201 Created"))
        #expect(vm.responseBodyText.isEmpty)
        #expect(vm.isExternalReference)
        #expect(vm.isSaveEnabled)
    }

    @Test("editor validates Local Directory target")
    func editorValidatesLocalDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalDirTarget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Directory"
        vm.urlText = "https://assets.example.com/*"
        vm.targetMode = .localDirectory
        vm.localDirectoryEnabled = true
        vm.directoryPath = tempDir.path

        #expect(vm.isDirectoryValid)
        #expect(vm.isSaveEnabled)

        vm.directoryPath = tempDir.appendingPathComponent("missing").path
        #expect(!vm.isDirectoryValid)
        #expect(!vm.isSaveEnabled)
    }

    @Test("editor explains invalid regex patterns inline")
    func editorExplainsInvalidRegex() {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Invalid"
        vm.matchType = .regex
        vm.urlText = "["

        #expect(!vm.isSaveEnabled)
        #expect(vm.urlValidationMessage?.contains("Invalid regex pattern") == true)

        vm.urlText = #"https:\/\/api\.example\.com\/v1\/.*"#
        #expect(vm.urlValidationMessage == nil)
    }

    @Test("tool enable setter updates view model immediately")
    func toolEnableSetter() async {
        await RuleTestLock.shared.acquire()
        let vm = MapLocalViewModel(isToolEnabled: true)
        vm.setToolEnabled(false)
        #expect(vm.isToolEnabled == false)
        await RuleSyncService.setMapLocalToolEnabled(true)
        await RuleTestLock.shared.release()
    }

    @Test("saving a rule that references an external file leaves its bytes unchanged")
    func externalReferencedFilesAreNotRewritten() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalExternal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let textURL = tempDir.appendingPathComponent("payload.json")
        let textBytes = Data(#"{"external":true}"#.utf8)
        try textBytes.write(to: textURL, options: .atomic)

        let binaryURL = tempDir.appendingPathComponent("payload.bin")
        let binaryBytes = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x10, 0x7F])
        try binaryBytes.write(to: binaryURL, options: .atomic)

        for fileURL in [textURL, binaryURL] {
            let existing = ProxyRule(
                name: "Reference",
                matchCondition: RuleMatchCondition(
                    urlPattern: MapLocalPatternFormatter.wildcardToRegex("https://api.example.com/*")
                ),
                action: .mapLocal(filePath: fileURL.path, statusCode: 200)
            )
            let vm = MapLocalEditorViewModel()
            vm.load(context: MapLocalEditorContext(existingRule: existing))
            #expect(vm.isExternalReference)
            // Mutating the editable buffer must not rewrite a user-owned file.
            vm.httpMessageText = "HTTP/1.1 500 Internal Server Error\n\nrewritten"
            _ = try #require(vm.makeRule())
        }

        let savedText = try Data(contentsOf: textURL)
        let savedBinary = try Data(contentsOf: binaryURL)
        #expect(savedText == textBytes)
        #expect(savedBinary == binaryBytes)
    }

    @Test("editor previews a full HTTP response file without taking ownership of it")
    func externalFullHTTPMessagePreview() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalFullMessage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("response.http")
        let original = Data("""
        HTTP/1.1 203 Non-Authoritative Information\r
        Content-Type: application/problem+json\r
        Set-Cookie: one=1\r
        Set-Cookie: two=2\r
        \r
        {"source":"file"}
        """.utf8)
        try original.write(to: fileURL)

        let rule = ProxyRule(
            name: "Full message",
            matchCondition: RuleMatchCondition(urlPattern: "http://example.test/items"),
            action: .mapLocal(filePath: fileURL.path, statusCode: 500)
        )
        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(existingRule: rule))

        #expect(vm.isExternalReference)
        #expect(vm.isExternalFullHTTPMessage)
        #expect(vm.responseStatusCode == 203)
        #expect(vm.httpMessageText.contains("Set-Cookie: one=1"))
        #expect(vm.httpMessageText.contains("Set-Cookie: two=2"))
        #expect(vm.responseBodyText == #"{"source":"file"}"#)
        let savedRule = try #require(vm.makeRule())
        if case let .mapLocal(_, statusCode, _, _, _) = savedRule.action {
            // The full message owns the live preview, while the action keeps its original
            // fallback metadata in case the external file later becomes a raw body.
            #expect(statusCode == 500)
        } else {
            Issue.record("Expected .mapLocal")
        }
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test("selecting a malformed file after a full response clears the stale file preview")
    func externalFileSelectionClearsStaleFullMessagePreview() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalStalePreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fullURL = tempDir.appendingPathComponent("full.http")
        try Data("HTTP/1.1 203 Non-Authoritative Information\r\nX-File: full\r\n\r\nFILE".utf8)
            .write(to: fullURL)
        let malformedURL = tempDir.appendingPathComponent("malformed.http")
        try Data("HTTP/1.1 nope\r\nBroken Header\r\n\r\nFILE".utf8).write(to: malformedURL)

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Stale preview"
        vm.urlText = "http://example.test/items"
        vm.httpMessageText = MapLocalHTTPMessage.message(
            statusCode: 202,
            headers: [HTTPHeader(name: "X-Configured", value: "fallback")],
            body: ""
        )

        vm.selectExternalFile(at: fullURL.path)
        #expect(vm.isExternalFullHTTPMessage)
        #expect(vm.responseStatusCode == 203)
        #expect(vm.httpMessageText.contains("X-File: full"))

        vm.selectExternalFile(at: malformedURL.path)
        #expect(!vm.isExternalFullHTTPMessage)
        #expect(vm.externalFileValidationMessage != nil)
        #expect(vm.responseStatusCode == 202)
        #expect(vm.httpMessageText.contains("X-Configured: fallback"))
        #expect(!vm.httpMessageText.contains("X-File: full"))
        #expect(!vm.httpMessageText.contains("FILE"))

        let savedRule = try #require(vm.makeRule())
        if case let .mapLocal(_, statusCode, _, _, headers) = savedRule.action {
            #expect(statusCode == 202)
            #expect(headers.contains(HTTPHeader(name: "X-Configured", value: "fallback")))
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("editor warns when an external file looks like a malformed HTTP response")
    func externalMalformedHTTPMessageWarning() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalMalformedMessage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("broken.http")
        try Data("HTTP/1.1 200 OK\r\nMissing-Colon\r\n\r\nbody".utf8).write(to: fileURL)
        let rule = ProxyRule(
            name: "Malformed message",
            matchCondition: RuleMatchCondition(urlPattern: "http://example.test/items"),
            action: .mapLocal(filePath: fileURL.path)
        )
        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(existingRule: rule))

        #expect(!vm.isExternalFullHTTPMessage)
        #expect(vm.externalFileValidationMessage != nil)
    }

    @Test("captured binary draft writes exact bytes to the generated app-owned file")
    func capturedBinaryDraftWritesExactBytes() throws {
        let binaryBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0x10, 0x7F])
        let draft = MapLocalDraft(
            origin: .selectedTransaction,
            suggestedName: "Binary",
            sourceURL: URL(string: "https://cdn.example.com/logo.png"),
            sourceHost: "cdn.example.com",
            sourcePath: "/logo.png",
            sourceMethod: "GET",
            responseBody: binaryBytes,
            responseContentType: "image/png",
            inferredExtension: "png",
            responseStatusCode: 206
        )

        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(draft: draft))

        let rule = try #require(vm.makeRule())
        guard case let .mapLocal(path, statusCode, _, _, _) = rule.action else {
            Issue.record("Expected .mapLocal")
            return
        }
        #expect(path.hasSuffix(".png"))
        #expect(statusCode == 206)

        let written = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(written == binaryBytes)

        let reopened = MapLocalEditorViewModel()
        reopened.load(context: MapLocalEditorContext(existingRule: rule))
        #expect(reopened.isCapturedBinary)
        reopened.setResponseStatusCode(304)
        let resaved = try #require(reopened.makeRule())
        let resavedBytes = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resavedBytes == binaryBytes)
        if case let .mapLocal(_, reopenedStatusCode, _, _, _) = resaved.action {
            #expect(reopenedStatusCode == 304)
        } else {
            Issue.record("Expected .mapLocal")
        }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    @Test("captured text draft writes the authored body and status to an app-owned file")
    func capturedTextDraftWritesEditableBody() throws {
        let body = Data(#"{"created":true}"#.utf8)
        let draft = MapLocalDraft(
            origin: .selectedTransaction,
            suggestedName: "Created",
            sourceURL: URL(string: "https://api.example.com/items"),
            sourceHost: "api.example.com",
            sourcePath: "/items",
            sourceMethod: "POST",
            responseBody: body,
            responseContentType: "application/json",
            inferredExtension: "json",
            responseStatusCode: 201,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Set-Cookie", value: "session=one"),
                HTTPHeader(name: "Set-Cookie", value: "session=two"),
            ]
        )

        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(draft: draft))
        #expect(vm.isInlineResponseEditable)
        #expect(vm.responseBodyText == #"{"created":true}"#)
        #expect(vm.httpMessageText.contains("Set-Cookie: session=one"))
        #expect(vm.httpMessageText.contains("Set-Cookie: session=two"))

        vm.responseBodyText = #"{"created":"updated"}"#
        let rule = try #require(vm.makeRule())
        guard case let .mapLocal(path, statusCode, _, _, responseHeaders) = rule.action else {
            Issue.record("Expected .mapLocal")
            return
        }
        #expect(statusCode == 201)
        #expect(responseHeaders.filter { $0.name == "Set-Cookie" }.map(\.value) == ["session=one", "session=two"])
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data(#"{"created":"updated"}"#.utf8))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    @Test("new wildcard rule retains authored source and match metadata")
    func wildcardRuleRetainsAuthoredMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalWildcard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")
        try Data(#"{"ok":true}"#.utf8).write(to: fileURL, options: .atomic)

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Wildcard"
        vm.matchType = .wildcard
        vm.includeSubpaths = true
        vm.urlText = "https://api.example.com/v1/*"
        vm.filePath = fileURL.path

        let rule = try #require(vm.makeRule())
        #expect(rule.matchCondition.matchType == .wildcard)
        #expect(rule.matchCondition.sourceURLPattern == "https://api.example.com/v1/*")
        #expect(rule.matchCondition.includeSubpaths == true)
        #expect(rule.matchCondition.urlPattern == RulePatternBuilder.regexSource(
            rawPattern: "https://api.example.com/v1/*",
            matchType: .wildcard,
            includeSubpaths: true
        ))

        let reopened = MapLocalEditorViewModel()
        reopened.load(context: MapLocalEditorContext(existingRule: rule))
        #expect(reopened.matchType == .wildcard)
        #expect(reopened.urlText == "https://api.example.com/v1/*")
        #expect(reopened.includeSubpaths == true)
    }

    @Test("advanced regex rule reopens from metadata without semantic rewriting")
    func regexRuleReopensWithoutRewriting() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalRegex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")
        try Data(#"{"ok":true}"#.utf8).write(to: fileURL, options: .atomic)

        let advancedRegex = #"https:\/\/api\.example\.com\/v(1|2)\/users\/\d+.*"#
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Regex"
        vm.matchType = .regex
        vm.urlText = advancedRegex
        vm.filePath = fileURL.path

        let rule = try #require(vm.makeRule())
        #expect(rule.matchCondition.matchType == .regex)
        #expect(rule.matchCondition.sourceURLPattern == advancedRegex)
        #expect(rule.matchCondition.urlPattern == advancedRegex)

        let reopened = MapLocalEditorViewModel()
        reopened.load(context: MapLocalEditorContext(existingRule: rule))
        #expect(reopened.matchType == .regex)
        #expect(reopened.urlText == advancedRegex)

        let resaved = try #require(reopened.makeRule())
        #expect(resaved.matchCondition.urlPattern == advancedRegex)
        #expect(resaved.matchCondition.sourceURLPattern == advancedRegex)
    }

    @Test("HTTP response editor persists status, repeated headers, and body separately")
    func httpResponseEditorPersistsHeaders() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalHeaders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Headers"
        vm.urlText = "http://example.com/items"
        vm.filePath = fileURL.path
        vm.httpMessageText = """
        HTTP/1.1 203 Non-Authoritative Information
        Content-Type: application/problem+json
        Set-Cookie: one=1
        Set-Cookie: two=2
        X-Map-Local: Rockxy

        {"source":"local"}
        """

        let rule = try #require(vm.makeRule())
        guard case let .mapLocal(_, statusCode, _, _, headers) = rule.action else {
            Issue.record("Expected .mapLocal")
            return
        }
        #expect(statusCode == 203)
        #expect(headers.filter { $0.name == "Set-Cookie" }.map(\.value) == ["one=1", "two=2"])
        #expect(headers.contains(HTTPHeader(name: "X-Map-Local", value: "Rockxy")))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == #"{"source":"local"}"#)

        let reopened = MapLocalEditorViewModel()
        reopened.load(context: MapLocalEditorContext(existingRule: rule))
        #expect(reopened.httpMessageText.contains("Content-Type: application/problem+json"))
        #expect(reopened.httpMessageText.contains("Set-Cookie: one=1"))
        #expect(reopened.httpMessageText.contains("Set-Cookie: two=2"))
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("wildcard exact URL has a boundary and HTTPS prerequisite host is explicit")
    func wildcardExactBoundaryAndHTTPSHost() {
        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.urlText = "https://api.example.com/v1/items"
        vm.matchType = .wildcard
        vm.includeSubpaths = false

        #expect(vm.httpsTargetHost == "api.example.com")
        #expect(vm.isHTTPSPattern)
        #expect(vm.urlPatternForSaving() == RulePatternBuilder.regexSource(
            rawPattern: vm.urlText,
            matchType: .wildcard,
            includeSubpaths: false
        ))

        vm.matchType = .regex
        #expect(vm.httpsTargetHost == nil)
    }

    @Test("Map Local reorder preserves every unrelated global rule slot")
    func mapLocalReorderPreservesGlobalSlots() {
        let first = ProxyRule(
            name: "First",
            matchCondition: RuleMatchCondition(),
            action: .mapLocal(filePath: "/tmp/first.json")
        )
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(),
            action: .block(statusCode: 403)
        )
        let second = ProxyRule(
            name: "Second",
            matchCondition: RuleMatchCondition(),
            action: .mapLocal(filePath: "/tmp/second.json")
        )

        let reordered = MapLocalViewModel.applyingMapLocalOrder([second, first], to: [first, block, second])

        #expect(reordered.map(\.id) == [second.id, block.id, first.id])
    }

    @Test("Map Local current app and rule-management shortcuts stay wired")
    func mapLocalShortcutsStayWired() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectRoot = testsDirectory.deletingLastPathComponent()
        let windowSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Rockxy/Views/Rules/MapLocalWindowView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Rockxy/RockxyApp.swift"),
            encoding: .utf8
        )

        #expect(appSource.contains(#".keyboardShortcut("l", modifiers: [.command, .option])"#))
        #expect(windowSource.contains(#".keyboardShortcut("n", modifiers: .command)"#))
        #expect(windowSource.contains(".keyboardShortcut(.return, modifiers: .command)"))
        #expect(windowSource.contains(#".keyboardShortcut("d", modifiers: .command)"#))
        #expect(windowSource.contains(".keyboardShortcut(.delete, modifiers: .command)"))
        #expect(windowSource.contains(".keyboardShortcut(.space, modifiers: [])"))
    }
}
