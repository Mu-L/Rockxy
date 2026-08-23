import SwiftUI

// Renders the toast interface for shared app surfaces.

// MARK: - ToastView

/// Transient bottom-anchored notification overlay. Shows a success checkmark or error X
/// icon alongside a message, then auto-dismisses after 3 seconds with a slide animation.
struct ToastView: View {
    // MARK: Internal

    let message: ToastMessage
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
        }
        .padding(.horizontal, Theme.Glass.toastHorizontalPadding)
        .padding(.vertical, Theme.Glass.toastVerticalPadding)
        .rockxyGlassEffect(
            in: RoundedRectangle(cornerRadius: Theme.Glass.toastCornerRadius, style: .continuous)
        )
        .shadow(
            color: .black.opacity(Theme.Glass.toastShadowOpacity),
            radius: Theme.Glass.toastShadowRadius,
            y: Theme.Glass.toastShadowY
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else {
                    return
                }
                onDismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: Private

    @State private var dismissTask: Task<Void, Never>?

    private var iconName: String {
        switch message.style {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch message.style {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
