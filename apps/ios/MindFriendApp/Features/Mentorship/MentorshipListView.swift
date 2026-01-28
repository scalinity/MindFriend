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
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab selector
                Picker("Matches", selection: $selectedTab) {
                    Text("Active").tag(Tab.active)
                    Text("Pending").tag(Tab.pending)
                    Text("All").tag(Tab.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(.secondarySystemBackground))

                // Content
                if matchingService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading mentorships...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if filteredMatches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: tabEmptyImage)
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text(tabEmptyTitle)
                            .font(.headline)

                        Text(tabEmptyMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
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
        .navigationTitle("My Mentorships")
        .navigationBarTitleDisplayMode(.inline)
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
            return .orange
        case .active:
            return .green
        case .completed:
            return .blue
        case .cancelled:
            return .gray
        case .ended:
            return .gray
        case .expired:
            return .red
        }
    }

    var statusLabel: String {
        match.status.rawValue.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mentorship Match")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(match.id.uuidString.prefix(8).uppercased())
                        .font(.headline)
                }

                Spacer()

                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)
            }

            if let compatibilityScore = match.compatibilityScore {
                HStack(spacing: 8) {
                    Text("Compatibility")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: compatibilityScore)
                        .tint(.blue)

                    Text("\(Int(compatibilityScore * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }

            if let reason = match.matchReason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Button(action: action) {
                Text("View Details")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.quaternarySystemFill))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var statusIcon: String {
        switch match.status {
        case .pending:
            return "clock"
        case .active:
            return "checkmark.circle.fill"
        case .completed:
            return "star.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        case .ended:
            return "xmark.circle.fill"
        case .expired:
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
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(match.status.rawValue.capitalized)
                                .font(.headline)
                        }

                        Spacer()

                        if let score = match.compatibilityScore {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Compatibility")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(Int(score * 100))%")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Match Created")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(match.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }

                    if let expiresAt = match.expiresAt {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expires")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(expiresAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                        }
                    }

                    if let reason = match.matchReason {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why You Matched")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(reason)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                if match.status == .active {
                    Button(action: {
                        isPresented = false
                        navigationPath.append(.chat(matchId: match.id))
                    }) {
                        Label("Send Message", systemImage: "bubble.left.and.bubble.right.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }

                    Button(role: .destructive, action: { showingEndConfirmation = true }) {
                        Label("End Mentorship", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                }

                Spacer()
            }
            .padding()
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
