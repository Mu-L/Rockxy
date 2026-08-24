import AppKit
import SwiftUI

// MARK: - UtilitySegmentedHeader

struct UtilitySegmentedHeader<Content: View>: View {
    let width: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: width)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - WorkspaceModeSegment

/// One icon-first mode in the native navigator and inspector switchers used by Xcode.
struct WorkspaceModeSegment<Value: Hashable> {
    let value: Value
    let title: String
    let systemImage: String
}

// MARK: - WorkspaceModeSegmentedControl

/// A native equal-width `NSSegmentedControl`. SwiftUI's segmented `Picker` keeps its intrinsic
/// icon width on macOS, while Xcode's navigator and inspector switchers fill their available bar.
struct WorkspaceModeSegmentedControl<Value: Hashable>: NSViewRepresentable {
    // MARK: Lifecycle

    init(
        selection: Binding<Value>,
        segments: [WorkspaceModeSegment<Value>],
        accessibilityLabel: String
    ) {
        _selection = selection
        self.segments = segments
        self.accessibilityLabel = accessibilityLabel
    }

    // MARK: Internal

    @Binding var selection: Value
    let segments: [WorkspaceModeSegment<Value>]
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, segments: segments)
    }

    func makeNSView(context: Context) -> EqualWidthSegmentedControl {
        let control = EqualWidthSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .capsule
        control.controlSize = .regular
        control.selectedSegmentBezelColor = .controlAccentColor
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        update(control, coordinator: context.coordinator)
        return control
    }

    func updateNSView(_ control: EqualWidthSegmentedControl, context: Context) {
        update(control, coordinator: context.coordinator)
    }

    // MARK: Private

    private func update(_ control: EqualWidthSegmentedControl, coordinator: Coordinator) {
        coordinator.selection = $selection
        coordinator.segments = segments

        if control.segmentCount != segments.count {
            control.segmentCount = segments.count
        }

        for (index, segment) in segments.enumerated() {
            let image = NSImage(
                systemSymbolName: segment.systemImage,
                accessibilityDescription: segment.title
            )
            image?.isTemplate = true
            control.setLabel("", forSegment: index)
            control.setImage(image, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(segment.title, forSegment: index)
            control.setEnabled(true, forSegment: index)
        }

        control.selectedSegment = segments.firstIndex { $0.value == selection } ?? -1
        control.setAccessibilityLabel(accessibilityLabel)
        control.needsLayout = true
    }

    final class Coordinator: NSObject {
        // MARK: Lifecycle

        init(selection: Binding<Value>, segments: [WorkspaceModeSegment<Value>]) {
            self.selection = selection
            self.segments = segments
        }

        // MARK: Internal

        var selection: Binding<Value>
        var segments: [WorkspaceModeSegment<Value>]

        @objc
        func selectionChanged(_ sender: NSSegmentedControl) {
            guard segments.indices.contains(sender.selectedSegment) else {
                return
            }
            selection.wrappedValue = segments[sender.selectedSegment].value
        }
    }
}

// MARK: - EqualWidthSegmentedControl

final class EqualWidthSegmentedControl: NSSegmentedControl {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = NSView.noIntrinsicMetric
        return size
    }

    override func layout() {
        super.layout()
        guard segmentCount > 0, bounds.width > 0 else {
            return
        }
        let segmentWidth = bounds.width / CGFloat(segmentCount)
        for index in 0 ..< segmentCount where abs(width(forSegment: index) - segmentWidth) > 0.5 {
            setWidth(segmentWidth, forSegment: index)
        }
    }
}

// MARK: - WorkspaceModeSwitcherStyle

extension View {
    /// Shared native presentation for the primary mode switchers in the workspace sidebar
    /// and Context Dock.
    func workspaceModeSwitcherStyle() -> some View {
        modifier(WorkspaceModeSwitcherModifier())
    }
}

private struct WorkspaceModeSwitcherModifier: ViewModifier {
    @Environment(\.appUIDisplayMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .font(.system(size: metrics.workspaceTabFontSize, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: metrics.inspectorTabHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}
