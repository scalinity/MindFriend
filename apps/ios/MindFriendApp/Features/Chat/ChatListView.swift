import SwiftUI
import OSLog

struct ChatListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @State private var linkedConversation: Conversation?
    @State private var linkedRequest: DeepLinkRouter.Request?
    @State private var showLinkedConversation = false

    private struct LinkTaskID: Hashable {
        let requestID: UUID
        let userID: UUID?
        let ready: Bool
    }

    private var linkTaskID: LinkTaskID {
        LinkTaskID(requestID: deepLinkRouter.requestID, userID: appState.currentUser?.id,
                   ready: appState.selectedTab == .chat && appState.authState == .authenticated && appState.sessionRestored &&
                          !showNewChat && !showVoiceChat && !showChatTutorial)
    }
    @State private var conversations: [Conversation] = []
    @State private var nextCursor: SupportConversationCursor?
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var loadGeneration = UUID()
    @State private var isLoading = true
    @State private var showNewChat = false
    @State private var newChatRequestID = UUID()
    @State private var showVoiceChat = false
    @State private var voiceAccess: SessionVoiceAccess?
    @State private var voiceTextID: UUID?
    @State private var voiceTextConversation: Conversation?
    @State private var showVoiceText = false
    @State private var loadError: String?
    @State private var pageError: String?
    @State private var refreshTrigger = UUID() // Changes to trigger refresh

    // Chat tutorial state
    @State private var showChatTutorial = false

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
                        if let pageError { Text(pageError).font(.caption).foregroundStyle(.secondary) }
                        if hasMore {
                            Button("Load older conversations") { Task { await loadConversations(more: true) } }
                                .disabled(loadingMore)
                                .accessibilityIdentifier("chat-load-older-conversations")
                        }
                        if loadingMore { ProgressView("Loading older conversations") }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chat")
            .safeAreaInset(edge: .bottom) {
                if let coordinator = container.supportSessionCoordinator {
                    SupportVoiceRecoveryLink(coordinator: coordinator)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.red)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Support and crisis resources")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showChatTutorial = true } label: {
                        Image(systemName: "questionmark.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("How Chat works")
                    Button {
                        if appState.entitlements.tier == .premium {
                            voiceAccess = SessionVoiceAccess(container: container, appState: appState)
                            showVoiceChat = true
                        } else {
                            appState.showPaywall = true
                        }
                    } label: {
                        Image(systemName: "mic.fill").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Voice mode")
                    .accessibilityHint(appState.entitlements.tier == .premium ? "Start a voice conversation" : "Premium feature - tap to upgrade")

                    Button {
                        newChatRequestID = UUID()
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("New conversation")
                }
            }
            .navigationDestination(isPresented: $showNewChat, destination: {
                NewChatView().id(newChatRequestID)
            })
            .navigationDestination(isPresented: $showLinkedConversation) {
                if let conversation = linkedConversation, let request = linkedRequest {
                    ChatView(conversation: conversation)
                        .id(request.id)
                }
            }
            .navigationDestination(isPresented: $showVoiceText) {
                if let voiceTextConversation {
                    ChatView(conversation: voiceTextConversation, supportSessionID: voiceAccess?.selectedSessionID)
                }
            }
            .fullScreenCover(isPresented: $showVoiceChat, onDismiss: {
                let owner = appState.currentUser?.id, epoch = appState.accountEpoch, id = voiceTextID
                voiceTextID = nil
                Task {
                    await loadConversations()
                    if let id, let value = try? await container.supabaseDataService.getConversation(id: id.uuidString),
                       appState.currentUser?.id == owner, appState.accountEpoch == epoch {
                        voiceTextConversation = value
                        showVoiceText = true
                    }
                }
            }) {
                VoiceChatView(supabase: container.supabaseClient, supportAccess: voiceAccess,
                    onUseText: { voiceTextID = voiceAccess?.attachedConversationID })
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
        .task(id: linkTaskID) { await openLinkedConversation() }
        .onChange(of: showLinkedConversation) { _, isShowing in
            if !isShowing, let request = linkedRequest {
                deepLinkRouter.dismiss(request)
                linkedConversation = nil
                linkedRequest = nil
            }
        }
        // Trigger refresh when returning from new chat
        .onChange(of: showNewChat) { _, isShowing in
            if !isShowing {
                Log.chat.debug("[ChatList] Returned from new chat, triggering refresh")
                refreshTrigger = UUID()
            }
        }
        // Handle SOS-initiated chat - automatically open new chat
        .onAppear {
            // Regular-width roots are created when first selected, after the entry request was set.
            if appState.shouldOpenNewChat { newChatRequestID = UUID(); showNewChat = true; appState.shouldOpenNewChat = false }
        }
        .onChange(of: appState.shouldOpenNewChat) { _, shouldOpen in
            if shouldOpen {
                newChatRequestID = UUID()
                showNewChat = true
                appState.shouldOpenNewChat = false
            }
        }
        .fullScreenCover(isPresented: $showChatTutorial) {
            ChatTutorialFlow(onComplete: {
                showChatTutorial = false
            })
            .environmentObject(container)
        }
    }

    private func openLinkedConversation() async {
        if deepLinkRouter.requestID != linkedRequest?.id {
            showLinkedConversation = false
            linkedConversation = nil
            linkedRequest = nil
        }
        guard linkTaskID.ready,
              let userID = appState.currentUser?.id,
              container.supabaseAuthService.userId == userID,
              let request = deepLinkRouter.requestForPresentation(isAuthenticated: true),
              case .chat(let id?) = request.route else { return }
        do {
            let conversation = try await container.supabaseDataService.getConversation(id: id)
            try Task.checkCancellation()
            guard deepLinkRouter.requestID == request.id, appState.currentUser?.id == userID,
                  container.supabaseAuthService.userId == userID, appState.authState == .authenticated else { return }
            guard let conversation else { throw DeepLinkRouter.DestinationError.unavailable }
            linkedConversation = conversation
            linkedRequest = request
            showLinkedConversation = true
            deepLinkRouter.consume(request)
        } catch {
            guard !Task.isCancelled, deepLinkRouter.requestID == request.id,
                  appState.currentUser?.id == userID, container.supabaseAuthService.userId == userID,
                  appState.authState == .authenticated else { return }
            deepLinkRouter.consume(request)
            let message = DeepLinkRouter.destinationError(for: error)?.errorDescription
                ?? "Couldn't load this conversation. Check your connection and try the link again."
            appState.showError(.apiError(message))
        }
    }

    private func loadConversations(more: Bool = false) async {
        guard !more || !loadingMore else { return }
        guard let id = appState.currentUser?.id else { isLoading = false; return }
        let owner = OfflineOwnerProof(userId: id, epoch: appState.accountEpoch)
        let generation = more ? loadGeneration : UUID()
        if !more { loadGeneration = generation }
        let cursor = more ? nextCursor : nil
        if more { loadingMore = true } else if conversations.isEmpty { isLoading = true }
        if more { pageError = nil } else { loadError = nil; pageError = nil }
        let proof: @Sendable () async -> OfflineOwnerProof? = { await MainActor.run {
            guard appState.currentUser?.id == id, appState.accountEpoch == owner.epoch else { return nil }
            return owner
        } }
        defer {
            if loadGeneration == generation { isLoading = false; loadingMore = false }
        }
        do {
            let page = try await container.supabaseDataService.getConversationPage(owner: owner, cursor: cursor, ownerProof: proof)
            guard !Task.isCancelled, await proof() == owner, loadGeneration == generation else { return }
            if !more { conversations = [] }
            for item in page.items {
                if let index = conversations.firstIndex(where: { $0.id == item.id }) { conversations[index] = item }
                else { conversations.append(item) }
            }
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch is CancellationError { }
        catch {
            guard await proof() == owner, loadGeneration == generation else { return }
            if more { pageError = "Couldn't load older conversations. Try again." }
            else { loadError = "Conversations could not be loaded. Your local drafts and practices remain available." }
        }
    }

    private enum ChatLoadError: Error {
        case timeout
        case cancelled
    }

    private func deleteConversations(at offsets: IndexSet) {
        let conversationsToDelete = offsets.map { conversations[$0] }
        let owner = appState.currentUser?.id, epoch = appState.accountEpoch
        let coordinator = container.supportSessionCoordinator

        // Optimistic UI update
        conversations.remove(atOffsets: offsets)

        // Delete from server
        Task {
            for conversation in conversationsToDelete {
                guard appState.currentUser?.id == owner, appState.accountEpoch == epoch else { return }
                do {
                    try await container.chatService.deleteConversation(id: conversation.id)
                    guard appState.currentUser?.id == owner, appState.accountEpoch == epoch else { return }
                    if let coordinator, coordinator.identity.ownerID == owner,
                       let id = UUID(uuidString: conversation.id) {
                        do {
                            try await coordinator.repository.discardConversationTranscripts(epoch: coordinator.identity.epochID, conversationID: id)
                        } catch {
                            appState.showError(.apiError("The conversation was deleted. Its local voice copies remain under Voice turns on this device, where you can copy or remove them."))
                        }
                    }
                } catch {
                    guard appState.currentUser?.id == owner, appState.accountEpoch == epoch else { return }
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

                Group {
                    if conversation.dateIsKnown != false { Text(conversation.updatedAt, style: .relative) }
                    else { Text("Date not supplied") }
                }.font(.caption)
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
        .environmentObject(DeepLinkRouter.shared)
}
