import SwiftUI
import OSLog

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    let conversation: Conversation
    typealias SendOperation = @MainActor (String, UUID, Bool, @escaping (String) -> Void) async throws -> SendMessageResponse
    private let sendOperation: SendOperation?
    private let loadOperation: (@MainActor () async throws -> [Message])?
    private let recordMessage: (@MainActor () async -> Void)?
    private struct PendingSend {
        let id: UUID
        let content: String
        var messageId: String { id.uuidString.lowercased() }
    }
    @State private var pendingSend: PendingSend?
    @State private var sendFailure: ChatRequestFailure?

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var showQuotaWarning = false
    @State private var displayTitle: String = "Chat"
    @State private var sendTask: Task<Void, Never>?
    @State private var reconciliationTask: Task<Void, Never>?
    @State private var viewGeneration = UUID()
    @State private var messageLoadGeneration = UUID()
    @State private var isVisible = false
    @State private var streamingText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showVoiceMode = false
    @State private var latestCoachData: CoachData?
    @StateObject private var coachViewModel: CoachViewModel

    private let quotaWarningThreshold = 3
    
    init(conversation: Conversation, initialDraft: String = "", send: SendOperation? = nil, load: (@MainActor () async throws -> [Message])? = nil, recordMessage: (@MainActor () async -> Void)? = nil) {
        self.conversation = conversation
        self.sendOperation = send; self.loadOperation = load; self.recordMessage = recordMessage
        _inputText = State(initialValue: initialDraft)
        // Initialize CoachViewModel - will be injected via container in body
        _coachViewModel = StateObject(wrappedValue: CoachViewModel(
            coachService: DependencyContainer.shared.coachService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            VStack(spacing: 4) {
                                MessageBubble(message: message)
                                    .accessibilityIdentifier("chat-message-\(message.id.lowercased())")
                                if pendingSend?.messageId == message.id.lowercased(), let failure = sendFailure {
                                    Text(failure.messageSaved == true ? "Reply unavailable" : "Send not confirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .id(message.id)
                        }

                        // Coach card - show after assistant's latest message
                        if let coachData = latestCoachData,
                           !coachViewModel.isAcknowledged,
                           !coachViewModel.isSuppressed() {
                            DistortionCoachCard(
                                coachData: coachData,
                                isAcknowledged: coachViewModel.isAcknowledged,
                                onAction: { action in
                                    withAnimation {
                                        coachViewModel.handleAction(
                                            action,
                                            encounterId: coachData.encounterId,
                                            distortionCode: coachData.distortionCode,
                                            confidence: coachData.confidence
                                        )
                                    }
                                }
                            )
                        }

                        // Coach error feedback
                        if let error = coachViewModel.interactionError {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    coachViewModel.interactionError = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .accessibilityLabel("Dismiss error")
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding()
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Coach error: \(error)")
                        }

                        if isSending && !streamingText.isEmpty {
                            MessageBubble(message: Message(id: "streaming", role: .assistant, content: streamingText, createdAt: Date(), blocked: false))
                                .id("streaming")
                        }
                        if isSending && streamingText.isEmpty {
                            TypingIndicator()
                                .id("typing-indicator")
                        }
                        if let failure = sendFailure {
                            failureBanner(failure).id("send-error")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: sendFailure?.kind) { _, value in
                    if value != nil { proxy.scrollTo("send-error", anchor: .bottom) }
                }
                .onChange(of: isSending) { _, newValue in
                    if newValue {
                        withAnimation {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            // Quota warning - tappable to show paywall
            if showQuotaWarning && sendFailure == nil {
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
        .sentryMaskChat()
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayTitle = conversation.title ?? "Chat"
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if appState.entitlements.tier == .premium {
                        showVoiceMode = true
                    } else {
                        appState.showPaywall = true
                    }
                } label: {
                    Image(systemName: "mic.fill")
                }
                .accessibilityLabel("Voice mode")
                .accessibilityHint(appState.entitlements.tier == .premium ? "Start a voice conversation" : "Premium feature - tap to upgrade")

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
        .fullScreenCover(isPresented: $showVoiceMode, onDismiss: {
            isInputFocused = true
            reconcileMessages(generation: viewGeneration)
        }) {
            VoiceChatView(supabase: container.supabaseClient, conversationId: conversation.id)
        }
        .onChange(of: appState.currentUser?.id) { previous, current in
            if let previous, previous != current {
                messages = []; pendingSend = nil; sendFailure = nil
                isVisible = false; viewGeneration = UUID()
                sendTask?.cancel(); reconciliationTask?.cancel()
                dismiss()
            }
        }
        .onDisappear {
            isVisible = false
            viewGeneration = UUID()
            sendTask?.cancel()
            reconciliationTask?.cancel()
            sendTask = nil
            reconciliationTask = nil
            isSending = false
            streamingText = ""
        }
        // Load messages on appearance
        .task(id: conversation.id) {
            viewGeneration = UUID()
            isVisible = true
            sendTask?.cancel()
            reconciliationTask?.cancel()
            messages = []
            pendingSend = nil
            sendFailure = nil
            isSending = false
            streamingText = ""
            displayTitle = conversation.title ?? "Chat"
            await loadMessages()
        }
    }

    private func loadMessages() async {
        let generation = viewGeneration
        let request = UUID()
        messageLoadGeneration = request
        isLoading = true
        defer {
            if viewGeneration == generation && messageLoadGeneration == request { isLoading = false }
        }

        do {
            let loaded: [Message]
            if let loadOperation { loaded = try await loadOperation() }
            else { loaded = try await container.chatService.getMessages(conversationId: conversation.id) }
            guard !Task.isCancelled, isVisible, viewGeneration == generation,
                  messageLoadGeneration == request else { return }
            messages = loaded
            // An unconfirmed send may have failed before a user row existed.
            // Keep the exact draft visible without inventing a saved message ID.
            if let pendingSend, sendFailure != nil, inputText.isEmpty,
               !loaded.contains(where: { $0.id.lowercased() == pendingSend.messageId }) {
                inputText = pendingSend.content
            }
            if pendingSend == nil { sendFailure = nil }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled, isVisible,
                  viewGeneration == generation, messageLoadGeneration == request else { return }
            if sendFailure == nil { sendFailure = ChatRequestFailure(kind: .network) }
        }
    }

    private func reconcileMessages(generation: UUID) {
        guard isVisible, viewGeneration == generation else { return }
        reconciliationTask?.cancel()
        // A fresh task does not inherit the cancelled send task's cancellation state.
        reconciliationTask = Task { @MainActor in
            guard !Task.isCancelled, isVisible, viewGeneration == generation else { return }
            await loadMessages()
        }
    }

    private func failureBanner(_ failure: ChatRequestFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failure.title).font(.headline)
            Text(failure.localizedDescription).font(.subheadline)
            if let used = failure.quotaUsed, let limit = failure.quotaLimit, used >= 0, limit > 0 {
                Text("\(used) of \(limit) daily messages used").font(.caption)
            }
            if let reset = failure.resetAt {
                Text("Allowance resets \(reset, style: .relative)").font(.caption)
            } else if let retryAt = failure.retryAt {
                Text("Retry \(retryAt, style: .relative)").font(.caption)
            }
            if pendingSend != nil, failure.canRetryRequest {
                Button(failure.kind == .pending ? "Check response" : failure.kind == .signIn ? "Retry after sign-in" : "Retry message") {
                    retryMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
            }
            Button("Reload history") { reconcileMessages(generation: viewGeneration) }
                .buttonStyle(.bordered)
            if failure.kind == .quota, appState.entitlements.tier != .premium {
                Button("View plans") { appState.showPaywall = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("chat-send-feedback")
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        if let pendingSend, sendFailure != nil, content == pendingSend.content {
            retryMessage()
            return
        }
        let pending = PendingSend(id: UUID(), content: content)
        pendingSend = pending
        inputText = ""
        startSend(pending, retryFailed: false)
    }

    private func retryMessage() {
        guard !isSending, let pendingSend, let failure = sendFailure,
              failure.canRetryRequest else { return }
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines) == pendingSend.content { inputText = "" }
        startSend(pendingSend, retryFailed: failure.retryable)
    }

    private func startSend(_ pending: PendingSend, retryFailed: Bool) {
        guard !isSending else { return }
        let tempMessageId = pending.messageId
        let content = pending.content
        if !messages.contains(where: { $0.id.lowercased() == tempMessageId }) {
            messages.append(Message(id: tempMessageId, role: .user, content: content, createdAt: Date(), blocked: false))
        }
        isSending = true
        sendFailure = nil
        streamingText = ""
        let generation = viewGeneration
        messageLoadGeneration = UUID()
        reconciliationTask?.cancel()

        // Store task reference for cancellation on view disappear
        sendTask = Task { @MainActor in
            defer {
                if viewGeneration == generation {
                    isSending = false
                    streamingText = ""
                    sendTask = nil
                }
            }

            do {
                // Check for cancellation before making network call
                try Task.checkCancellation()

                let operation = sendOperation ?? { content, id, retry, delta in
                    try await container.chatService.sendMessage(conversationId: conversation.id, content: content,
                        requestId: id, retryFailed: retry, onDelta: delta)
                }
                let response = try await operation(content, pending.id, retryFailed) {
                    if isVisible && viewGeneration == generation { streamingText += $0 }
                }

                // Check for cancellation after network call
                try Task.checkCancellation()
                guard isVisible, viewGeneration == generation else { return }

                // Use removeAll(where:) for atomic removal (prevents race condition)
                messages.removeAll { $0.id.lowercased() == tempMessageId }
                for saved in [response.userMessage, response.assistantMessage] {
                    if let index = messages.firstIndex(where: { $0.id.lowercased() == saved.id.lowercased() }) { messages[index] = saved }
                    else { messages.append(saved) }
                }
                pendingSend = nil
                sendFailure = nil

                // Update quota tracking from server (authoritative source)
                if appState.entitlements.tier != .premium, let serverUsed = response.quotaUsed {
                    // Sync from server-provided value (not local increment)
                    let limit = response.quotaLimit.flatMap { $0 > 0 ? $0 : nil } ?? appState.entitlements.dailyAiQuota
                    appState.entitlements = Entitlements(tier: appState.entitlements.tier, dailyAiQuota: limit, dailyAiUsed: serverUsed)
                    // Only show warning if not unlimited (Int.max) and near limit
                    showQuotaWarning = response.quotaRemaining < Int.max && response.quotaRemaining <= quotaWarningThreshold
                } else {
                    showQuotaWarning = false
                }

                // Record first chat message for progressive disclosure activation
                if let recordMessage { await recordMessage() }
                else { try? await container.activationService.recordChatMessage() }
                guard !Task.isCancelled, isVisible, viewGeneration == generation else { return }

                // Update title if generated
                if let newTitle = response.conversationTitle {
                    displayTitle = newTitle
                }
                
                // Handle coach data if present
                if let coachData = response.coachData {
                    withAnimation {
                        latestCoachData = coachData
                        coachViewModel.isAcknowledged = false // Reset for new coach card
                    }
                }

                // Show crisis resources after a brief delay
                if response.crisisDetected == true {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        appState.showCrisisResources = true
                    }
                }
            } catch is CancellationError {
                if isVisible, viewGeneration == generation { sendFailure = ChatRequestFailure(kind: .unconfirmed) }
                reconcileMessages(generation: generation)
            } catch let error as URLError where error.code == .cancelled {
                if isVisible, viewGeneration == generation { sendFailure = ChatRequestFailure(kind: .unconfirmed) }
                reconcileMessages(generation: generation)
            } catch {
                guard !Task.isCancelled, isVisible, viewGeneration == generation else { return }
                let failure = error as? ChatRequestFailure ?? ChatRequestFailure(kind: .unconfirmed)
                sendFailure = failure
                let used = failure.quotaUsed.flatMap { $0 >= 0 ? $0 : nil } ?? appState.entitlements.dailyAiUsed
                let limit = failure.quotaLimit.flatMap { $0 > 0 ? $0 : nil } ?? appState.entitlements.dailyAiQuota
                appState.entitlements = Entitlements(tier: appState.entitlements.tier, dailyAiQuota: limit, dailyAiUsed: used)
                if failure.messageSaved == false {
                    messages.removeAll { $0.id.lowercased() == tempMessageId }
                    if inputText.isEmpty { inputText = content }
                } else if failure.kind == .signIn, inputText.isEmpty {
                    inputText = content
                }
                reconcileMessages(generation: generation)
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
                // MarkdownContentView handles all styling internally
                MarkdownContentView(content: message.content, isUserMessage: isUser)

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
            .background(Color(uiColor: .secondarySystemBackground))
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
                .background(Color(uiColor: .secondarySystemBackground))
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
        .background(Color(uiColor: .systemBackground))
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
            status: ConversationStatus.active,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
