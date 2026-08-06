import SwiftUI

// MARK: - ContextDockView

/// Native two-tab shell for request diagnostics and the conversational AI workflow.
struct ContextDockView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Inspector"), selection: selectedTab) {
                Text(String(localized: "Details")).tag(ContextDockTab.details)
                Text(String(localized: "AI Assistant")).tag(ContextDockTab.aiAssistant)
            }
            .workspaceModeSwitcherStyle()

            Divider()

            switch coordinator.activeWorkspace.contextDockTab {
            case .details:
                ContextDetailsView(coordinator: coordinator)
            case .aiAssistant:
                AIAssistantDockView(coordinator: coordinator, onOpenSettings: onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Inspector"))
    }

    // MARK: Private

    private var selectedTab: Binding<ContextDockTab> {
        Binding(
            get: { coordinator.activeWorkspace.contextDockTab },
            set: { tab in
                guard coordinator.activeWorkspace.contextDockTab != tab else {
                    return
                }
                // Picker callbacks can arrive during the native inspector's constraint pass.
                // Publish the content swap on the next run-loop turn so both tab roots keep
                // a stable inspector size while AppKit finishes the current layout.
                DispatchQueue.main.async { [weak coordinator] in
                    coordinator?.activeWorkspace.contextDockTab = tab
                }
            }
        )
    }
}

// MARK: - AIAssistantDockView

/// A selection-aware conversation with Rockxy's debugging assistant.
/// Captured traffic is attached as context; provider configuration remains secondary plumbing.
private struct AIAssistantDockView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            assistantHeader
            Divider()
            attachedContextHeader
            Divider()
            if conversationContextMismatch {
                AssistantConversationContextMismatchBanner(
                    context: coordinator.activeWorkspace.debugAssistantConversationContext,
                    onRestore: coordinator.restoreDebugAssistantConversationContext,
                    onStartNew: coordinator.startNewDebugAssistantConversationForCurrentSelection
                )
                Divider()
            }
            conversationTranscript
            Divider()
            promptComposer
        }
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant"))
        .sheet(item: reviewPackBinding) { _ in
            DebugAssistantReviewDataSheet(
                coordinator: coordinator,
                onSend: coordinator.sendDebugAssistantReview,
                onDismiss: coordinator.dismissDebugAssistantReview,
                onOverride: coordinator.applyDebugAssistantReviewFocusNoiseOverride
            )
        }
        .alert(
            String(localized: "Rename Conversation"),
            isPresented: renameConversationBinding
        ) {
            TextField(String(localized: "Conversation name"), text: $conversationRenameDraft)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Rename")) {
                guard let conversationBeingRenamed else {
                    return
                }
                coordinator.renameDebugAssistantConversation(
                    conversationBeingRenamed.id,
                    title: conversationRenameDraft
                )
            }
        }
        .confirmationDialog(
            String(localized: "Delete this conversation?"),
            isPresented: deleteConversationBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Conversation"), role: .destructive) {
                guard let conversationPendingDeletion else {
                    return
                }
                coordinator.deleteDebugAssistantConversation(conversationPendingDeletion.id)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This removes the conversation from this workspace history."))
        }
        .confirmationDialog(
            String(localized: "Prepare this request for replay?"),
            isPresented: prepareReplayBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Open in Compose")) {
                guard let resultPendingReplay else {
                    return
                }
                coordinator.performUserInitiatedDebugAssistantHandoff(.prepareReplay, result: resultPendingReplay)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "Rockxy will create an editable draft. Nothing is sent until you press Send in Compose."
                )
            )
        }
        .onAppear(perform: focusComposerIfRequested)
        .onChange(of: coordinator.activeWorkspace.isDebugAssistantComposerFocusRequested) {
            focusComposerIfRequested()
        }
    }

    // MARK: Private

    private static let activeTurnID = "debug-assistant-active-turn"
    private static let transcriptBottomID = "debug-assistant-transcript-bottom"

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @FocusState private var isComposerFocused: Bool
    @State private var isConversationSwitcherPresented = false
    @State private var conversationSearch = ""
    @State private var conversationBeingRenamed: DebugAssistantConversation?
    @State private var conversationRenameDraft = ""
    @State private var conversationPendingDeletion: DebugAssistantConversation?
    @State private var isTrustPopoverPresented = false
    @State private var resultPendingReplay: InvestigationResult?

    private var draftBinding: Binding<String> {
        Binding(
            get: { coordinator.activeWorkspace.debugAssistantDraft },
            set: { coordinator.activeWorkspace.debugAssistantDraft = $0 }
        )
    }

    private var reviewPackBinding: Binding<InvestigationContextPack?> {
        Binding(
            get: { coordinator.activeWorkspace.debugAssistantReviewPack },
            set: { value in
                if value == nil {
                    coordinator.dismissDebugAssistantReview()
                }
            }
        )
    }

    private var renameConversationBinding: Binding<Bool> {
        Binding(
            get: { conversationBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    conversationBeingRenamed = nil
                    conversationRenameDraft = ""
                }
            }
        )
    }

    private var deleteConversationBinding: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    conversationPendingDeletion = nil
                }
            }
        )
    }

    private var prepareReplayBinding: Binding<Bool> {
        Binding(
            get: { resultPendingReplay != nil },
            set: { isPresented in
                if !isPresented {
                    resultPendingReplay = nil
                }
            }
        )
    }

    private var filteredConversations: [DebugAssistantConversation] {
        coordinator.activeWorkspace.debugAssistantConversations
            .filter { $0.matches(conversationSearch) }
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var assistantConfiguration: AssistantProviderConfiguration? {
        AppSettingsManager.shared.settings.assistantProviderConfiguration
    }

    private var configuredModelIsAvailable: Bool {
        AppSettingsManager.shared.settings.debugAssistantModelAccessEnabled
            && assistantConfiguration?.isComplete == true
    }

    private var configuredModelLabel: String {
        guard let assistantConfiguration, assistantConfiguration.isComplete else {
            return String(localized: "No Configured Model")
        }
        return String(
            localized: "Global Default · \(assistantConfiguration.kind.title) · \(assistantConfiguration.model)"
        )
    }

    private var modelSelectionLabel: String {
        guard coordinator.activeWorkspace.debugAssistantUsesConfiguredModel,
              configuredModelIsAvailable else
        {
            return String(localized: "Built-in")
        }
        return assistantConfiguration?.model ?? String(localized: "Model")
    }

    private var selectedTransactions: [HTTPTransaction] {
        coordinator.debugAssistantSelectedTransactions()
    }

    private var primaryTransaction: HTTPTransaction? {
        selectedTransactions.first ?? coordinator.selectedTransaction
    }

    private var contextTransactions: [HTTPTransaction] {
        coordinator.debugAssistantContextTransactions()
    }

    private var relatedTransactionCount: Int {
        coordinator.debugAssistantRelatedTransactionCount()
    }

    private var selectedContextCount: Int {
        min(selectedTransactions.count, InvestigationContextLimits.default.maxTransactions)
    }

    private var selectedContextLabel: String {
        guard selectedContextCount < selectedTransactions.count else {
            return selectedContextCount.formatted()
        }
        return String(localized: "\(selectedContextCount) of \(selectedTransactions.count)")
    }

    private var conversationIsEmpty: Bool {
        coordinator.activeWorkspace.debugAssistantMessages.isEmpty
    }

    private var conversationContextMismatch: Bool {
        coordinator.debugAssistantConversationHasContextMismatch()
    }

    private var isBusy: Bool {
        if coordinator.activeWorkspace.isPreparingDebugAssistantReview {
            return true
        }
        if case .investigating = coordinator.activeWorkspace.debugAssistantState {
            return true
        }
        if case .streaming = coordinator.activeWorkspace.modelInvestigationState {
            return true
        }
        return false
    }

    private var canSendDraft: Bool {
        !isBusy
            && !conversationContextMismatch
            && !coordinator.activeWorkspace.debugAssistantDraft
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var streamingText: String {
        guard case let .streaming(_, _, _, _, _, text) = coordinator.activeWorkspace.modelInvestigationState else {
            return ""
        }
        return text
    }

    private var assistantHeader: some View {
        HStack(spacing: 8) {
            Text(coordinator.activeWorkspace.debugAssistantConversationTitle)
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                isConversationSwitcherPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut("k", modifiers: .command)
            .help(String(localized: "Search conversations (⌘K)"))
            .accessibilityLabel(String(localized: "Conversation History"))
            .popover(isPresented: $isConversationSwitcherPresented, arrowEdge: .top) {
                conversationSwitcher
            }

            Button {
                coordinator.newDebugAssistantConversation()
                isConversationSwitcherPresented = false
                isComposerFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "New conversation"))
            .accessibilityLabel(String(localized: "New Conversation"))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: max(36, appMetrics.primaryFontSize + 20))
        .background(Color.clear)
    }

    private var conversationSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Conversations"))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "Search titles and messages"),
                    text: $conversationSearch
                )
                .textFieldStyle(.plain)
            }
            .font(assistantFont(appMetrics.controlFontSize))
            .padding(.horizontal, 8)
            .frame(height: max(30, appMetrics.controlFontSize + 16))
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            if filteredConversations.isEmpty {
                ContentUnavailableView {
                    Label(
                        conversationSearch.isEmpty
                            ? String(localized: "No Conversations")
                            : String(localized: "No Results"),
                        systemImage: conversationSearch.isEmpty
                            ? "bubble.left.and.bubble.right"
                            : "magnifyingglass"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredConversations) { conversation in
                            conversationHistoryRow(conversation)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 352, height: 320)
        .background(Color.clear)
    }

    @ViewBuilder private var attachedContextHeader: some View {
        if let transaction = primaryTransaction {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: transaction))
                    .frame(width: 7, height: 7)

                Text(requestSummary(for: transaction))
                    .font(assistantFont(appMetrics.secondaryFontSize, monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Menu {
                    Button {
                        coordinator.setDebugAssistantTrafficScope(.selectedOnly)
                    } label: {
                        Label(
                            String(localized: "Selected Traffic Only (\(selectedContextLabel))"),
                            systemImage: coordinator.activeWorkspace.debugAssistantTrafficScope == .selectedOnly
                                ? "checkmark" : "circle"
                        )
                    }

                    Button {
                        coordinator.setDebugAssistantTrafficScope(.selectedAndRelated)
                    } label: {
                        Label(
                            String(localized: "Include Related Requests (+\(relatedTransactionCount))"),
                            systemImage: coordinator.activeWorkspace.debugAssistantTrafficScope == .selectedAndRelated
                                ? "checkmark" : "circle"
                        )
                    }
                    .disabled(relatedTransactionCount == 0)
                } label: {
                    Label("\(contextTransactions.count)", systemImage: "paperclip")
                        .font(assistantFont(appMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .controlSize(.small)
                .help(String(localized: "Choose the read-only traffic scope"))
                .accessibilityLabel(
                    String(localized: "Read-only traffic scope, \(contextTransactions.count) requests")
                )
            }
            .padding(.horizontal, 10)
            .frame(minHeight: max(32, appMetrics.secondaryFontSize + 18))
            .background(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                String(
                    localized: "Attached traffic: \(requestSummary(for: transaction)), \(contextTransactions.count) requests"
                )
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Select traffic to add context"))
                    .font(assistantFont(appMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: max(32, appMetrics.secondaryFontSize + 18))
            .background(Color.clear)
        }
    }

    private var conversationTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if conversationIsEmpty {
                        emptyConversationView
                    }

                    ForEach(coordinator.activeWorkspace.debugAssistantMessages) { message in
                        conversationMessage(message)
                            .id(message.id)
                    }

                    activeAssistantTurn
                        .id(Self.activeTurnID)

                    Color.clear
                        .frame(height: 1)
                        .id(Self.transcriptBottomID)
                }
                .padding(10)
            }
            .onChange(of: coordinator.activeWorkspace.debugAssistantMessages.count) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: streamingText) {
                scrollToBottom(proxy, animated: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    @ViewBuilder private var emptyConversationView: some View {
        if primaryTransaction == nil {
            noSelectionEmptyState
        } else {
            investigationLauncher
        }
    }

    /// The no-selection empty state: a restrained native prompt telling the user to select traffic.
    /// It intentionally shows no recipe cards — there is nothing to investigate yet.
    private var noSelectionEmptyState: some View {
        VStack(spacing: 6) {
            Text(String(localized: "Investigate captured traffic"))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))
            Text(String(localized: "Select a request to investigate, or type a question below."))
                .font(assistantFont(appMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// The selected-traffic launcher: a centered sparkles hero, a "Start an investigation" title, and
    /// every `DebugAssistantRecipe` as a native bordered button in a two-column grid (the fifth card
    /// sits alone on the left). Each card is fully clickable, shows the recipe's SF Symbol and short
    /// title, and surfaces the longer `recipe.detail` only as help.
    private var investigationLauncher: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(assistantFont(appMetrics.primaryFontSize + 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(String(localized: "Start an investigation"))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(DebugAssistantRecipe.allCases) { recipe in
                    suggestionCard(recipe)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var activeAssistantTurn: some View {
        switch coordinator.activeWorkspace.debugAssistantState {
        case .idle:
            modelAssistantTurn
        case let .result(result):
            currentResultTurn(result)
        case let .investigating(_, recipe):
            workEvent(
                title: String(localized: "Inspecting selected traffic"),
                detail: String(localized: "Gathering evidence for \(recipe.title.lowercased())."),
                cancel: coordinator.cancelDebugAssistant
            )
        case let .failed(message):
            failureTurn(message)
        }
    }

    @ViewBuilder private var modelAssistantTurn: some View {
        switch coordinator.activeWorkspace.modelInvestigationState {
        case .idle,
             .completed:
            EmptyView()
        case let .streaming(_, provider, executionLocation, model, endpointHost, text):
            assistantBubble {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(text.isEmpty
                        ? String(localized: "Generating with \(model)")
                        : String(localized: "Responding with \(model)"))
                        .font(assistantFont(appMetrics.secondaryFontSize, weight: .medium))
                    Spacer(minLength: 0)
                    Button(String(localized: "Stop")) {
                        coordinator.cancelDebugAssistantModelAnalysis()
                    }
                    .controlSize(.mini)
                }
                if text.isEmpty {
                    Text(
                        executionLocation.isLocal
                            ? String(localized: "The local model is reading the reviewed request context.")
                            : String(localized: "The configured provider is processing the reviewed request context.")
                    )
                    .font(assistantFont(appMetrics.metadataFontSize))
                    .foregroundStyle(.secondary)
                } else {
                    AssistantStreamingText(source: text)
                }
                modelSourceLabel(
                    provider: provider.title,
                    model: model,
                    endpointHost: endpointHost,
                    usage: nil
                )
            }
        case let .failed(message):
            assistantBubble {
                Label(
                    String(localized: "I couldn’t complete the model response."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.red)
                Text(message)
                    .font(assistantFont(appMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(String(localized: "Review & Retry")) {
                        coordinator.prepareDebugAssistantReview()
                    }
                    .controlSize(.small)

                    if assistantConfiguration?.kind == .ollama {
                        Button(String(localized: "Check Local Model…")) {
                            RockxySettingsTab.select(.assistant)
                            onOpenSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    primaryTransaction == nil
                        ? String(localized: "Ask Rockxy AI Assistant…")
                        : String(localized: "Ask about this traffic…"),
                    text: draftBinding,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(assistantFont(appMetrics.primaryFontSize))
                .lineLimit(1 ... 4)
                .focused($isComposerFocused)
                .onSubmit(sendDraft)
                .disabled(isBusy || conversationContextMismatch)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(assistantFont(appMetrics.controlFontSize, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSendDraft)
                .help(String(localized: "Send message"))
                .accessibilityLabel(String(localized: "Send Message"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isComposerFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isBusy, !conversationContextMismatch else {
                    return
                }
                isComposerFocused = true
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        coordinator.activeWorkspace.debugAssistantUsesConfiguredModel = false
                    } label: {
                        Label(
                            String(localized: "Built-in Analysis (No Model)"),
                            systemImage: coordinator.activeWorkspace.debugAssistantUsesConfiguredModel
                                ? "circle" : "checkmark"
                        )
                    }

                    Divider()

                    Button {
                        coordinator.activeWorkspace.debugAssistantUsesConfiguredModel = true
                    } label: {
                        Label(
                            configuredModelLabel,
                            systemImage: coordinator.activeWorkspace.debugAssistantUsesConfiguredModel
                                ? "checkmark" : "circle"
                        )
                    }
                    .disabled(!configuredModelIsAvailable)

                    Divider()

                    Button {
                        RockxySettingsTab.select(.assistant)
                        onOpenSettings()
                    } label: {
                        Label(String(localized: "Manage AI Models…"), systemImage: "gearshape")
                    }
                } label: {
                    Label(modelSelectionLabel, systemImage: "cpu")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .controlSize(.mini)
                .font(assistantFont(appMetrics.metadataFontSize))
                .fixedSize()
                .help(String(localized: "Choose local analysis or the app-wide AI model"))

                Spacer(minLength: 4)

                Button {
                    isTrustPopoverPresented.toggle()
                } label: {
                    Label(String(localized: "Read-only"), systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .font(assistantFont(appMetrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .help(String(localized: "Review the AI Assistant trust boundary"))
                .accessibilityLabel(String(localized: "Read-only Assistant privacy details"))
                .popover(isPresented: $isTrustPopoverPresented, arrowEdge: .bottom) {
                    AssistantTrustPopover()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.clear)
    }

    private func suggestionCard(_ recipe: DebugAssistantRecipe) -> some View {
        Button {
            coordinator.startDebugAssistant(recipe)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: recipe.systemImage)
                Text(recipe.title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isBusy)
        .help(recipe.detail)
        .accessibilityLabel(recipe.title)
    }

    @ViewBuilder
    private func currentResultTurn(_ result: InvestigationResult) -> some View {
        switch coordinator.activeWorkspace.modelInvestigationState {
        case .streaming,
             .failed:
            modelAssistantTurn
        case .completed:
            EmptyView()
        case .idle:
            if resultIsInTranscript(result) {
                EmptyView()
            } else if coordinator.activeWorkspace.isPreparingDebugAssistantReview {
                assistantBubble {
                    AssistantProgressRow(
                        title: String(localized: "Selected traffic inspected"),
                        systemImage: "checkmark.circle.fill",
                        color: .green
                    )
                    AssistantProgressRow(
                        title: String(localized: "Redacting sensitive fields"),
                        showsProgress: true
                    )
                    Text(String(localized: "Preparing the exact request for Review Data."))
                        .font(assistantFont(appMetrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                }
            } else if coordinator.activeWorkspace.debugAssistantReviewPack != nil {
                assistantBubble {
                    AssistantProgressRow(
                        title: String(localized: "Waiting for Review Data"),
                        systemImage: "lock.shield",
                        color: .secondary
                    )
                    Text(String(localized: "Confirm the redacted traffic and conversation before the model runs."))
                        .font(assistantFont(appMetrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                }
            } else {
                reviewReadyTurn(result)
            }
        }
    }

    private func conversationHistoryRow(_ conversation: DebugAssistantConversation) -> some View {
        Button {
            coordinator.selectDebugAssistantConversation(conversation.id)
            isConversationSwitcherPresented = false
            isComposerFocused = true
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(assistantFont(appMetrics.metadataFontSize))
                                .foregroundStyle(.secondary)
                        }
                        Text(conversation.title)
                            .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(conversation.preview)
                        .font(assistantFont(appMetrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(relativeDateLabel(conversation.updatedAt))
                    .font(assistantFont(appMetrics.metadataFontSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                conversation.id == coordinator.activeWorkspace.debugAssistantConversationID
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                coordinator.togglePinnedDebugAssistantConversation(conversation.id)
            } label: {
                Label(
                    conversation.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                conversationBeingRenamed = conversation
                conversationRenameDraft = conversation.title
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                conversationPendingDeletion = conversation
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .accessibilityLabel("\(conversation.title), \(conversation.preview)")
    }

    @ViewBuilder
    private func conversationMessage(_ message: DebugAssistantMessage) -> some View {
        switch message.role {
        case .user:
            AssistantUserMessageBubble(text: message.text)
        case .assistant:
            if message.investigation != nil {
                investigationReport(message)
            } else {
                assistantBubble {
                    AssistantMarkdownText(
                        source: message.text.isEmpty
                            ? String(localized: "The model completed without returning text.")
                            : message.text
                    )

                    if let modelResult = message.modelResult, modelResult.blockedToolCallCount > 0 {
                        blockedToolCallWarning(modelResult.blockedToolCallCount)
                    }

                    assistantResponseActions(
                        text: message.text,
                        investigation: nil,
                        canRetryModel: message.modelResult != nil,
                        modelResult: message.modelResult
                    )
                }
            }
        }
    }

    private func assistantBubble(@ViewBuilder content: () -> some View) -> some View {
        AssistantResponseContainer(content: content)
    }

    private func assistantResponseActions(
        text: String,
        investigation: InvestigationResult?,
        canRetryModel: Bool,
        modelResult: ModelInvestigationResult?
    )
        -> some View
    {
        let requestID = investigation?.selectedTransactionID
        return AssistantResponseActionBar(
            canCopy: !text.isEmpty,
            canRevealRequest: requestID != nil,
            canRetry: canRetryModel && investigation.map(isCurrentResult) == true,
            onCopy: {
                AssistantClipboard.copy(text)
            },
            onFollowUp: {
                startFollowUp(for: investigation)
            },
            onRevealRequest: {
                if let requestID {
                    coordinator.revealDebugAssistantRequest(id: requestID)
                }
            },
            onRetry: {
                if canRetryModel, investigation.map(isCurrentResult) == true {
                    coordinator.prepareDebugAssistantReview()
                }
            },
            overflowItems: {
                if let modelResult {
                    modelProvenanceMenuItems(modelResult)
                }
            }
        )
    }

    /// The completed model reply keeps the answer as its surface: standard provenance never renders
    /// inline. Provider, model, endpoint host, and token usage stay accessible only as plain,
    /// icon-free rows in the footer's overflow menu, revealed on intent.
    @ViewBuilder
    private func modelProvenanceMenuItems(_ modelResult: ModelInvestigationResult) -> some View {
        Button("\(modelResult.provider.title) · \(modelResult.model)") {}
            .disabled(true)
        Button(modelResult.endpointHost) {}
            .disabled(true)
        if let usage = modelResult.usage {
            Button(String(localized: "\(usage.inputTokens) input · \(usage.outputTokens) output tokens")) {}
                .disabled(true)
        }
        Divider()
    }

    /// A blocked-tool-call safety warning stays visible on the reply, rendered as concise plain text
    /// without a decorative hand icon so the answer remains the surface.
    private func blockedToolCallWarning(_ count: Int) -> some View {
        Text(String(localized: "Rockxy blocked \(count) model action request(s)."))
            .font(assistantFont(appMetrics.metadataFontSize))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func investigationReport(_ message: DebugAssistantMessage) -> some View {
        if let result = message.investigation {
            let requestID = result.selectedTransactionID
            let canRetry = message.modelResult != nil && isCurrentResult(result)
            assistantBubble {
                InvestigationReportView(
                    message: message,
                    isCurrentResult: isCurrentResult(result),
                    showsContinueWithModel: isCurrentResult(result)
                        && coordinator.activeWorkspace.debugAssistantUsesConfiguredModel
                        && configuredModelIsAvailable,
                    isPreparingReview: coordinator.activeWorkspace.isPreparingDebugAssistantReview,
                    canRevealRequest: true,
                    canRetry: canRetry,
                    onReveal: coordinator.revealDebugAssistantEvidence,
                    onContinueWithModel: { coordinator.prepareDebugAssistantReview() },
                    onHandoff: { handoff, target in
                        coordinator.performUserInitiatedDebugAssistantHandoff(handoff, result: target)
                    },
                    onPrepareReplay: { resultPendingReplay = $0 },
                    onCopy: { AssistantClipboard.copy(message.text) },
                    onFollowUp: { startFollowUp(for: result) },
                    onRevealRequest: {
                        coordinator.revealDebugAssistantRequest(id: requestID)
                    },
                    onRetry: {
                        if canRetry {
                            coordinator.prepareDebugAssistantReview()
                        }
                    }
                )
            }
        }
    }

    private func modelSourceLabel(
        provider: String,
        model: String,
        endpointHost: String,
        usage: AssistantUsage?
    )
        -> some View
    {
        Menu {
            Button("\(provider) · \(model)") {}
                .disabled(true)
            Button(endpointHost) {}
                .disabled(true)
            if let usage {
                Divider()
                Button(String(localized: "\(usage.inputTokens) input · \(usage.outputTokens) output")) {}
                    .disabled(true)
            }
        } label: {
            Label(model, systemImage: "cpu")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.mini)
        .font(assistantFont(appMetrics.metadataFontSize, monospaced: true))
        .foregroundStyle(.secondary)
        .help("\(provider) · \(model) · \(endpointHost)")
        .accessibilityLabel(String(localized: "Model details: \(provider), \(model), \(endpointHost)"))
    }

    private func reviewReadyTurn(_ result: InvestigationResult) -> some View {
        assistantBubble {
            AssistantProgressRow(
                title: String(localized: "Selected traffic inspected"),
                systemImage: "checkmark.circle.fill",
                color: .green
            )
            Text(result.summary)
                .font(assistantFont(appMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                coordinator.prepareDebugAssistantReview()
            } label: {
                Label(String(localized: "Review Data & Run Model"), systemImage: "lock.shield")
            }
            .controlSize(.small)
        }
    }

    private func workEvent(
        title: String,
        detail: String,
        cancel: @escaping () -> Void
    )
        -> some View
    {
        assistantBubble {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(assistantFont(appMetrics.secondaryFontSize, weight: .medium))
                Spacer(minLength: 4)
                Button(String(localized: "Stop"), action: cancel)
                    .controlSize(.mini)
            }
            Text(detail)
                .font(assistantFont(appMetrics.metadataFontSize))
                .foregroundStyle(.secondary)
        }
    }

    private func failureTurn(_ message: String) -> some View {
        assistantBubble {
            Label(
                String(localized: "I couldn’t finish that investigation."),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
            .foregroundStyle(.red)
            Text(message)
                .font(assistantFont(appMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if primaryTransaction != nil {
                Button(String(localized: "Try Again")) {
                    coordinator.startDebugAssistant(.explainFailure)
                }
                .controlSize(.small)
            }
        }
    }

    private func startFollowUp(for investigation: InvestigationResult?) {
        coordinator.prepareDebugAssistantFollowUp(for: investigation)
        isComposerFocused = false
        Task { @MainActor in
            await Task.yield()
            isComposerFocused = true
        }
    }

    private func sendDraft() {
        guard canSendDraft else {
            return
        }
        coordinator.sendDebugAssistantMessage()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.transcriptBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.transcriptBottomID, anchor: .bottom)
            }
        }
    }

    /// Explicit `.system(size:)` roles that mirror the horizontal request/response inspector:
    /// UI labels and prose stay proportional; callers opt into monospaced only for technical data
    /// (request summaries, model IDs, endpoints). Deliberately does not honor the global
    /// `useMonospacedFont` preference, so prose never renders monospaced.
    private func assistantFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        monospaced: Bool = false
    )
        -> Font
    {
        monospaced
            ? .system(size: size, weight: weight, design: .monospaced)
            : .system(size: size, weight: weight)
    }
}

private extension AIAssistantDockView {
    func focusComposerIfRequested() {
        let workspace = coordinator.activeWorkspace
        guard workspace.isDebugAssistantComposerFocusRequested else {
            return
        }
        workspace.isDebugAssistantComposerFocusRequested = false
        isComposerFocused = false
        Task { @MainActor in
            await Task.yield()
            isComposerFocused = true
        }
    }

    func isCurrentResult(_ result: InvestigationResult) -> Bool {
        guard case let .result(current) = coordinator.activeWorkspace.debugAssistantState else {
            return false
        }
        return current == result
    }

    func resultIsInTranscript(_ result: InvestigationResult) -> Bool {
        coordinator.activeWorkspace.debugAssistantMessages.contains {
            $0.investigation == result
        }
    }

    func requestSummary(for transaction: HTTPTransaction) -> String {
        let status = transaction.response.map { String($0.statusCode) } ?? "—"
        return "\(transaction.request.method) \(status)  \(transaction.request.host)\(transaction.request.path)"
    }

    func statusColor(for transaction: HTTPTransaction) -> Color {
        guard let status = transaction.response?.statusCode else {
            return transaction.state == .failed ? .red : .secondary
        }
        switch status {
        case 200 ..< 300: return .green
        case 300 ..< 400: return .blue
        case 400 ..< 500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }

    func relativeDateLabel(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 {
            return String(localized: "Now")
        }
        if interval < 3_600 {
            return String(localized: "\(Int(interval / 60))m")
        }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
