import SwiftUI
import Combine

/// Opening Chat creates only a protected local draft. A deliberate Send reserves its cloud identity.
struct SupportChatEntryView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sessionID: UUID?
    @State private var conversation: Conversation?
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    @State private var sendOnOpen = false
    @State private var capabilitiesVerified = false
    @State private var showContext = false
    @State private var showVoice = false
    @State private var voiceAccess: SessionVoiceAccess?
    @State private var voiceTextID: UUID?

    var body: some View {
        Group {
            if let conversation {
                ChatView(conversation: conversation, initialDraft: text, supportSessionID: sessionID,
                    sendOnOpen: sendOnOpen, capabilitiesVerified: capabilitiesVerified)
            } else if let sessionID {
                VStack(spacing: SupportTheme.Spacing.m) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                            if dynamicTypeSize.isAccessibilitySize {
                                Text(coordinator.journal.sessions[sessionID]?.title ?? "Conversation")
                                    .font(.headline).accessibilityAddTraits(.isHeader)
                            }
                            Text("What would be useful right now?").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Text("You can just talk. A practice or a goal is optional.").foregroundStyle(SupportTheme.textSecondary)
                            ForEach(SupportActivityTemplateKey.allCases, id: \.self) { template in
                                Button(template.title) { start(template, sessionID: sessionID) }
                                    .buttonStyle(.supportSecondary).frame(minHeight: SupportTheme.minimumTarget)
                            }
                            if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline) }
                            Text("Draft saved on this device. Reconnecting does not send it.").font(.caption).foregroundStyle(SupportTheme.textSecondary)
                        }.padding(SupportTheme.Spacing.l).frame(maxWidth: SupportTheme.readableWidth, alignment: .leading)
                    }
                    if appState.isOutOfFreeMessages {
                        QuotaWarningBanner(remaining: 0, resetsAt: EntitlementSnapshot.nextServerReset(after: Date())) {
                            appState.showPaywall = true
                        }
                    }
                    ChatInputBar(text: $text, isSending: sending, isOutOfMessages: appState.isOutOfFreeMessages,
                                 onSend: { send(sessionID: sessionID) })
                }
                .foregroundStyle(SupportTheme.textPrimary)
                .supportScreen()
                .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "Chat" : coordinator.journal.sessions[sessionID]?.title ?? "Conversation")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Context") { showContext = true }
                        Button {
                            guard appState.entitlements.tier == .premium else { appState.showPaywall = true; return }
                            voiceAccess = SessionVoiceAccess(container: container, appState: appState, sessionID: sessionID)
                            showVoice = true
                        } label: {
                            Image(systemName: "mic.fill").frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        }.accessibilityLabel("Voice mode")
                    }
                }
                .onChange(of: text) { _, value in coordinator.scheduleDraft(value, sessionID: sessionID) }
                .sheet(isPresented: $showContext) { SupportContextView(sessionID: sessionID, receipt: nil) }
            } else { ProgressView("Opening your draft") }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .onReceive(coordinator.$chatDraftHandoff.receive(on: DispatchQueue.main)) { handoff in
            guard let handoff, handoff.sessionID == sessionID, !sending,
                  let accepted = coordinator.consumeChatDraftHandoff(handoff.id, sessionID: handoff.sessionID) else { return }
            text = accepted.text
        }
        .fullScreenCover(isPresented: $showVoice, onDismiss: {
            let id = voiceTextID, owner = coordinator.identity.ownerID, epoch = appState.accountEpoch
            voiceTextID = nil
            guard let id else { return }
            Task {
                if let saved = try? await container.supabaseDataService.getConversation(id: id.uuidString),
                   appState.currentUser?.id == owner, appState.accountEpoch == epoch,
                   container.supportSessionCoordinator === coordinator {
                    sendOnOpen = false
                    conversation = saved
                }
            }
        }) {
            VoiceChatView(supabase: container.supabaseClient, supportAccess: voiceAccess,
                onUseText: { voiceTextID = voiceAccess?.attachedConversationID })
        }
        .task {
            guard sessionID == nil else { return }
            do {
                let session: SupportSession
                if let id = coordinator.foregroundSessionID, let existing = coordinator.journal.sessions[id], existing.status == .open { session = existing }
                else { session = try await coordinator.createSession() }
                sessionID = session.id
                text = coordinator.journal.drafts[session.id] ?? ""
                if let handoff = coordinator.chatDraftHandoff {
                    _ = coordinator.consumeChatDraftHandoff(handoff.id, sessionID: session.id)
                }
                if let id = session.conversationID {
                    conversation = try await container.supabaseDataService.getConversation(id: id.uuidString)
                    if conversation == nil { error = "This conversation is unavailable. Your local session is still saved." }
                }
            } catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }

    private func start(_ template: SupportActivityTemplateKey, sessionID: UUID) {
        Task {
            do { try await coordinator.flushDraft(text, sessionID: sessionID); _ = try await coordinator.start(template, in: sessionID, origin: .chatDraft) }
            catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }

    private func send(sessionID: UUID) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !content.isEmpty else { return }
        sending = true; error = nil
        let owner = coordinator.identity.ownerID, accountEpoch = appState.accountEpoch
        let proof: @Sendable () async -> OfflineOwnerProof? = { await MainActor.run {
            guard appState.currentUser?.id == owner, appState.accountEpoch == accountEpoch,
                  container.supportSessionCoordinator === coordinator else { return nil }
            return OfflineOwnerProof(userId: owner, epoch: accountEpoch)
        } }
        Task { @MainActor in
            defer { sending = false }
            do {
                // A session closed elsewhere (History, Today) cannot take a message; continue in a new one.
                var sessionID = sessionID
                if coordinator.journal.sessions[sessionID]?.status != .open {
                    sessionID = try await coordinator.createSession().id
                    self.sessionID = sessionID
                }
                try await coordinator.flushDraft(content, sessionID: sessionID)
                _ = try await container.supabaseDataService.supportChatCapabilities(owner: .init(userId: owner, epoch: accountEpoch), ownerProof: proof)
                let id = try await coordinator.repository.reserveConversationID(epoch: coordinator.identity.epochID, sessionID: sessionID)
                let saved = try await container.supabaseDataService.createConversation(title: nil, id: id, expectedOwner: owner)
                guard await proof() != nil, !Task.isCancelled else { throw CancellationError() }
                try await coordinator.repository.attachConversation(epoch: coordinator.identity.epochID, sessionID: sessionID, conversationID: id)
                capabilitiesVerified = true
                sendOnOpen = true
                conversation = saved
            } catch {
                guard await proof() != nil else { return }
                error.report(context: ["action": "support_chat_first_send"])
                self.error = (error as? ChatRequestFailure)?.localizedDescription ?? "The message has not been sent. Your draft is saved; retry when ready."
            }
        }
    }
}
