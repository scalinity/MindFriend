// LiveSessionsView.swift
// MindFriend - Live Sessions List View

import SwiftUI

struct LiveSessionsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var isLoading = true
    @State private var loadError: String?
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
            VStack(spacing: SupportTheme.Spacing.l) {
                if isLoading {
                    loadingView
                } else if let loadError {
                    SupportUnavailableState(title: "Sessions unavailable", message: loadError, actionTitle: "Try again") {
                        Task { await loadSessions() }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                } else if liveService.liveSessions.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle(SupportDestination.liveSessions.title)
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
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
            Text("Loading sessions...")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SupportTheme.Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No Live Sessions")
                .font(.headline)

            Text("Check back later for scheduled group sessions")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SupportTheme.Spacing.xl)
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Live Now")
                    .font(.headline)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(liveSessions) { session in
                        LiveSessionCard(
                            session: session,
                            isLive: true,
                            onTap: { selectedSession = session }
                        )
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Upcoming")
                .font(.headline)
                .padding(.horizontal, SupportTheme.Spacing.m)

            LazyVStack(spacing: SupportTheme.Spacing.s) {
                ForEach(upcomingSessions) { session in
                    UpcomingSessionRow(
                        session: session,
                        onTap: { selectedSession = session }
                    )
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
    }

    // MARK: - Actions

    private func loadSessions() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            try await liveService.fetchLiveSessionsWithCounts()
        } catch {
            loadError = error.localizedDescription
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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header
                HStack {
                    Image(systemName: session.sessionType.icon)
                        .font(.title2)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(SupportTheme.surface)
                        .clipShape(Circle())

                    Spacer()

                    if isLive {
                        LiveBadge()
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(session.sessionType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Footer
                HStack {
                    Label("\(session.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Spacer()

                    if let count = session.participantCount {
                        Label("\(count)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
            .frame(width: 200)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.cardRadius)
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return SupportTheme.accent
        case .meditation: return SupportTheme.accent
        case .bodyScan: return SupportTheme.accent
        }
    }
}

// MARK: - Live Badge

struct LiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.2 : 1.0))
                .animation(reduceMotion ? nil :
                    .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("LIVE")
                .font(.caption2.bold())
                .foregroundStyle(.red)
        }
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(Color.red.opacity(0.15))
        .cornerRadius(SupportTheme.controlRadius)
        .onAppear { isPulsing = true }
    }
}

// MARK: - Upcoming Session Row

struct UpcomingSessionRow: View {
    let session: LiveSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SupportTheme.Spacing.s) {
                // Icon
                Image(systemName: session.sessionType.icon)
                    .font(.title3)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(SupportTheme.surface)
                    .clipShape(Circle())

                // Content
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SupportTheme.textPrimary)

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        if let startsIn = session.startsIn {
                            Text(startsIn)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                        }

                        Text("\(session.durationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                // Participant count
                if let count = session.participantCount, count > 0 {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "person.2.fill")
                        Text("\(count)")
                    }
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return SupportTheme.accent
        case .meditation: return SupportTheme.accent
        case .bodyScan: return SupportTheme.accent
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
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Hero
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: session.sessionType.icon)
                            .font(.system(.largeTitle))
                            .foregroundStyle(typeColor)

                        Text(session.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        if let description = session.description {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, SupportTheme.Spacing.l)

                    // Details
                    VStack(spacing: SupportTheme.Spacing.s) {
                        DetailRow(icon: "clock", label: "Duration", value: "\(session.durationMinutes) min")
                        DetailRow(icon: "sparkles", label: "Type", value: session.sessionType.displayName)

                        if let count = session.participantCount {
                            DetailRow(icon: "person.2.fill", label: "Participants", value: "\(count) joined")
                        }

                        if session.isLive {
                            DetailRow(icon: "circle.fill", label: "Status", value: "Live Now", valueColor: SupportTheme.accent)
                        } else if let startsIn = session.startsIn {
                            DetailRow(icon: "clock.arrow.circlepath", label: "Starts", value: startsIn, valueColor: SupportTheme.accent)
                        }
                    }
                    .supportCard()

                    // What to expect
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("What to Expect")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            ExpectationRow(icon: "headphones", text: "Guided audio session")
                            ExpectationRow(icon: "person.3.fill", text: "Practice with others in real-time")
                            ExpectationRow(icon: "heart.fill", text: "Send reactions to encourage others")
                            ExpectationRow(icon: "star.fill", text: "Earn bonus XP for completing")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .supportCard()

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
                                    .tint(SupportTheme.onAccent)
                            } else {
                                Text(session.isLive ? "Join Now" : "Notify Me")
                            }
                        }
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(isJoining || !session.isLive)
                }
                .padding(SupportTheme.Spacing.m)
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
        case .breathing: return SupportTheme.accent
        case .meditation: return SupportTheme.accent
        case .bodyScan: return SupportTheme.accent
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
                .foregroundStyle(SupportTheme.textSecondary)

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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.textSecondary)
                .frame(minWidth: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
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
