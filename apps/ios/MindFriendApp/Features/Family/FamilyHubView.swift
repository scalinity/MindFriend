import SwiftUI

/// Main family wellness hub view showing family overview and quick actions
struct FamilyHubView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel: FamilyHubViewModel

    @State private var showCreateFamilySheet = false
    @State private var showJoinFamilySheet = false
    @State private var selectedTab: FamilyTab = .overview

    init() {
        _viewModel = StateObject(wrappedValue: FamilyHubViewModel())
    }

    var body: some View {
        ZStack {
            if let family = viewModel.familyGroup {
                TabView(selection: $selectedTab) {
                    // Overview Tab
                    overviewTabContent
                        .tag(FamilyTab.overview)

                    // Members Tab
                    FamilyMembersView(familyGroup: family)
                        .tag(FamilyTab.members)

                    // Challenges Tab
                    FamilyChallengesView(familyGroup: family)
                        .tag(FamilyTab.challenges)

                    // Together Tab
                    TogetherSessionsView(familyGroup: family)
                        .tag(FamilyTab.together)

                    // Alerts Tab (if user is parent)
                    if viewModel.userRole.canManageFamily {
                        FamilyAlertsView(familyGroup: family)
                            .tag(FamilyTab.alerts)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                // No family - show empty state with actions
                emptyStateContent
            }
        }
        .navigationTitle("Family Wellness")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData(
                familyService: container.familyService,
                supabase: container.supabaseClient
            )
        }
        .refreshable {
            await viewModel.loadData(
                familyService: container.familyService,
                supabase: container.supabaseClient
            )
        }
    }

    // MARK: - Overview Tab Content

    private var overviewTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let family = viewModel.familyGroup {
                    // Family Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(family.name)
                                    .font(.headline)
                                Text("\(viewModel.familyMembers.count) members")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let avatar = family.avatarUrl {
                                AsyncImage(url: URL(string: avatar)) { image in
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 32))
                                }
                            }
                        }

                        // Invite code
                        if let inviteCode = family.inviteCode {
                            HStack {
                                Text("Invite Code:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(inviteCode)
                                    .font(.caption.monospaced())
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(action: { UIPasteboard.general.string = inviteCode }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                            }
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(.white)
                    .cornerRadius(12)
                    .shadow(radius: 1)

                    // Active Challenges
                    if !viewModel.activeChallenges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Active Challenges")
                                .font(.headline)
                            ForEach(viewModel.activeChallenges.prefix(3), id: \.id) { challenge in
                                ChallengeProgressCard(challenge: challenge)
                            }
                        }
                        .padding()
                        .background(.white)
                        .cornerRadius(12)
                        .shadow(radius: 1)
                    }

                    // Recent Together Sessions
                    if !viewModel.recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Activities")
                                .font(.headline)
                            ForEach(viewModel.recentSessions.prefix(2), id: \.id) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(session.status.rawValue.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(.white)
                        .cornerRadius(12)
                        .shadow(radius: 1)
                    }

                    // Quick Actions
                    VStack(spacing: 12) {
                        Button(action: {
                            // Start Together Session
                        }) {
                            Label("Start Activity", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            // Create Challenge
                        }) {
                            Label("New Challenge", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.green)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("No Family Group")
                .font(.headline)

            Text("Connect with family members for shared wellness activities")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: { showCreateFamilySheet = true }) {
                    Text("Create Family")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                Button(action: { showJoinFamilySheet = true }) {
                    Text("Join Family")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showCreateFamilySheet) {
            CreateFamilySheet(isPresented: $showCreateFamilySheet)
                .environmentObject(container)
        }
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet(isPresented: $showJoinFamilySheet)
                .environmentObject(container)
        }
    }
}

// MARK: - Supporting Views

struct ChallengeProgressCard: View {
    let challenge: FamilyChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(challenge.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: challenge.progressPercentage)
                }

                VStack(alignment: .trailing) {
                    Text("\(challenge.currentProgress)/\(challenge.targetValue)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Tab Enumeration

enum FamilyTab: String, CaseIterable {
    case overview = "Overview"
    case members = "Members"
    case challenges = "Challenges"
    case together = "Together"
    case alerts = "Alerts"
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FamilyHubView()
            .environmentObject(DependencyContainer.preview)
    }
}
