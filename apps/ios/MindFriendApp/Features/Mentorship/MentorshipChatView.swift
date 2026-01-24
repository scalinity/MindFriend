import SwiftUI
import Supabase

/// Secure messaging view for mentorship conversations
struct MentorshipChatView: View {
    let match: DBMentorshipMatch
    @StateObject private var service: MentorshipService
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var showReportSheet = false
    @State private var showEndConfirmation = false
    @State private var isSending = false
    @State private var errorMessage: String?

    private let currentUserId: UUID?

    init(match: DBMentorshipMatch, supabase: SupabaseClient) {
        self.match = match
        _service = StateObject(wrappedValue: MentorshipService(supabase: supabase))
        self.currentUserId = supabase.auth.currentUser?.id
    }

    private var isMentor: Bool {
        currentUserId == match.mentorId
    }

    private var myAlias: String {
        isMentor ? match.mentorAlias : match.menteeAlias
    }

    private var theirAlias: String {
        isMentor ? match.menteeAlias : match.mentorAlias
    }

    private var otherUserId: UUID {
        isMentor ? match.menteeId : match.mentorId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Info
            headerView

            Divider()

            // Messages
            messagesView

            Divider()

            // Input Area
            if match.status == .active {
                inputArea
            } else {
                matchStatusBanner
            }
        }
        .navigationTitle(theirAlias)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showReportSheet = true
                    } label: {
                        Label("Report Issue", systemImage: "exclamationmark.triangle")
                    }

                    if match.status == .active {
                        Button(role: .destructive) {
                            showEndConfirmation = true
                        } label: {
                            Label("End Mentorship", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportIssueSheet(
                matchId: match.id,
                reportedUserId: otherUserId,
                service: service
            )
        }
        .confirmationDialog(
            "End Mentorship",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Mentorship", role: .destructive) {
                Task { await endMentorship() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this mentorship? This action cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await loadMessages()
            await service.subscribeToMessages(matchId: match.id)
        }
        .onDisappear {
            Task {
                await service.cleanup()
            }
        }
    }

    // MARK: - View Components

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                // Compatibility Score
                if let score = match.compatibilityScore {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("\(Int(score))% match")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(Capsule())
                }

                Spacer()

                // Duration info
                if let startedAt = match.startedAt {
                    Text("Started \(startedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = match.matchReason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.currentMessages) { message in
                        MentorshipMessageBubble(
                            message: message,
                            isFromMe: message.senderId == currentUserId,
                            senderAlias: message.senderId == currentUserId ? myAlias : theirAlias
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: service.currentMessages.count) { _, _ in
                if let lastMessage = service.currentMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button {
                Task { await sendMessage() }
            } label: {
                if isSending {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var matchStatusBanner: some View {
        HStack {
            Image(systemName: statusIcon)
            Text(statusMessage)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var statusIcon: String {
        switch match.status {
        case .pending: return "clock"
        case .accepted: return "checkmark.circle"
        case .completed: return "checkmark.seal"
        case .declined: return "xmark.circle"
        case .ended: return "stop.circle"
        case .suspended: return "exclamationmark.triangle"
        case .active: return "bubble.left.and.bubble.right"
        }
    }

    private var statusMessage: String {
        switch match.status {
        case .pending: return "Waiting for mentor to accept..."
        case .accepted: return "Mentorship accepted! Waiting to start..."
        case .completed: return "This mentorship has been completed."
        case .declined: return "This request was declined."
        case .ended: return "This mentorship has ended."
        case .suspended: return "This mentorship has been suspended."
        case .active: return ""
        }
    }

    // MARK: - Actions

    private func loadMessages() async {
        do {
            _ = try await service.fetchMessages(matchId: match.id)
            try await service.markMessagesAsRead(matchId: match.id)
        } catch {
            Log.social.error("Failed to load messages", error: error)
        }
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        messageText = ""

        do {
            try await service.sendMessage(matchId: match.id, content: text)
        } catch {
            messageText = text // Restore message on failure
            errorMessage = error.localizedDescription
            Log.social.error("Failed to send message", error: error)
        }

        isSending = false
    }

    private func endMentorship() async {
        do {
            try await service.endMentorship(match.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Log.social.error("Failed to end mentorship", error: error)
        }
    }
}

// MARK: - Message Bubble

private struct MentorshipMessageBubble: View {
    let message: DBMentorshipMessage
    let isFromMe: Bool
    let senderAlias: String

    var body: some View {
        HStack {
            if isFromMe { Spacer(minLength: 60) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                if !isFromMe {
                    Text(senderAlias)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromMe ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundStyle(isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    Text(message.sentAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if message.flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !isFromMe { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(senderAlias): \(message.content)")
    }
}

// MARK: - Report Sheet

private struct ReportIssueSheet: View {
    let matchId: UUID
    let reportedUserId: UUID
    let service: MentorshipService

    @State private var selectedReason: DBMentorshipReport.ReportReason = .other
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(DBMentorshipReport.ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                } header: {
                    Text("What's the issue?")
                }

                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                } header: {
                    Text("Additional Details")
                } footer: {
                    Text("Please provide as much detail as possible to help us investigate.")
                }

                Section {
                    Button {
                        Task { await submitReport() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Submit Report")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you for reporting. Our team will review this within 24 hours.")
            }
        }
    }

    private func submitReport() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await service.reportIssue(
                matchId: matchId,
                reportedUserId: reportedUserId,
                reason: selectedReason,
                description: description.isEmpty ? nil : description
            )
            showSuccess = true
        } catch {
            Log.social.error("Failed to submit report", error: error)
        }
    }
}

#Preview {
    NavigationStack {
        MentorshipChatView(
            match: DBMentorshipMatch(
                id: UUID(),
                mentorId: UUID(),
                menteeId: UUID(),
                matchedAt: Date(),
                status: .active,
                compatibilityScore: 85.5,
                matchReason: "Experienced in anxiety and stress management",
                expertiseMatchScore: 1.0,
                languageMatchScore: 1.0,
                timezoneMatchScore: 0.8,
                availabilityMatchScore: 0.9,
                introductionMessage: nil,
                mentorResponse: nil,
                startedAt: Date().addingTimeInterval(-86400 * 7),
                endedAt: nil,
                endReason: nil,
                durationWeeks: 4,
                mentorAlias: "Wise Oak",
                menteeAlias: "Calm River",
                createdAt: Date(),
                updatedAt: Date()
            ),
            supabase: DependencyContainer.preview.supabase
        )
    }
}
