import SwiftUI

// MARK: - DebugAssistantReviewDataSheet

/// Exact, read-only view of the redacted context pack shown before an outbound request.
/// Reads live review state from the coordinator so the one-time Focus/Noise override can
/// recompute the reviewed pack in place without dismissing and reopening the sheet.
struct DebugAssistantReviewDataSheet: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onSend: () -> Void
    let onDismiss: () -> Void
    let onOverride: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            actionBar
        }
        .font(toolMetrics.font())
        .frame(width: sheetWidth, height: sheetHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant Review Data"))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var workspace: WorkspaceState {
        coordinator.activeWorkspace
    }

    private var pack: InvestigationContextPack? {
        workspace.debugAssistantReviewPack
    }

    private var request: AssistantCompletionRequest? {
        workspace.debugAssistantReviewRequest
    }

    private var configuration: AssistantProviderConfiguration? {
        workspace.debugAssistantReviewConfiguration
    }

    private var trafficScope: AssistantTrafficScope {
        workspace.debugAssistantReviewTrafficScope ?? AssistantTrustPolicy.defaultTrafficScope
    }

    private var modelAccessEnabled: Bool {
        workspace.debugAssistantReviewModelAccessEnabled
    }

    private var reviewSummary: DebugAssistantReviewSummary {
        workspace.debugAssistantReviewSummary ?? DebugAssistantReviewSummary()
    }

    private var isPreparingOverride: Bool {
        workspace.isPreparingDebugAssistantReviewOverride
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var sheetWidth: CGFloat {
        max(760, toolMetrics.bodyFontSize * 16 + 520)
    }

    private var sheetHeight: CGFloat {
        max(620, toolMetrics.bodyFontSize * 8 + 500)
    }

    private var canSend: Bool {
        modelAccessEnabled && configuration?.isComplete == true && request != nil && !isPreparingOverride
    }

    private var isLocalExecution: Bool {
        configuration?.executionLocation.isLocal == true
    }

    private var contextPlan: AssistantContextPlan? {
        configuration.map { AssistantContextBudgeter().plan(for: $0) }
    }

    private var previewEditorSettings: InspectorTextEditorSettings {
        var settings = toolMetrics.codeEditorSettings
        settings.wordWrap = true
        return settings
    }

    private var showsScopeSummary: Bool {
        trafficScope == .selectedAndRelated && reviewSummary.rawRelatedFound > 0
    }

    private var headerSubtitle: String {
        if isLocalExecution {
            return String(localized: "Confirm the redacted traffic and conversation before local inference begins.")
        }
        return String(localized: "Confirm the exact redacted traffic before it leaves this Mac.")
    }

    private var primaryActionTitle: String {
        isLocalExecution ? String(localized: "Run Locally") : String(localized: "Send Redacted Data")
    }

    private var footerStatus: String {
        if isPreparingOverride {
            return String(localized: "Rebuilding the reviewed context with the excluded traffic")
        }
        if !modelAccessEnabled {
            return String(localized: "Model access is disabled in AI Assistant Settings")
        }
        if configuration?.isComplete != true {
            return String(localized: "Configure a provider and model in AI Assistant Settings")
        }
        if isLocalExecution {
            return String(localized: "Inference uses the configured local endpoint")
        }
        return String(localized: "Only reviewed content and required provider metadata will be sent")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isLocalExecution ? "lock.shield" : "arrow.up.forward.app")
                .font(.system(size: toolMetrics.compactIconFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Review Data"))
                    .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                Text(headerSubtitle)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    @ViewBuilder private var content: some View {
        if let pack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    destinationSection(pack)
                    if showsScopeSummary {
                        scopeSummarySection
                    }
                    redactionSection(pack)
                    previewSection(pack)
                }
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private var actionBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Label(footerStatus, systemImage: canSend ? "checkmark.shield" : "lock.shield")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button(String(localized: "Cancel"), action: onDismiss)
                .keyboardShortcut(.cancelAction)

            Button(primaryActionTitle, action: onSend)
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!canSend)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .frame(minHeight: toolMetrics.footerControlHeight + 20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scopeSummarySection: some View {
        reviewSection(String(localized: "Related Traffic Scope")) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                    GridRow {
                        manifestRow(
                            String(localized: "Related found"),
                            value: reviewSummary.rawRelatedFound,
                            systemImage: "magnifyingglass",
                            color: .secondary
                        )
                        manifestRow(
                            String(localized: "Included in review"),
                            value: reviewSummary.relatedIncluded,
                            systemImage: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                    GridRow {
                        manifestRow(
                            String(localized: "Normally excluded by Focus / Noise"),
                            value: reviewSummary.focusNoiseExcluded,
                            systemImage: "eye.slash",
                            color: reviewSummary.focusNoiseExcluded == 0 ? .secondary : .orange
                        )
                        Color.clear.frame(height: 0)
                    }
                }

                if reviewSummary.overrideApplied {
                    Label(
                        String(localized: "Focus and Noise were ignored once for this review."),
                        systemImage: "checkmark.circle"
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                } else if reviewSummary.canOverrideFocusNoise {
                    overrideControl
                }
            }
        }
    }

    private var overrideControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPreparingOverride {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Including excluded traffic…"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(String(localized: "Include Excluded Traffic Once"), action: onOverride)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Include Excluded Traffic Once"))
                    .help(String(localized: "Focus and Noise settings will not change."))
            }
            Text(
                String(
                    localized: "Adds the \(reviewSummary.focusNoiseExcluded) request(s) hidden by Focus or Noise to this review only. Your Focus and Noise settings will not change."
                )
            )
            .font(toolMetrics.metadataFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func destinationSection(_ pack: InvestigationContextPack) -> some View {
        reviewSection(String(localized: "Request Summary")) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), alignment: .topLeading),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(reviewDetails(pack)) { detail in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(detail.title)
                            .font(toolMetrics.metadataFont(weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(detail.value)
                            .font(toolMetrics.font())
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func redactionSection(_ pack: InvestigationContextPack) -> some View {
        reviewSection(String(localized: "Redaction Manifest")) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                GridRow {
                    manifestRow(
                        String(localized: "Sensitive fields redacted"),
                        value: pack.manifest.redactedFieldCount,
                        systemImage: "checkmark.shield.fill",
                        color: .green
                    )
                    manifestRow(
                        String(localized: "Payloads truncated"),
                        value: pack.manifest.truncatedBodyCount,
                        systemImage: "scissors",
                        color: pack.manifest.truncatedBodyCount == 0 ? .secondary : .orange
                    )
                }
                GridRow {
                    manifestRow(
                        String(localized: "Binary payloads omitted"),
                        value: pack.manifest.omittedBinaryBodyCount,
                        systemImage: "nosign",
                        color: pack.manifest.omittedBinaryBodyCount == 0 ? .secondary : .orange
                    )
                    manifestRow(
                        String(localized: "Requests outside the bound"),
                        value: pack.manifest.omittedTransactionCount,
                        systemImage: "square.stack.3d.down.right",
                        color: pack.manifest.omittedTransactionCount == 0 ? .secondary : .orange
                    )
                }
            }
        }
    }

    private func previewSection(_ pack: InvestigationContextPack) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(localized: "Exact Reviewed Content"))
                    .font(toolMetrics.font(weight: .semibold))
                Spacer()
                let totalRequestCount = pack.manifest.requestCount + pack.manifest.omittedTransactionCount
                Text(
                    pack.manifest.omittedTransactionCount == 0
                        ? String(localized: "\(pack.manifest.requestCount) requests")
                        : String(localized: "\(pack.manifest.requestCount) of \(totalRequestCount) requests")
                )
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
            }

            InspectorBodyTextEditor(
                text: request?.reviewedContentPreview ?? pack.preview,
                editorID: "debug-assistant-review-\((request?.reviewedContentPreview ?? pack.preview).hashValue)",
                editorSettings: previewEditorSettings,
                isEditable: false
            )
            .frame(minHeight: 210, idealHeight: 260)
            .overlay {
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private func reviewSection(
        _ title: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(toolMetrics.font(weight: .semibold))

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manifestRow(
        _ title: String,
        value: Int,
        systemImage: String,
        color: Color
    )
        -> some View
    {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
                .font(toolMetrics.secondaryFont())
            Spacer(minLength: 8)
            Text(value.formatted())
                .font(toolMetrics.secondaryFont())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scopeDescription(_ pack: InvestigationContextPack) -> String {
        let totalRequestCount = pack.manifest.requestCount + pack.manifest.omittedTransactionCount
        let countDescription = pack.manifest.omittedTransactionCount == 0
            ? pack.manifest.requestCount.formatted()
            : String(localized: "\(pack.manifest.requestCount) of \(totalRequestCount)")
        return switch trafficScope {
        case .selectedOnly:
            String(localized: "\(countDescription) selected request(s)")
        case .selectedAndRelated:
            String(localized: "\(countDescription) selected and opted-in related request(s)")
        }
    }

    private func reviewDetails(_ pack: InvestigationContextPack) -> [ReviewDetail] {
        var details = [
            ReviewDetail(
                title: String(localized: "Provider"),
                value: configuration?.kind.title ?? String(localized: "Not configured")
            ),
            ReviewDetail(
                title: String(localized: "Model"),
                value: configuration?.model ?? "—"
            ),
            ReviewDetail(
                title: String(localized: "Destination"),
                value: configuration?.baseURL ?? String(localized: "No outbound request")
            ),
            ReviewDetail(
                title: String(localized: "Scope"),
                value: scopeDescription(pack)
            ),
            ReviewDetail(
                title: String(localized: "Redaction"),
                value: configuration?.redactSensitiveData == true
                    ? String(localized: "Enabled")
                    : String(localized: "Unavailable")
            ),
            ReviewDetail(
                title: String(localized: "Access"),
                value: String(localized: "Read-only analysis")
            ),
            ReviewDetail(
                title: String(localized: "Reviewed Content Size"),
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(request?.reviewedContentBytes ?? pack.manifest.outboundBytes),
                    countStyle: .file
                )
            ),
        ]
        if let contextWindow = contextPlan?.contextWindowTokens {
            details.append(ReviewDetail(
                title: String(localized: "Context Window"),
                value: String(localized: "\(contextWindow.formatted()) tokens")
            ))
        }
        if let outputLimit = contextPlan?.maxOutputTokens {
            details.append(ReviewDetail(
                title: String(localized: "Output Limit"),
                value: String(localized: "\(outputLimit.formatted()) tokens")
            ))
        }
        if !isLocalExecution {
            details.append(ReviewDetail(
                title: String(localized: "Provider Storage"),
                value: configuration?.storeResponses == true
                    ? String(localized: "Allowed")
                    : String(localized: "Disabled where supported")
            ))
        }
        if let region = configuration?.region, !region.isEmpty {
            details.append(ReviewDetail(
                title: String(localized: "Platform / Region"),
                value: region
            ))
        }
        return details
    }
}

// MARK: - ReviewDetail

private struct ReviewDetail: Identifiable {
    let title: String
    let value: String

    var id: String {
        title
    }
}
