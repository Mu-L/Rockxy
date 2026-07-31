import CryptoKit
import Foundation

// Renders the diff interface for the diff workflow.

// MARK: - CompareTarget

enum CompareTarget: String, CaseIterable, Sendable {
    case request = "Request"
    case response = "Response"
    case timing = "Timing"

    var title: String {
        switch self {
        case .request: String(localized: "Request")
        case .response: String(localized: "Response")
        case .timing: String(localized: "Timing")
        }
    }
}

// MARK: - PresentationMode

enum PresentationMode: String, CaseIterable, Sendable {
    case sideBySide = "Side by Side"
    case unified = "Unified"

    var title: String {
        switch self {
        case .sideBySide: String(localized: "Side by Side")
        case .unified: String(localized: "Unified")
        }
    }
}

// MARK: - DiffTransactionSnapshot

struct DiffTransactionSnapshot: Sendable {
    let request: HTTPRequestData
    let response: HTTPResponseData?
    let timingInfo: TimingInfo?
    let measuredDuration: TimeInterval?

    init(transaction: HTTPTransaction) {
        request = transaction.request
        response = transaction.response
        timingInfo = transaction.timingInfo
        measuredDuration = transaction.measuredDuration
    }
}

// MARK: - DiffFormatter

/// Formats HTTPTransaction data into structured sections for diffing.
/// Produces named section pairs that DiffEngine can compare.
enum DiffFormatter {
    // MARK: Internal

    static let maximumBodyPreviewBytes = 512 * 1_024

    /// Formats a transaction into named sections based on the compare target.
    static func format(
        transaction: HTTPTransaction,
        target: CompareTarget
    )
        -> [(title: String, content: String)]
    {
        format(snapshot: DiffTransactionSnapshot(transaction: transaction), target: target)
    }

    static func format(
        snapshot: DiffTransactionSnapshot,
        target: CompareTarget
    )
        -> [(title: String, content: String)]
    {
        switch target {
        case .request:
            formatRequest(snapshot)
        case .response:
            formatResponse(snapshot)
        case .timing:
            formatTiming(snapshot)
        }
    }

    /// Computes a structured diff between two transactions for the given compare target.
    static func diff(
        left: HTTPTransaction,
        right: HTTPTransaction,
        target: CompareTarget
    )
        -> DiffResult
    {
        let leftSections = format(transaction: left, target: target)
        let rightSections = format(transaction: right, target: target)
        return DiffEngine.diffSections(leftSections: leftSections, rightSections: rightSections)
    }

    static func diff(
        left: DiffTransactionSnapshot,
        right: DiffTransactionSnapshot,
        target: CompareTarget
    )
        -> DiffResult
    {
        let leftSections = format(snapshot: left, target: target)
        let rightSections = format(snapshot: right, target: target)
        return DiffEngine.diffSections(leftSections: leftSections, rightSections: rightSections)
    }

    // MARK: Private

    // MARK: - Request Formatting

    private static func formatRequest(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        var sections: [(String, String)] = []

        // Request line
        sections.append((
            String(localized: "Request Line"),
            "\(transaction.request.method) \(transaction.request.url.path) \(normalizeHTTPVersion(transaction.request.httpVersion))"
        ))

        // Host
        sections.append((
            String(localized: "Host"),
            transaction.request.url.host ?? "—"
        ))

        // Query
        let queryItems = URLComponents(url: transaction.request.url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        if !queryItems.isEmpty {
            let queryText = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "\n")
            sections.append((String(localized: "Query"), queryText))
        } else {
            sections.append((
                String(localized: "Query"),
                String(localized: "(no query parameters)")
            ))
        }

        // Request headers
        let headersText = transaction.request.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
        sections.append((
            String(localized: "Headers"),
            headersText.isEmpty ? String(localized: "(no headers)") : headersText
        ))

        // Request body
        if let body = transaction.request.body {
            sections.append((
                String(localized: "Body"),
                formatBody(body, contentType: transaction.request.contentType?.rawValue)
            ))
        } else {
            sections.append((
                String(localized: "Body"),
                String(localized: "No request body")
            ))
        }

        return sections
    }

    // MARK: - Response Formatting

    private static func formatResponse(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        var sections: [(String, String)] = []

        guard let response = transaction.response else {
            return [
                (String(localized: "Status Line"), String(localized: "No response")),
                (String(localized: "Headers"), String(localized: "(no headers)")),
                (String(localized: "Body"), String(localized: "No response body")),
            ]
        }

        // Status line
        sections.append((
            String(localized: "Status Line"),
            "HTTP/1.1 \(response.statusCode) \(response.statusMessage)"
        ))

        // Response headers
        let headersText = response.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
        sections.append((
            String(localized: "Headers"),
            headersText.isEmpty ? String(localized: "(no headers)") : headersText
        ))

        // Response body
        if let body = response.body {
            let contentType = response.headers.first { $0.name.lowercased() == "content-type" }?.value
            sections.append((
                String(localized: "Body"),
                formatBody(
                    body,
                    contentType: contentType,
                    captureWasTruncated: response.bodyTruncated
                )
            ))
        } else {
            let bodyText = response.bodyTruncated
                ? "\(String(localized: "No response body"))\n\(captureTruncationNotice)"
                : String(localized: "No response body")
            sections.append((String(localized: "Body"), bodyText))
        }

        return sections
    }

    // MARK: - Timing Formatting

    private static func formatTiming(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        guard let timing = transaction.timingInfo else {
            if let measuredDuration = transaction.measuredDuration {
                return [(
                    String(localized: "Timing"),
                    "\(String(localized: "Total measured duration")): \(formatMs(measuredDuration))\n"
                        + String(localized: "Detailed phase timing unavailable")
                )]
            }
            return [(
                String(localized: "Timing"),
                String(localized: "No timing data")
            )]
        }

        let content = """
        \(String(localized: "DNS Lookup")): \(formatMs(timing.dnsLookup))
        \(String(localized: "TCP Connection")): \(formatMs(timing.tcpConnection))
        \(String(localized: "TLS Handshake")): \(formatMs(timing.tlsHandshake))
        \(String(localized: "Time to First Byte")): \(formatMs(timing.timeToFirstByte))
        \(String(localized: "Content Transfer")): \(formatMs(timing.contentTransfer))
        \(String(localized: "Total")): \(formatMs(timing.totalDuration))
        """

        return [(String(localized: "Timing"), content)]
    }

    // MARK: - Body Formatting

    private static let captureTruncationNotice = String(
        localized: "Capture truncated — comparison covers captured bytes only."
    )

    private static func formatBody(
        _ data: Data,
        contentType: String?,
        captureWasTruncated: Bool = false
    ) -> String {
        let bodyIsLimited = data.count > maximumBodyPreviewBytes
        let previewData = validUTF8Prefix(of: data, limit: maximumBodyPreviewBytes)
        let shouldTreatAsBinary = isBinaryContentType(contentType)
            || containsBinaryControlBytes(previewData)
            || String(data: previewData, encoding: .utf8) == nil

        if shouldTreatAsBinary {
            return binaryDescription(
                data,
                contentType: contentType,
                captureWasTruncated: captureWasTruncated
            )
        }

        guard let text = String(data: previewData, encoding: .utf8) else {
            return binaryDescription(
                data,
                contentType: contentType,
                captureWasTruncated: captureWasTruncated
            )
        }

        // Try JSON pretty-print
        let renderedText: String
        if !bodyIsLimited,
           let jsonObject = try? JSONSerialization.jsonObject(with: previewData),
           let prettyData = try? JSONSerialization.data(
               withJSONObject: jsonObject,
               options: [.prettyPrinted, .sortedKeys]
           ),
           let prettyText = String(data: prettyData, encoding: .utf8)
        {
            renderedText = prettyText
        } else {
            renderedText = text
        }

        var lines = [renderedText]
        if bodyIsLimited {
            lines.append(
                String(
                    localized:
                    "Body preview limited to \(previewData.count) of \(data.count) captured bytes."
                )
            )
            lines.append(
                "\(String(localized: "SHA-256 (all captured bytes)")): \(sha256(data))"
            )
        }
        if captureWasTruncated {
            lines.append(captureTruncationNotice)
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizeHTTPVersion(_ version: String) -> String {
        version.hasPrefix("HTTP/") ? version : "HTTP/\(version)"
    }

    private static func formatMs(_ seconds: TimeInterval) -> String {
        String(format: "%.1fms", seconds * 1_000)
    }

    private static func sha256(_ data: Data) -> String {
        let chunkSize = 64 * 1_024
        var hasher = SHA256()
        var offset = data.startIndex

        while offset < data.endIndex {
            guard !Task.isCancelled else {
                return ""
            }
            let end = min(offset + chunkSize, data.endIndex)
            hasher.update(data: data[offset ..< end])
            offset = end
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func binaryDescription(
        _ data: Data,
        contentType: String?,
        captureWasTruncated: Bool
    ) -> String {
        var lines = [
            String(localized: "Binary body"),
            "\(String(localized: "Size")): \(data.count) \(String(localized: "bytes"))",
            "\(String(localized: "Content-Type")): \(contentType ?? String(localized: "unknown"))",
            "\(String(localized: "SHA-256 (captured bytes)")): \(sha256(data))",
        ]
        if captureWasTruncated {
            lines.append(captureTruncationNotice)
        }
        return lines.joined(separator: "\n")
    }

    private static func validUTF8Prefix(of data: Data, limit: Int) -> Data {
        var prefix = Data(data.prefix(limit))
        guard data.count > limit else {
            return prefix
        }
        for _ in 0 ..< 4 where String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
            prefix.removeLast()
        }
        return prefix
    }

    private static func isBinaryContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else {
            return false
        }
        if contentType.hasPrefix("text/")
            || contentType.contains("json")
            || contentType.contains("xml")
            || contentType.contains("javascript")
            || contentType.contains("x-www-form-urlencoded")
        {
            return false
        }
        return contentType.hasPrefix("image/")
            || contentType.hasPrefix("audio/")
            || contentType.hasPrefix("video/")
            || contentType.hasPrefix("font/")
            || contentType.contains("octet-stream")
            || contentType.contains("pdf")
            || contentType.contains("zip")
            || contentType.contains("gzip")
            || contentType.contains("protobuf")
    }

    private static func containsBinaryControlBytes(_ data: Data) -> Bool {
        for (index, byte) in data.enumerated() {
            if index.isMultiple(of: 64 * 1_024), Task.isCancelled {
                return false
            }
            if byte == 0 || byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                return true
            }
        }
        return false
    }
}
