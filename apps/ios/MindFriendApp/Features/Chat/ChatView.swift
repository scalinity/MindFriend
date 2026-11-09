import SwiftUI
import Combine
import OSLog

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let conversation: Conversation
    private let suppliedSessionID: UUID?
    private let sendOnOpen: Bool
    @State private var didSendOnOpen = false
    @State private var chatCapabilitiesVerified = false
    @State private var latestSupport: SupportChatMetadata?
    @State private var showSupportContext = false
    @State private var showManualChoices = false
    @State private var proposalError: String?
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
    @State private var localVoiceEvents: [SupportTranscriptEvent] = []
    @State private var activityEvents: [SupportActivityChatEvent] = []
    @State private var removingVoiceEvent: SupportTranscriptEvent?
    @State private var olderCursor: ChatHistoryCursor?
    @State private var hasLoadedOlderPages = false
    @State private var isLoadingOlder = false
    @State private var olderLoadTask: Task<Void, Never>?
    @State private var olderLoadError: String?
    @State private var prependAnchor: String?
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var displayTitle: String = "Chat"
    @State private var sendTask: Task<Void, Never>?
    @State private var reconciliationTask: Task<Void, Never>?
    @State private var viewGeneration = UUID()
    @State private var messageLoadGeneration = UUID()
    @State private var isVisible = false
    @State private var streamingText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showVoiceMode = false
    @State private var voiceAccess: SessionVoiceAccess?
    @State private var latestCoachData: CoachData?
    @StateObject private var coachViewModel: CoachViewModel

    private let quotaWarningThreshold = 3
    
    init(conversation: Conversation, initialDraft: String = "", supportSessionID: UUID? = nil,
         sendOnOpen: Bool = false, capabilitiesVerified: Bool = false,
         send: SendOperation? = nil, load: (@MainActor () async throws -> [Message])? = nil, recordMessage: (@MainActor () async -> Void)? = nil) {
        self.conversation = conversation
        self.suppliedSessionID = supportSessionID
        self.sendOnOpen = sendOnOpen
        _chatCapabilitiesVerified = State(initialValue: capabilitiesVerified)
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
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(displayTitle).font(.headline).accessibilityAddTraits(.isHeader)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let olderLoadError { Text(olderLoadError).font(.caption).foregroundStyle(.secondary) }
                        if olderCursor != nil {
                            Button(isLoadingOlder ? "Loading…" : "Load earlier messages") {
                                olderLoadTask = Task { await loadOlderMessages() }
                            }
                            .disabled(isLoadingOlder || isLoading || isSending)
                            .accessibilityIdentifier("chat-load-earlier-messages")
                        }
                        ForEach(SupportChatRow.merge(messages: messages, localEvents: localVoiceEvents, activityEvents: activityEvents)) { row in
                            switch row {
                            case .message(let message):
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
                            case .localVoice(let event):
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.syncState == .rejected ? "Voice turn · not saved to account" : "Voice turn · saved on this device, account sync pending")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(event.role == .user ? "You" : "MindFriend").font(.subheadline.bold())
                                Text(event.text).textSelection(.enabled)
                                if event.syncState == .rejected {
                                    Text("The account did not accept this turn. Its local copy is kept here.").font(.subheadline)
                                    Button("Try saving again") { retryVoiceEvent(event) }
                                }
                                Button("Copy voice turn") {
                                    UIPasteboard.general.setObjects([event.text as NSString], localOnly: true,
                                        expirationDate: Date().addingTimeInterval(120))
                                }
                                Button("Remove local copy", role: .destructive) { removingVoiceEvent = event }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            case .activity(let event):
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(event.template.title, systemImage: "checklist").font(.headline)
                                    Text(event.stepState.map(SupportHistoryText.stepState) ?? SupportHistoryText.activityStatus(event.status))
                                    if let reflection = event.reflection { Text("Your reflection: " + reflection.displayTitle) }
                                    Text(event.answersShared ? "Written answers may be used as session context by your choice." : "Activity answers excluded from automatic session context. Answers you send in Chat are part of that message.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    NavigationLink("View session") { SupportHistoryDetailView(sessionID: event.sessionID) }
                                        .frame(minHeight: 44)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding()
                                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("chat-activity-" + event.activityID.uuidString.lowercased())
                            }
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Reply in progress · not yet saved").font(.caption).foregroundStyle(.secondary)
                                MessageBubble(message: Message(id: "streaming", role: .assistant, content: streamingText, createdAt: Date(), blocked: false))
                            }.id("streaming")
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
                    if let anchor = prependAnchor {
                        proxy.scrollTo(anchor, anchor: .top)
                        prependAnchor = nil
                    } else {
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
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

            // The server's count decides both whether the banner shows and what it says.
            if sendFailure == nil, appState.entitlements.tier != .premium,
               let remaining = appState.entitlementSnapshot?.remaining, remaining <= quotaWarningThreshold {
                QuotaWarningBanner(remaining: remaining, resetsAt: EntitlementSnapshot.nextServerReset(after: Date())) {
                    appState.showPaywall = true
                }
            }

            Divider()

            if !isSending, let metadata = latestSupport, !metadata.suppressOrdinaryCards,
               let coordinator = container.supportSessionCoordinator,
               let id = resolvedSessionID, let session = coordinator.journal.sessions[id],
               let revision = container.supportSync?.privacyRevision,
               let proposal = metadata.actionableProposal(now: Date(), scope: session.contextScope, privacyRevision: revision),
               coordinator.journal.declinedTemplates[id]?.contains(proposal.template) != true {
                supportProposal(proposal, sessionID: id)
            }
            if let proposalError { Text(proposalError).font(.subheadline).padding(.horizontal) }

            // Input
            ChatInputBar(
                text: $inputText,
                isSending: isSending,
                isOutOfMessages: appState.isOutOfFreeMessages,
                onSend: sendMessage
            )
            .focused($isInputFocused)
        }
        .sentryMaskChat()
        .supportScreen()
        .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "Chat" : displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayTitle = conversation.title ?? "Chat"
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if resolvedSessionID != nil { Button("Context") { showSupportContext = true } }
                Button {
                    if appState.entitlements.tier == .premium {
                        voiceAccess = SessionVoiceAccess(container: container, appState: appState,
                            sessionID: resolvedSessionID, conversationID: UUID(uuidString: conversation.id))
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
                    Image(systemName: "lifepreserver")
                }
                .accessibilityLabel("Support and crisis resources")
                .accessibilityHint("Opens crisis resources and hotlines")
            }
        }
        .fullScreenCover(isPresented: $showVoiceMode, onDismiss: {
            isInputFocused = true
            reconcileMessages(generation: viewGeneration)
        }) {
            VoiceChatView(supabase: container.supabaseClient, conversationId: conversation.id, supportAccess: voiceAccess)
        }
        .sheet(isPresented: $showSupportContext) {
            if let id = resolvedSessionID { SupportContextView(sessionID: id, receipt: latestSupport?.contextReceipt) }
        }
        .alert("Remove this local voice turn?", isPresented: Binding(get: { removingVoiceEvent != nil }, set: { if !$0 { removingVoiceEvent = nil } })) {
            if let event = removingVoiceEvent {
                Button("Remove local copy", role: .destructive) {
                    removingVoiceEvent = nil
                    Task {
                        guard let coordinator = container.supportSessionCoordinator,
                              coordinator.identity.ownerID == appState.currentUser?.id else { return }
                        do { try await coordinator.repository.discardTranscriptEvents(epoch: coordinator.identity.epochID, ids: [event.id]) }
                        catch { proposalError = SupportSessionCoordinator.message(for: error) }
                    }
                }
            }
            Button("Cancel", role: .cancel) { removingVoiceEvent = nil }
        } message: { Text("Copy anything you want to keep before removing this device’s copy. An upload already in progress may still save an account copy.") }
        .alert("Choose an option", isPresented: $showManualChoices) {
            ForEach(SupportActivityTemplateKey.allCases, id: \.self) { template in
                Button(template.title) { startManual(template) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: inputText) { _, value in
            if !value.isEmpty || !isSending, let id = resolvedSessionID {
                container.supportSessionCoordinator?.scheduleDraft(value, sessionID: id)
            }
        }
        .onReceive(supportChatDraftHandoffs.receive(on: DispatchQueue.main)) { handoff in
            guard let handoff, handoff.sessionID == resolvedSessionID, !isSending, pendingSend == nil,
                  let coordinator = container.supportSessionCoordinator,
                  coordinator.identity.ownerID == appState.currentUser?.id,
                  let accepted = coordinator.consumeChatDraftHandoff(handoff.id, sessionID: handoff.sessionID) else { return }
            inputText = accepted.text
        }
        .onReceive(supportJournalUpdates) { journal in
            guard journal.ownerID == appState.currentUser?.id else { localVoiceEvents = []; activityEvents = []; return }
            let activitySessionID = suppliedSessionID ?? journal.sessions.values.first {
                $0.conversationID == UUID(uuidString: conversation.id) && $0.status != .deleted
            }?.id
            activityEvents = activitySessionID.map { SupportActivityChatEvent.rows(in: journal, sessionID: $0) } ?? []
            localVoiceEvents = journal.transcriptEvents.filter {
                $0.conversationID == UUID(uuidString: conversation.id) && $0.syncState != .saved
            }.sorted { ($0.sequence, $0.id.uuidString) < ($1.sequence, $1.id.uuidString) }
            let pending = pendingSend.flatMap { journal.pendingChatRequests[$0.id] }
            let changedScope = pending.map { journal.sessions[$0.sessionID]?.contextScope != $0.scope } == true
            let changedRevision = pending.map { (journal.accountPrivacyRevision ?? $0.privacyRevision) > $0.privacyRevision } == true
            if isSending, journal.personalizedCloudPaused || changedScope || changedRevision {
                sendTask?.cancel()
                sendFailure = ChatRequestFailure(kind: .contextChanged)
            }
        }
        .onChange(of: appState.currentUser?.id) { previous, current in
            if let previous, previous != current {
                messages = []; localVoiceEvents = []; activityEvents = []; pendingSend = nil; sendFailure = nil
                isVisible = false; viewGeneration = UUID()
                sendTask?.cancel(); reconciliationTask?.cancel(); olderLoadTask?.cancel()
                dismiss()
            }
        }
        .onDisappear {
            isVisible = false
            viewGeneration = UUID()
            sendTask?.cancel()
            reconciliationTask?.cancel()
            olderLoadTask?.cancel()
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
            olderCursor = nil
            hasLoadedOlderPages = false
            isLoadingOlder = false
            olderLoadError = nil
            prependAnchor = nil
            pendingSend = nil
            sendFailure = nil
            isSending = false
            streamingText = ""
            displayTitle = conversation.title ?? "Chat"
            await loadMessages()
            await restoreSupportDraft()
            if sendOnOpen, !didSendOnOpen, pendingSend == nil, !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                didSendOnOpen = true
                sendMessage()
            }
        }
    }

    private func retryVoiceEvent(_ event: SupportTranscriptEvent) {
        guard let coordinator = container.supportSessionCoordinator,
              let sync = container.supportSync, coordinator.identity.ownerID == appState.currentUser?.id else { return }
        let owner = coordinator.identity.ownerID, accountEpoch = appState.accountEpoch
        Task {
            do {
                guard container.supportSessionCoordinator === coordinator,
                      appState.currentUser?.id == owner, appState.accountEpoch == accountEpoch else { return }
                try await coordinator.repository.retryRejectedTranscriptEvent(epoch: coordinator.identity.epochID, id: event.id)
                try await sync.retry()
            } catch {
                if container.supportSessionCoordinator === coordinator,
                   appState.currentUser?.id == owner, appState.accountEpoch == accountEpoch {
                    proposalError = SupportSessionCoordinator.message(for: error)
                }
            }
        }
    }

    private func loadMessages() async {
        let generation = viewGeneration
        let request = UUID()
        messageLoadGeneration = request
        olderLoadTask?.cancel()
        isLoadingOlder = false
        isLoading = true
        defer {
            if viewGeneration == generation && messageLoadGeneration == request { isLoading = false }
        }

        do {
            let loaded: [Message]
            let page: ChatHistoryPage<Message>?
            if let loadOperation { loaded = try await loadOperation(); page = nil }
            else {
                let result = try await container.chatService.getMessagePage(conversationId: conversation.id)
                loaded = result.items
                page = result
            }
            guard !Task.isCancelled, isVisible, viewGeneration == generation,
                  messageLoadGeneration == request else { return }
            if hasLoadedOlderPages {
                let currentPageIDs = Set(loaded.map { $0.id.lowercased() })
                let older = messages.filter {
                    !currentPageIDs.contains($0.id.lowercased()) && $0.id.lowercased() != pendingSend?.messageId
                }
                messages = older + loaded
            } else {
                messages = loaded
                olderCursor = page?.nextCursor
            }
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

    private func loadOlderMessages() async {
        guard !isLoadingOlder, let cursor = olderCursor else { return }
        let generation = viewGeneration
        let loadGeneration = messageLoadGeneration
        isLoadingOlder = true
        olderLoadError = nil
        defer { if viewGeneration == generation && messageLoadGeneration == loadGeneration { isLoadingOlder = false } }
        do {
            let page = try await container.chatService.getMessagePage(conversationId: conversation.id, before: cursor)
            guard !Task.isCancelled, isVisible, viewGeneration == generation, messageLoadGeneration == loadGeneration else { return }
            let existing = Set(messages.map { $0.id.lowercased() })
            let earlier = page.items.filter { !existing.contains($0.id.lowercased()) }
            if !earlier.isEmpty {
                prependAnchor = messages.first?.id
                messages.insert(contentsOf: earlier, at: 0)
            }
            hasLoadedOlderPages = true
            olderCursor = page.nextCursor
        } catch {
            if !Task.isCancelled, isVisible, viewGeneration == generation, messageLoadGeneration == loadGeneration {
                olderLoadError = "Couldn't load earlier messages. Try again."
            }
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
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
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
        let quotaOwner = appState.currentUser?.id
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
                    try await sendSupportMessage(content: content, requestID: id, retryFailed: retry, onDelta: delta)
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
                latestSupport = response.support

                // Update quota tracking from server (authoritative source)
                if appState.entitlements.tier != .premium, let serverUsed = response.quotaUsed, let quotaOwner {
                    appState.recordChatQuota(ownerID: quotaOwner, used: serverUsed, limit: response.quotaLimit,
                                             countedOn: response.quotaDay)
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
                if let quotaOwner {
                    appState.recordChatQuota(ownerID: quotaOwner, used: failure.quotaUsed, limit: failure.quotaLimit,
                                             countedOn: failure.quotaDay)
                }
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
    private var resolvedSessionID: UUID? {
        suppliedSessionID ?? container.supportSessionCoordinator?.journal.sessions.values.first(where: {
            $0.conversationID == UUID(uuidString: conversation.id) && $0.status != .deleted
        })?.id
    }

    private var supportChatDraftHandoffs: AnyPublisher<SupportChatDraftHandoff?, Never> {
        container.supportSessionCoordinator?.$chatDraftHandoff.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    private var supportJournalUpdates: AnyPublisher<SupportJournal, Never> {
        container.supportSessionCoordinator?.$journal.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    private func restoreSupportDraft() async {
        guard sendOperation == nil, let coordinator = container.supportSessionCoordinator else { return }
        do {
            let session: SupportSession
            if let id = resolvedSessionID, let existing = coordinator.journal.sessions[id] { session = existing }
            else {
                guard let id = UUID(uuidString: conversation.id) else { return }
                session = try await coordinator.createSession(conversationID: id)
            }
            if let pending = coordinator.journal.pendingChatRequests.values.first(where: { $0.sessionID == session.id }) {
                pendingSend = PendingSend(id: pending.id, content: pending.content)
                sendFailure = ChatRequestFailure(kind: .pending)
                if inputText.isEmpty { inputText = pending.content }
            } else if inputText.isEmpty { inputText = coordinator.journal.drafts[session.id] ?? "" }
        } catch { proposalError = SupportSessionCoordinator.message(for: error) }
    }

    private func sendSupportMessage(content: String, requestID: UUID, retryFailed: Bool,
                                    onDelta: @escaping (String) -> Void) async throws -> SendMessageResponse {
        guard let coordinator = container.supportSessionCoordinator, let sync = container.supportSync,
              let id = resolvedSessionID else { throw ChatRequestFailure(kind: .contractUnavailable) }
        let owner = coordinator.identity.ownerID, epoch = appState.accountEpoch
        let proof: @Sendable () async -> OfflineOwnerProof? = { await MainActor.run {
            guard appState.currentUser?.id == owner, appState.accountEpoch == epoch,
                  container.supportSessionCoordinator === coordinator else { return nil }
            return .init(userId: owner, epoch: epoch)
        } }
        try await coordinator.flushDraft(content, sessionID: id)
        guard !coordinator.journal.personalizedCloudPaused else { throw ChatRequestFailure(kind: .contextChanged) }
        if !chatCapabilitiesVerified {
            _ = try await container.supabaseDataService.supportChatCapabilities(owner: .init(userId: owner, epoch: epoch), ownerProof: proof)
            chatCapabilitiesVerified = true
        }
        try await sync.synchronize()
        guard await proof() != nil else { throw CancellationError() }
        let journal = try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID)
        guard !journal.personalizedCloudPaused, let session = journal.sessions[id], session.status == .open,
              session.syncStatus == .synced, let privacyRevision = sync.privacyRevision else { throw ChatRequestFailure(kind: .contextChanged) }
        let pending: SupportPendingChatRequest
        if let existing = journal.pendingChatRequests[requestID] { pending = existing }
        else {
            pending = try await coordinator.repository.prepareChatRequest(epoch: coordinator.identity.epochID,
                sessionID: id, requestID: requestID, content: content, scope: session.contextScope, privacyRevision: privacyRevision)
        }
        guard pending.content == content, pending.conversationID == UUID(uuidString: conversation.id) else { throw ChatRequestFailure(kind: .contextChanged) }
        let context = SupportChatRequestContext(owner: .init(userId: owner, epoch: epoch), sessionID: id,
            scope: pending.scope, privacyRevision: pending.privacyRevision)
        do {
            let response = try await container.chatService.sendMessage(conversationId: conversation.id, content: content,
                requestId: requestID, retryFailed: retryFailed, supportContext: context, ownerProof: proof, onDelta: onDelta)
            guard await proof() != nil else { throw CancellationError() }
            try await coordinator.repository.settleChatRequest(epoch: coordinator.identity.epochID, requestID: requestID)
            return response
        } catch let failure as ChatRequestFailure {
            if failure.messageSaved == false {
                try await coordinator.repository.settleChatRequest(epoch: coordinator.identity.epochID, requestID: requestID, rejectedBeforeSend: true)
            }
            throw failure
        }
    }

    private func supportProposal(_ proposal: SupportChatProposal, sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A small next step").font(.headline)
            Text(proposal.template.title).font(.title3.weight(.semibold))
            Text(proposal.reason).font(.subheadline)
            if proposal.reasonCode == "approved_preference" { Button("Why this?") { showSupportContext = true } }
            HStack {
                Button("Start") { acceptProposal(proposal, sessionID: sessionID) }.buttonStyle(.borderedProminent)
                Button("Another option") { showManualChoices = true }
                Button("Not now") {
                    Task {
                        do { try await container.supportSessionCoordinator?.suppressTemplate(proposal.template, sessionID: sessionID); latestSupport = nil }
                        catch { proposalError = SupportSessionCoordinator.message(for: error) }
                    }
                }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(SupportTheme.surface)
    }

    private func acceptProposal(_ proposal: SupportChatProposal, sessionID: UUID) {
        Task {
            do {
                guard let coordinator = container.supportSessionCoordinator, let sync = container.supportSync else { return }
                try await coordinator.acceptProposal(proposal, sessionID: sessionID, sync: sync,
                    conversationID: try conversationUUID())
                latestSupport = nil
            } catch { proposalError = "This suggestion could not be started. Your conversation is saved; choose another option or keep talking." }
        }
    }
    private func conversationUUID() throws -> UUID {
        guard let id = UUID(uuidString: conversation.id) else { throw DataError.invalidId }
        return id
    }
    private func startManual(_ template: SupportActivityTemplateKey) {
        guard let id = resolvedSessionID, let conversationID = UUID(uuidString: conversation.id) else { return }
        Task { do {
            try await container.supportSessionCoordinator?.flushDraft(inputText, sessionID: id)
            _ = try await container.supportSessionCoordinator?.start(template, in: id, origin: .chat(conversationID: conversationID))
        }
               catch { proposalError = SupportSessionCoordinator.message(for: error) } }
    }
}

struct MessageBubble: View {
    let message: Message

    var isUser: Bool { message.role == .user }

    private var accessibilityLabel: String {
        let sender = isUser ? "You said" : message.contentOrigin == .interfaceFallback ? "App guidance" : "MindFriend said"
        let time = message.createdAt.formatted(date: .omitted, time: .shortened)
        return "\(sender): \(message.content). Sent at \(time)"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if message.contentOrigin == .interfaceFallback { Text("App guidance").font(.caption.weight(.semibold)) }
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
                        .fill(SupportTheme.textSecondary)
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
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: 20))
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
    var isOutOfMessages = false
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !isOutOfMessages
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(SupportTheme.textPrimary)
                .background(SupportTheme.field, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SupportTheme.border, lineWidth: 1))
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
                    .foregroundStyle(canSend ? SupportTheme.accent : SupportTheme.textSecondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityHint(isOutOfMessages ? "You're out of messages for today" : canSend ? "Sends your message" : "Type a message first")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(SupportTheme.canvas)
    }
}

struct QuotaWarningBanner: View {
    let remaining: Int
    let resetsAt: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    if remaining == 0 {
                        Text("You're out of messages for today")
                        Text("More messages at \(resetsAt, style: .time)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(remaining) messages left today")
                    }
                }
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
        .accessibilityHint("Opens subscription options")
    }
}

struct NewChatView: View {
    var body: some View { SupportChatEntryView() }
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
