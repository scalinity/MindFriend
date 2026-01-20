import SwiftUI
import OSLog

struct ChatListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var showNewChat = false
    @State private var showVoiceChat = false
    @State private var loadError: String?
    @State private var refreshTrigger = UUID() // Changes to trigger refresh

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading conversations...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Couldn't load conversations")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try Again") {
                            Task {
                                await loadConversations()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if conversations.isEmpty {
                    EmptyConversationsView(showNewChat: $showNewChat)
                        .onAppear {
                            // Also refresh here in case a conversation was just created
                            refreshTrigger = UUID()
                        }
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            NavigationLink {
                                ChatView(conversation: conversation)
                            } label: {
                                ConversationRow(conversation: conversation)
                            }
                        }
                        .onDelete(perform: deleteConversations)
                    }
                    .listStyle(.plain)
                    .onAppear {
                        // Refresh when returning from viewing a conversation
                        // This fires when the List becomes visible again after navigation
                        Log.chat.debug("[ChatList] List appeared, refreshing for updated titles")
                        refreshTrigger = UUID()
                    }
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

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showVoiceChat = true
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                    .accessibilityLabel("Voice mode")
                    .accessibilityHint("Start a voice conversation")

                    Button {
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(isPresented: $showNewChat, destination: {
                NewChatView()
            })
            .fullScreenCover(isPresented: $showVoiceChat, onDismiss: {
                Task {
                    await loadConversations()
                }
            }) {
                VoiceChatView(supabase: container.supabaseClient)
            }
            .refreshable {
                await loadConversations()
            }
        }
        // Load conversations when view appears or refreshTrigger changes
        .task(id: refreshTrigger) {
            Log.chat.debug("[ChatList] Task triggered, refreshing conversations")
            await loadConversations()
        }
        // Trigger refresh when returning from new chat
        .onChange(of: showNewChat) { _, isShowing in
            if !isShowing {
                Log.chat.debug("[ChatList] Returned from new chat, triggering refresh")
                refreshTrigger = UUID()
            }
        }
        // Handle SOS-initiated chat - automatically open new chat
        .onChange(of: appState.shouldOpenNewChat) { _, shouldOpen in
            if shouldOpen {
                showNewChat = true
                appState.shouldOpenNewChat = false
            }
        }
    }

    private func loadConversations() async {
        Log.chat.debug("[ChatList] Starting to load conversations...")

        // Only show loading indicator on initial load, not during refresh
        let isInitialLoad = conversations.isEmpty && loadError == nil
        if isInitialLoad {
            isLoading = true
        }
        loadError = nil

        defer {
            if isInitialLoad {
                isLoading = false
            }
            Log.chat.debug("[ChatList] Finished loading, isLoading=false")
        }

        do {
            // Check for cancellation before starting
            try Task.checkCancellation()

            // Add a timeout to prevent infinite waits
            let result = try await withThrowingTaskGroup(of: [Conversation].self) { group in
                group.addTask {
                    try await self.container.chatService.getConversations()
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw ChatLoadError.timeout
                }

                // Return whichever finishes first
                guard let first = try await group.next() else {
                    throw ChatLoadError.cancelled
                }
                group.cancelAll()
                return first
            }

            // Check for cancellation before updating UI
            try Task.checkCancellation()

            conversations = result
            Log.chat.debug("[ChatList] Loaded \(result.count) conversations")
        } catch is CancellationError {
            // SwiftUI cancelled the task (e.g., user released pull-to-refresh early)
            // This is normal behavior, not an error to show the user
            Log.chat.debug("[ChatList] Task was cancelled by SwiftUI")
        } catch ChatLoadError.timeout {
            Log.chat.error("[ChatList] Request timed out after 30s")
            loadError = "Request timed out. Please check your connection and try again."
        } catch ChatLoadError.cancelled {
            Log.chat.warning("[ChatList] Request was cancelled")
            // Don't show error for internal cancellation either
        } catch {
            Log.chat.error("[ChatList] Error loading conversations: \(error.localizedDescription)")
            loadError = error.localizedDescription
        }
    }

    private enum ChatLoadError: Error {
        case timeout
        case cancelled
    }

    private func deleteConversations(at offsets: IndexSet) {
        let conversationsToDelete = offsets.map { conversations[$0] }

        // Optimistic UI update
        conversations.remove(atOffsets: offsets)

        // Delete from server
        Task {
            for conversation in conversationsToDelete {
                do {
                    try await container.chatService.deleteConversation(id: conversation.id)
                } catch {
                    // Reload on error to restore state
                    await loadConversations()
                    appState.showError(.apiError(error.localizedDescription))
                    break
                }
            }
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
