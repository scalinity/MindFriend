//
//  BriefingExpandedView.swift
//  MindFriendApp
//
//  F009: Full Briefing Sheet View
//  Shows all briefing details with sections
//

import SwiftUI

/// Full briefing view presented as a sheet
struct BriefingExpandedView: View {
    @ObservedObject var viewModel: DailyBriefingViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    /// Dynamic greeting using current user name (not cached briefing name)
    private var currentGreeting: String {
        let name = appState.currentUser?.displayName ?? String(localized: "Friend")
        return String(format: String(localized: "Hello, %@!"), name)
    }

    /// Current streak from user stats
    private var currentStreak: Int {
        appState.currentStreak
    }

    /// Recent badges (earned in last 7 days)
    private var recentBadges: [UserBadgeProgress] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return container.achievementService.earnedBadges.filter { badge in
            guard let earnedAt = badge.earnedAt else { return false }
            return earnedAt >= sevenDaysAgo
        }.sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if let briefing = viewModel.briefing {
                    briefingContent(briefing)
                } else {
                    Text("No briefing available")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Daily Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.regenerateBriefing()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Greeting Section
            greetingSection(briefing)

            // Streak Section (show if active streak)
            if currentStreak > 0 {
                streakSection
            }

            // Mood Prediction Section
            if briefing.predictedMood != nil {
                moodSection(briefing)
            }

            // Quest Section
            if briefing.questTitle != nil {
                questSection(briefing)
            }

            // Recent Achievements Section
            if !recentBadges.isEmpty {
                achievementsSection
            }

            // Calendar Section
            if briefing.hasCalendarEvents {
                calendarSection(briefing)
            }

            // Suggestion Section
            suggestionSection(briefing)
        }
        .padding()
    }

    // MARK: - Sections

    private func greetingSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentGreeting)
                .font(.title2)
                .fontWeight(.semibold)

            if let context = briefing.moodContext {
                Text(context)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func moodSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mood Prediction")
                    .font(.headline)
                Spacer()
                if let outlook = briefing.moodOutlook {
                    Text(outlook.emoji)
                        .font(.title)
                }
            }

            if let mood = briefing.predictedMood, let outlook = briefing.moodOutlook {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outlook.displayText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(String(format: "%.1f/10", mood))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func questSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Quest")
                    .font(.headline)
                Spacer()
                if appState.todayQuest?.status == .completed {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if let questTitle = briefing.questTitle {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.blue)
                    Text(questTitle)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func calendarSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar (Next 24h)")
                .font(.headline)

            ForEach(briefing.calendarEvents) { event in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundColor(.orange)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text(event.formattedStartTime)
                            if let location = event.location {
                                Text("•")
                                Text(location)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if event.isSoon {
                            Text(event.timeUntilStart)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func suggestionSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestion")
                .font(.headline)

            Text(briefing.suggestion)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're on a \(currentStreak)-day streak!")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Keep it going!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.1), .yellow.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Achievements")
                .font(.headline)

            ForEach(recentBadges.prefix(3)) { badgeProgress in
                HStack(spacing: 12) {
                    Image(systemName: "medal.fill")
                        .foregroundColor(.yellow)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(badgeProgress.badge.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(badgeProgress.badge.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("+\(badgeProgress.badge.xpReward) XP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
