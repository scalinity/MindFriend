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
                    VStack(spacing: SupportTheme.Spacing.m) {
                        ProgressView()
                        Text("Loading conversations...")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                } else if let error = loadError {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Text("Couldn't load conversations")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try Again") {
                            Task {
                                await loadConversations()
                            }
                        }
                        .buttonStyle(.supportPrimary)
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
                            .listRowBackground(SupportTheme.surface)
                        }
                        .onDelete(perform: deleteConversations)
                        if let pageError { Text(pageError).font(.caption).foregroundStyle(SupportTheme.textSecondary) }
                        if hasMore {
                            Button("Load older conversations") { Task { await loadConversations(more: true) } }
                                .disabled(loadingMore)
                                .accessibilityIdentifier("chat-load-older-conversations")
                        }
                        if loadingMore { ProgressView("Loading older conversations") }
                    }
                    .listRowBackground(SupportTheme.surface)
                    .listStyle(.plain)
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
                        Image(systemName: "lifepreserver")
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .accessibilityLabel("Support and crisis resources")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showChatTutorial = true } label: {
                        Image(systemName: "questionmark.circle").frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
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
                        Image(systemName: "mic.fill").frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .accessibilityLabel("Voice mode")
                    .accessibilityHint(appState.entitlements.tier == .premium ? "Start a voice conversation" : "Premium feature - tap to upgrade")

                    Button {
                        newChatRequestID = UUID()
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil").frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.s))) {
                Text(conversation.title ?? "New Conversation")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Group {
                    if conversation.dateIsKnown != false { Text(conversation.updatedAt, style: .relative) }
                    else { Text("Date not supplied") }
                }.font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            if let lastMessage = conversation.lastMessage {
                Text(lastMessage.content)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }
}

struct EmptyConversationsView: View {
    @Binding var showNewChat: Bool

    var body: some View {
        // Centered when it fits; scrollable at large text sizes instead of truncating.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.vertical, SupportTheme.Spacing.l)
                    .frame(minHeight: proxy.size.height)
            }
        }
    }

    private var content: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text("No conversations yet")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Start a conversation with your AI wellness companion")
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showNewChat = true
            } label: {
                Label("Start Chat", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.onAccent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.vertical, SupportTheme.Spacing.s)
            }
            .buttonStyle(.supportPrimary)
            .tint(SupportTheme.accent)
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ChatListView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
        .environmentObject(DeepLinkRouter.shared)
}
