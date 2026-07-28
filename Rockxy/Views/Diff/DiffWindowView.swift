import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Diff workspace window — 4-zone layout: header, candidate pool card,
/// diff viewer, and control bar. Supports Request/Response/Timing comparison
/// in Side by Side or Unified mode. Comparison is local and read-only.
struct DiffWindowView: View {
    // MARK: Internal

    @State var viewModel = DiffViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.workspaceMode == .captured {
                DiffCandidateTableView(viewModel: viewModel)
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 230)
                Divider()
            }
            DiffViewerView(viewModel: viewModel)
            Divider()
            DiffControlBar(viewModel: viewModel)
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 32 + 484),
            idealWidth: max(1_240, toolMetrics.bodyFontSize * 42 + 694),
            minHeight: max(600, min(780, toolMetrics.bodyFontSize * 18 + 366)),
            idealHeight: max(820, toolMetrics.bodyFontSize * 24 + 508)
        )
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.swapSides()
                } label: {
                    Label(String(localized: "Swap Sides"), systemImage: "arrow.left.arrow.right")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!viewModel.canSwapSides)
                .help(String(localized: "Swap the left and right sides"))

                Button {
                    exportDiff()
                } label: {
                    Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)
                .help(String(localized: "Export the comparison as a text file"))
            }
        }
        .alert(
            String(localized: "Export Failed"),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: {
                    if !$0 {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { exportErrorMessage = nil }
        } message: {
            if let exportErrorMessage {
                Text(exportErrorMessage)
            }
        }
        .onAppear {
            viewModel.consumeFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDiffWindow)) { _ in
            viewModel.consumeFromStore()
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @State private var exportErrorMessage: String?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var canExport: Bool {
        guard !viewModel.isComparing, !viewModel.activeDiffResult.sections.isEmpty else {
            return false
        }
        return viewModel.workspaceState == .ready || viewModel.workspaceState == .textReady
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Basic Compare"))
                    .font(toolMetrics.font(weight: .semibold))
                Text(
                    String(
                        localized: "Compare captured transactions or pasted text without modifying live traffic."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: toolMetrics.controlSpacing)

            comparisonSourcePicker

            contextBadge
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    private var contextBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: toolMetrics.smallIconFontSize))
                .accessibilityHidden(true)
            Text(String(localized: "Local · Read-only"))
        }
        .font(toolMetrics.metadataFont(weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .help(String(localized: "Comparison runs on your captured transactions and never modifies live traffic."))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Local, read-only comparison"))
    }

    @ViewBuilder private var comparisonSourcePicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(String(localized: "Comparison Source"), selection: $viewModel.workspaceMode) {
                ForEach(DiffViewModel.WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 150)
            .accessibilityLabel(String(localized: "Comparison source"))
        } else {
            Picker(String(localized: "Comparison Source"), selection: $viewModel.workspaceMode) {
                ForEach(DiffViewModel.WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: max(200, toolMetrics.secondaryFontSize * 10 + 92))
            .accessibilityLabel(String(localized: "Comparison source"))
        }
    }

    private func exportDiff() {
        let result = viewModel.activeDiffResult
        guard !result.sections.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Diff")
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "diff.txt"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try DiffExportFormatter.write(result, to: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - DiffExportFormatter

enum DiffExportFormatter {
    static func text(for result: DiffResult) -> String {
        var output = ""
        for section in result.sections {
            output += "--- \(section.title) ---\n"
            for line in section.lines {
                switch line.type {
                case .unchanged: output += "  \(line.content)\n"
                case .added: output += "+ \(line.content)\n"
                case .removed: output += "- \(line.content)\n"
                }
            }
            output += "\n"
        }
        return output
    }

    static func write(_ result: DiffResult, to url: URL) throws {
        try text(for: result).write(to: url, atomically: true, encoding: .utf8)
    }
}
