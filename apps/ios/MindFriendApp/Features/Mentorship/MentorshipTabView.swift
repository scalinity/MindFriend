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
        NavigationStack(path: $navigationPath) {
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
                    MentorshipProfileView(profileService: profileService)
                }
            }
            .navigationDestination(for: MentorshipNavigationDestination.self) { destination in
                navigationDestinationView(for: destination)
            }
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
            MentorshipChatView(
                matchId: matchId,
                navigationPath: $navigationPath,
                messagingService: messagingService,
                safetyService: safetyService,
                encryptionService: encryptionService
            )

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
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
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
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(matchingService.activeMatches.count)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Quick Actions
                    VStack(spacing: 10) {
                        Button(action: {
                            selectedSection = .findMentor
                        }) {
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

                        Button(action: {
                            selectedSection = .myMatches
                        }) {
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

                        if matchingService.pendingRequests.count > 0 {
                            Button(action: {
                                selectedSection = .myMatches
                            }) {
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
                    .padding(.horizontal)

                    // Recent Matches
                    if !matchingService.activeMatches.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Conversations")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(matchingService.activeMatches.prefix(3)) { match in
                                Button(action: {
                                    navigationPath.append(.chat(matchId: match.id))
                                }) {
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
                                            Text("Compatibility: \(Int(match.compatibilityScore * 100))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
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
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Mentorship")
            .navigationBarTitleDisplayMode(.inline)
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
                    VStack(spacing: 8) {
                        Text("Compatibility Score")
                            .font(.headline)
                        HStack(spacing: 12) {
                            ProgressView(value: match.compatibilityScore)
                                .tint(Color.green)
                            Text("\(Int(match.compatibilityScore * 100))%")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        if !match.matchReason.isEmpty {
                            Text(match.matchReason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

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
