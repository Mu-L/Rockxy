import SwiftUI

/// Editable Notes tab for annotating individual HTTP transactions. Routes edits through the
/// coordinator's note seam so whitespace is normalized, the Library's Notes collection stays in sync,
/// and persistence is debounced rather than rewriting the transaction row on every keystroke.
struct CommentsTabView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let transaction: HTTPTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $commentText)
                .font(.system(size: metrics.primaryFontSize))
                .scrollContentBackground(.hidden)
                .padding(8)
                .accessibilityLabel(String(localized: "Request note", bundle: RockxyLocalization.bundle))

            Divider()

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: saveNote) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!isDirty)
                .help(String(localized: "Save Note", bundle: RockxyLocalization.bundle))
                .accessibilityLabel(String(localized: "Save Note", bundle: RockxyLocalization.bundle))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .onAppear {
            commentText = transaction.comment ?? ""
            lastExplicitlySavedNote = MainContentCoordinator.normalizedNote(commentText)
        }
        .onChange(of: commentText) { _, newValue in
            coordinator.updateNoteDraft(newValue, for: transaction)
        }
        .onDisappear {
            coordinator.flushNotePersistence(for: transaction)
        }
    }

    // MARK: Private

    @State private var commentText: String = ""
    @State private var lastExplicitlySavedNote: String?
    @Environment(\.appUIDisplayMetrics) private var metrics

    /// Tracks changes since the user's last explicit save. Inline editing still keeps the existing
    /// debounce and selection-change safety, while this state gives the Save action a stable lifecycle
    /// even though the coordinator updates the in-memory transaction immediately.
    private var isDirty: Bool {
        MainContentCoordinator.normalizedNote(commentText) != lastExplicitlySavedNote
    }

    /// Commits the current draft immediately, cancelling the debounced write so the note is
    /// persisted right away instead of waiting on the autosave timer.
    private func saveNote() {
        coordinator.setNote(commentText, for: transaction)
        lastExplicitlySavedNote = MainContentCoordinator.normalizedNote(commentText)
    }
}
