import CryptoKit
import Foundation

// Renders the diff interface for the diff workflow.

// MARK: - DiffLineType

enum DiffLineType: Equatable, Sendable {
    case unchanged
    case added
    case removed
}

// MARK: - DiffLine

struct DiffLine: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(lineNumber: Int, content: String, type: DiffLineType) {
        self.id = UUID()
        self.lineNumber = lineNumber
        self.content = content
        self.type = type
    }

    // MARK: Internal

    let id: UUID
    let lineNumber: Int
    let content: String
    let type: DiffLineType

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.lineNumber == rhs.lineNumber && lhs.content == rhs.content && lhs.type == rhs.type
    }
}

// MARK: - DiffSection

/// A named section within a structured diff result (e.g., "Request Line", "Headers", "Body").
struct DiffSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let lines: [DiffLine]
}

// MARK: - SideBySideRow

/// A paired row for side-by-side rendering. Both panes render from the same sequence,
/// so lines always align vertically. nil means a spacer at that position.
struct SideBySideRow: Identifiable, Sendable {
    // MARK: Lifecycle

    init(left: DiffLine?, right: DiffLine?) {
        id = left?.id ?? right?.id ?? UUID()
        self.left = left
        self.right = right
    }

    // MARK: Internal

    let id: UUID
    let left: DiffLine?
    let right: DiffLine?
}

// MARK: - DiffResult

/// Structured diff result containing named sections, each with their own diff lines.
struct DiffResult: Sendable {
    static let empty = DiffResult(sections: [])

    let sections: [DiffSection]

    var allLines: [DiffLine] {
        sections.flatMap(\.lines)
    }

    var addedCount: Int {
        allLines.filter { $0.type == .added }.count
    }

    var removedCount: Int {
        allLines.filter { $0.type == .removed }.count
    }

    var differenceCount: Int {
        addedCount + removedCount
    }

    var leftLines: [DiffLine] {
        allLines.filter { $0.type != .added }
    }

    var rightLines: [DiffLine] {
        allLines.filter { $0.type != .removed }
    }

    /// Builds paired rows for side-by-side rendering from a section's diff lines.
    /// Unchanged lines appear on both sides. Removed lines appear left-only (right=nil).
    /// Added lines appear right-only (left=nil).
    static func sideBySideRows(from lines: [DiffLine]) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        for line in lines {
            switch line.type {
            case .unchanged:
                rows.append(SideBySideRow(left: line, right: line))
            case .removed:
                rows.append(SideBySideRow(left: line, right: nil))
            case .added:
                rows.append(SideBySideRow(left: nil, right: line))
            }
        }
        return rows
    }
}

// MARK: - DiffEngine

/// Pure diff algorithm using Longest Common Subsequence. Extracted for testability.
enum DiffEngine {
    // MARK: Internal

    static let maximumLineCount = 1_000
    static let maximumLineLength = 16_384
    static let maximumTextPreviewBytes = 512 * 1_024

    /// Computes a line-level diff between two string arrays.
    static func diff(old: [String], new: [String]) -> [DiffLine] {
        let boundedOld = boundedLines(old)
        let boundedNew = boundedLines(new)
        let lcs = longestCommonSubsequence(boundedOld, boundedNew)
        var result: [DiffLine] = []
        var oldIdx = 0
        var newIdx = 0
        var lineNumber = 1

        for commonLine in lcs {
            guard !Task.isCancelled else {
                return []
            }
            while oldIdx < boundedOld.count, boundedOld[oldIdx] != commonLine {
                result.append(DiffLine(lineNumber: lineNumber, content: boundedOld[oldIdx], type: .removed))
                oldIdx += 1
                lineNumber += 1
            }
            while newIdx < boundedNew.count, boundedNew[newIdx] != commonLine {
                result.append(DiffLine(lineNumber: lineNumber, content: boundedNew[newIdx], type: .added))
                newIdx += 1
                lineNumber += 1
            }
            result.append(DiffLine(lineNumber: lineNumber, content: commonLine, type: .unchanged))
            oldIdx += 1
            newIdx += 1
            lineNumber += 1
        }

        while oldIdx < boundedOld.count {
            result.append(DiffLine(lineNumber: lineNumber, content: boundedOld[oldIdx], type: .removed))
            oldIdx += 1
            lineNumber += 1
        }
        while newIdx < boundedNew.count {
            result.append(DiffLine(lineNumber: lineNumber, content: boundedNew[newIdx], type: .added))
            newIdx += 1
            lineNumber += 1
        }

        return result
    }

    /// Computes a bounded line diff directly from text without first allocating
    /// an unbounded array for every line in the input.
    static func diffText(old: String, new: String) -> [DiffLine] {
        let boundedOld = boundedTextLines(old)
        guard !Task.isCancelled else {
            return []
        }
        let boundedNew = boundedTextLines(new)
        guard !Task.isCancelled else {
            return []
        }
        return diff(old: boundedOld, new: boundedNew)
    }

    /// Computes a structured diff with named sections, matching by title.
    /// Uses an ordered title list from both sides to keep section order stable.
    static func diffSections(leftSections: [(String, String)], rightSections: [(String, String)]) -> DiffResult {
        var sections: [DiffSection] = []

        // Build ordered title list preserving order from left side, then adding any right-only titles
        var orderedTitles: [String] = []
        for (title, _) in leftSections where !orderedTitles.contains(title) {
            orderedTitles.append(title)
        }
        for (title, _) in rightSections where !orderedTitles.contains(title) {
            orderedTitles.append(title)
        }

        let leftMap = Dictionary(leftSections.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        let rightMap = Dictionary(rightSections.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })

        for title in orderedTitles {
            guard !Task.isCancelled else {
                return .empty
            }
            let leftContent = leftMap[title] ?? ""
            let rightContent = rightMap[title] ?? ""

            let leftLines = leftContent.components(separatedBy: "\n")
            let rightLines = rightContent.components(separatedBy: "\n")
            let diffLines = diff(old: leftLines, new: rightLines)

            sections.append(DiffSection(title: title, lines: diffLines))
        }

        return DiffResult(sections: sections)
    }

    // MARK: Private

    private static let hashChunkSize = 64 * 1_024

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        guard m > 0, n > 0 else {
            return []
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1 ... m {
            guard !Task.isCancelled else {
                return []
            }
            for j in 1 ... n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = m
        var j = n
        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }

    private static func boundedLines(_ lines: [String]) -> [String] {
        guard lines.count > maximumLineCount else {
            return lines.map(boundedLine)
        }

        let digest = sha256(lines)
        guard !Task.isCancelled else {
            return []
        }
        return lines.prefix(maximumLineCount - 1).map(boundedLine) + [
            String(
                localized:
                "Comparison limited to \(maximumLineCount - 1) of \(lines.count) lines · SHA-256 \(digest)",
                bundle: RockxyLocalization.bundle
            ),
        ]
    }

    private static func boundedLine(_ line: String) -> String {
        guard line.count > maximumLineLength else {
            return line
        }
        let prefix = String(line.prefix(maximumLineLength))
        return String(
            localized:
            "\(prefix)… [line limited to \(maximumLineLength) of \(line.count) characters · SHA-256 \(sha256(line))]",
            bundle: RockxyLocalization.bundle
        )
    }

    private static func sha256(_ value: String) -> String {
        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(hashChunkSize)
        var processedByteCount = 0

        for byte in value.utf8 {
            if processedByteCount.isMultiple(of: hashChunkSize), Task.isCancelled {
                return ""
            }
            buffer.append(byte)
            processedByteCount += 1
            if buffer.count >= hashChunkSize {
                hasher.update(data: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            hasher.update(data: buffer)
        }
        return hexDigest(hasher.finalize())
    }

    private static func sha256(_ lines: [String]) -> String {
        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(hashChunkSize)
        var processedByteCount = 0

        for (index, line) in lines.enumerated() {
            for byte in line.utf8 {
                if processedByteCount.isMultiple(of: hashChunkSize), Task.isCancelled {
                    return ""
                }
                buffer.append(byte)
                processedByteCount += 1
                if buffer.count >= hashChunkSize {
                    hasher.update(data: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if index < lines.count - 1 {
                buffer.append(0x0A)
                processedByteCount += 1
                if buffer.count >= hashChunkSize {
                    hasher.update(data: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        }
        if !buffer.isEmpty {
            hasher.update(data: buffer)
        }
        return hexDigest(hasher.finalize())
    }

    private static func boundedTextLines(_ text: String) -> [String] {
        var hasher = SHA256()
        var hashBuffer = Data()
        hashBuffer.reserveCapacity(hashChunkSize)
        var previewData = Data()
        previewData.reserveCapacity(maximumTextPreviewBytes)
        var totalByteCount = 0
        var totalLineCount = 1

        for byte in text.utf8 {
            if totalByteCount.isMultiple(of: hashChunkSize), Task.isCancelled {
                return []
            }
            if previewData.count < maximumTextPreviewBytes {
                previewData.append(byte)
            }
            if byte == 0x0A {
                totalLineCount += 1
            }
            hashBuffer.append(byte)
            totalByteCount += 1
            if hashBuffer.count >= hashChunkSize {
                hasher.update(data: hashBuffer)
                hashBuffer.removeAll(keepingCapacity: true)
            }
        }
        if !hashBuffer.isEmpty {
            hasher.update(data: hashBuffer)
        }
        guard !Task.isCancelled else {
            return []
        }

        previewData = validUTF8Prefix(previewData)
        guard let previewText = String(data: previewData, encoding: .utf8) else {
            return []
        }

        var lines = previewText.components(separatedBy: "\n")
        let inputWasLimited = totalByteCount > previewData.count
        let linesWereLimited = totalLineCount > maximumLineCount
        guard inputWasLimited || linesWereLimited else {
            return lines.map(boundedLine)
        }

        let retainedLineCount = min(lines.count, maximumLineCount - 1)
        lines = Array(lines.prefix(retainedLineCount))
        let digest = hexDigest(hasher.finalize())
        lines.append(
            String(
                localized:
                "Comparison limited to \(retainedLineCount) of \(totalLineCount) lines and \(previewData.count) of \(totalByteCount) UTF-8 bytes · SHA-256 \(digest)",
                bundle: RockxyLocalization.bundle
            )
        )
        return lines.map(boundedLine)
    }

    private static func validUTF8Prefix(_ data: Data) -> Data {
        var prefix = data
        for _ in 0 ..< 4 where String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
            prefix.removeLast()
        }
        return prefix
    }

    private static func hexDigest(_ digest: SHA256.Digest) -> String {
        digest
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
