import SwiftUI

/// Container view for mentorship tab navigation
/// Handles routing between profile, find mentors, match list, and chat views
struct MentorshipTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    // Navigation state
    @State private var navigationPath: [MentorshipNavigationDestination] = []
    @State private var selectedSection: MentorshipSection = .home

    // Convenience accessors to facade's sub-services
    private var profileService: MentorshipProfileService { container.mentorshipService.profileService }
    private var matchingService: MentorshipMatchingService { container.mentorshipService.matchingService }
    private var messagingService: MentorshipMessagingService { container.mentorshipService.messagingService }
    private var safetyService: MentorshipSafetyService { container.mentorshipService.safetyService }
    private var encryptionService: MentorshipEncryptionService { container.mentorshipService.encryptionService }

    enum MentorshipSection: String, CaseIterable {
        case home
        case findMentor
        case myMatches
        case profile

        var title: String {
            switch self {
            case .home: return "Mentorship"
            case .findMentor: return "Find a Mentor"
            case .myMatches: return "My Matches"
            case .profile: return "Profile"
            }
        }

        var icon: String {
            switch self {
            case .home: return "star.fill"
            case .findMentor: return "magnifyingglass"
            case .myMatches: return "person.2.fill"
            case .profile: return "person.fill"
            }
        }
    }

    var body: some View {
        Group {
            switch selectedSection {
            case .home:
                MentorshipHomeView(
                    navigationPath: $navigationPath,
                    selectedSection: $selectedSection,
                    matchingService: matchingService,
                    profileService: profileService
                )

            case .findMentor:
                FindMentorView(
                    navigationPath: $navigationPath,
                    matchingService: matchingService
                )

            case .myMatches:
                MentorshipListView(
                    navigationPath: $navigationPath,
                    matchingService: matchingService,
                    messagingService: messagingService
                )

            case .profile:
                MentorshipProfileView()
            }
        }
        .navigationDestination(for: MentorshipNavigationDestination.self) { destination in
            navigationDestinationView(for: destination)
        }
        .environmentObject(profileService)
        .environmentObject(matchingService)
        .environmentObject(messagingService)
        .environmentObject(safetyService)
        .environmentObject(encryptionService)
    }

    @ViewBuilder
    private func navigationDestinationView(for destination: MentorshipNavigationDestination) -> some View {
        switch destination {
        case .chat(let matchId):
            MentorshipChatView(matchId: matchId)

        case .matchDetails(let matchId):
            MentorshipMatchDetailsView(
                matchId: matchId,
                navigationPath: $navigationPath,
                matchingService: matchingService
            )
        }
    }
}

/// Navigation destinations for mentorship flow
enum MentorshipNavigationDestination: Hashable {
    case chat(matchId: UUID)
    case matchDetails(matchId: UUID)
}

/// Home view for mentorship tab - shows quick stats and actions
struct MentorshipHomeView: View {
    @Binding var navigationPath: [MentorshipNavigationDestination]
    @Binding var selectedSection: MentorshipTabView.MentorshipSection

    @ObservedObject var matchingService: MentorshipMatchingService
    @ObservedObject var profileService: MentorshipProfileService

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusCard
                quickActions
                recentMatchesSection
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Mentorship")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Extracted Views

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusInfo
                Spacer()
                activeCount
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    private var statusInfo: some View {
        VStack(alignment: .leading) {
            Text("Your Mentorship Status")
                .font(.headline)
            if profileService.isMentorAvailable {
                Label("Available as mentor", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            } else {
                Label("Seeking a mentor", systemImage: "magnifyingglass.circle")
                    .foregroundColor(.blue)
                    .font(.subheadline)
            }
        }
    }

    private var activeCount: some View {
        VStack(alignment: .trailing) {
            Text("\(matchingService.activeMatches.count)")
                .font(.title2)
                .fontWeight(.bold)
            Text("Active")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            findMentorButton
            viewMatchesButton
            pendingRequestsButton
        }
        .padding(.horizontal)
    }

    private var findMentorButton: some View {
        Button(action: { selectedSection = .findMentor }) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Find a Mentor")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    private var viewMatchesButton: some View {
        Button(action: { selectedSection = .myMatches }) {
            HStack {
                Image(systemName: "person.2.fill")
                Text("View My Matches (\(matchingService.activeMatches.count))")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(10)
        }
    }

    @ViewBuilder
    private var pendingRequestsButton: some View {
        if matchingService.pendingRequests.count > 0 {
            Button(action: { selectedSection = .myMatches }) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                    Text("Pending Requests (\(matchingService.pendingRequests.count))")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(10)
            }
        }
    }

    @ViewBuilder
    private var recentMatchesSection: some View {
        if !matchingService.activeMatches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Conversations")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(matchingService.activeMatches.prefix(3)) { match in
                    recentMatchRow(match)
                }
            }
            .padding(.horizontal)
        }
    }

    private func recentMatchRow(_ match: MentorshipMatch) -> some View {
        Button(action: { navigationPath.append(.chat(matchId: match.id)) }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Match \(match.id.uuidString.prefix(8).uppercased())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if let score = match.compatibilityScore {
                        Text("Compatibility: \(Int(score * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

/// Match details view with full information and actions
struct MentorshipMatchDetailsView: View {
    let matchId: UUID
    @Binding var navigationPath: [MentorshipNavigationDestination]
    @ObservedObject var matchingService: MentorshipMatchingService
    @State private var isLoading = true
    @State private var error: String?

    var match: MentorshipMatch? {
        matchingService.userMatches.first { $0.id == matchId }
    }

    var body: some View {
        ScrollView {
            if let match = match {
                VStack(spacing: 20) {
                    // Match Header
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Match \(match.id.uuidString.prefix(8).uppercased())")
                                    .font(.headline)
                                HStack {
                                    Circle()
                                        .fill(statusColor(match.status))
                                        .frame(width: 8, height: 8)
                                    Text(match.status.rawValue.capitalized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Compatibility Score
                    if let score = match.compatibilityScore {
                        VStack(spacing: 8) {
                            Text("Compatibility Score")
                                .font(.headline)
                            HStack(spacing: 12) {
                                ProgressView(value: score)
                                    .tint(Color.green)
                                Text("\(Int(score * 100))%")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            if let reason = match.matchReason, !reason.isEmpty {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Match Information
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Status", value: match.status.rawValue.capitalized)
                        Divider()
                        InfoRow(label: "Created", value: formatDate(match.createdAt))
                        Divider()
                        if let expiresAt = match.expiresAt {
                            InfoRow(label: "Expires", value: formatDate(expiresAt))
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Actions
                    if match.isActive {
                        Button(action: {
                            navigationPath.append(.chat(matchId: match.id))
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Send Message")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)
            } else {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading match details...")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Match Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusColor(_ status: MentorshipStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .active: return .green
        case .completed: return .blue
        case .cancelled: return .gray
        case .ended: return .gray
        case .expired: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// Helper component for displaying key-value information
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    MentorshipTabView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
