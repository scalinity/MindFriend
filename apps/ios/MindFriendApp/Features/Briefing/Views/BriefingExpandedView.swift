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
    @Environment(\.dismiss) var dismiss

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

            // Mood Prediction Section
            if briefing.predictedMood != nil {
                moodSection(briefing)
            }

            // Quest Section
            if briefing.questTitle != nil {
                questSection(briefing)
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
            Text(briefing.greeting)
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
            Text("Today's Quest")
                .font(.headline)

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
}
