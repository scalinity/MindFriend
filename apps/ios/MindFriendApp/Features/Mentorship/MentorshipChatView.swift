import SwiftUI

/// View for mentorship messaging/chat
struct MentorshipChatView: View {
    let matchId: UUID
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        MentorshipChatContent(matchId: matchId, service: container.mentorshipService)
    }
}

private struct MentorshipChatContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let matchId: UUID
    @ObservedObject var service: MentorshipService
    @ObservedObject var messagingService: MentorshipMessagingService

    init(matchId: UUID, service: MentorshipService) {
        self.matchId = matchId
        self.service = service
        self.messagingService = service.messagingService
    }

    @State private var messageText = ""
    @State private var showingReportSheet = false
    @State private var showingEndSheet = false
    @State private var mentorshipEnded = false
    @Environment(\.dismiss) private var dismiss

    private var safetyService: MentorshipSafetyService { service.safetyService }

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: SupportTheme.Spacing.xs, pinnedViews: []) {
                            ForEach(messagingService.messages) { message in
                                MentorshipMessageBubble(message: message)
                                    .environment(\.currentUser, service.currentUserId)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messagingService.messages.count) {
                        if let lastId = messagingService.messages.last?.id {
                            withAnimation(reduceMotion ? nil : .default) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Message input
                VStack(spacing: SupportTheme.Spacing.xs) {
                    if messagingService.error != nil {
                        Text("Unable to complete the message request. Your draft is still here; please try again.")
                            .font(.callout).foregroundStyle(.red)
                    }
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        TextField("Type a message...", text: $messageText)
                            .supportField()
                            .lineLimit(3)

                        Button(action: {
                            if !messageText.trimmingCharacters(in: .whitespaces).isEmpty {
                                let draft = messageText
                                Task {
                                    do {
                                        try await messagingService.sendMessage(matchId: matchId, content: draft)
                                        if messageText == draft { messageText = "" }
                                    } catch { /* The observed service keeps the failure visible and draft intact. */ }
                                }
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(SupportTheme.accent)
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        }
                        .accessibilityLabel("Send message")
                        .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  messagingService.isSending)
                    }

                    HStack(spacing: SupportTheme.Spacing.s) {
                        Menu {
                            Button(role: .destructive, action: { showingReportSheet = true }) {
                                Label("Report Safety Concern", systemImage: "exclamationmark.shield")
                            }

                            Button(role: .destructive, action: { showingEndSheet = true }) {
                                Label("End Mentorship", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(SupportTheme.textSecondary)
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        }
                        .accessibilityLabel("Mentorship options")

                        Spacer()

                        if messagingService.hasUnreadMessages {
                            Button(action: {
                                Task {
                                    await messagingService.markAsRead(matchId: matchId)
                                }
                            }) {
                                Text("Mark as Read")
                                    .font(.caption)
                            }
                            .buttonStyle(.supportSecondary)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                }
                .padding()
                .background(SupportTheme.surface)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Mentorship Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReportSheet) {
            ReportSafetySheet(
                isPresented: $showingReportSheet,
                onReport: { reason, description in
                    try await safetyService.reportMentorship(
                        matchId: matchId, reason: reason, description: description
                    )
                }
            )
        }
        .sheet(isPresented: $showingEndSheet, onDismiss: {
            if mentorshipEnded { dismiss() }
        }) {
            EndMentorshipSheet(isPresented: $showingEndSheet) { reason in
                try await service.endMentorship(matchId, reason: reason.isEmpty ? "completed" : reason)
                messagingService.stopAutoUpdate()
                mentorshipEnded = true
            }
        }
        .onAppear {
            Task {
                await messagingService.loadMessages(matchId: matchId)
                messagingService.startAutoUpdate(matchId: matchId, interval: 3)
            }
        }
        .onDisappear {
            messagingService.stopAutoUpdate()
        }
    }
}

// MARK: - Message Bubble

struct MentorshipMessageBubble: View {
    let message: MentorshipMessage
    @Environment(\.currentUser) var currentUser

    var isCurrentUser: Bool {
        currentUser == message.senderId
    }

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(message.content)
                    .padding(.horizontal, SupportTheme.Spacing.s)
                    .padding(.vertical, SupportTheme.Spacing.xs)
                    .background(
                        isCurrentUser
                            ? SupportTheme.accent
                            : SupportTheme.surface
                    )
                    .foregroundColor(isCurrentUser ? SupportTheme.onAccent : SupportTheme.textPrimary)
                    .cornerRadius(SupportTheme.controlRadius)

                HStack(spacing: SupportTheme.Spacing.xxs) {
                    if message.isSafetyFlagged {
                        Label("Flagged", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(SupportTheme.accent)
                    }

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
            }

            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

// MARK: - Report Safety Sheet

struct ReportSafetySheet: View {
    @Binding var isPresented: Bool
    let onReport: (String, String?) async throws -> Void

    @State private var selectedReason: String = ""
    @State private var detailsText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Reason selector
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("What's your concern?")
                        .font(.headline)

                    Picker("Reason", selection: $selectedReason) {
                        ForEach(MentorshipSafetyService.safetyReasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Details
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Additional details (optional)")
                        .font(.subheadline)

                    TextEditor(text: $detailsText)
                        .scrollContentBackground(.hidden)
                        .supportField()
                        .frame(height: 100)
                        .padding(SupportTheme.Spacing.xs)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)
                }

                Spacer()

                // Actions
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button(action: {
                        isSending = true
                        errorMessage = nil
                        Task {
                            defer { isSending = false }
                            do {
                                try await onReport(selectedReason, detailsText.isEmpty ? nil : detailsText)
                                isPresented = false
                            } catch {
                                errorMessage = "The report could not be saved. Your details are still here; please try again."
                            }
                        }
                    }) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Submit Report")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.s)
                    .background(Color.red)
                    .foregroundColor(SupportTheme.textPrimary)
                    .cornerRadius(SupportTheme.controlRadius)
                    .disabled(selectedReason.isEmpty || isSending)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }

                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(SupportTheme.field)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
            .padding()
            .disabled(isSending)
            .interactiveDismissDisabled(isSending)
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Report Safety Concern")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - End Mentorship Sheet

struct EndMentorshipSheet: View {
    @Binding var isPresented: Bool
    let onEnd: (String) async throws -> Void
    @State private var errorMessage: String?
    @State private var reasonText = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Why are you ending this mentorship?")
                        .font(.headline)

                    TextEditor(text: $reasonText)
                        .scrollContentBackground(.hidden)
                        .supportField()
                        .frame(height: 120)
                        .padding(SupportTheme.Spacing.xs)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)
                }

                Spacer()
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button(action: {
                        isSending = true
                        errorMessage = nil
                        Task {
                            defer { isSending = false }
                            do {
                                try await onEnd(reasonText.trimmingCharacters(in: .whitespacesAndNewlines))
                                isPresented = false
                            } catch {
                                errorMessage = "The mentorship could not be ended. Please try again."
                            }
                        }
                    }) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("End Mentorship")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.s)
                    .background(Color.red)
                    .foregroundColor(SupportTheme.textPrimary)
                    .cornerRadius(SupportTheme.controlRadius)
                    .disabled(isSending)

                    Button(action: { isPresented = false }) {
                        Text("Keep Going")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(SupportTheme.field)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                    .disabled(isSending)
                }
            }
            .padding()
            .interactiveDismissDisabled(isSending)
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("End Mentorship")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Environment Key

struct CurrentUserKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var currentUser: UUID? {
        get { self[CurrentUserKey.self] }
        set { self[CurrentUserKey.self] = newValue }
    }
}
