import SwiftUI

// MARK: - AIInspectorView

/// Native response-inspector tab for captured AI model traffic.
///
/// The view renders from a bounded detector snapshot so switching selected transactions
/// cannot leave stale parser output in the inspector.
struct AIInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let inspection {
                VStack(spacing: 0) {
                    summaryStrip(inspection)
                    Divider()
                    if inspection.kind == .session {
                        sessionPane(inspection)
                    } else {
                        HSplitView {
                            eventList(inspection)
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                            detailPane(inspection)
                                .frame(minWidth: 280, maxWidth: .infinity)
                        }
                    }
                }
            } else {
                InspectorEmptyStateView(
                    String(localized: "No AI Metadata", bundle: RockxyLocalization.bundle),
                    systemImage: "sparkles",
                    description: String(
                        localized: "This response does not look like captured AI model traffic.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
        .task(id: transaction.id) {
            await loadInspection()
        }
    }

    // MARK: Private

    @State private var inspection: AIInspection?
    @State private var selectedEventID: String?
    @State private var filter: AIInspectorEventFilter = .all
    @State private var isLoading = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var selectedEvent: AIEventSummary? {
        guard let inspection else {
            return nil
        }
        if let selectedEventID,
           let event = inspection.events.first(where: { $0.id == selectedEventID })
        {
            return event
        }
        return inspection.events.first
    }

    private var sessionTransportLabel: String {
        if transaction.webSocketConnection != nil || transaction.request.url.scheme?.lowercased() == "wss" {
            return String(localized: "WebSocket / TLS", bundle: RockxyLocalization.bundle)
        }
        if transaction.request.method.caseInsensitiveCompare("CONNECT") == .orderedSame {
            return String(localized: "CONNECT / TLS", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "HTTPS / TLS", bundle: RockxyLocalization.bundle)
    }

    @ViewBuilder private var selectedEventSection: some View {
        if let selectedEvent {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(String(localized: "Selected Event", bundle: RockxyLocalization.bundle))
                Text(selectedEvent.detail)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func summaryStrip(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                badge(inspection.kind.displayName, color: inspection.kind == .session ? .teal : .accentColor)
                if inspection.kind == .session {
                    badge(String(localized: "TLS only", bundle: RockxyLocalization.bundle), color: .orange)
                } else if inspection.isStreaming {
                    badge(String(localized: "Stream", bundle: RockxyLocalization.bundle), color: .blue)
                }
                if !inspection.toolCalls.isEmpty {
                    badge(String(localized: "Tool", bundle: RockxyLocalization.bundle), color: .orange)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 18) {
                summaryItem(
                    String(localized: "Provider", bundle: RockxyLocalization.bundle),
                    value: inspection.provider.displayName
                )
                summaryItem(
                    String(localized: "Model", bundle: RockxyLocalization.bundle),
                    value: inspection.model ?? String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
                )
                summaryItem(
                    String(localized: "Finish", bundle: RockxyLocalization.bundle),
                    value: finishLabel(for: inspection)
                )
                summaryItem(
                    String(localized: "Evidence", bundle: RockxyLocalization.bundle),
                    value: evidenceLabel(for: inspection)
                )
            }

            Text(unavailableSummary(for: inspection))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

    private func sessionPane(_ inspection: AIInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Captured app session", bundle: RockxyLocalization.bundle))
                            .font(.system(size: metrics.primaryFontSize, weight: .semibold))
                        metadataPair(
                            String(localized: "App", bundle: RockxyLocalization.bundle),
                            value: transaction.clientApp ?? String(
                                localized: "Unknown",
                                bundle: RockxyLocalization.bundle
                            )
                        )
                        metadataPair(
                            String(localized: "Host", bundle: RockxyLocalization.bundle),
                            value: transaction.request.host
                        )
                        metadataPair(
                            String(localized: "Transport", bundle: RockxyLocalization.bundle),
                            value: sessionTransportLabel
                        )
                    }
                }

                warningCard(
                    title: String(localized: "Body unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Rockxy can identify this AI app session, but model, tokens, and tools need decrypted API evidence.",
                        bundle: RockxyLocalization.bundle
                    ),
                    color: .orange
                )

                sectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(String(localized: "Suggested Check", bundle: RockxyLocalization.bundle))
                        Text(String(
                            localized: "Open SSL Proxying for this host or capture SDK traffic with HTTPS_PROXY when debugging local apps.",
                            bundle: RockxyLocalization.bundle
                        ))
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func eventList(_ inspection: AIInspection) -> some View {
        VStack(spacing: 0) {
            Picker(selection: $filter) {
                Text(String(localized: "All", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.all)
                Text(String(localized: "Stream", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.stream)
                Text(String(localized: "Tools", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.tools)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            let events = filteredEvents(inspection.events)
            if events.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "No Events", bundle: RockxyLocalization.bundle),
                    systemImage: "list.bullet",
                    description: String(
                        localized: "No captured events match this filter.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } else {
                List(events, selection: $selectedEventID) { event in
                    eventRow(event)
                        .tag(event.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func eventRow(_ event: AIEventSummary) -> some View {
        HStack(spacing: 6) {
            severityDot(event.severity)
            Text(event.title)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(event.offsetLabel)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(event.severity == .error ? .red : .secondary)
                .lineLimit(1)
        }
    }

    private func severityDot(_ severity: AIEventSeverity) -> some View {
        Circle()
            .fill(severity == .error ? Color.red : Color.accentColor)
            .frame(width: 7, height: 7)
    }

    private func detailPane(_ inspection: AIInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                debugFocusSection(inspection)
                timingSection(inspection)
                usageSection(inspection)
                toolChainSection(inspection)
                retrievalSection(inspection)
                warningSection(inspection)
                selectedEventSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugFocusSection(_ inspection: AIInspection) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sectionHeader(String(localized: "Debug Focus", bundle: RockxyLocalization.bundle))
                    badge(aiDebugFocusLabel(inspection), color: aiDebugFocusColor(inspection))
                    Spacer(minLength: 0)
                }
                metadataPair(
                    String(localized: "Outcome", bundle: RockxyLocalization.bundle),
                    value: aiDebugOutcome(inspection)
                )
                metadataPair(
                    String(localized: "Next Check", bundle: RockxyLocalization.bundle),
                    value: aiDebugNextCheck(inspection)
                )
            }
        }
    }

    private func timingSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Timing and Stream", bundle: RockxyLocalization.bundle))
            HStack(spacing: 14) {
                metadataPair(
                    String(localized: "Duration", bundle: RockxyLocalization.bundle),
                    value: durationLabel(inspection.duration)
                )
                metadataPair(
                    String(localized: "Streaming", bundle: RockxyLocalization.bundle),
                    value: inspection
                        .isStreaming ? String(localized: "Yes", bundle: RockxyLocalization.bundle) : String(
                            localized: "No",
                            bundle: RockxyLocalization.bundle
                        )
                )
                metadataPair(
                    String(localized: "Events", bundle: RockxyLocalization.bundle),
                    value: "\(inspection.events.count)"
                )
            }
            streamBars(inspection.events)
            Text(String(
                localized: "SSE cadence is shown from captured events. Token boundaries stay unavailable unless the provider exposes them.",
                bundle: RockxyLocalization.bundle
            ))
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(.secondary)
        }
    }

    private func streamBars(_ events: [AIEventSummary]) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(events.prefix(18).enumerated()), id: \.element.id) { index, event in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(event.category == .tool ? Color.orange : Color.accentColor)
                    .frame(width: 8, height: CGFloat(10 + ((index * 7) % 24)))
                    .help(event.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 48, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
    }

    private func usageSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Usage", bundle: RockxyLocalization.bundle))
            if let usage = inspection.usage {
                HStack(spacing: 16) {
                    metadataPair(
                        String(localized: "Input", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.inputTokens)
                    )
                    metadataPair(
                        String(localized: "Cached", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.cachedTokens)
                    )
                    metadataPair(
                        String(localized: "Output", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.outputTokens)
                    )
                    metadataPair(
                        String(localized: "Total", bundle: RockxyLocalization.bundle),
                        value: "\(usage.totalTokens)"
                    )
                }
                tokenBar(usage)
            } else {
                unavailableText(String(
                    localized: "Usage fields were not present in the captured provider response.",
                    bundle: RockxyLocalization.bundle
                ))
            }
        }
    }

    private func tokenBar(_ usage: AIUsage) -> some View {
        GeometryReader { proxy in
            let input = CGFloat(usage.inputTokens ?? 0)
            let cached = CGFloat(usage.cachedTokens ?? 0)
            let output = CGFloat(usage.outputTokens ?? 0)
            let total = max(CGFloat(usage.totalTokens), 1)
            let width = proxy.size.width

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: width * input / total)
                Rectangle()
                    .fill(Color.blue.opacity(0.65))
                    .frame(width: width * cached / total)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: width * output / total)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }

    private func toolChainSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Tool Chain", bundle: RockxyLocalization.bundle))
            if inspection.toolCalls.isEmpty {
                unavailableText(String(
                    localized: "No tool-call payloads were visible in the captured traffic.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                ForEach(Array(inspection.toolCalls.enumerated()), id: \.offset) { index, tool in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: metrics.metadataFontSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(tool.name)
                            .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                        Spacer()
                        Text(tool.state.displayName)
                            .font(.system(size: metrics.metadataFontSize))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
    }

    private func retrievalSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Retrieval", bundle: RockxyLocalization.bundle))
            if inspection.retrieval.isEmpty {
                unavailableText(String(
                    localized: "No retrieval or embedding result was visible for this selected transaction.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                ForEach(Array(inspection.retrieval.enumerated()), id: \.offset) { _, match in
                    HStack {
                        Text(match.source)
                            .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                        Spacer()
                        Text(scoreLabel(match.score))
                            .foregroundStyle(.secondary)
                        Text(match.risk)
                            .foregroundStyle(match.risk.contains("sensitive") ? .red : .secondary)
                    }
                    .font(.system(size: metrics.metadataFontSize))
                    Divider()
                }
            }
        }
    }

    private func warningSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Warnings", bundle: RockxyLocalization.bundle))
            if inspection.warnings.isEmpty {
                unavailableText(String(
                    localized: "No AI-specific warning was detected from visible traffic fields.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                ForEach(Array(inspection.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(
                        warning.message,
                        systemImage: warning.severity == .error ? "exclamationmark.triangle" : "lock.shield"
                    )
                    .font(.system(size: metrics.metadataFontSize, weight: .medium))
                    .foregroundStyle(warning.severity == .error ? .red : .orange)
                }
            }
        }
    }

    private func warningCard(title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
            Text(message)
                .font(.system(size: metrics.metadataFontSize))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func sectionCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: metrics.badgeFontSize))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
        }
    }

    private func metadataPair(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func unavailableText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(.secondary)
    }

    private func loadInspection() async {
        isLoading = true
        let snapshot = AITrafficSnapshot(transaction: transaction)
        let transactionID = transaction.id
        let detected = await Task.detached(priority: .userInitiated) {
            AITrafficDetector.detect(snapshot: snapshot)
        }.value

        guard transaction.id == transactionID else {
            return
        }
        inspection = detected
        selectedEventID = detected?.events.first?.id
        isLoading = false
    }

    private func filteredEvents(_ events: [AIEventSummary]) -> [AIEventSummary] {
        switch filter {
        case .all:
            events
        case .stream:
            events.filter { $0.category == .stream }
        case .tools:
            events.filter { $0.category == .tool }
        }
    }

    private func aiDebugFocusLabel(_ inspection: AIInspection) -> String {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return String(localized: "Provider Error", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming, !inspection.toolCalls.isEmpty {
            return String(localized: "Streaming Tool", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming {
            return String(localized: "Streaming", bundle: RockxyLocalization.bundle)
        }
        if !inspection.toolCalls.isEmpty {
            return String(localized: "Tool Call", bundle: RockxyLocalization.bundle)
        }
        if !inspection.retrieval.isEmpty {
            return String(localized: "Retrieval", bundle: RockxyLocalization.bundle)
        }
        if inspection.usage == nil {
            return String(localized: "Metadata Sparse", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Completion", bundle: RockxyLocalization.bundle)
    }

    private func aiDebugFocusColor(_ inspection: AIInspection) -> Color {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return .red
        }
        if !inspection.toolCalls.isEmpty {
            return .orange
        }
        if inspection.isStreaming {
            return .blue
        }
        if !inspection.retrieval.isEmpty {
            return .green
        }
        return .secondary
    }

    private func aiDebugOutcome(_ inspection: AIInspection) -> String {
        if let warning = inspection.warnings.first(where: { $0.severity == .error }) {
            return warning.message
        }
        if let statusCode = transaction.response?.statusCode,
           statusCode >= 400
        {
            return String(localized: "HTTP \(statusCode) from provider", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming {
            return String(
                localized: "\(inspection.events.count) captured stream events, finish \(finishLabel(for: inspection))",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Finish \(finishLabel(for: inspection))", bundle: RockxyLocalization.bundle)
    }

    private func aiDebugNextCheck(_ inspection: AIInspection) -> String {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return String(
                localized: "Check provider error body, request id, auth, rate-limit headers, and retry timing.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.isStreaming, !inspection.toolCalls.isEmpty {
            return String(
                localized: "Filter Tools and verify partial arguments, final tool call state, and stream completion.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.isStreaming {
            return String(
                localized: "Check event count, final event, interruption signs, and first-token/overall duration.",
                bundle: RockxyLocalization.bundle
            )
        }
        if !inspection.toolCalls.isEmpty {
            return String(
                localized: "Verify declared tool name, arguments, completion state, and app-side tool result follow-up.",
                bundle: RockxyLocalization.bundle
            )
        }
        if !inspection.retrieval.isEmpty {
            return String(
                localized: "Review retrieved sources, score, and sensitive-data risk before sharing traces.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.usage == nil {
            return String(
                localized: "Confirm provider adapter, response body visibility, and whether usage is omitted by this endpoint.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Compare model, tokens, finish reason, and latency against adjacent retries.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        duration.map { DurationFormatter.format(seconds: $0) } ?? String(
            localized: "Unavailable",
            bundle: RockxyLocalization.bundle
        )
    }

    private func tokenLabel(_ value: Int?) -> String {
        value.map(String.init) ?? String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
    }

    private func scoreLabel(_ score: Double?) -> String {
        guard let score else {
            return String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
        }
        return String(format: "%.2f", score)
    }

    private func finishLabel(for inspection: AIInspection) -> String {
        if inspection.events.contains(where: { $0.title.lowercased().contains("completed") }) {
            return String(localized: "completed", bundle: RockxyLocalization.bundle)
        }
        if let status = inspection.httpStatusCode, status >= 400 {
            return "HTTP \(status)"
        }
        return String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
    }

    private func confidenceLabel(for inspection: AIInspection) -> String {
        inspection.events.contains(where: { $0.category == .stream || $0.category == .tool })
            ? String(localized: "observed + derived", bundle: RockxyLocalization.bundle)
            : String(localized: "observed", bundle: RockxyLocalization.bundle)
    }

    private func evidenceLabel(for inspection: AIInspection) -> String {
        if inspection.evidence.isEmpty {
            return confidenceLabel(for: inspection)
        }
        return inspection.evidence.joined(separator: ", ")
    }

    private func unavailableSummary(for inspection: AIInspection) -> String {
        if inspection.unavailableFields.isEmpty {
            return String(
                localized: "All displayed values come from visible captured traffic.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Unavailable: \(inspection.unavailableFields.joined(separator: ", ")). Missing fields are not inferred.",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - AIInspectorEventFilter

private enum AIInspectorEventFilter: Hashable {
    case all
    case stream
    case tools
}

private extension AITrafficSignalKind {
    var displayName: String {
        switch self {
        case .api:
            String(localized: "AI API", bundle: RockxyLocalization.bundle)
        case .session:
            String(localized: "AI Session", bundle: RockxyLocalization.bundle)
        case .heuristic:
            String(localized: "Likely AI", bundle: RockxyLocalization.bundle)
        case .none:
            String(localized: "AI", bundle: RockxyLocalization.bundle)
        }
    }
}
