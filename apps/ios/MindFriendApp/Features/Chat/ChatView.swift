import SwiftUI
import OSLog

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let conversation: Conversation

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var showQuotaWarning = false
    @State private var displayTitle: String = "Chat"
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private let quotaWarningThreshold = 3

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isSending {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            // Quota warning - tappable to show paywall
            if showQuotaWarning {
                QuotaWarningBanner(remaining: appState.entitlements.remaining) {
                    appState.showPaywall = true
                }
            }

            Divider()

            // Input
            ChatInputBar(
                text: $inputText,
                isSending: isSending,
                onSend: sendMessage
            )
            .focused($isInputFocused)
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayTitle = conversation.title ?? "Chat"
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    VoiceChatView(supabase: container.supabaseClient) {
                        isInputFocused = true
                    }
                } label: {
                    Image(systemName: "mic.fill")
                }
                .accessibilityLabel("Voice mode")
                .accessibilityHint("Start a voice conversation")

                Button {
                    appState.showCrisisResources = true
                } label: {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Get crisis help")
                .accessibilityHint("Opens crisis resources and hotlines")
            }
        }
        .task {
            await loadMessages()
        }
        .onDisappear {
            // Cancel any in-flight send task when view disappears
            sendTask?.cancel()
        }
    }

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            messages = try await container.chatService.getMessages(
                conversationId: conversation.id
            )
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        // Check quota
        if appState.entitlements.isQuotaExceeded {
            appState.showPaywall = true
            return
        }

        // Create optimistic user message
        let tempMessageId = UUID().uuidString
        let tempUserMessage = Message(
            id: tempMessageId,
            role: .user,
            content: content,
            createdAt: Date(),
            blocked: false
        )

        // Add user message immediately (optimistic UI)
        messages.append(tempUserMessage)
        inputText = ""
        isSending = true

        // Store task reference for cancellation on view disappear
        sendTask = Task {
            defer { isSending = false }

            do {
                // Check for cancellation before making network call
                try Task.checkCancellation()

                let response = try await container.chatService.sendMessage(
                    conversationId: conversation.id,
                    content: content
                )

                // Check for cancellation after network call
                try Task.checkCancellation()

                // Use removeAll(where:) for atomic removal (prevents race condition)
                messages.removeAll { $0.id == tempMessageId }
                messages.append(response.userMessage)
                messages.append(response.assistantMessage)

                // Update quota tracking from server (authoritative source)
                if appState.entitlements.tier != .premium, let serverUsed = response.quotaUsed {
                    // Sync from server-provided value (not local increment)
                    appState.entitlements.dailyAiUsed = serverUsed
                    // Only show warning if not unlimited (Int.max) and near limit
                    showQuotaWarning = response.quotaRemaining < Int.max && response.quotaRemaining <= quotaWarningThreshold
                } else {
                    showQuotaWarning = false
                }

                // Update title if generated
                if let newTitle = response.conversationTitle {
                    displayTitle = newTitle
                }

                // Show crisis resources after a brief delay
                if response.crisisDetected == true {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        appState.showCrisisResources = true
                    }
                }
            } catch is CancellationError {
                // Task was cancelled, clean up optimistic message
                messages.removeAll { $0.id == tempMessageId }
            } catch let error as APIError {
                if case .quotaExceeded = error {
                    appState.showPaywall = true
                } else {
                    appState.showError(.apiError(error.localizedDescription))
                }
                // Keep the user message visible on error so user can see what they typed
            } catch {
                appState.showError(.apiError(error.localizedDescription))
                // Keep the user message visible on error
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var isUser: Bool { message.role == .user }

    private var accessibilityLabel: String {
        let sender = isUser ? "You said" : "MindFriend said"
        let time = message.createdAt.formatted(date: .omitted, time: .shortened)
        return "\(sender): \(message.content). Sent at \(time)"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(20)

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("MindFriend is typing")

            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
                .submitLabel(.send)
                .onSubmit {
                    if canSend {
                        onSend()
                    }
                }
                .accessibilityLabel("Message input")
                .accessibilityHint("Type your message here")

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityHint(canSend ? "Sends your message" : "Type a message first")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct QuotaWarningBanner: View {
    let remaining: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("Only \(remaining) message\(remaining == 1 ? "" : "s") left today")
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Only \(remaining) message\(remaining == 1 ? "" : "s") left today. Tap to upgrade.")
        .accessibilityHint("Opens subscription options")
    }
}

struct NewChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var conversation: Conversation?
    @State private var errorMessage: String?
    @State private var isRetrying = false

    var body: some View {
        Group {
            if let conversation = conversation {
                ChatView(conversation: conversation)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Couldn't start conversation")
                        .font(.headline)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        isRetrying = true
                        errorMessage = nil
                        Task {
                            await createChat()
                        }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)
                }
                .padding()
            } else {
                ProgressView("Starting conversation...")
            }
        }
        .task {
            await createChat()
        }
    }

    private func createChat() async {
        do {
            // Debug: Check if authenticated
            guard container.supabaseAuthService.userId != nil else {
                Log.chat.warning("User not authenticated when creating chat")
                errorMessage = "Please sign in to start a chat"
                return
            }

            conversation = try await container.chatService.createConversation()
        } catch {
            Log.chat.error("Error creating conversation: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isRetrying = false
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: Conversation(
            id: "1",
            title: "Test Chat",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
