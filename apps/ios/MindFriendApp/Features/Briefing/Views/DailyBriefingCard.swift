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
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your briefing...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Briefing View

    private func briefingView(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Greeting - use current name, not cached
            Text(currentGreeting)
                .font(.headline)

            // Mood prediction
            if let mood = briefing.predictedMood, let outlook = briefing.moodOutlook {
                HStack {
                    Text(outlook.emoji)
                    Text("Mood: \(outlook.displayText)")
                        .font(.subheadline)
                    Text("(\(String(format: "%.1f", mood)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Error State

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Unable to load briefing")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshBriefing()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        EmptyView()
    }
}
