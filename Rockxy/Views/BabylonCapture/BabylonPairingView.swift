import AppKit
import SwiftUI

// MARK: - BabylonPairingAvailability

/// Presentation-only projection of live pairing readiness.
///
/// Composes the observed listener lifecycle with pairing-token availability into
/// a single pure value so overall readiness is
/// truthful and unit-testable without opening a real network listener. A listener
/// that is ready but has no token would reject every frame, so token availability
/// participates in the projection.
enum BabylonPairingAvailability: Equatable {
    case stopped
    case starting
    case waiting(String)
    case tokenMissing
    case ready
    case unavailable(String)

    // MARK: Lifecycle

    init(listenerStatus: BabylonListenerStatus, hasToken: Bool) {
        switch listenerStatus {
        case .stopped:
            self = .stopped
        case .starting:
            self = .starting
        case let .waiting(message):
            self = .waiting(message)
        case .ready:
            self = hasToken ? .ready : .tokenMissing
        case let .failed(message):
            self = .unavailable(message)
        }
    }

    // MARK: Internal

    /// Non-nil only for a listener failure — the sole case that offers Retry.
    var listenerErrorMessage: String? {
        if case let .unavailable(message) = self {
            return message
        }
        return nil
    }

    var waitingMessage: String? {
        if case let .waiting(message) = self {
            return message
        }
        return nil
    }
}

// MARK: - BabylonPairingClipboard

@MainActor
final class BabylonPairingClipboard {
    // MARK: Lifecycle

    init(
        pasteboard: NSPasteboard = .general,
        notificationCenter: NotificationCenter = .default
    ) {
        self.pasteboard = pasteboard
        self.notificationCenter = notificationCenter
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearCopiedTokenIfCurrent()
            }
        }
    }

    deinit {
        cleanupTask?.cancel()
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
    }

    // MARK: Internal

    static let shared = BabylonPairingClipboard()

    @discardableResult
    func copy(_ token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }

        let item = NSPasteboardItem()
        guard item.setString(token, forType: .string) else {
            return false
        }
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.concealedType)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            return false
        }

        copiedToken = token
        copiedChangeCount = pasteboard.changeCount
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            self?.clearCopiedTokenIfCurrent()
        }
        return true
    }

    /// Clears only the exact token written by this object. Clipboard content
    /// copied later by Rockxy or another app is never replaced or destroyed.
    func clearCopiedTokenIfCurrent() {
        defer {
            copiedToken = nil
            copiedChangeCount = nil
            cleanupTask = nil
        }
        guard let copiedToken,
              let copiedChangeCount,
              pasteboard.changeCount == copiedChangeCount,
              pasteboard.string(forType: .string) == copiedToken else
        {
            return
        }
        pasteboard.clearContents()
    }

    // MARK: Private

    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard: NSPasteboard
    private let notificationCenter: NotificationCenter
    private var copiedToken: String?
    private var copiedChangeCount: Int?
    private var cleanupTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
}

// MARK: - BabylonPairingView

struct BabylonPairingView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
                    connectionSection
                    tokenSection
                }
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(440, toolMetrics.bodyFontSize * 22 + 154),
            minHeight: max(400, toolMetrics.bodyFontSize * 18 + 166)
        )
        .confirmationDialog(
            String(localized: "Regenerate Babylon Pairing Token?"),
            isPresented: $showsRegenerateConfirmation
        ) {
            Button(String(localized: "Regenerate Token"), role: .destructive) {
                regenerateToken()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "Existing connections disconnect immediately, and every Babylon client must be updated with the new token before it can reconnect."
                )
            )
        }
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
            didCopyToken = false
            isTokenRevealed = false
        }
    }

    // MARK: Private

    @State private var store = BabylonPairingStore.shared
    @State private var receiver = BabylonCaptureReceiver.shared
    @State private var showsRegenerateConfirmation = false
    @State private var isTokenRevealed = false
    @State private var didCopyToken = false
    @State private var copyResetTask: Task<Void, Never>?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var availability: BabylonPairingAvailability {
        BabylonPairingAvailability(
            listenerStatus: receiver.listenerStatus,
            hasToken: !store.token.isEmpty
        )
    }

    private var statusIcon: String {
        switch availability {
        case .stopped: "stop.circle"
        case .starting: "hourglass"
        case .waiting: "wifi.exclamationmark"
        case .ready: "checkmark.circle.fill"
        case .tokenMissing: "key.slash"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch availability {
        case .stopped: .secondary
        case .starting: .secondary
        case .waiting: .orange
        case .ready: .green
        case .tokenMissing,
             .unavailable: .orange
        }
    }

    private var statusTitle: String {
        switch availability {
        case .stopped: String(localized: "Stopped")
        case .starting: String(localized: "Starting…")
        case .waiting: String(localized: "Waiting for Network")
        case .ready: String(localized: "Ready")
        case .tokenMissing: String(localized: "Not Ready")
        case .unavailable: String(localized: "Unavailable")
        }
    }

    private var statusSubtitle: String {
        switch availability {
        case .stopped:
            String(localized: "Babylon capture is not running.")
        case .starting:
            String(localized: "Waiting for the local Babylon listener to come online.")
        case .waiting:
            String(localized: "The listener will resume automatically when a viable network becomes available.")
        case .ready:
            String(localized: "The listener is accepting local-network connections on this Mac.")
        case .tokenMissing:
            String(localized: "Generate a pairing token so Babylon clients can authenticate.")
        case .unavailable:
            String(localized: "The Babylon listener isn't running. Clients can't connect until it restarts.")
        }
    }

    private var maskedToken: String {
        String(repeating: "•", count: 24)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "Babylon Pairing"))
                .font(toolMetrics.font(weight: .medium))
            Text(String(localized: "Pair the Babylon debug client with this Mac over the local network."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Connection"))
                .font(toolMetrics.tableHeaderFont())

            HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                statusGlyph
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(toolMetrics.font(weight: .medium))
                    Text(statusSubtitle)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if let message = availability.listenerErrorMessage {
                listenerDiagnosticRow(message, showsRetry: true)
            } else if let message = availability.waitingMessage {
                listenerDiagnosticRow(message, showsRetry: false)
            }

            connectionDetails
        }
        .padding(toolMetrics.formHorizontalPadding)
        .cardStyle()
    }

    @ViewBuilder private var statusGlyph: some View {
        if case .starting = availability {
            ProgressView()
                .controlSize(.small)
                .frame(width: toolMetrics.compactIconFontSize, height: toolMetrics.compactIconFontSize)
                .accessibilityHidden(true)
        } else {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: toolMetrics.compactIconFontSize))
                .accessibilityHidden(true)
        }
    }

    private var connectionDetails: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                detailLabel(String(localized: "Bonjour Service"))
                Text(BabylonCaptureProtocol.serviceType)
                    .font(toolMetrics.font(monospaced: true))
                    .textSelection(.enabled)
            }
            GridRow {
                detailLabel(String(localized: "Port"))
                Text("\(BabylonCaptureProtocol.port)")
                    .font(toolMetrics.font(monospaced: true))
                    .textSelection(.enabled)
            }
            GridRow {
                detailLabel(String(localized: "Open Connections"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(receiver.openConnectionCount)")
                        .font(toolMetrics.font(monospaced: true))
                    Text(String(localized: "Open connections may still be authenticating."))
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Token

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Pairing Token"))
                .font(toolMetrics.tableHeaderFont())

            if store.token.isEmpty {
                tokenUnavailableRow
            } else {
                tokenValueRow
            }
            tokenActions

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .cardStyle()
    }

    private var tokenValueRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            tokenText
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(localized: "Pairing token"))
                .accessibilityValue(
                    isTokenRevealed ? store.token : String(localized: "Hidden")
                )

            Button {
                isTokenRevealed.toggle()
            } label: {
                Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize, height: toolMetrics.compactButtonSize)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(.borderless)
            .help(isTokenRevealed ? String(localized: "Hide Token") : String(localized: "Show Token"))
            .accessibilityLabel(
                isTokenRevealed ? String(localized: "Hide Token") : String(localized: "Show Token")
            )
        }
        .padding(.horizontal, toolMetrics.controlSpacing)
        .frame(minHeight: toolMetrics.formControlHeight)
        .privacySensitive()
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    @ViewBuilder private var tokenText: some View {
        if isTokenRevealed {
            Text(store.token)
                .textSelection(.enabled)
        } else {
            Text(maskedToken)
                .textSelection(.disabled)
        }
    }

    private var tokenActions: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button {
                copyToken()
            } label: {
                actionButtonLabel(
                    didCopyToken ? String(localized: "Copied") : String(localized: "Copy")
                )
            }
            .disabled(store.token.isEmpty)
            .accessibilityLabel(
                didCopyToken
                    ? String(localized: "Pairing token copied")
                    : String(localized: "Copy pairing token")
            )

            Button(role: .destructive) {
                showsRegenerateConfirmation = true
            } label: {
                actionButtonLabel(String(localized: "Regenerate…"))
            }

            Spacer(minLength: 0)
        }
    }

    private var tokenUnavailableRow: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Image(systemName: "key.slash")
                .foregroundStyle(.secondary)
                .font(.system(size: toolMetrics.compactIconFontSize))
                .accessibilityHidden(true)
            Text(String(localized: "No pairing token is available. Regenerate a token to allow clients to connect."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text(String(localized: "Keep this token private. Anyone with it can send capture data to this Mac."))
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.footerTopPadding)
    }

    private func detailLabel(_ label: String) -> some View {
        Text(label)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private func listenerDiagnosticRow(_ message: String, showsRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(showsRetry ? Color.red : Color.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsRetry {
                Button(String(localized: "Retry Listener")) {
                    receiver.retryListener()
                }
            }
        }
    }

    private func actionButtonLabel(_ title: String) -> some View {
        // Shared width sized for the longest label ("Regenerate…") so Copy and
        // Regenerate stay equal-sized and never clip at large Appearance fonts.
        Text(title)
            .lineLimit(1)
            .frame(
                width: max(120, toolMetrics.bodyFontSize * 8),
                height: max(20, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func copyToken() {
        let token = store.token
        guard BabylonPairingClipboard.shared.copy(token) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            didCopyToken = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                didCopyToken = false
            }
        }
    }

    private func regenerateToken() {
        let previousToken = store.token
        store.regenerate()
        // Only reset reveal/copy affordances when the token actually changed. On a
        // persistence failure the token is unchanged and `store.errorMessage`
        // surfaces the problem, so the current reveal/copy state is preserved.
        guard store.token != previousToken else {
            return
        }
        isTokenRevealed = false
        copyResetTask?.cancel()
        didCopyToken = false
    }
}

// MARK: - View + cardStyle

private extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
