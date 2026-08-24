import SwiftUI

// Shared Quick Tools system: one seven-tool catalog and one persisted layout own both the
// top `TrafficCommandBar` (3 slots) and the footer `StatusBarView` (4 slots). Both regions render
// the same labeled native `FooterToolingButton`, preserving discoverability without a separate
// top-only style. `proxyOverride` stays a dynamic footer control outside this layout.

// MARK: - FooterActionKind + Quick Tools

extension FooterActionKind {
    /// The seven customizable tools, in canonical order. Excludes `proxyOverride`, which is a
    /// dynamic footer status control rather than a customizable launcher.
    static let customizableQuickTools: [FooterActionKind] = allCases.filter { $0 != .proxyOverride }

    /// The tool-window ID opened when this launcher is activated, or `nil` for non-launchers.
    var toolWindowID: String? {
        switch self {
        case .blockList: "blockList"
        case .allowList: "allowList"
        case .mapLocal: "mapLocal"
        case .scripting: "scriptingList"
        case .mapRemote: "mapRemote"
        case .breakpoint: "breakpointRules"
        case .networkConditions: "networkConditions"
        case .proxyOverride: nil
        }
    }
}

// MARK: - QuickToolsLayout

/// Pure value model for the synchronized 3+4 Quick Tools layout. All seven customizable tools
/// occur exactly once across the three command-bar slots and four footer slots. Every constructor
/// path returns a repaired, valid layout so the UI can trust the invariant without extra checks.
struct QuickToolsLayout: Equatable {
    // MARK: Lifecycle

    /// Repairs whatever it is given into a valid 3+4 layout. Drops duplicates and `proxyOverride`,
    /// then backfills any missing tools in canonical order so the invariant always holds.
    init(commandBar rawCommandBar: [FooterActionKind], footer rawFooter: [FooterActionKind]) {
        var seen = Set<FooterActionKind>()
        func cleaned(_ list: [FooterActionKind]) -> [FooterActionKind] {
            list.filter { $0 != .proxyOverride && seen.insert($0).inserted }
        }

        let cleanedCommandBar = cleaned(rawCommandBar)
        let cleanedFooter = cleaned(rawFooter)
        let missing = FooterActionKind.customizableQuickTools.filter { !seen.contains($0) }

        let pool = cleanedCommandBar + cleanedFooter + missing
        commandBar = Array(pool.prefix(Self.commandBarSlotCount))
        footer = Array(pool.dropFirst(Self.commandBarSlotCount).prefix(Self.footerSlotCount))
    }

    // MARK: Internal

    enum Region: Equatable {
        case commandBar
        case footer
    }

    static let commandBarSlotCount = 3
    static let footerSlotCount = 4
    static let storageKey = RockxyIdentity.current.defaultsKey("quickToolsLayout")
    static let legacyFooterStorageKey = "footerQuickToolOrder"

    /// Approved defaults: Block List, Allow List, Map Remote on top; Breakpoint, Map Local,
    /// Scripting, Network Conditions in the footer.
    static let `default` = QuickToolsLayout(
        commandBar: [.blockList, .allowList, .mapRemote],
        footer: FooterActionKind.defaultQuickTools
    )

    private(set) var commandBar: [FooterActionKind]
    private(set) var footer: [FooterActionKind]

    // MARK: Encoding

    /// Compact `command|footer` storage form, each side comma-separated raw values.
    var encoded: String {
        let top = commandBar.map(\.rawValue).joined(separator: ",")
        let bottom = footer.map(\.rawValue).joined(separator: ",")
        return "\(top)|\(bottom)"
    }

    /// Decodes a stored layout string, repairing malformed or duplicate state. Returns `nil` only
    /// for empty input so callers can fall back to legacy migration.
    static func decode(_ raw: String) -> QuickToolsLayout? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let commandBar = kinds(from: parts.first.map(String.init) ?? "")
        let footer = parts.count > 1 ? kinds(from: String(parts[1])) : []
        return QuickToolsLayout(commandBar: commandBar, footer: footer)
    }

    /// Resolves the effective layout from the new shared storage value, falling back to a one-time
    /// read migration of the legacy `footerQuickToolOrder` value when the new key is absent.
    static func resolved(storageRaw: String, legacyFooterRaw: String) -> QuickToolsLayout {
        if let decoded = decode(storageRaw) {
            return decoded
        }
        let legacyFooter = kinds(from: legacyFooterRaw)
        guard !legacyFooter.isEmpty else {
            return .default
        }
        return migrated(fromLegacyFooter: legacyFooter)
    }

    /// Migration path: keep the four legacy footer selections in the footer and place the
    /// remaining three tools on the command bar.
    static func migrated(fromLegacyFooter legacyFooter: [FooterActionKind]) -> QuickToolsLayout {
        let footer = legacyFooter.filter { $0 != .proxyOverride }
        let commandBar = FooterActionKind.customizableQuickTools.filter { !footer.contains($0) }
        return QuickToolsLayout(commandBar: commandBar, footer: footer)
    }

    // MARK: Mutation

    func tools(in region: Region) -> [FooterActionKind] {
        region == .commandBar ? commandBar : footer
    }

    /// Assigns `tool` to the given slot. If `tool` already lives elsewhere, the two slots swap so
    /// every tool stays assigned exactly once.
    func assigning(_ tool: FooterActionKind, to region: Region, slot: Int) -> QuickToolsLayout {
        var updated = self
        guard updated.slots(for: region).indices.contains(slot) else {
            return updated
        }

        let current = updated.slots(for: region)[slot]
        guard current != tool else {
            return updated
        }

        if let location = updated.location(of: tool) {
            updated.setSlot(location.region, location.slot, to: current)
        }
        updated.setSlot(region, slot, to: tool)
        return updated
    }

    // MARK: Private

    private static func kinds(from raw: String) -> [FooterActionKind] {
        raw.split(separator: ",").compactMap {
            FooterActionKind(rawValue: String($0).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func slots(for region: Region) -> [FooterActionKind] {
        region == .commandBar ? commandBar : footer
    }

    private mutating func setSlot(_ region: Region, _ slot: Int, to tool: FooterActionKind) {
        if region == .commandBar {
            commandBar[slot] = tool
        } else {
            footer[slot] = tool
        }
    }

    private func location(of tool: FooterActionKind) -> (region: Region, slot: Int)? {
        if let index = commandBar.firstIndex(of: tool) {
            return (.commandBar, index)
        }
        if let index = footer.firstIndex(of: tool) {
            return (.footer, index)
        }
        return nil
    }
}

// MARK: - QuickToolsResponsivePolicy

/// Pure policy for how many command-bar capsules stay visible as the center workspace narrows.
/// The command bar shows the largest fitting count and never degrades to icon-only controls;
/// hidden tools stay reachable through the Traffic Actions submenu.
enum QuickToolsResponsivePolicy {
    /// Candidate visible-capsule counts, largest first: three when wide, two when medium, none
    /// when narrow.
    static let candidateCommandBarCounts = [3, 2, 0]

    /// The largest candidate count whose row fits, per the supplied fit predicate.
    static func visibleCommandBarCount(fitting fits: (Int) -> Bool) -> Int {
        candidateCommandBarCounts.first(where: fits) ?? 0
    }
}

// MARK: - QuickToolsEditor

/// One reusable editor for the shared Quick Tools layout, with Command Bar and Footer sections.
/// Choosing a tool already assigned elsewhere swaps the two slots; Reset restores approved defaults.
/// Opened from the footer ellipsis and from the Traffic Actions menu — both write the same key.
struct QuickToolsEditor: View {
    // MARK: Lifecycle

    init(
        layout: QuickToolsLayout,
        onSave: @escaping (QuickToolsLayout) -> Void,
        onReset: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        _layout = State(initialValue: layout)
        self.onSave = onSave
        self.onReset = onReset
        self.onDone = onDone
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Customize Quick Tools"))
                .font(.headline)

            section(
                title: String(localized: "Command Bar"),
                region: .commandBar,
                identifierPrefix: "commandBarQuickTools"
            )
            section(
                title: String(localized: "Footer"),
                region: .footer,
                identifierPrefix: "footerQuickTools"
            )

            Divider()

            HStack {
                Button(String(localized: "Reset Defaults")) {
                    layout = .default
                    onReset()
                }
                Spacer()
                Button(String(localized: "Done")) {
                    onSave(layout)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle()
            }
        }
        .padding(16)
        .frame(width: 288)
        .onChange(of: layout) { _, value in onSave(value) }
    }

    // MARK: Private

    @State private var layout: QuickToolsLayout

    private let onSave: (QuickToolsLayout) -> Void
    private let onReset: () -> Void
    private let onDone: () -> Void

    private func section(
        title: String,
        region: QuickToolsLayout.Region,
        identifierPrefix: String
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            let tools = layout.tools(in: region)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(tools.indices, id: \.self) { index in
                    GridRow {
                        Text(String(localized: "Slot \(index + 1)"))
                            .frame(width: 44, alignment: .leading)
                        slotMenu(
                            region: region,
                            slot: index,
                            identifier: "\(identifierPrefix).slot\(index + 1)"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slotMenu(
        region: QuickToolsLayout.Region,
        slot: Int,
        identifier: String
    )
        -> some View
    {
        let current = layout.tools(in: region)[slot]
        return Menu {
            ForEach(FooterActionKind.customizableQuickTools, id: \.self) { kind in
                Button {
                    layout = layout.assigning(kind, to: region, slot: slot)
                } label: {
                    if kind == current {
                        Label(Self.title(for: kind), systemImage: "checkmark")
                    } else {
                        Text(Self.title(for: kind))
                    }
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                HStack(spacing: 8) {
                    Text(Self.title(for: current))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 180, height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .frame(width: 180, height: 24, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(Self.title(for: current))
        .accessibilityIdentifier(identifier)
    }

    private static func title(for kind: FooterActionKind) -> String {
        FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            quickTools: [kind]
        ).first?.title ?? kind.rawValue
    }
}
