import SwiftUI

/// Bottom control bar for the Diff workspace. Contains compare target picker,
/// presentation mode picker, and a localized difference summary.
struct DiffControlBar: View {
    // MARK: Internal

    @Bindable var viewModel: DiffViewModel

    var body: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            if viewModel.isTextMode {
                textAction
            } else {
                Text(String(localized: "Compare", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)

                compareTargetPicker
            }

            Spacer()

            Text(String(localized: "View", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            presentationModePicker

            differenceSummary
        }
        .font(toolMetrics.font())
        .frame(minHeight: toolMetrics.footerControlHeight)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var comparePickerWidth: CGFloat {
        max(250, toolMetrics.secondaryFontSize * 15 + 96)
    }

    private var presentationPickerWidth: CGFloat {
        max(260, toolMetrics.secondaryFontSize * 13 + 140)
    }

    private var differenceSummary: some View {
        let result = viewModel.activeDiffResult
        return HStack(spacing: toolMetrics.controlSpacing) {
            if viewModel.isComparing {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Comparing…", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            if result.addedCount > 0 {
                Label("+\(result.addedCount)", systemImage: "plus.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(Theme.Highlight.green)
                    .accessibilityLabel(String(
                        localized: "\(result.addedCount) added",
                        bundle: RockxyLocalization.bundle
                    ))
            }
            if result.removedCount > 0 {
                Label("-\(result.removedCount)", systemImage: "minus.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(Theme.Highlight.red)
                    .accessibilityLabel(String(
                        localized: "\(result.removedCount) removed",
                        bundle: RockxyLocalization.bundle
                    ))
            }
            Text("^[\(result.differenceCount) line change](inflect: true)")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var textAction: some View {
        if viewModel.isPresentingTextDiff {
            Button(String(localized: "Edit Text", bundle: RockxyLocalization.bundle)) {
                viewModel.editText()
            }
            .disabled(viewModel.isComparing)
        } else {
            Button(String(localized: "Compare Text", bundle: RockxyLocalization.bundle)) {
                viewModel.compareText()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(viewModel.isComparing || viewModel.textA.isEmpty && viewModel.textB.isEmpty)
        }
    }

    @ViewBuilder private var compareTargetPicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(
                String(localized: "Compare", bundle: RockxyLocalization.bundle),
                selection: $viewModel.compareTarget
            ) {
                ForEach(CompareTarget.allCases, id: \.self) { target in
                    Text(target.title).tag(target)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180)
            .accessibilityLabel(String(localized: "Comparison target", bundle: RockxyLocalization.bundle))
        } else {
            Picker(
                String(localized: "Compare", bundle: RockxyLocalization.bundle),
                selection: $viewModel.compareTarget
            ) {
                ForEach(CompareTarget.allCases, id: \.self) { target in
                    Text(target.title).tag(target)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: comparePickerWidth)
            .accessibilityLabel(String(localized: "Comparison target", bundle: RockxyLocalization.bundle))
        }
    }

    @ViewBuilder private var presentationModePicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(
                String(localized: "View", bundle: RockxyLocalization.bundle),
                selection: $viewModel.presentationMode
            ) {
                ForEach(PresentationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190)
            .accessibilityLabel(String(localized: "Presentation mode", bundle: RockxyLocalization.bundle))
            .disabled(viewModel.isTextMode && !viewModel.isPresentingTextDiff)
        } else {
            Picker(
                String(localized: "View", bundle: RockxyLocalization.bundle),
                selection: $viewModel.presentationMode
            ) {
                ForEach(PresentationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: presentationPickerWidth)
            .accessibilityLabel(String(localized: "Presentation mode", bundle: RockxyLocalization.bundle))
            .disabled(viewModel.isTextMode && !viewModel.isPresentingTextDiff)
        }
    }
}
