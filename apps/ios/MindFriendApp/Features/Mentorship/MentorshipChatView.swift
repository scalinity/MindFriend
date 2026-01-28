import SwiftUI

/// View for mentorship messaging/chat
struct MentorshipChatView: View {
    let matchId: UUID
    @EnvironmentObject var container: DependencyContainer

    @State private var messageText = ""
    @State private var showingReportSheet = false
    @State private var showingEndSheet = false

    private var messagingService: MentorshipMessagingService { container.mentorshipService.messagingService }
    private var safetyService: MentorshipSafetyService { container.mentorshipService.safetyService }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8, pinnedViews: []) {
                            ForEach(messagingService.messages) { message in
                                MentorshipMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messagingService.messages.count) { _ in
                        if let lastId = messagingService.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Message input
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Type a message...", text: $messageText)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3)

                        Button(action: {
                            if !messageText.trimmingCharacters(in: .whitespaces).isEmpty {
                                Task {
                                    do {
                                        try await messagingService.sendMessage(
                                            matchId: matchId,
                                            content: messageText
                                        )
                                        messageText = ""
                                    } catch {
                                        // Error handled by messagingService.error
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  messagingService.isSending)
                    }

                    HStack(spacing: 12) {
                        Menu {
                            Button(role: .destructive, action: { showingReportSheet = true }) {
                                Label("Report Safety Concern", systemImage: "exclamationmark.shield")
                            }

                            Button(role: .destructive, action: { showingEndSheet = true }) {
                                Label("End Mentorship", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if messagingService.hasUnreadMessages {
                            Button(action: {
                                Task {
                                    await messagingService.markAsRead(matchId: matchId)
                                }
                            }) {
                                Text("Mark as Read")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
        }
        .navigationTitle("Mentorship Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReportSheet) {
            ReportSafetySheet(
                matchId: matchId,
                isPresented: $showingReportSheet,
                onReport: { reason, description in
                    Task {
                        await safetyService.reportMentorship(
                            matchId: matchId,
                            reportedUserId: UUID(),  // Would come from match data
                            reason: reason,
                            description: description
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $showingEndSheet) {
            EndMentorshipSheet(isPresented: $showingEndSheet)
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
        // Compare sender ID with current user ID
        true  // Placeholder - would check actual user
    }

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isCurrentUser
                            ? Color.blue.opacity(0.8)
                            : Color(.secondarySystemBackground)
                    )
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(12)

                HStack(spacing: 4) {
                    if message.isSafetyFlagged {
                        Label("Flagged", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
    let matchId: UUID
    @Binding var isPresented: Bool
    let onReport: (String, String?) -> Void

    @State private var selectedReason: String = ""
    @State private var detailsText = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Reason selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's your concern?")
                        .font(.headline)

                    Picker("Reason", selection: $selectedReason) {
                        ForEach(MentorshipSafetyService.safetyReasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional details (optional)")
                        .font(.subheadline)

                    TextEditor(text: $detailsText)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        isSending = true
                        onReport(selectedReason, detailsText.isEmpty ? nil : detailsText)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isPresented = false
                        }
                    }) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Submit Report")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(selectedReason.isEmpty || isSending)

                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.quaternarySystemFill))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationTitle("Report Safety Concern")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - End Mentorship Sheet

struct EndMentorshipSheet: View {
    @Binding var isPresented: Bool
    @State private var reasonText = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why are you ending this mentorship?")
                        .font(.headline)

                    TextEditor(text: $reasonText)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        isSending = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isPresented = false
                        }
                    }) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("End Mentorship")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isSending)

                    Button(action: { isPresented = false }) {
                        Text("Keep Going")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.quaternarySystemFill))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
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
