import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var showNewChat = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if conversations.isEmpty {
                    EmptyConversationsView(showNewChat: $showNewChat)
                } else {
                    List(conversations) { conversation in
                        NavigationLink {
                            ChatView(conversation: conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.red)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(isPresented: $showNewChat) {
                NewChatView()
            }
            .refreshable {
                await loadConversations()
            }
            .task {
                await loadConversations()
            }
        }
    }

    private func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await container.chatService.getConversations()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.title ?? "New Conversation")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastMessage = conversation.lastMessage {
                Text(lastMessage.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyConversationsView: View {
    @Binding var showNewChat: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No conversations yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start a conversation with your AI wellness companion")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showNewChat = true
            } label: {
                Label("Start Chat", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ChatListView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
