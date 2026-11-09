import SwiftUI

/// View showing all mentorship matches for current user
struct MentorshipListView: View {
    @Binding var navigationPath: [MentorshipNavigationDestination]
    @ObservedObject var matchingService: MentorshipMatchingService
    @ObservedObject var messagingService: MentorshipMessagingService
    @State private var selectedTab: Tab = .active
    @State private var selectedMatch: MentorshipMatch?
    @State private var showingDetails = false

    enum Tab {
        case active
        case pending
        case all
    }

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab selector
                Picker("Matches", selection: $selectedTab) {
                    Text("Active").tag(Tab.active)
                    Text("Pending").tag(Tab.pending)
                    Text("All").tag(Tab.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(SupportTheme.surface)

                // Content
                if matchingService.isLoading {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        ProgressView()
                        Text("Loading mentorships...")
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if filteredMatches.isEmpty {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: tabEmptyImage)
                            .font(.system(size: 48))
                            .foregroundColor(SupportTheme.textSecondary)

                        Text(tabEmptyTitle)
                            .font(.headline)

                        Text(tabEmptyMessage)
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: SupportTheme.Spacing.s) {
                            ForEach(filteredMatches) { match in
                                MatchCard(
                                    match: match,
                                    action: {
                                        selectedMatch = match
                                        showingDetails = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("My Mentorships")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let error = matchingService.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
            }
        }
        .sheet(isPresented: $showingDetails) {
            if let match = selectedMatch {
                MatchDetailsSheet(
                    match: match,
                    navigationPath: $navigationPath,
                    isPresented: $showingDetails
                )
            }
        }
        .onAppear {
            Task {
                await matchingService.loadMatches()
            }
        }
    }

    private var filteredMatches: [MentorshipMatch] {
        switch selectedTab {
        case .active:
            return matchingService.activeMatches
        case .pending:
            return matchingService.pendingRequests
        case .all:
            return matchingService.userMatches
        }
    }

    private var tabEmptyTitle: String {
        switch selectedTab {
        case .active:
            return "No Active Mentorships"
        case .pending:
            return "No Pending Requests"
        case .all:
            return "No Mentorships"
        }
    }

    private var tabEmptyMessage: String {
        switch selectedTab {
        case .active:
            return "Start by finding a mentor or waiting for mentee requests"
        case .pending:
            return "You don't have any pending mentorship requests"
        case .all:
            return "You haven't joined any mentorships yet"
        }
    }

    private var tabEmptyImage: String {
        switch selectedTab {
        case .active:
            return "person.2"
        case .pending:
            return "clock"
        case .all:
            return "person.slash"
        }
    }
}

// MARK: - Match Card

struct MatchCard: View {
    let match: MentorshipMatch
    let action: () -> Void

    var statusColor: Color {
        switch match.status {
        case .pending:
            return SupportTheme.accent
        case .active, .accepted:
            return SupportTheme.accent
        case .completed:
            return SupportTheme.accent
        case .cancelled, .declined:
            return SupportTheme.textSecondary
        case .ended:
            return SupportTheme.textSecondary
        case .expired, .suspended:
            return .red
        }
    }

    var statusLabel: String {
        match.status.rawValue.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Mentorship Match")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)

                    Text(match.id.uuidString.prefix(8).uppercased())
                        .font(.headline)
                }

                Spacer()

                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption)
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(SupportTheme.controlRadius)
            }

            if let compatibilityScore = match.compatibilityScore {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Text("Compatibility")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)

                    ProgressView(value: compatibilityScore)
                        .tint(SupportTheme.accent)

                    Text("\(Int(compatibilityScore * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }

            if let reason = match.matchReason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            Button(action: action) {
                Text("View Details")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xs)
                    .background(SupportTheme.field)
                    .foregroundColor(SupportTheme.textPrimary)
                    .cornerRadius(SupportTheme.controlRadius)
            }
        }
        .supportCard()
    }

    private var statusIcon: String {
        switch match.status {
        case .pending:
            return "clock"
        case .active, .accepted:
            return "checkmark.circle.fill"
        case .completed:
            return "star.circle.fill"
        case .cancelled, .declined:
            return "minus.circle.fill"
        case .ended:
            return "xmark.circle.fill"
        case .expired, .suspended:
            return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Match Details Sheet

struct MatchDetailsSheet: View {
    let match: MentorshipMatch
    @Binding var navigationPath: [MentorshipNavigationDestination]
    @Binding var isPresented: Bool
    @State private var showingEndConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Status")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)

                            Text(match.status.rawValue.capitalized)
                                .font(.headline)
                        }

                        Spacer()

                        if let score = match.compatibilityScore {
                            VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                                Text("Compatibility")
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textSecondary)

                                Text("\(Int(score * 100))%")
                                    .font(.headline)
                                    .foregroundColor(SupportTheme.accent)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Match Created")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)

                        Text(match.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }

                    if let expiresAt = match.expiresAt {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text("Expires")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)

                            Text(expiresAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                        }
                    }

                    if let reason = match.matchReason {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text("Why You Matched")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)

                            Text(reason)
                                .font(.subheadline)
                        }
                    }
                }
                .supportCard()

                if match.status == .active {
                    Button(action: {
                        isPresented = false
                        navigationPath.append(.chat(matchId: match.id))
                    }) {
                        Label("Send Message", systemImage: "bubble.left.and.bubble.right.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)

                    Button(role: .destructive, action: { showingEndConfirmation = true }) {
                        Label("End Mentorship", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }

                Spacer()
            }
            .padding()
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Mentorship Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
            .alert("End Mentorship?", isPresented: $showingEndConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("End", role: .destructive) {
                    isPresented = false
                }
            } message: {
                Text("Are you sure you want to end this mentorship relationship?")
            }
        }
    }
}
