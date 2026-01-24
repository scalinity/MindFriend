import SwiftUI
import Supabase

/// View displaying the user's mentorship matches (as mentor or mentee)
struct MentorshipMatchesView: View {
    @StateObject private var service: MentorshipService
    @Environment(\.dismiss) private var dismiss

    private let supabase: SupabaseClient
    private let currentUserId: UUID?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        _service = StateObject(wrappedValue: MentorshipService(supabase: supabase))
        self.currentUserId = supabase.auth.currentUser?.id
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    ProgressView("Loading matches...")
                } else if service.matches.isEmpty {
                    emptyState
                } else {
                    matchesList
                }
            }
            .navigationTitle("My Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                _ = try? await service.fetchMatches()
            }
            .refreshable {
                _ = try? await service.fetchMatches()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Matches Yet",
            systemImage: "person.2.slash",
            description: Text("Find a mentor or become one to start meaningful connections.")
        )
    }

    // MARK: - Matches List

    private var matchesList: some View {
        List {
            // Pending requests (I sent or received)
            let pendingMatches = service.matches.filter { $0.status == .pending }
            if !pendingMatches.isEmpty {
                Section("Pending Requests") {
                    ForEach(pendingMatches) { match in
                        MatchRow(
                            match: match,
                            isMentor: currentUserId == match.mentorId,
                            supabase: supabase,
                            service: service
                        )
                    }
                }
            }

            // Active mentorships
            let activeMatches = service.matches.filter { $0.status == .active }
            if !activeMatches.isEmpty {
                Section("Active Mentorships") {
                    ForEach(activeMatches) { match in
                        NavigationLink {
                            MentorshipChatView(match: match, supabase: supabase)
                        } label: {
                            MatchRow(
                                match: match,
                                isMentor: currentUserId == match.mentorId,
                                supabase: supabase,
                                service: service,
                                showNavArrow: false
                            )
                        }
                    }
                }
            }

            // Completed/ended
            let pastMatches = service.matches.filter {
                $0.status == .completed || $0.status == .ended || $0.status == .declined
            }
            if !pastMatches.isEmpty {
                Section("Past Mentorships") {
                    ForEach(pastMatches) { match in
                        MatchRow(
                            match: match,
                            isMentor: currentUserId == match.mentorId,
                            supabase: supabase,
                            service: service
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Match Row

private struct MatchRow: View {
    let match: DBMentorshipMatch
    let isMentor: Bool
    let supabase: SupabaseClient
    let service: MentorshipService
    var showNavArrow: Bool = true

    @State private var showAcceptSheet = false
    @State private var showDeclineSheet = false
    @State private var isProcessing = false

    private var otherAlias: String {
        isMentor ? match.menteeAlias : match.mentorAlias
    }

    private var roleLabel: String {
        isMentor ? "You are mentoring" : "Your mentor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Avatar placeholder
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: isMentor ? "person.fill" : "person.fill.checkmark")
                            .foregroundStyle(Color.accentColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(otherAlias)
                        .font(.headline)
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge

                    if let score = match.compatibilityScore {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("\(Int(score))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if showNavArrow && match.status == .active {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Match reason
            if let reason = match.matchReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Pending actions for mentor
            if match.status == .pending && isMentor {
                pendingActions
            }

            // Introduction message preview for pending
            if match.status == .pending, let intro = match.introductionMessage {
                Text(intro)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showAcceptSheet) {
            RespondToMatchSheet(
                match: match,
                service: service,
                isAccepting: true
            )
        }
        .sheet(isPresented: $showDeclineSheet) {
            RespondToMatchSheet(
                match: match,
                service: service,
                isAccepting: false
            )
        }
    }

    private var statusBadge: some View {
        Text(match.status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch match.status {
        case .pending: return .orange
        case .accepted: return .blue
        case .active: return .green
        case .completed: return .purple
        case .declined: return .red
        case .ended: return .gray
        case .suspended: return .red
        }
    }

    private var pendingActions: some View {
        HStack(spacing: 12) {
            Button {
                showDeclineSheet = true
            } label: {
                Text("Decline")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)

            Button {
                showAcceptSheet = true
            } label: {
                Text("Accept")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
        }
        .padding(.top, 8)
    }
}

// MARK: - Respond Sheet

private struct RespondToMatchSheet: View {
    let match: DBMentorshipMatch
    let service: MentorshipService
    let isAccepting: Bool

    @State private var responseMessage = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentColor)
                            }

                        VStack(alignment: .leading) {
                            Text(match.menteeAlias)
                                .font(.headline)
                            if let reason = match.matchReason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Mentee Request")
                }

                if let intro = match.introductionMessage {
                    Section("Their Message") {
                        Text(intro)
                            .font(.subheadline)
                    }
                }

                Section {
                    TextEditor(text: $responseMessage)
                        .frame(minHeight: 80)
                } header: {
                    Text("Your Response (Optional)")
                } footer: {
                    Text(isAccepting
                        ? "Share a welcome message or set expectations."
                        : "Let them know why this isn't a good fit right now."
                    )
                }

                Section {
                    Button {
                        Task { await submitResponse() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text(isAccepting ? "Accept Request" : "Decline Request")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting)
                    .foregroundStyle(isAccepting ? .white : .red)
                    .listRowBackground(isAccepting ? Color.accentColor : Color.red.opacity(0.15))
                }
            }
            .navigationTitle(isAccepting ? "Accept Mentorship" : "Decline Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private func submitResponse() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if isAccepting {
                try await service.acceptMatch(
                    match.id,
                    responseMessage: responseMessage.isEmpty ? nil : responseMessage
                )
            } else {
                try await service.declineMatch(
                    match.id,
                    responseMessage: responseMessage.isEmpty ? nil : responseMessage
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Log.social.error("Failed to respond to match", error: error)
        }
    }
}

#Preview {
    MentorshipMatchesView(supabase: DependencyContainer.preview.supabase)
}
