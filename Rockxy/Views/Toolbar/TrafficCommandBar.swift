import SwiftUI

// Renders the traffic quick-action strip that sits above the protocol filter bar.

// MARK: - TrafficCommandKind

enum TrafficCommandKind: String, CaseIterable {
    case clearSession
    case jumpToFirstRequest
    case followLive
    case jumpToLastRequest
    case copyAsCURL
    case togglePin
    case toggleSave
}

// MARK: - TrafficCommandDescriptor

/// Value-typed presentation contract for traffic-strip controls and their structured overflow menu.
/// The main menu remains the keyboard-shortcut owner; this surface mirrors those commands and keeps
/// their live state and availability close to the request list.
struct TrafficCommandDescriptor: Identifiable, Equatable {
    let id: TrafficCommandKind
    let title: String
    let systemImage: String
    let help: String
    let isActive: Bool
    let isEnabled: Bool

    static func clearSession(isEnabled: Bool = true) -> Self {
        .init(
            id: .clearSession,
            title: String(localized: "Clear Session"),
            systemImage: "trash",
            help: String(localized: "Clear captured requests and logs from this session across all tabs. ⌘K"),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func jumpToFirstRequest(isEnabled: Bool) -> Self {
        .init(
            id: .jumpToFirstRequest,
            title: String(localized: "Jump to First Request"),
            systemImage: "arrow.up.to.line",
            help: String(localized: "Jump to the first visible request. ⌘↑"),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func followLive(isActive: Bool) -> Self {
        .init(
            id: .followLive,
            title: String(localized: "Follow Live"),
            systemImage: "dot.radiowaves.right",
            help: isActive
                ? String(localized: "Follow Live is on for this tab. Scroll, select a row, or click again to stop. ⇧⌘L")
                : String(localized: "Keep the newest request in this tab selected. ⇧⌘L"),
            isActive: isActive,
            isEnabled: true
        )
    }

    static func jumpToLastRequest(isEnabled: Bool) -> Self {
        .init(
            id: .jumpToLastRequest,
            title: String(localized: "Jump to Last Request"),
            systemImage: "arrow.down.to.line",
            help: String(localized: "Jump to the latest visible request without changing Follow Live. ⌘↓"),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func copyAsCURL(isEnabled: Bool) -> Self {
        .init(
            id: .copyAsCURL,
            title: String(localized: "Copy as cURL"),
            systemImage: "terminal",
            help: String(localized: "Copy the selected request as a cURL command. ⇧⌘C"),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func togglePin(isPinned: Bool, isEnabled: Bool) -> Self {
        .init(
            id: .togglePin,
            title: isPinned ? String(localized: "Unpin Request") : String(localized: "Pin Request"),
            systemImage: isPinned ? "pin.fill" : "pin",
            help: isPinned
                ? String(localized: "Unpin the selected request from the current session.")
                : String(localized: "Keep the selected request pinned in the current session."),
            isActive: isPinned,
            isEnabled: isEnabled
        )
    }

    static func toggleSave(isSaved: Bool, isEnabled: Bool) -> Self {
        .init(
            id: .toggleSave,
            title: isSaved ? String(localized: "Unsave Request") : String(localized: "Save Request"),
            systemImage: isSaved ? "tray.full.fill" : "tray.and.arrow.down",
            help: isSaved
                ? String(localized: "Remove the selected request from the Library.")
                : String(localized: "Save the selected request to the Library."),
            isActive: isSaved,
            isEnabled: isEnabled
        )
    }
}

// MARK: - TrafficRecordingCommandPresentation

/// Presentation for the capture-buffer toggle. Start/Stop remains a window-toolbar lifecycle
/// control, while this command explicitly names the recording-buffer state so the two actions
/// cannot be mistaken for one another.
struct TrafficRecordingCommandPresentation: Equatable {
    let title: String
    let systemImage: String
    let help: String
    let isEnabled: Bool

    static func make(isProxyRunning: Bool, isRecording: Bool) -> Self {
        .init(
            title: isRecording ? String(localized: "Pause Recording") : String(localized: "Resume Recording"),
            systemImage: isRecording ? "pause.circle" : "record.circle",
            help: isProxyRunning
                ? (isRecording
                    ? String(localized: "Pause recording new traffic without stopping the proxy. ⌥⌘R")
                    : String(localized: "Resume recording new traffic. ⌥⌘R"))
                : String(localized: "Start the proxy before changing recording. ⌥⌘R"),
            isEnabled: isProxyRunning
        )
    }
}

// MARK: - TrafficActionsMenuPresentation

enum TrafficActionsMenuPresentation {
    static let systemImage = "ellipsis.circle"
    static let help = String(localized: "More traffic actions")
    static let accessibilityLabel = String(localized: "More Traffic Actions")
}

// MARK: - TrafficCommandBar

/// A native command strip for immediate traffic work. Recording, session clearing, and live-tail
/// state stay visible; richer request, rule, navigation, session, and export workflows live in one
/// structured icon menu. Proxy Start/Stop remains in the window toolbar, spatially separate from
/// the explicitly labeled recording-buffer control here.
struct TrafficCommandBar: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    var onOpenToolWindow: (String) -> Void = { _ in }
    var isEmbeddedInControlShelf = false
    var showsQuickTools = true

    var body: some View {
        commandRow
            .padding(.horizontal, Theme.Layout.contentPadding)
            .padding(.vertical, max(4, (metrics.fontSize - 10) / 3))
            .background {
                if !isEmbeddedInControlShelf {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
            .overlay(alignment: .bottom) {
                if !isEmbeddedInControlShelf {
                    Divider()
                }
            }
            .fixedSize(horizontal: isEmbeddedInControlShelf, vertical: true)
            .task { persistResolvedQuickToolsLayoutIfNeeded() }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @AppStorage(QuickToolsLayout.storageKey) private var quickToolsLayoutRaw = ""
    @AppStorage(QuickToolsLayout.legacyFooterStorageKey) private var legacyFooterQuickToolOrder = ""
    @State private var isCustomizingQuickTools = false

    /// Stable reference to the Allow List singleton so Observation tracks `isActive` inside `body`
    /// and re-renders the Allow List capsule's active state when the master toggle changes.
    private let allowListManager = AllowListManager.shared

    private var actions: MainContentCommandActions {
        MainContentCommandActions(coordinator: coordinator)
    }

    private var quickToolsLayout: QuickToolsLayout {
        QuickToolsLayout.resolved(
            storageRaw: quickToolsLayoutRaw,
            legacyFooterRaw: legacyFooterQuickToolOrder
        )
    }

    private var selectedTransaction: HTTPTransaction? {
        coordinator.selectedTransaction
    }

    private var effectiveSelectionCount: Int {
        max(coordinator.selectedTransactionIDs.count, selectedTransaction == nil ? 0 : 1)
    }

    private var hasSingleRequestSelection: Bool {
        TrafficCommandAvailability.canActOnSingleRequest(
            hasPrimarySelection: selectedTransaction != nil,
            selectionCount: effectiveSelectionCount
        )
    }

    private var canUseHTTPOnlySelection: Bool {
        guard let selectedTransaction else {
            return false
        }
        return TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: effectiveSelectionCount,
            isWebSocket: selectedTransaction.webSocketConnection != nil,
            method: selectedTransaction.request.method
        )
    }

    private var canClearSession: Bool {
        TrafficCommandAvailability.canClearSession(
            transactionCount: coordinator.transactions.count,
            logCount: coordinator.logEntries.count,
            hasSessionProvenance: coordinator.sessionProvenance != nil,
            isClearingSession: coordinator.isClearingSession
        )
    }

    private var commandRow: some View {
        HStack(spacing: 8) {
            recordingButton
            clearSessionButton
            commandDivider
            followLiveButton
            if showsQuickTools {
                responsiveQuickToolsGroup
            }

            Spacer(minLength: showsQuickTools ? 12 : 4)
            moreActionsMenu
        }
    }

    private var recordingButton: some View {
        let presentation = TrafficRecordingCommandPresentation.make(
            isProxyRunning: coordinator.isProxyRunning,
            isRecording: coordinator.isRecording
        )
        return Button {
            actions.toggleRecording()
        } label: {
            commandLabel(title: presentation.title, systemImage: presentation.systemImage)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .disabled(!presentation.isEnabled)
        .help(presentation.help)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(
            coordinator.isRecording ? String(localized: "Recording") : String(localized: "Paused")
        )
    }

    /// The shared quick-tool capsules for the command bar. Responsive: three capsules when wide,
    /// two when medium, none when narrow — it never degrades to icon-only controls. Hidden tools
    /// stay reachable through the Traffic Actions "Quick Tools" submenu.
    private var responsiveQuickToolsGroup: some View {
        let descriptors = FooterActionDescriptor.toolingActions(
            isAllowListActive: allowListManager.isActive,
            quickTools: quickToolsLayout.commandBar
        )
        return ViewThatFits(in: .horizontal) {
            quickToolsGroup(descriptors)
            quickToolsGroup(Array(descriptors.prefix(2)))
            EmptyView()
        }
    }

    private var clearSessionButton: some View {
        let descriptor = TrafficCommandDescriptor.clearSession(isEnabled: canClearSession)
        return Button {
            actions.clearSession()
        } label: {
            commandLabel(title: descriptor.title, systemImage: descriptor.systemImage)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .disabled(!descriptor.isEnabled)
        .help(descriptor.help)
        .accessibilityLabel(descriptor.title)
    }

    private var followLiveButton: some View {
        let descriptor = TrafficCommandDescriptor.followLive(isActive: coordinator.isFollowingLiveTraffic)
        return Button {
            coordinator.setFollowingLiveTraffic(!coordinator.isFollowingLiveTraffic)
        } label: {
            commandLabel(title: descriptor.title, systemImage: descriptor.systemImage)
                .foregroundStyle(.primary)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .overlay {
            if descriptor.isActive {
                Capsule(style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(Theme.Glass.activeStrokeOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .help(descriptor.help)
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(descriptor.isActive ? String(localized: "On") : String(localized: "Off"))
    }

    private var moreActionsMenu: some View {
        Menu {
            navigationMenu

            Divider()

            requestMenu
            createRuleMenu

            Divider()

            quickToolsMenu

            Divider()

            Button(String(localized: "Compose…")) { actions.composeFreshRequest() }
            sessionMenu
            exportMenu
        } label: {
            Image(systemName: TrafficActionsMenuPresentation.systemImage)
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: metrics.filterBarHeight, height: metrics.filterBarHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(TrafficActionsMenuPresentation.help)
        .accessibilityLabel(TrafficActionsMenuPresentation.accessibilityLabel)
        .popover(isPresented: $isCustomizingQuickTools, arrowEdge: .bottom) {
            QuickToolsEditor(
                layout: quickToolsLayout,
                onSave: { quickToolsLayoutRaw = $0.encoded },
                onReset: { quickToolsLayoutRaw = QuickToolsLayout.default.encoded },
                onDone: { isCustomizingQuickTools = false }
            )
        }
    }

    /// Keeps the command-bar quick tools discoverable when the responsive strip collapses, and
    /// bridges into the shared customization editor through the stable trailing More menu.
    @ViewBuilder private var quickToolsMenu: some View {
        Menu(String(localized: "Quick Tools")) {
            ForEach(
                FooterActionDescriptor.toolingActions(
                    isAllowListActive: allowListManager.isActive,
                    quickTools: quickToolsLayout.commandBar
                )
            ) { descriptor in
                Button {
                    openQuickTool(descriptor.id)
                } label: {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
            }
        }
        Button(String(localized: "Customize Quick Tools…")) {
            // A macOS `Menu` tears down its transient window before the next presentation can
            // begin. Defer the popover state change to the next main-queue turn so the stable
            // command-bar anchor presents reliably after the menu has closed.
            DispatchQueue.main.async {
                isCustomizingQuickTools = true
            }
        }
    }

    @ViewBuilder private var navigationMenu: some View {
        Button(String(localized: "Jump to First Request")) { actions.selectFirstTransaction() }
            .disabled(coordinator.filteredTransactions.isEmpty)
        Button(String(localized: "Jump to Last Request")) { actions.selectLastTransaction() }
            .disabled(coordinator.filteredTransactions.isEmpty)
    }

    private var requestMenu: some View {
        Menu(String(localized: "Selected Request")) {
            let copy = TrafficCommandDescriptor.copyAsCURL(isEnabled: canUseHTTPOnlySelection)
            Button(copy.title) { actions.copyAsCURL() }
                .disabled(!copy.isEnabled)

            let pin = TrafficCommandDescriptor.togglePin(
                isPinned: selectedTransaction?.isPinned == true,
                isEnabled: hasSingleRequestSelection
            )
            Button(pin.title) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.togglePin(for: selectedTransaction)
            }

            let save = TrafficCommandDescriptor.toggleSave(
                isSaved: selectedTransaction?.isSaved == true,
                isEnabled: hasSingleRequestSelection
            )
            Button(save.title) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.saveRequest(selectedTransaction)
            }

            Divider()

            Button(String(localized: "Repeat")) { actions.replayRequest() }
                .disabled(!canUseHTTPOnlySelection)
            Button(String(localized: "Edit and Repeat…")) { actions.editAndRepeat() }
                .disabled(!canUseHTTPOnlySelection)

            Divider()

            Button(String(localized: "Add Note…")) { actions.addComment() }
            Menu(String(localized: "Highlight")) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) { actions.setHighlight(color) }
                }
                Divider()
                Button(String(localized: "Remove Highlight")) { actions.setHighlight(nil) }
            }
        }
        .disabled(!hasSingleRequestSelection)
    }

    private var createRuleMenu: some View {
        Menu(String(localized: "Create Rule from Request")) {
            Button(String(localized: "Breakpoint…")) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createBreakpointRule(for: selectedTransaction)
            }
            Button(String(localized: "Map Local…")) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createMapLocalRule(for: selectedTransaction)
            }
            Button(String(localized: "Map Remote…")) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createMapRemoteRule(for: selectedTransaction)
            }
            Button(String(localized: "Network Condition…")) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createNetworkConditionsRule(for: selectedTransaction)
            }
        }
        .disabled(!canUseHTTPOnlySelection)
    }

    private var sessionMenu: some View {
        Menu(String(localized: "Session")) {
            Button(String(localized: "Clear Session and Filters")) { actions.clearCaptureAndFilters() }
                .disabled(!canClearSession)
            Button(String(localized: "Save Session…")) { actions.saveSession() }
                .disabled(coordinator.transactions.isEmpty)
        }
    }

    private var exportMenu: some View {
        Menu(String(localized: "Export")) {
            Button(String(localized: "Export as HAR…")) { actions.exportHAR() }
                .disabled(coordinator.transactions.isEmpty)
            Button(String(localized: "Export as OpenAPI YAML…")) { actions.exportOpenAPIYAML() }
                .disabled(!actions.canExportOpenAPI)
            Button(String(localized: "Export as OpenAPI HTML…")) { actions.exportOpenAPIHTML() }
                .disabled(!actions.canExportOpenAPI)
            Divider()
            Button(String(localized: "Publish Selected to Gist…")) { actions.publishSelectedToGist() }
                .disabled(!actions.canPublishGist)
        }
    }

    private var commandDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func commandLabel(title: String, systemImage: String) -> some View {
        if isEmbeddedInControlShelf {
            Image(systemName: systemImage)
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .frame(width: metrics.filterBarHeight, height: metrics.filterBarHeight)
        } else {
            Label(title, systemImage: systemImage)
                .font(.system(size: metrics.secondaryFontSize))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func quickToolsRow(_ descriptors: [FooterActionDescriptor]) -> some View {
        HStack(spacing: 6) {
            ForEach(descriptors) { descriptor in
                FooterToolingButton(descriptor: descriptor) {
                    openQuickTool(descriptor.id)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func quickToolsGroup(_ descriptors: [FooterActionDescriptor]) -> some View {
        HStack(spacing: 8) {
            commandDivider
            quickToolsRow(descriptors)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func persistResolvedQuickToolsLayoutIfNeeded() {
        let normalized = quickToolsLayout.encoded
        if quickToolsLayoutRaw != normalized {
            quickToolsLayoutRaw = normalized
        }
    }

    private func openQuickTool(_ kind: FooterActionKind) {
        guard let windowID = kind.toolWindowID else {
            return
        }
        onOpenToolWindow(windowID)
    }
}

// MARK: - TrafficCommandAvailability

enum TrafficCommandAvailability {
    static func canClearSession(
        transactionCount: Int,
        logCount: Int,
        hasSessionProvenance: Bool,
        isClearingSession: Bool
    )
        -> Bool
    {
        !isClearingSession && (transactionCount > 0 || logCount > 0 || hasSessionProvenance)
    }

    static func canActOnSingleRequest(hasPrimarySelection: Bool, selectionCount: Int) -> Bool {
        hasPrimarySelection && selectionCount == 1
    }

    static func canUseHTTPOnlyRequestAction(
        hasPrimarySelection: Bool,
        selectionCount: Int,
        isWebSocket: Bool,
        method: String
    )
        -> Bool
    {
        canActOnSingleRequest(
            hasPrimarySelection: hasPrimarySelection,
            selectionCount: selectionCount
        ) && !isWebSocket && method.caseInsensitiveCompare("CONNECT") != .orderedSame
    }
}
