import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapLocalModelTests {
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
        #expect(rule.matchCondition.urlPattern == #"https:\/\/api\.example\.com\/v1\/.*"#)

        if case let .mapLocal(path, statusCode, isDirectory, delayMs) = rule.action {
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
        #expect(rule.matchCondition.urlPattern == #"https:\/\/api\.example\.com\/v2\/.*"#)
        if case let .mapLocal(path, statusCode, isDirectory, delayMs) = rule.action {
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
        #expect(vm.httpMessageText.contains("HTTP/1.1 201 CREATED"))
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
        guard case let .mapLocal(path, statusCode, _, _) = rule.action else {
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
        if case let .mapLocal(_, reopenedStatusCode, _, _) = resaved.action {
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
            responseStatusCode: 201
        )

        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(draft: draft))
        #expect(vm.isInlineResponseEditable)
        #expect(vm.responseBodyText == #"{"created":true}"#)

        vm.responseBodyText = #"{"created":"updated"}"#
        let rule = try #require(vm.makeRule())
        guard case let .mapLocal(path, statusCode, _, _) = rule.action else {
            Issue.record("Expected .mapLocal")
            return
        }
        #expect(statusCode == 201)
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
        #expect(rule.matchCondition.urlPattern == MapLocalPatternFormatter
            .wildcardToRegex("https://api.example.com/v1/*"))

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
}
