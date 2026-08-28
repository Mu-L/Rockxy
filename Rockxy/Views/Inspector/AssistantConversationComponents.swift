import AppKit
import SwiftUI

// MARK: - AssistantClipboard

enum AssistantClipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - AssistantResponseContainer

/// The shared assistant-turn wrapper: one coherent neutral rounded response component. It provides a
/// subtle background, a hairline separator border, and compact padding so every assistant payload
/// reads as a single self-contained response — never an assistant logo, icon, or identity row.
struct AssistantResponseContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - AssistantProgressRow

struct AssistantProgressRow: View {
    // MARK: Internal

    let title: String
    var systemImage: String?
    var color = Color.secondary
    var showsProgress = false

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
            Spacer(minLength: 0)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantConversationContextMismatchBanner

struct AssistantConversationContextMismatchBanner: View {
    // MARK: Internal

    let context: DebugAssistantConversationContext?
    let onRestore: () -> Void
    let onStartNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                String(localized: "This conversation belongs to different traffic", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.trianglehead.branch"
            )
            .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
            .foregroundStyle(.orange)

            if let context {
                Text(
                    String(
                        localized: "It was started with \(context.summary). Restore that selection or start a clean conversation for the traffic shown above.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Button(String(localized: "Restore Traffic", bundle: RockxyLocalization.bundle), action: onRestore)
                    .rockxyGlassButtonStyle()
                    .controlSize(.small)

                Button(String(localized: "New Conversation", bundle: RockxyLocalization.bundle), action: onStartNew)
                    .rockxyGlassButtonStyle(prominent: true)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Conversation traffic changed", bundle: RockxyLocalization.bundle))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantUserMessageBubble

/// A user prompt rendered as a compact, right-aligned chat bubble — the request side of the
/// conversation. Native control colors and a constrained width keep it visually distinct from the
/// assistant's full-width rounded response container while staying dense enough for the inspector column.
struct AssistantUserMessageBubble: View {
    // MARK: Internal

    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 44)
            Text(text)
                .font(.system(size: metrics.primaryFontSize))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "You: \(text)", bundle: RockxyLocalization.bundle))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantResponseActionBar

/// The generic assistant-response footer: at most two quiet affordances — a standard Copy control
/// and one ellipsis overflow menu. No workflow button ever appears in the response body; follow-up,
/// reveal, retry, and any caller-supplied handoffs live only inside the overflow menu, revealed on
/// intent. Each control keeps an accessibility label and help for discoverability.
struct AssistantResponseActionBar<OverflowItems: View>: View {
    // MARK: Internal

    let canCopy: Bool
    let canRevealRequest: Bool
    let canRetry: Bool
    let onCopy: () -> Void
    let onFollowUp: () -> Void
    let onRevealRequest: () -> Void
    let onRetry: () -> Void
    @ViewBuilder let overflowItems: OverflowItems

    var body: some View {
        HStack(spacing: 12) {
            compactAction(
                String(localized: "Copy", bundle: RockxyLocalization.bundle),
                systemImage: "doc.on.doc",
                action: onCopy
            )
            .disabled(!canCopy)
            overflowMenu
            Spacer(minLength: 0)
        }
        .font(.system(size: metrics.metadataFontSize))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var overflowMenu: some View {
        Menu {
            overflowItems
            Button(action: onFollowUp) {
                Label(
                    String(localized: "Follow Up", bundle: RockxyLocalization.bundle),
                    systemImage: "arrowshape.turn.up.left"
                )
            }
            if canRevealRequest {
                Button(action: onRevealRequest) {
                    Label(String(localized: "Reveal Request", bundle: RockxyLocalization.bundle), systemImage: "scope")
                }
            }
            if canRetry {
                Button(action: onRetry) {
                    Label(
                        String(localized: "Review & Retry", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: metrics.controlFontSize))
                .frame(minWidth: 18, minHeight: 18)
        }
        .font(.system(size: metrics.controlFontSize))
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(localized: "More actions", bundle: RockxyLocalization.bundle))
        .help(String(localized: "More actions", bundle: RockxyLocalization.bundle))
    }

    private func compactAction(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: 18, minHeight: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
        .accessibilityLabel(title)
        .help(title)
    }
}

extension AssistantResponseActionBar where OverflowItems == EmptyView {
    init(
        canCopy: Bool,
        canRevealRequest: Bool,
        canRetry: Bool,
        onCopy: @escaping () -> Void,
        onFollowUp: @escaping () -> Void,
        onRevealRequest: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.init(
            canCopy: canCopy,
            canRevealRequest: canRevealRequest,
            canRetry: canRetry,
            onCopy: onCopy,
            onFollowUp: onFollowUp,
            onRevealRequest: onRevealRequest,
            onRetry: onRetry,
            overflowItems: { EmptyView() }
        )
    }
}

// MARK: - AssistantMarkdownText

/// Renders common model Markdown as native SwiftUI text without exposing formatting markers.
/// Block parsing runs away from the main actor and is retained by the view's stable message identity.
struct AssistantMarkdownText: View {
    // MARK: Internal

    let source: String

    var body: some View {
        Group {
            if let document {
                AssistantMarkdownDocumentView(document: document)
            } else {
                Text(AssistantMarkdownInlineRenderer.render(source))
                    .font(.system(size: metrics.primaryFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .task(id: source) {
            let parsed = await Task.detached(priority: .utility) {
                AssistantMarkdownDocumentParser.parse(source)
            }.value
            guard !Task.isCancelled else {
                return
            }
            document = parsed
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var document: AssistantMarkdownDocument?
}

// MARK: - AssistantStreamingText

/// Streaming output deliberately stays plain and cheap. Completed messages are parsed into
/// native Markdown once, after the provider finishes.
struct AssistantStreamingText: View {
    // MARK: Internal

    let source: String

    var body: some View {
        Text(source)
            .font(.system(size: metrics.primaryFontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantMarkdownDocument

struct AssistantMarkdownDocument: Equatable, Sendable {
    let blocks: [AssistantMarkdownBlock]
}

// MARK: - AssistantMarkdownBlock

enum AssistantMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([AssistantMarkdownListItem])
    case code(language: String?, text: String)
    case quote(String)
    case separator
}

// MARK: - AssistantMarkdownListItem

struct AssistantMarkdownListItem: Equatable, Sendable {
    let number: Int
    let text: String
}

// MARK: - AssistantMarkdownDocumentParser

enum AssistantMarkdownDocumentParser {
    // MARK: Internal

    static func parse(_ source: String) -> AssistantMarkdownDocument {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [AssistantMarkdownBlock] = []
        var paragraph: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [AssistantMarkdownListItem] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else {
                return
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else {
                return
            }
            blocks.append(.unorderedList(unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else {
                return
            }
            blocks.append(.orderedList(orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else {
                return
            }
            blocks.append(.quote(quoteLines.joined(separator: "\n")))
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushTextBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isInsideCodeBlock {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(
                        language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                        text: codeLines.joined(separator: "\n")
                    ))
                    codeLines.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                    isInsideCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushTextBlocks()
                codeLanguage = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isInsideCodeBlock = true
                continue
            }

            if trimmed.isEmpty {
                flushTextBlocks()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushTextBlocks()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if isSeparator(trimmed) {
                flushTextBlocks()
                blocks.append(.separator)
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                unorderedItems.append(item)
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushQuote()
                orderedItems.append(item)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(
                    String(trimmed.dropFirst())
                        .trimmingCharacters(in: .whitespaces)
                )
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            flushQuote()
            paragraph.append(line)
        }

        if isInsideCodeBlock {
            blocks.append(.code(
                language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                text: codeLines.joined(separator: "\n")
            ))
        }
        flushTextBlocks()
        return AssistantMarkdownDocument(blocks: blocks)
    }

    // MARK: Private

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(markerCount),
              line.dropFirst(markerCount).first == " " else
        {
            return nil
        }
        return (
            markerCount,
            String(line.dropFirst(markerCount + 1))
        )
    }

    private static func unorderedItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> AssistantMarkdownListItem? {
        guard let period = line.firstIndex(of: "."),
              period != line.startIndex,
              line.index(after: period) < line.endIndex,
              line[line.index(after: period)] == " ",
              let number = Int(line[..<period]) else
        {
            return nil
        }
        return AssistantMarkdownListItem(
            number: number,
            text: String(line[line.index(period, offsetBy: 2)...])
        )
    }

    private static func isSeparator(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else {
            return false
        }
        return ["-", "*", "_"].contains(String(marker))
            && compact.allSatisfy { $0 == marker }
    }
}

// MARK: - AssistantMarkdownDocumentView

private struct AssistantMarkdownDocumentView: View {
    // MARK: Internal

    let document: AssistantMarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(AssistantMarkdownInlineRenderer.render(text))
                .font(.system(size: headingFontSize(level), weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 2 : 0)
        case let .paragraph(text):
            Text(AssistantMarkdownInlineRenderer.render(text))
                .font(.system(size: metrics.primaryFontSize))
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(AssistantMarkdownInlineRenderer.render(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: metrics.primaryFontSize))
            .padding(.leading, 4)
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(item.number).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(AssistantMarkdownInlineRenderer.render(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: metrics.primaryFontSize))
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 5) {
                if let language {
                    Text(language)
                        .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text)
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 2)
                Text(AssistantMarkdownInlineRenderer.render(text))
                    .font(.system(size: metrics.primaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .separator:
            Divider()
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            metrics.primaryFontSize + 2
        case 2:
            metrics.primaryFontSize + 1
        default:
            metrics.primaryFontSize
        }
    }
}

// MARK: - AssistantMarkdownInlineRenderer

enum AssistantMarkdownInlineRenderer {
    static func render(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }
}
