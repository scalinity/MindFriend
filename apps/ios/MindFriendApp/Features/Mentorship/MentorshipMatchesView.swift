import SwiftUI

/// View displaying the user's mentorship matches (as mentor or mentee)
struct MentorshipMatchesView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    private var service: MentorshipService { container.mentorshipService }
    private var currentUserId: UUID? { container.supabaseAuthService.currentUser?.id }

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
                            MentorshipChatView(matchId: match.id)
                        } label: {
                            MatchRow(
                                match: match,
                                isMentor: currentUserId == match.mentorId,
                                service: service,
                                showNavArrow: false
                            )
                        }
                    }
                }
            }

            // Completed/ended
            let pastMatches = service.matches.filter {
                $0.status == .completed || $0.status == .ended || $0.status == .cancelled || $0.status == .expired
            }
            if !pastMatches.isEmpty {
                Section("Past Mentorships") {
                    ForEach(pastMatches) { match in
                        MatchRow(
                            match: match,
                            isMentor: currentUserId == match.mentorId,
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
    let match: MentorshipMatch
    let isMentor: Bool
    let service: MentorshipService
    var showNavArrow: Bool = true

    @State private var showAcceptSheet = false
    @State private var showDeclineSheet = false
    @State private var isProcessing = false

    private var displayName: String {
        // Use truncated UUID as display name since aliases aren't stored on match
        let otherId = isMentor ? match.menteeId : match.mentorId
        return String(otherId.uuidString.prefix(8)).uppercased()
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
                    Text(displayName)
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
        Text(match.status.rawValue.capitalized)
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
        case .active: return .green
        case .completed: return .purple
        case .cancelled: return .gray
        case .ended: return .gray
        case .expired: return .red
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
    let match: MentorshipMatch
    let service: MentorshipService
    let isAccepting: Bool

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var displayName: String {
        String(match.menteeId.uuidString.prefix(8)).uppercased()
    }

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
                            Text(displayName)
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
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
                try await service.acceptMatch(match.id)
            } else {
                try await service.declineMatch(match.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MentorshipMatchesView()
        .environmentObject(DependencyContainer())
}
