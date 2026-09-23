import SwiftUI

// MARK: - AssistantConversationHistoryView

/// Searchable history of the workspace's assistant conversations, shown from the dock header.
/// Rename and delete are surfaced here but confirmed by the dock, which owns the alerts.
struct AssistantConversationHistoryView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    @Binding var isPresented: Bool
    @Binding var conversationBeingRenamed: DebugAssistantConversation?
    @Binding var conversationRenameDraft: String
    @Binding var conversationPendingDeletion: DebugAssistantConversation?

    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Conversations", bundle: RockxyLocalization.bundle))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))

            searchField

            if filteredConversations.isEmpty {
                ContentUnavailableView {
                    Label(
                        conversationSearch.isEmpty
                            ? String(localized: "No Conversations", bundle: RockxyLocalization.bundle)
                            : String(localized: "No Results", bundle: RockxyLocalization.bundle),
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

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var conversationSearch = ""

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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Search titles and messages", bundle: RockxyLocalization.bundle),
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
    }

    private func conversationHistoryRow(_ conversation: DebugAssistantConversation) -> some View {
        Button {
            coordinator.selectDebugAssistantConversation(conversation.id)
            isPresented = false
            onSelect()
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
                    conversation.isPinned ? String(localized: "Unpin", bundle: RockxyLocalization.bundle) : String(
                        localized: "Pin",
                        bundle: RockxyLocalization.bundle
                    ),
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                conversationBeingRenamed = conversation
                conversationRenameDraft = conversation.title
            } label: {
                Label(String(localized: "Rename", bundle: RockxyLocalization.bundle), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                conversationPendingDeletion = conversation
            } label: {
                Label(String(localized: "Delete", bundle: RockxyLocalization.bundle), systemImage: "trash")
            }
        }
        .accessibilityLabel("\(conversation.title), \(conversation.preview)")
    }

    private func relativeDateLabel(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 {
            return String(localized: "Now", bundle: RockxyLocalization.bundle)
        }
        if interval < 3_600 {
            return String(localized: "\(Int(interval / 60))m", bundle: RockxyLocalization.bundle)
        }
        if Calendar.current.isDateInToday(date) {
            return TimestampFormatter.string(date, date: .omitted, time: .shortened)
        }
        return TimestampFormatter.weekday(date)
    }
}
