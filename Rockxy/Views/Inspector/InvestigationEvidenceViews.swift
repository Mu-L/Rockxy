import SwiftUI

// MARK: - InvestigationEvidenceGroupView

/// Dense native rendering of one evidence kind ("Observed", "Derived", "Inferred") in the
/// Investigate dock. Grouping is computed by `InvestigationResultPresentation`; this view only
/// lays the rows out.
struct InvestigationEvidenceGroupView: View {
    // MARK: Internal

    let group: InvestigationEvidenceGroup
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.kind.title)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(group.evidence) { evidence in
                InvestigationEvidenceRow(evidence: evidence, onReveal: onReveal)
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InvestigationUnknownsView

/// Open questions the local investigation could not resolve from captured traffic alone. Rendered
/// only when unknowns exist — the answer-first report never shows an empty "no open questions" state.
struct InvestigationUnknownsView: View {
    // MARK: Internal

    let unknowns: [InvestigationEvidence]
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        if !unknowns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Unknowns", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                ForEach(unknowns) { evidence in
                    InvestigationEvidenceRow(evidence: evidence, onReveal: onReveal)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InvestigationEvidenceRow

/// A single finding row, rendered as plain text. When it is backed by a captured request, tapping
/// reveals that request; the row carries no colored dot or trailing scope glyph — the disabled state
/// and help text convey whether it can navigate.
struct InvestigationEvidenceRow: View {
    // MARK: Internal

    let evidence: InvestigationEvidence
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        Button {
            onReveal(evidence)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(evidence.title)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !evidence.detail.isEmpty {
                    Text(evidence.detail)
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(evidence.sourceTransactionID == nil)
        .help(evidence.sourceTransactionID == nil
            ? evidence.detail
            : String(localized: "Reveal the request behind this finding", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(
            localized: "\(evidence.kind.title) finding: \(evidence.title)",
            bundle: RockxyLocalization.bundle
        ))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InvestigationReportSection

/// A text-only section for the collapsed evidence disclosure — a restrained secondary title above
/// its content, with no SF Symbol. Keeps every technical label consistent and readable at large
/// fonts without web-style dashboard chrome.
struct InvestigationReportSection<Content: View>: View {
    // MARK: Internal

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InvestigationSectionFrame

/// A small, text-only bounded section frame used for the visible "Summary" and "Next step" blocks
/// of an investigation turn. It renders a bold text title above its content inside the shared
/// restrained frame chrome (`investigationSectionFrameStyle`) — no icon, badge, tint, shadow,
/// material, status color, action, or decorative header. Editorial grouping only.
struct InvestigationSectionFrame<Content: View>: View {
    // MARK: Internal

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
            content
        }
        .investigationSectionFrameStyle()
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

private extension View {
    /// Restrained bounded frame shared by the Summary / Next step / Details sections: compact
    /// padding, a small rounded rectangle, and a 0.5 separator-color hairline over a clear
    /// background. No fill tint, icon, shadow, or material — the frame is purely editorial grouping.
    func investigationSectionFrameStyle() -> some View {
        padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

// MARK: - InvestigationReportView

/// A completed investigation turn, rendered with editorial typography: a bold text-only "Summary"
/// heading above the answer, a "Next step" heading above `result.nextStep` when nonempty, then all
/// technical evidence collapsed behind one quiet "Details" disclosure. No workflow button appears in the response body
/// — every
/// handoff, model escalation, follow-up, reveal, and retry is preserved inside the footer's single
/// ellipsis overflow menu next to a standard Copy control. Evidence-level reveal and every workflow
/// callback are injected as closures so this stays a pure presentation surface.
struct InvestigationReportView: View {
    // MARK: Internal

    let message: DebugAssistantMessage
    let isCurrentResult: Bool
    let showsContinueWithModel: Bool
    let isPreparingReview: Bool
    let canRevealRequest: Bool
    let canRetry: Bool
    let onReveal: (InvestigationEvidence) -> Void
    let onContinueWithModel: () -> Void
    let onHandoff: (AssistantUserHandoff, InvestigationResult) -> Void
    let onPrepareReplay: (InvestigationResult) -> Void
    let onCopy: () -> Void
    let onFollowUp: () -> Void
    let onRevealRequest: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if let result = message.investigation {
            VStack(alignment: .leading, spacing: 10) {
                answer(result)
                nextStep(result)
                evidenceDisclosure(result)
                if isPreparingReview {
                    preparingReviewRow
                }
                responseFooter(result)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Investigation answer", bundle: RockxyLocalization.bundle))
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var isEvidenceExpanded = false

    private var preparingReviewRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Preparing redacted preview…", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
        }
    }

    private func answer(_ result: InvestigationResult) -> some View {
        InvestigationSectionFrame(title: String(localized: "Summary", bundle: RockxyLocalization.bundle)) {
            if usesModelAnswer(result) {
                AssistantMarkdownText(source: message.text)
            } else {
                Text(result.summary)
                    .font(.system(size: metrics.primaryFontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(String(
                        localized: "Answer: \(result.summary)",
                        bundle: RockxyLocalization.bundle
                    ))
            }
        }
    }

    @ViewBuilder
    private func nextStep(_ result: InvestigationResult) -> some View {
        if !result.nextStep.isEmpty {
            InvestigationSectionFrame(title: String(localized: "Next step", bundle: RockxyLocalization.bundle)) {
                Text(result.nextStep)
                    .font(.system(size: metrics.primaryFontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func evidenceDisclosure(_ result: InvestigationResult) -> some View {
        let unknowns = InvestigationResultPresentation.unknowns(for: result.evidence)
        return DisclosureGroup(isExpanded: $isEvidenceExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                scopeSection(result)
                    .padding(.vertical, 8)

                Divider()

                findingsSection(result)
                    .padding(.vertical, 8)

                if !unknowns.isEmpty {
                    Divider()
                    InvestigationUnknownsView(unknowns: unknowns, onReveal: onReveal)
                        .padding(.vertical, 8)
                }

                Divider()

                attributionLabel(result)
                    .padding(.vertical, 8)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(String(localized: "Details", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .investigationSectionFrameStyle()
    }

    private func scopeSection(_ result: InvestigationResult) -> some View {
        InvestigationReportSection(title: String(localized: "Scope", bundle: RockxyLocalization.bundle)) {
            Text(result.scopeSummary)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(
                    localized: "Investigation scope: \(result.scopeSummary)",
                    bundle: RockxyLocalization.bundle
                ))
        }
    }

    @ViewBuilder
    private func findingsSection(_ result: InvestigationResult) -> some View {
        let findingGroups = InvestigationResultPresentation.findingGroups(for: result.evidence)
        InvestigationReportSection(title: String(localized: "Findings", bundle: RockxyLocalization.bundle)) {
            if findingGroups.isEmpty {
                Text(String(
                    localized: "No concrete findings from the captured traffic.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(findingGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Divider()
                        }
                        InvestigationEvidenceGroupView(group: group, onReveal: onReveal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attributionLabel(_ result: InvestigationResult) -> some View {
        if let modelResult = message.modelResult {
            modelAttributionLabel(modelResult, requestCount: result.scopeTransactionIDs.count)
        } else {
            let text = String(
                localized: "Local analysis · \(result.scopeTransactionIDs.count) requests",
                bundle: RockxyLocalization.bundle
            )
            Text(text)
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .accessibilityLabel(text)
        }
    }

    /// Exact model provenance for an investigation answer, kept inside the collapsed "Details"
    /// disclosure instead of a second always-visible report section: provider, model, and scoped
    /// request count in a plain text label (no decorative icon), with endpoint host and token usage
    /// tucked into a quiet native menu so the surface stays a single restrained line.
    private func modelAttributionLabel(
        _ modelResult: ModelInvestigationResult,
        requestCount: Int
    )
        -> some View
    {
        let summary = String(
            localized: "\(modelResult.provider.title) · \(modelResult.model) · \(requestCount) requests",
            bundle: RockxyLocalization.bundle
        )
        return Menu {
            Button(modelResult.endpointHost) {}
                .disabled(true)
            if let usage = modelResult.usage {
                Divider()
                Button(String(
                    localized: "\(usage.inputTokens) input · \(usage.outputTokens) output tokens",
                    bundle: RockxyLocalization.bundle
                )) {}
                    .disabled(true)
            }
        } label: {
            Text(summary)
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.mini)
        .help("\(modelResult.provider.title) · \(modelResult.model) · \(modelResult.endpointHost)")
        .accessibilityLabel(summary)
    }

    private func responseFooter(_ result: InvestigationResult) -> some View {
        AssistantResponseActionBar(
            canCopy: !message.text.isEmpty,
            canRevealRequest: canRevealRequest,
            canRetry: canRetry,
            onCopy: onCopy,
            onFollowUp: onFollowUp,
            onRevealRequest: onRevealRequest,
            onRetry: onRetry,
            overflowItems: { handoffMenuItems(result) }
        )
    }

    /// Every workflow handoff and the configured-model escalation, rendered only as items in the
    /// footer's overflow menu — never as a visible button in the response body. Standard SF Symbols
    /// are acceptable here because they appear only after intentional disclosure.
    @ViewBuilder
    private func handoffMenuItems(_ result: InvestigationResult) -> some View {
        let handoffs = AssistantTrustPolicy.recommendedHandoffs(for: result.recipe)
        if showsContinueWithModel {
            Button {
                onContinueWithModel()
            } label: {
                Label(
                    String(localized: "Ask Configured Model", bundle: RockxyLocalization.bundle),
                    systemImage: "lock.shield"
                )
            }
        }
        ForEach(handoffs) { handoff in
            Button {
                performHandoff(handoff, result: result)
            } label: {
                Label(handoff.title, systemImage: handoff.systemImage)
            }
            .disabled(!isCurrentResult)
        }
        if showsContinueWithModel || !handoffs.isEmpty {
            Divider()
        }
    }

    private func usesModelAnswer(_ result: InvestigationResult) -> Bool {
        message.modelResult != nil && !message.text.isEmpty && message.text != result.summary
    }

    private func performHandoff(
        _ handoff: AssistantUserHandoff,
        result: InvestigationResult
    ) {
        if handoff == .prepareReplay {
            onPrepareReplay(result)
        } else {
            onHandoff(handoff, result)
        }
    }
}
