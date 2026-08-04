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
                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
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

/// The dedicated "Unknowns" section surfaced from `.unknown` evidence — open questions the local
/// investigation could not resolve from captured traffic alone. Always rendered so the report is
/// honest about whether open questions remain, including a truthful empty state.
struct InvestigationUnknownsView: View {
    // MARK: Internal

    let unknowns: [InvestigationEvidence]
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "Unknowns"), systemImage: "questionmark.circle")
                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
            if unknowns.isEmpty {
                Text(String(localized: "No open questions — captured traffic answered this investigation."))
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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

/// A single finding row. When it is backed by a captured request, tapping reveals that request;
/// the `scope` glyph keeps the reveal affordance discoverable.
struct InvestigationEvidenceRow: View {
    // MARK: Internal

    let evidence: InvestigationEvidence
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        Button {
            onReveal(evidence)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(evidenceColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(evidence.title)
                        .font(.system(size: metrics.metadataFontSize, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !evidence.detail.isEmpty {
                        Text(evidence.detail)
                            .font(.system(size: metrics.metadataFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if evidence.sourceTransactionID != nil {
                    Image(systemName: "scope")
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(evidence.sourceTransactionID == nil)
        .help(evidence.sourceTransactionID == nil
            ? evidence.detail
            : String(localized: "Reveal the request behind this finding"))
        .accessibilityLabel(String(localized: "\(evidence.kind.title) finding: \(evidence.title)"))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var evidenceColor: Color {
        switch evidence.kind {
        case .observed: .blue
        case .derived: .purple
        case .inferred: .orange
        case .unknown: .secondary
        }
    }
}

// MARK: - InvestigationReportSection

/// A labelled native inspector section for the investigation report — a restrained secondary title
/// with an SF Symbol above its content. Keeps every section header consistent and readable at large
/// fonts without web-style uppercase dashboard headings.
struct InvestigationReportSection<Content: View>: View {
    // MARK: Internal

    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InvestigationReportHeader

/// Report title row: the recipe that produced the investigation plus honest local/model
/// attribution and the number of requests in scope.
struct InvestigationReportHeader: View {
    // MARK: Internal

    let result: InvestigationResult
    let hasModelResult: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: result.recipe.systemImage)
                .foregroundStyle(.secondary)
            Text(result.recipe.title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Label(attribution, systemImage: hasModelResult ? "cpu" : "checkmark.seal")
                .font(.system(size: metrics.metadataFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var attribution: String {
        hasModelResult
            ? String(localized: "Model analysis · \(result.scopeTransactionIDs.count) requests")
            : String(localized: "Local analysis · \(result.scopeTransactionIDs.count) requests")
    }
}

// MARK: - InvestigationFindingsDisclosure

/// The "Findings" section: grouped Observed / Derived / Inferred evidence, expanded by default so
/// the report reads as a native inspector list rather than a hidden drawer.
struct InvestigationFindingsDisclosure: View {
    // MARK: Internal

    let findingGroups: [InvestigationEvidenceGroup]
    let findingCount: Int
    let onReveal: (InvestigationEvidence) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(findingGroups) { group in
                    InvestigationEvidenceGroupView(group: group, onReveal: onReveal)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Label(String(localized: "Findings"), systemImage: "list.bullet")
                    .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(findingCount.formatted())
                    .font(.system(size: metrics.metadataFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(String(localized: "Findings, \(findingCount) total"))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var isExpanded = true
}

// MARK: - InvestigationReportView

/// The completed investigation turn, rendered as a full-width native report rather than a chat
/// exchange. Presents Scope, Summary, optional Model Analysis, Findings, Unknowns, Next Step, and
/// Proposed Actions. Evidence-level reveal and all handoffs are surfaced through injected closures
/// so this stays a pure presentation surface; the caller supplies attribution + action-bar `footer`.
struct InvestigationReportView<Footer: View>: View {
    // MARK: Internal

    let message: DebugAssistantMessage
    let isCurrentResult: Bool
    let showsContinueWithModel: Bool
    let isPreparingReview: Bool
    let onReveal: (InvestigationEvidence) -> Void
    let onContinueWithModel: () -> Void
    let onHandoff: (AssistantUserHandoff, InvestigationResult) -> Void
    let onPrepareReplay: (InvestigationResult) -> Void
    @ViewBuilder let footer: Footer

    var body: some View {
        if let result = message.investigation {
            VStack(alignment: .leading, spacing: 12) {
                InvestigationReportHeader(result: result, hasModelResult: message.modelResult != nil)

                InvestigationReportSection(title: String(localized: "Scope"), systemImage: "scope") {
                    reportBody(result.scopeSummary)
                        .accessibilityLabel(String(localized: "Investigation scope: \(result.scopeSummary)"))
                }

                InvestigationReportSection(title: String(localized: "Summary"), systemImage: "text.alignleft") {
                    reportBody(result.summary)
                        .textSelection(.enabled)
                }

                if message.modelResult != nil, !message.text.isEmpty, message.text != result.summary {
                    InvestigationReportSection(title: String(localized: "Model Analysis"), systemImage: "cpu") {
                        AssistantMarkdownText(source: message.text)
                    }
                }

                findingsSection(result)

                InvestigationUnknownsView(
                    unknowns: InvestigationResultPresentation.unknowns(for: result.evidence),
                    onReveal: onReveal
                )

                InvestigationReportSection(
                    title: String(localized: "Next Step"),
                    systemImage: "arrow.turn.down.right"
                ) {
                    reportBody(result.nextStep, weight: .medium)
                        .accessibilityLabel(String(localized: "Next step: \(result.nextStep)"))
                }

                proposedActionsSection(result)

                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Investigation report"))
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var continueWithModelControl: some View {
        HStack(spacing: 8) {
            if isPreparingReview {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Preparing redacted preview…"))
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
            } else {
                Button(action: onContinueWithModel) {
                    Label(String(localized: "Continue With Model"), systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private func reportBody(_ text: String, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: metrics.secondaryFontSize, weight: weight))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func findingsSection(_ result: InvestigationResult) -> some View {
        let findingGroups = InvestigationResultPresentation.findingGroups(for: result.evidence)
        if findingGroups.isEmpty {
            InvestigationReportSection(title: String(localized: "Findings"), systemImage: "list.bullet") {
                Text(String(localized: "No concrete findings from the captured traffic."))
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.secondary)
            }
        } else {
            InvestigationFindingsDisclosure(
                findingGroups: findingGroups,
                findingCount: InvestigationResultPresentation.findingCount(for: result.evidence),
                onReveal: onReveal
            )
        }
    }

    @ViewBuilder
    private func proposedActionsSection(_ result: InvestigationResult) -> some View {
        let handoffs = AssistantTrustPolicy.recommendedHandoffs(for: result.recipe)
        InvestigationReportSection(
            title: String(localized: "Proposed Actions"),
            systemImage: "wrench.and.screwdriver"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if showsContinueWithModel {
                    continueWithModelControl
                }
                if handoffs.isEmpty {
                    if !showsContinueWithModel {
                        Text(String(localized: "No follow-up workflow is recommended for this investigation."))
                            .font(.system(size: metrics.metadataFontSize))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    handoffButtons(result, handoffs: handoffs)
                }
            }
        }
    }

    private func handoffButtons(
        _ result: InvestigationResult,
        handoffs: [AssistantUserHandoff]
    )
        -> some View
    {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(handoffs) { handoff in
                    handoffButton(handoff, result: result)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(handoffs) { handoff in
                    handoffButton(handoff, result: result)
                }
            }
        }
    }

    private func handoffButton(
        _ handoff: AssistantUserHandoff,
        result: InvestigationResult
    )
        -> some View
    {
        Button {
            if handoff == .prepareReplay {
                onPrepareReplay(result)
            } else {
                onHandoff(handoff, result)
            }
        } label: {
            Label(handoff.title, systemImage: handoff.systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isCurrentResult)
        .help(isCurrentResult
            ? handoff.title
            : String(localized: "Reselect the original request to reopen this action"))
    }
}
