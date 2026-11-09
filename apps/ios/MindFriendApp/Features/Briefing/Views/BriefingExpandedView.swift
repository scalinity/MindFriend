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
                        .foregroundColor(SupportTheme.textSecondary)
                        .padding()
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
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
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Refresh")
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
            // Greeting Section
            greetingSection(briefing)

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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(currentGreeting)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            if let context = briefing.moodContext {
                Text(context)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
    }

    private func moodSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text("Mood Prediction")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let outlook = briefing.moodOutlook {
                    Text(outlook.emoji)
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if let mood = briefing.predictedMood, let outlook = briefing.moodOutlook {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(outlook.displayText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(String(format: "%.1f/10", mood))
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
    }

    private func questSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text("Today's Quest")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if appState.todayQuest?.status == .completed {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(SupportTheme.accent)
                }
            }

            if let questTitle = briefing.questTitle {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(SupportTheme.accent)
                    Text(questTitle)
                        .font(.subheadline)
                }
            }
        }
        .supportCard()
    }

    private func calendarSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Calendar (Next 24h)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(briefing.calendarEvents) { event in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "calendar")
                        .foregroundColor(SupportTheme.accent)
                        .frame(minWidth: 20)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
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
                        .foregroundColor(SupportTheme.textSecondary)

                        if event.isSoon {
                            Text(event.timeUntilStart)
                                .font(.caption)
                                .foregroundColor(SupportTheme.accent)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .supportCard()
    }

    private func suggestionSection(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Suggestion")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(briefing.suggestion)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textPrimary)
        }
        .supportCard()
    }

    // MARK: - Streak Section

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Recent Achievements")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(recentBadges.prefix(3)) { badgeProgress in
                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "medal.fill")
                        .foregroundColor(SupportTheme.Celebration.gold)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(badgeProgress.badge.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(badgeProgress.badge.description)
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("+\(badgeProgress.badge.xpReward) XP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(SupportTheme.accent)
                }
            }
        }
        .supportCard()
    }
}
