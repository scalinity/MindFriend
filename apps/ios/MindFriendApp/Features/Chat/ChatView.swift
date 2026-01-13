import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let conversation: Conversation

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var showQuotaWarning = false
    @FocusState private var isInputFocused: Bool

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

            // Quota warning
            if showQuotaWarning {
                QuotaWarningBanner(remaining: appState.entitlements.remaining)
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
        .navigationTitle(conversation.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.showCrisisResources = true
                } label: {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .task {
            await loadMessages()
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

        inputText = ""
        isSending = true

        Task {
            do {
                let response = try await container.chatService.sendMessage(
                    conversationId: conversation.id,
                    content: content
                )

                await MainActor.run {
                    messages.append(response.userMessage)
                    messages.append(response.assistantMessage)
                    appState.entitlements.dailyAiUsed += 1

                    showQuotaWarning = response.quotaRemaining <= 3

                    if response.crisisDetected == true {
                        // Show crisis resources
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            appState.showCrisisResources = true
                        }
                    }
                }
            } catch let error as APIError {
                if case .quotaExceeded = error {
                    appState.showPaywall = true
                } else {
                    appState.showError(.apiError(error.localizedDescription))
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }

            isSending = false
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var isUser: Bool { message.role == .user }

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

            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(text.isEmpty || isSending ? Color.secondary : Color.accentColor)
            }
            .disabled(text.isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct QuotaWarningBanner: View {
    let remaining: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("Only \(remaining) message\(remaining == 1 ? "" : "s") left today")
                .font(.caption)

            Spacer()

            Text("Upgrade")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

struct NewChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var conversation: Conversation?
    @State private var isCreating = true

    var body: some View {
        Group {
            if let conversation = conversation {
                ChatView(conversation: conversation)
            } else {
                ProgressView("Starting conversation...")
            }
        }
        .task {
            do {
                conversation = try await container.chatService.createConversation()
            } catch {
                appState.showError(.apiError(error.localizedDescription))
                dismiss()
            }
        }
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
