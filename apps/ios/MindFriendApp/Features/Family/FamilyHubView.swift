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
            if viewModel.isLoading && viewModel.familyGroup == nil {
                ProgressView("Loading family…")
            } else if let error = viewModel.error, viewModel.familyGroup == nil {
                ContentUnavailableView {
                    Label("Family Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await reloadFamily() } }
                }
            } else if let family = viewModel.familyGroup {
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
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Family Wellness")
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
            VStack(spacing: SupportTheme.Spacing.m) {
                if let family = viewModel.familyGroup {
                    // Family Card
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        HStack {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text(family.name)
                                    .font(.headline)
                                Text("\(viewModel.familyMembers.count) members")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
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
                                    .foregroundStyle(SupportTheme.textSecondary)
                                Text(inviteCode)
                                    .font(.caption.monospaced())
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(action: { UIPasteboard.general.string = inviteCode }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                }
                                .accessibilityLabel("Copy family invite code")
                            }
                            .padding(SupportTheme.Spacing.xs)
                            .background(SupportTheme.surface)
                            .cornerRadius(SupportTheme.controlRadius)
                        }
                    }
                    .supportCard()
                    .shadow(radius: 1)

                    // Active Challenges
                    if !viewModel.activeChallenges.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Active Challenges")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(viewModel.activeChallenges.filter { $0.challengeType != .streak }.prefix(3), id: \.id) { challenge in
                                ChallengeProgressCard(challenge: challenge)
                            }
                        }
                        .supportCard()
                        .shadow(radius: 1)
                    }

                    // Recent Together Sessions
                    if !viewModel.recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Recent Activities")
                                .font(.headline)
                            ForEach(viewModel.recentSessions.prefix(2), id: \.id) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                        Text(session.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(session.status.rawValue.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(SupportTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                                .supportCard()
                            }
                        }
                        .supportCard()
                        .shadow(radius: 1)
                    }

                    // Quick Actions
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Button(action: {
                            // Start Together Session
                        }) {
                            Label("Start Activity", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.supportSecondary)

                        Button(action: {
                            // Create Challenge
                        }) {
                            Label("New Challenge", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.supportSecondary)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(SupportTheme.accent)

                Text("No Family Group")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Connect with family members for shared wellness activities")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button(action: { showCreateFamilySheet = true }) {
                        Text("Create Family")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)

                    Button(action: { showJoinFamilySheet = true }) {
                        Text("Join Family")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .padding()
        .sheet(isPresented: $showCreateFamilySheet, onDismiss: {
            Task { await reloadFamily() }
        }) {
            NavigationStack {
                CreateFamilySheet(isPresented: $showCreateFamilySheet)
                    .environmentObject(container)
            }
        }
        .sheet(isPresented: $showJoinFamilySheet, onDismiss: {
            Task { await reloadFamily() }
        }) {
            NavigationStack {
                JoinFamilySheet(isPresented: $showJoinFamilySheet)
                    .environmentObject(container)
            }
        }
    }

    private func reloadFamily() async {
        await viewModel.loadData(familyService: container.familyService, supabase: container.supabaseClient)
    }
}

// MARK: - Supporting Views

struct ChallengeProgressCard: View {
    let challenge: FamilyChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(challenge.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: SupportTheme.Spacing.s) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Progress")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    ProgressView(value: challenge.progressPercentage)
                }

                VStack(alignment: .trailing) {
                    Text("\(challenge.currentProgress)/\(challenge.targetValue)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .supportCard()
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
