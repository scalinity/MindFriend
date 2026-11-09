//
//  DailyBriefingCard.swift
//  MindFriendApp
//
//  F009: Daily Briefing Card for Home Screen
//  Collapsed preview of daily briefing
//

import SwiftUI

/// Collapsed briefing card displayed on home screen
struct DailyBriefingCard: View {
    @ObservedObject var viewModel: DailyBriefingViewModel
    @EnvironmentObject var appState: AppState

    /// Dynamic greeting using current user name (not cached briefing name)
    private var currentGreeting: String {
        let name = appState.currentUser?.displayName ?? String(localized: "Friend")
        return String(format: String(localized: "Hello, %@!"), name)
    }

    var body: some View {
        Button {
            viewModel.isExpanded = true
            Task {
                await viewModel.markAsViewed()
            }
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $viewModel.isExpanded) {
            BriefingExpandedView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if viewModel.isLoading {
            loadingView
        } else if let briefing = viewModel.briefing {
            briefingView(briefing)
        } else if let error = viewModel.error {
            errorView(error)
        } else {
            emptyView
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            ProgressView()
            Text("Loading your briefing...")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
        .shadow(radius: 2)
    }

    // MARK: - Briefing View

    private func briefingView(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Greeting - use current name, not cached
            Text(currentGreeting)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // Mood prediction
            if let mood = briefing.predictedMood, let outlook = briefing.moodOutlook {
                HStack {
                    Text(outlook.emoji)
                    Text("Mood: \(outlook.displayText)")
                        .font(.subheadline)
                    Text("(\(String(format: "%.1f", mood)))")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }

            // Quest
            if let questTitle = briefing.questTitle {
                HStack {
                    Image(systemName: "target")
                    Text(questTitle)
                        .font(.subheadline)
                }
            }

            // Next event
            if let nextEvent = briefing.nextEvent {
                HStack {
                    Image(systemName: "calendar")
                    Text("\(nextEvent.title) \(nextEvent.timeUntilStart)")
                        .font(.subheadline)
                }
            }

            // Tap to expand hint
            HStack {
                Spacer()
                Text("Tap to view full briefing →")
                    .font(.caption)
                    .foregroundColor(SupportTheme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.canvas)
        .cornerRadius(SupportTheme.controlRadius)
        .shadow(radius: 2)
    }

    // MARK: - Error State

    private func errorView(_ error: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(SupportTheme.accent)
            Text("Unable to load briefing")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(error)
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshBriefing()
                }
            }
            .buttonStyle(.supportPrimary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(SupportTheme.canvas)
        .cornerRadius(SupportTheme.controlRadius)
        .shadow(radius: 2)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        EmptyView()
    }
}
