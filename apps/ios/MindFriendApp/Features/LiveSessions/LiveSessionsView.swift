// LiveSessionsView.swift
// MindFriend - Live Sessions List View

import SwiftUI

struct LiveSessionsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var isLoading = true
    @State private var selectedSession: LiveSession?
    @State private var activeSession: LiveSession?
    @State private var showActiveSession = false

    var liveService: LiveService {
        container.liveService
    }

    var liveSessions: [LiveSession] {
        liveService.liveSessions.filter { $0.isLive }
    }

    var upcomingSessions: [LiveSession] {
        liveService.liveSessions.filter { $0.isUpcoming }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    loadingView
                } else if liveService.liveSessions.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Live Sessions")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadSessions()
        }
        .task {
            await loadSessions()
        }
        .sheet(item: $selectedSession) { session in
            LiveSessionDetailSheet(
                session: session,
                liveService: liveService,
                onJoin: { joinedSession in
                    selectedSession = nil
                    activeSession = joinedSession
                    showActiveSession = true
                }
            )
        }
        .fullScreenCover(isPresented: $showActiveSession) {
            if let session = activeSession {
                ActiveSessionView(
                    session: session,
                    liveService: liveService
                )
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading sessions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Live Sessions")
                .font(.headline)

            Text("Check back later for scheduled group sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal)
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Live Now Section
            if !liveSessions.isEmpty {
                liveNowSection
            }

            // Upcoming Section
            if !upcomingSessions.isEmpty {
                upcomingSection
            }
        }
    }

    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Live Now")
                    .font(.headline)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(liveSessions) { session in
                        LiveSessionCard(
                            session: session,
                            isLive: true,
                            onTap: { selectedSession = session }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming")
                .font(.headline)
                .padding(.horizontal)

            LazyVStack(spacing: 12) {
                ForEach(upcomingSessions) { session in
                    UpcomingSessionRow(
                        session: session,
                        onTap: { selectedSession = session }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await liveService.fetchLiveSessionsWithCounts()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Live Session Card

struct LiveSessionCard: View {
    let session: LiveSession
    let isLive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: session.sessionType.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(typeColor.opacity(0.8))
                        .clipShape(Circle())

                    Spacer()

                    if isLive {
                        LiveBadge()
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(session.sessionType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Footer
                HStack {
                    Label("\(session.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let count = session.participantCount {
                        Label("\(count)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(width: 200)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return .blue
        case .meditation: return .purple
        case .bodyScan: return .green
        }
    }
}

// MARK: - Live Badge

struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("LIVE")
                .font(.caption2.bold())
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
        .cornerRadius(8)
        .onAppear { isPulsing = true }
    }
}

// MARK: - Upcoming Session Row

struct UpcomingSessionRow: View {
    let session: LiveSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: session.sessionType.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(typeColor.opacity(0.8))
                    .clipShape(Circle())

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if let startsIn = session.startsIn {
                            Text(startsIn)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text("\(session.durationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Participant count
                if let count = session.participantCount, count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                        Text("\(count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return .blue
        case .meditation: return .purple
        case .bodyScan: return .green
        }
    }
}

// MARK: - Live Session Detail Sheet

struct LiveSessionDetailSheet: View {
    let session: LiveSession
    let liveService: LiveService
    let onJoin: (LiveSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero
                    VStack(spacing: 16) {
                        Image(systemName: session.sessionType.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(typeColor)

                        Text(session.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        if let description = session.description {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 24)

                    // Details
                    VStack(spacing: 12) {
                        DetailRow(icon: "clock", label: "Duration", value: "\(session.durationMinutes) min")
                        DetailRow(icon: "sparkles", label: "Type", value: session.sessionType.displayName)

                        if let count = session.participantCount {
                            DetailRow(icon: "person.2.fill", label: "Participants", value: "\(count) joined")
                        }

                        if session.isLive {
                            DetailRow(icon: "circle.fill", label: "Status", value: "Live Now", valueColor: .green)
                        } else if let startsIn = session.startsIn {
                            DetailRow(icon: "clock.arrow.circlepath", label: "Starts", value: startsIn, valueColor: .orange)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    // What to expect
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What to Expect")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ExpectationRow(icon: "headphones", text: "Guided audio session")
                            ExpectationRow(icon: "person.3.fill", text: "Practice with others in real-time")
                            ExpectationRow(icon: "heart.fill", text: "Send reactions to encourage others")
                            ExpectationRow(icon: "star.fill", text: "Earn bonus XP for completing")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Join button
                    Button {
                        Task { await joinSession() }
                    } label: {
                        HStack {
                            if isJoining {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(session.isLive ? "Join Now" : "Notify Me")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(session.isLive ? Color.accentColor : Color.secondary)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isJoining || !session.isLive)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return .blue
        case .meditation: return .purple
        case .bodyScan: return .green
        }
    }

    private func joinSession() async {
        guard session.isLive else { return }

        isJoining = true
        errorMessage = nil

        do {
            let result = try await liveService.joinSession(sessionId: session.id)
            onJoin(result.session)
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

// MARK: - Helper Views

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }
}

private struct ExpectationRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        LiveSessionsView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
