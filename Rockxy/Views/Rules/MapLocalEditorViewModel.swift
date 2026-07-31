import AppKit
import Foundation
import SwiftUI

// Editor view-model and message helpers for the Map Local editor window.
// Split out of `MapLocalWindowView.swift` to keep that file within the length limit;
// the two-window `mapLocal` / `mapLocalEditor` flow and all type names are unchanged.

// MARK: - MapLocalFileSource

/// How the editor should persist the Map Local response file on save.
/// Keeps app-owned generated content, captured binary payloads, and user-owned
/// external references distinct so we never rewrite files we do not own.
private enum MapLocalFileSource: Equatable {
    /// App-owned generated file — the editable HTTP message buffer is the source of truth.
    case generated
    /// Captured binary response seeded from a transaction — written byte-for-byte.
    case capturedBinary(Data)
    /// User-owned external file referenced by the rule — never rewritten on save.
    case externalReference
}

// MARK: - MapLocalEditorViewModel

@MainActor @Observable
final class MapLocalEditorViewModel {
    // MARK: Internal

    var name = "Untitled"
    var urlText = ""
    var method: MapLocalHTTPMethod = .any
    var matchType: MapLocalMatchType = .wildcard
    var includeSubpaths = false
    var delayPreset: MapLocalDelayPreset = .none
    var customDelaySeconds = 15
    var targetMode: MapLocalTargetMode = .localFile
    var localFileEnabled = true
    var localDirectoryEnabled = false
    var filePath = ""
    var directoryPath = ""
    var httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
    var errorMessage: String?

    private(set) var existingID: UUID?
    private(set) var originalRule: ProxyRule?
    private(set) var draft: MapLocalDraft?
    private(set) var isLoaded = false

    /// True when the selected local file is a user-owned external reference that
    /// must never be rewritten when the rule is saved.
    var isExternalReference: Bool {
        fileSource == .externalReference
    }

    var isCapturedBinary: Bool {
        if case .capturedBinary = fileSource {
            return true
        }
        return false
    }

    var isInlineResponseEditable: Bool {
        fileSource == .generated
    }

    var isSelectedFileAvailable: Bool {
        guard !filePath.isEmpty else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    var responseContentType: String {
        MimeTypeResolver.mimeType(for: filePath)
    }

    var responseStatusCode: Int {
        MapLocalHTTPMessage.parse(httpMessageText).statusCode
    }

    var responseBodyText: String {
        get {
            MapLocalHTTPMessage.parse(httpMessageText).body
        }
        set {
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: responseStatusCode,
                contentType: responseContentType,
                body: newValue
            )
        }
    }

    var windowTitle: String {
        "Map Local Editor: \(name.isEmpty ? "Untitled" : name)"
    }

    var selectedPath: String {
        targetMode == .localDirectory ? directoryPath : filePath
    }

    var isDirectoryValid: Bool {
        guard !directoryPath.isEmpty else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isTargetValid
            && RegexValidator.compile(urlPatternForSaving()).isSuccess
    }

    var urlValidationMessage: String? {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if case let .failure(error) = RegexValidator.compile(urlPatternForSaving()) {
            return error.localizedDescription
        }
        return nil
    }

    var delayMs: Int {
        if delayPreset == .custom {
            return max(0, customDelaySeconds) * 1_000
        }
        return delayPreset.delayMs
    }

    func load(context: MapLocalEditorContext) {
        existingID = context.existingRule?.id
        originalRule = context.existingRule
        draft = context.draft

        if let rule = context.existingRule {
            load(existingRule: rule)
        } else if let draft = context.draft {
            load(draft: draft)
        } else {
            loadBlank()
        }
        isLoaded = true
    }

    func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = targetMode == .localFile
        panel.canChooseDirectories = targetMode == .localDirectory
        panel.allowsMultipleSelection = false
        panel.message = targetMode == .localDirectory
            ? String(localized: "Select a local directory to serve files from")
            : String(localized: "Select a local file to serve for matched requests")

        if panel.runModal() == .OK, let url = panel.url {
            if targetMode == .localDirectory {
                directoryPath = url.path(percentEncoded: false)
                localDirectoryEnabled = true
            } else {
                filePath = url.path(percentEncoded: false)
                localFileEnabled = true
                // A user-selected file is referenced as-is: never load it into the
                // editable buffer and never rewrite it when the rule is saved.
                fileSource = .externalReference
            }
        }
    }

    func setResponseStatusCode(_ statusCode: Int) {
        let normalizedStatus = min(max(statusCode, 100), 599)
        httpMessageText = MapLocalHTTPMessage.message(
            statusCode: normalizedStatus,
            contentType: responseContentType,
            body: responseBodyText
        )
    }

    func showSelectedPathInFinder() {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSelectedPath(with app: MapLocalExternalEditor) {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        if let bundleID = app.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func makeRule() -> ProxyRule? {
        guard isSaveEnabled else {
            errorMessage = String(localized: "Complete the matching rule and local target before saving.")
            return nil
        }

        do {
            if targetMode == .localFile {
                try saveLocalFileIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        var condition = originalRule?.matchCondition ?? RuleMatchCondition()
        condition.urlPattern = urlPatternForSaving()
        condition.method = method.ruleValue
        // Retain the authored pattern + match semantics so reopening the rule does
        // not have to guess (and rewrite) advanced regex from the compiled pattern.
        condition.sourceURLPattern = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.matchType = matchType == .regex ? .regex : .wildcard
        condition.includeSubpaths = matchType == .wildcard ? includeSubpaths : false

        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: originalRule?.isEnabled ?? true,
            matchCondition: condition,
            action: .mapLocal(
                filePath: targetMode == .localDirectory ? directoryPath : filePath,
                statusCode: statusCodeFromText(),
                isDirectory: targetMode == .localDirectory,
                delayMs: delayMs
            ),
            priority: originalRule?.priority ?? 0
        )
    }

    func urlPatternForSaving() -> String {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchType == .wildcard else {
            return trimmed
        }
        let pattern = includeSubpaths && !trimmed.hasSuffix("*") ? "\(trimmed)*" : trimmed
        return MapLocalPatternFormatter.wildcardToRegex(pattern)
    }

    // MARK: Private

    /// Root directory Rockxy owns for generated Map Local response files.
    private static var mapLocalDirectoryRoot: URL {
        RockxyIdentity.current
            .appSupportDirectory()
            .appendingPathComponent("map-local", isDirectory: true)
    }

    private var fileSource: MapLocalFileSource = .generated

    private var isTargetValid: Bool {
        switch targetMode {
        case .localFile:
            !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .localDirectory:
            isDirectoryValid
        }
    }

    private static func defaultMapLocalFilePath() -> String {
        generatedMapLocalFilePath(fileExtension: nil)
    }

    /// Builds an app-owned generated file path using the inferred extension so
    /// binary responses land in a correctly-typed file instead of always `.json`.
    private static func generatedMapLocalFilePath(fileExtension: String?) -> String {
        let ext = sanitizedExtension(fileExtension) ?? "json"
        return mapLocalDirectoryRoot
            .appendingPathComponent("default_message_\(UUID().uuidString.prefix(8)).\(ext)")
            .path
    }

    private static func sanitizedExtension(_ candidate: String?) -> String? {
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespaces).lowercased(), !trimmed.isEmpty else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Returns true only when `path` resolves inside Rockxy's app-owned Map Local
    /// directory. Paths are standardized and symlink-resolved before the containment
    /// check to avoid naive string-prefix false positives.
    private static func isAppOwnedPath(_ path: String) -> Bool {
        guard !path.isEmpty else {
            return false
        }
        let root = mapLocalDirectoryRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        if candidate.path == root.path {
            return true
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPrefix)
    }

    private func loadBlank() {
        name = "Untitled"
        urlText = ""
        method = .any
        matchType = .wildcard
        includeSubpaths = false
        delayPreset = .none
        customDelaySeconds = 15
        targetMode = .localFile
        localFileEnabled = true
        localDirectoryEnabled = false
        filePath = Self.defaultMapLocalFilePath()
        directoryPath = ""
        httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
        fileSource = .generated
    }

    private func load(draft: MapLocalDraft) {
        loadBlank()
        name = draft.suggestedName.isEmpty ? "Untitled" : draft.suggestedName
        method = MapLocalHTTPMethod(ruleMethod: draft.sourceMethod)
        matchType = .wildcard
        includeSubpaths = draft.origin == .domainQuickCreate
        if let sourceURL = draft.sourceURL {
            urlText = sourceURL.absoluteString
        } else {
            urlText = "https://\(draft.sourceHost)/*"
        }

        // Seed an app-owned generated file using the inferred extension.
        filePath = Self.generatedMapLocalFilePath(fileExtension: draft.inferredExtension)

        let status = draft.responseStatusCode ?? 200
        guard let body = draft.responseBody, !body.isEmpty else {
            if draft.responseStatusCode != nil {
                // No body but a captured status — reflect it in the template.
                let contentType = draft.responseContentType ?? "application/json; charset=utf-8"
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: status,
                    contentType: contentType,
                    body: "{\n  \"status\": \"ok\"\n}"
                )
            }
            fileSource = .generated
            return
        }

        let contentType = draft.responseContentType ?? MimeTypeResolver.mimeType(for: filePath)
        if let bodyText = String(data: body, encoding: .utf8) {
            httpMessageText = MapLocalHTTPMessage.message(statusCode: status, contentType: contentType, body: bodyText)
            fileSource = .generated
        } else {
            // Binary payload — keep the raw bytes for byte-identical persistence and
            // show a header-only preview (never a fallback JSON/empty-UTF-8 conversion).
            httpMessageText = MapLocalHTTPMessage.message(statusCode: status, contentType: contentType, body: "")
            fileSource = .capturedBinary(body)
        }
    }

    private func load(existingRule rule: ProxyRule) {
        name = rule.name.isEmpty ? "Untitled" : rule.name
        loadURLMetadata(from: rule.matchCondition)
        method = MapLocalHTTPMethod(ruleMethod: rule.matchCondition.method)
        if case let .mapLocal(path, statusCode, isDirectory, delayMs) = rule.action {
            targetMode = isDirectory ? .localDirectory : .localFile
            filePath = isDirectory ? "" : path
            directoryPath = isDirectory ? path : ""
            localFileEnabled = !isDirectory
            localDirectoryEnabled = isDirectory
            delayPreset = MapLocalDelayPreset.from(delayMs: delayMs)
            if delayPreset == .custom {
                customDelaySeconds = max(0, delayMs / 1_000)
            }
            if isDirectory {
                fileSource = .externalReference
            } else {
                loadExistingFile(path: path, statusCode: statusCode)
            }
        }
    }

    private func loadExistingFile(path: String, statusCode: Int) {
        guard Self.isAppOwnedPath(path) else {
            // External references are never loaded into the editor or rewritten.
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: statusCode,
                contentType: MimeTypeResolver.mimeType(for: path),
                body: ""
            )
            fileSource = .externalReference
            return
        }

        if let data = MapLocalFileValidator.loadFileData(at: path) {
            let contentType = MimeTypeResolver.mimeType(for: path)
            if let body = String(data: data, encoding: .utf8) {
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: statusCode,
                    contentType: contentType,
                    body: body
                )
                fileSource = .generated
            } else {
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: statusCode,
                    contentType: contentType,
                    body: ""
                )
                fileSource = .capturedBinary(data)
            }
            return
        }

        let fileExists = FileManager.default.fileExists(atPath: path)
        httpMessageText = MapLocalHTTPMessage.message(
            statusCode: statusCode,
            contentType: MimeTypeResolver.mimeType(for: path),
            body: ""
        )
        // A missing app-owned target may be recreated. Existing data that failed
        // validation stays read-only so Save cannot destroy an oversized or unsafe file.
        fileSource = fileExists ? .externalReference : .generated
    }

    /// Restores the editor's URL fields, preferring authored metadata when present
    /// and falling back to the legacy heuristic for rules saved before metadata existed.
    private func loadURLMetadata(from condition: RuleMatchCondition) {
        if let authored = condition.sourceURLPattern, let storedMatchType = condition.matchType {
            urlText = authored
            matchType = storedMatchType == .regex ? .regex : .wildcard
            includeSubpaths = condition.includeSubpaths ?? false
            return
        }

        let storedPattern = condition.urlPattern ?? ""
        if MapLocalPatternFormatter.prefersWildcardPresentation(storedPattern) {
            urlText = MapLocalPatternFormatter.readablePattern(storedPattern)
            matchType = .wildcard
        } else {
            urlText = storedPattern
            matchType = .regex
        }
        includeSubpaths = false
    }

    private func statusCodeFromText() -> Int {
        MapLocalHTTPMessage.parse(httpMessageText).statusCode
    }

    private func saveLocalFileIfNeeded() throws {
        switch fileSource {
        case .externalReference:
            // Referenced user-owned file — leave its bytes untouched.
            return
        case let .capturedBinary(data):
            try writeData(data)
        case .generated:
            let parsed = MapLocalHTTPMessage.parse(httpMessageText)
            try writeData(Data(parsed.body.utf8))
        }
    }

    private func writeData(_ data: Data) throws {
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private extension Result where Success == NSRegularExpression, Failure == RegexValidator.ValidationError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

// MARK: - MapLocalHTTPMessage

enum MapLocalHTTPMessage {
    static func defaultMessage(statusCode: Int) -> String {
        message(
            statusCode: statusCode,
            contentType: "application/json; charset=utf-8",
            body: "{\n  \"status\": \"ok\"\n}"
        )
    }

    static func message(statusCode: Int, contentType: String, body: String) -> String {
        let status = HTTPURLResponse.localizedString(forStatusCode: statusCode).uppercased()
        return "HTTP/1.1 \(statusCode) \(status)\nContent-Type: \(contentType)\n\n\(body)"
    }

    static func parse(_ text: String) -> (statusCode: Int, body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let statusCode = lines.first
            .flatMap { line in
                line.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            } ?? 200

        if let range = normalized.range(of: "\n\n") {
            return (statusCode, String(normalized[range.upperBound...]))
        }
        return (statusCode, normalized)
    }
}
